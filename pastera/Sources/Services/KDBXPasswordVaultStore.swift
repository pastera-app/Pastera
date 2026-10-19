import CryptoKit
import Foundation
import KDBXKit

final class VaultFileCoordinator {
    static func vaultURL(for syncRootURL: URL) -> URL {
        syncRootURL
            .appendingPathComponent("PasteraSync", isDirectory: true)
            .appendingPathComponent("vault", isDirectory: true)
            .appendingPathComponent("PasteraVault.kdbx", isDirectory: false)
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func read(from url: URL) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else { throw PasswordVaultError.databaseNotConfigured }
        return try Data(contentsOf: url)
    }

    func revision(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = url.appendingPathExtension("bak")
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
    }

    func conflictFiles(alongside url: URL) throws -> [URL] {
        let directory = url.deletingLastPathComponent()
        let vaultPath = url.standardizedFileURL.path
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            $0.standardizedFileURL.path != vaultPath && $0.pathExtension.lowercased() == "kdbx"
        }
    }

    func archiveResolvedConflict(_ conflictURL: URL, alongside vaultURL: URL) throws {
        let resolved = vaultURL.deletingLastPathComponent()
            .appendingPathComponent("conflicts", isDirectory: true)
            .appendingPathComponent("resolved", isDirectory: true)
        try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        var destination = resolved.appendingPathComponent(conflictURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            destination = resolved.appendingPathComponent("\(UUID().uuidString)-\(conflictURL.lastPathComponent)")
        }
        try fileManager.moveItem(at: conflictURL, to: destination)
    }
}

final class KDBXPasswordVaultStore: PasswordVaultStore, PasswordVaultSyncAccess {
    private let localStorage: PasswordVaultLocalStoring
    private let coordinator = VaultFileCoordinator()
    private let unlockKeyStore: VaultUnlockKeyStoring
    private let automationUnlockKeyStore: VaultAutomationUnlockKeyStoring
    private let rekeyTransaction: VaultArtifactRekeyTransaction
    private let merger = KDBXVaultMerger()
    private let now: () -> Date
    private let autoLockTimeoutProvider: () -> TimeInterval
    private var content: KDBXContent?
    private var unlockData: UnlockData?
    private var lastRevision: Data?
    private let sessionExecutorLock = NSLock()
    private var sessionExecutor: VaultAgentSerialExecutor?
    private var sessionStateChange: (() -> Void)?
    private let sessionNotificationCenter: NotificationCenter?
    private var commitObserver: (PasswordVaultCommit) -> Void = { _ in }
    private(set) var state: PasswordVaultState
    var canQuickUnlock: Bool { unlockKeyStore.containsKey }
    var canAutomationUnlock: Bool { automationUnlockKeyStore.containsKey }
    private lazy var sessionController = VaultSessionController(
        timeoutProvider: autoLockTimeoutProvider,
        notificationCenter: sessionNotificationCenter,
        lockRequestAction: { [weak self] request in self?.enqueueSessionLock(request) }
    )

    init(
        localStorage: PasswordVaultLocalStoring = FilePasswordVaultLocalStorage.live(),
        unlockKeyStore: VaultUnlockKeyStoring = VaultUnlockKeyStore(),
        automationUnlockKeyStore: VaultAutomationUnlockKeyStoring = VaultAutomationUnlockKeyStore(),
        rekeyTransaction: VaultArtifactRekeyTransaction = VaultArtifactRekeyTransaction(),
        sessionNotificationCenter: NotificationCenter? = nil,
        autoLockTimeoutProvider: @escaping () -> TimeInterval = {
            VaultSessionController.resolvedTimeout(defaults: .standard)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.localStorage = localStorage
        self.unlockKeyStore = unlockKeyStore
        self.automationUnlockKeyStore = automationUnlockKeyStore
        self.rekeyTransaction = rekeyTransaction
        self.sessionNotificationCenter = sessionNotificationCenter
        self.autoLockTimeoutProvider = autoLockTimeoutProvider
        self.now = now
        do {
            state = try localStorage.containsVault() ? .locked : .notConfigured
        } catch {
            state = .localCopyUnavailable(.localWriteFailed)
        }
    }

    func createDatabase(masterPassword: String, rememberQuickUnlock: Bool) throws {
        guard !masterPassword.isEmpty else { throw PasswordVaultError.invalidPassword }
        let unlock = UnlockData(masterPassword: masterPassword)
        var newContent = KDBXContent.makeEmpty(databaseName: "Pastera", generator: "Pastera")
        newContent.database.meta.historyMaxItems = .value(10)
        let persistence: (data: Data, revision: Data)
        do {
            persistence = try withLocalTransaction {
                guard try !localStorage.containsVault() else { throw PasswordVaultError.duplicateEntry }
                let bytes = try encoded(newContent, unlockData: unlock)
                try localStorage.writeAtomically(bytes)
                let written = try readLocalDataWithinTransaction()
                _ = try KDBXReader.parse(written, unlockData: unlock)
                return (written, coordinator.revision(of: written))
            }
        } catch PasswordVaultError.duplicateEntry {
            throw PasswordVaultError.duplicateEntry
        } catch {
            state = .failed("save")
            throw PasswordVaultError.saveFailed
        }
        content = newContent
        unlockData = unlock
        lastRevision = persistence.revision
        state = .unlocked
        sessionController.touch()
        if rememberQuickUnlock { try? remember(unlock) }
        publishCommit(data: persistence.data, origin: .userMutation)
    }

    func unlock(masterPassword: String, rememberQuickUnlock: Bool) throws {
        state = .unlocking
        let unlock = UnlockData(masterPassword: masterPassword)
        do {
            let data = try readLocalData()
            content = try KDBXReader.parse(data, unlockData: unlock)
            lastRevision = coordinator.revision(of: data)
            unlockData = unlock
            state = .unlocked
            sessionController.touch()
            if rememberQuickUnlock { try? remember(unlock) }
        } catch KDBXReader.Error.wrongCredentials {
            state = .locked
            throw PasswordVaultError.wrongMasterPassword
        } catch let error as PasswordVaultError {
            state = localReadFailureState(for: error)
            throw error
        } catch {
            state = .failed("corrupted")
            throw PasswordVaultError.corruptedData
        }
    }

    func unlockWithQuickKey(reason: String) throws {
        state = .unlocking
        do {
            let unlock = UnlockData(rawKeyData: try unlockKeyStore.load(reason: reason))
            let data = try readLocalData()
            content = try KDBXReader.parse(data, unlockData: unlock)
            lastRevision = coordinator.revision(of: data)
            unlockData = unlock
            state = .unlocked
            sessionController.touch()
        } catch KDBXReader.Error.wrongCredentials {
            state = .locked
            throw PasswordVaultError.wrongMasterPassword
        } catch let error as PasswordVaultError {
            state = localReadFailureState(for: error)
            throw error
        } catch {
            state = .failed("corrupted")
            throw PasswordVaultError.corruptedData
        }
    }

    func lock() {
        let binding = sessionBinding()
        guard let executor = binding.executor else {
            performLock(onStateChange: nil)
            return
        }
        executor.sync { performLock(onStateChange: binding.onStateChange) }
    }

    private func performLock(onStateChange: (() -> Void)?) {
        sessionController.cancel()
        content = nil
        unlockData = nil
        lastRevision = nil
        do {
            state = try localStorage.containsVault() ? .locked : .notConfigured
        } catch {
            state = .localCopyUnavailable(.localWriteFailed)
        }
        onStateChange?()
    }

    func reloadAndMerge() throws {
        let unlock = try requiredUnlockData()
        do {
            let persistence = try withLocalTransaction { () -> (
                merge: KDBXVaultMergeResult,
                revision: Data,
                committedData: Data?
            ) in
                let data = try readLocalDataWithinTransaction()
                let diskContent = try KDBXReader.parse(data, unlockData: unlock)
                let merged = content.map { merger.merge(local: $0, remote: diskContent) }
                    ?? KDBXVaultMergeResult(content: diskContent, conflictCopyCount: 0)
                let diskRevision = coordinator.revision(of: data)
                guard diskRevision != lastRevision else {
                    return (merged, diskRevision, nil)
                }
                let bytes = try encoded(merged.content, unlockData: unlock)
                try localStorage.writeAtomically(bytes)
                return (merged, coordinator.revision(of: bytes), bytes)
            }
            content = persistence.merge.content
            lastRevision = persistence.revision
            state = persistence.merge.hasConflictCopies ? .readOnlyWarning("conflict-copy") : .unlocked
            if let committedData = persistence.committedData {
                publishCommit(data: committedData, origin: .syncMerge)
            }
        } catch {
            state = .readOnlyWarning("external-change")
            throw PasswordVaultError.externalConflict
        }
    }

    func listFolders() throws -> [PasswordVaultFolder] {
        try requiredContent().database.root.group.groups.map(folder(from:))
    }

    func listEntries() throws -> [PasswordVaultEntry] {
        let root = try requiredContent().database.root.group
        return root.groups.flatMap { group in group.entries.map { entry(from: $0, folderID: group.uuid) } }
    }

    func createFolder(name: String) throws -> PasswordVaultFolder {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PasswordVaultError.invalidTitle }
        var content = try requiredContent()
        guard !content.database.root.group.groups.contains(where: { $0.name == normalized }) else {
            throw PasswordVaultError.duplicateFolder
        }
        let timestamp = now()
        let group = KDBX.Group(
            uuid: UUID(), name: normalized,
            times: .init(creationTime: timestamp, lastModificationTime: timestamp), isExpanded: true
        )
        content.database.root.group.groups.append(group)
        try save(content)
        return folder(from: group)
    }

    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PasswordVaultError.invalidTitle }
        var content = try requiredContent()
        guard let index = content.database.root.group.groups.firstIndex(where: { $0.uuid == id }) else {
            throw PasswordVaultError.folderNotFound
        }
        guard !content.database.root.group.groups.contains(where: { $0.uuid != id && $0.name == normalized }) else {
            throw PasswordVaultError.duplicateFolder
        }
        content.database.root.group.groups[index].name = normalized
        content.database.root.group.groups[index].times?.lastModificationTime = now()
        let group = content.database.root.group.groups[index]
        try save(content)
        return folder(from: group)
    }

    func deleteFolder(id: UUID) throws {
        var content = try requiredContent()
        guard let index = content.database.root.group.groups.firstIndex(where: { $0.uuid == id }) else {
            throw PasswordVaultError.folderNotFound
        }
        let folder = content.database.root.group.groups.remove(at: index)
        let deletionTime = now()
        content.database.root.deletedObjects.append(.init(uuid: id, deletionTime: deletionTime))
        content.database.root.deletedObjects.append(contentsOf: folder.entries.map {
            .init(uuid: $0.uuid, deletionTime: deletionTime)
        })
        try save(content)
    }

    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        let normalized = try normalized(draft)
        var content = try requiredContent()
        let folderIndex = try ensureFolder(in: &content, requestedID: normalized.folderID)
        let timestamp = now()
        let entry = makeEntry(draft: normalized, id: UUID(), createdAt: timestamp, updatedAt: timestamp)
        content.database.root.group.groups[folderIndex].entries.append(entry)
        try save(content)
        return self.entry(from: entry, folderID: content.database.root.group.groups[folderIndex].uuid)
    }

    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        let normalized = try normalized(draft)
        var content = try requiredContent()
        guard let source = content.database.root.group.groups.firstIndex(where: { $0.entries.contains { $0.uuid == id } }),
              let entryIndex = content.database.root.group.groups[source].entries.firstIndex(where: { $0.uuid == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        let previous = content.database.root.group.groups[source].entries[entryIndex]
        let destination = try ensureFolder(in: &content, requestedID: normalized.folderID ?? content.database.root.group.groups[source].uuid)
        var updated = makeEntry(
            draft: normalized, id: id,
            createdAt: previous.times?.creationTime ?? now(), updatedAt: now(), preserving: previous
        )
        var historyEntry = previous
        historyEntry.history = []
        updated.history = Array((previous.history + [historyEntry]).suffix(10))
        content.database.root.group.groups[source].entries.remove(at: entryIndex)
        content.database.root.group.groups[destination].entries.append(updated)
        try save(content)
        return entry(from: updated, folderID: content.database.root.group.groups[destination].uuid)
    }

    func revealPassword(id: UUID, reason: String) throws -> String {
        let root = try requiredContent().database.root.group
        guard let entry = root.groups.lazy.flatMap(\.entries).first(where: { $0.uuid == id }),
              let password = value("Password", in: entry) else { throw PasswordVaultError.entryNotFound }
        return password
    }

    func delete(id: UUID, reason: String) throws {
        var content = try requiredContent()
        guard let source = content.database.root.group.groups.firstIndex(where: { $0.entries.contains { $0.uuid == id } }) else {
            throw PasswordVaultError.entryNotFound
        }
        content.database.root.group.groups[source].entries.removeAll { $0.uuid == id }
        content.database.root.deletedObjects.append(.init(uuid: id, deletionTime: now()))
        try save(content)
    }

    private func requiredContent() throws -> KDBXContent {
        sessionController.touch()
        guard let content else {
            throw state == .notConfigured
                ? PasswordVaultError.databaseNotConfigured
                : PasswordVaultError.vaultLocked
        }
        return content
    }

    private func enqueueSessionLock(_ request: VaultSessionLockRequest) {
        let binding = sessionBinding()
        guard let executor = binding.executor else {
            guard request.consume() else { return }
            performLock(onStateChange: nil)
            return
        }
        executor.async { [weak self] in
            guard request.consume() else { return }
            self?.performLock(onStateChange: binding.onStateChange)
        }
    }

    private func sessionBinding() -> (executor: VaultAgentSerialExecutor?, onStateChange: (() -> Void)?) {
        sessionExecutorLock.lock()
        defer { sessionExecutorLock.unlock() }
        return (sessionExecutor, sessionStateChange)
    }

    private func requiredUnlockData() throws -> UnlockData {
        guard let unlockData else { throw PasswordVaultError.vaultLocked }
        return unlockData
    }

    private func save(_ newContent: KDBXContent) throws {
        let unlock = try requiredUnlockData()
        do {
            let persistence = try withLocalTransaction { () -> (
                merge: KDBXVaultMergeResult,
                data: Data,
                revision: Data
            ) in
                let diskData = try readLocalDataWithinTransaction()
                let diskRevision = coordinator.revision(of: diskData)
                let mergeResult: KDBXVaultMergeResult
                if let lastRevision, lastRevision != diskRevision {
                    let diskContent = try KDBXReader.parse(diskData, unlockData: unlock)
                    mergeResult = merger.merge(local: newContent, remote: diskContent)
                } else {
                    mergeResult = .init(content: newContent, conflictCopyCount: 0)
                }
                let bytes = try encoded(mergeResult.content, unlockData: unlock)
                try localStorage.writeAtomically(bytes)
                return (mergeResult, bytes, coordinator.revision(of: bytes))
            }
            content = persistence.merge.content
            lastRevision = persistence.revision
            state = persistence.merge.hasConflictCopies ? .readOnlyWarning("conflict-copy") : .unlocked
            publishCommit(data: persistence.data, origin: .userMutation)
        } catch let error as PasswordVaultError {
            throw error
        } catch {
            state = .readOnlyWarning("save")
            throw PasswordVaultError.saveFailed
        }
    }

    private func ensureFolder(in content: inout KDBXContent, requestedID: UUID?) throws -> Int {
        if let requestedID {
            guard let index = content.database.root.group.groups.firstIndex(where: { $0.uuid == requestedID }) else {
                throw PasswordVaultError.folderNotFound
            }
            return index
        }
        if let first = content.database.root.group.groups.indices.first { return first }
        let timestamp = now()
        content.database.root.group.groups.append(.init(
            uuid: UUID(), name: String(localized: "Unfiled"),
            times: .init(creationTime: timestamp, lastModificationTime: timestamp), isExpanded: true
        ))
        return 0
    }

    private func encoded(_ content: KDBXContent, unlockData: UnlockData) throws -> Data {
        let stream = OutputStream(toMemory: ())
        stream.open()
        defer { stream.close() }
        try KDBXWriter(to: stream).write(content, unlockData: unlockData)
        guard let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw PasswordVaultError.saveFailed
        }
        return data
    }

    private func normalized(_ draft: PasswordVaultDraft) throws -> PasswordVaultDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw PasswordVaultError.invalidTitle }
        guard !draft.password.isEmpty else { throw PasswordVaultError.invalidPassword }
        return PasswordVaultDraft(
            folderID: draft.folderID, title: title,
            website: draft.website.trimmingCharacters(in: .whitespacesAndNewlines),
            username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines), password: draft.password
        )
    }

    private func makeEntry(
        draft: PasswordVaultDraft,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        preserving original: KDBX.Entry? = nil
    ) -> KDBX.Entry {
        var entry = original ?? .init(uuid: id)
        entry.uuid = id
        entry.times = .init(
            creationTime: createdAt, lastModificationTime: updatedAt,
            lastAccessTime: original?.times?.lastAccessTime,
            expiryTime: original?.times?.expiryTime, expires: original?.times?.expires,
            usageCount: original?.times?.usageCount, locationChanged: original?.times?.locationChanged
        )
        let replacements: [String: KDBX.ProtectedString.Value] = [
            "Title": .regular(draft.title), "UserName": .regular(draft.username),
            "Password": .protectedInMemory(draft.password), "URL": .regular(draft.website),
            "Notes": .regular(draft.note)
        ]
        entry.strings.removeAll { replacements[$0.key] != nil }
        entry.strings.append(contentsOf: replacements.map { .init(key: $0.key, value: $0.value) })
        return entry
    }

}

private extension KDBXPasswordVaultStore {
    func folder(from group: KDBX.Group) -> PasswordVaultFolder {
        PasswordVaultFolder(
            id: group.uuid, name: group.name ?? String(localized: "Unfiled"),
            createdAt: group.times?.creationTime ?? .distantPast,
            updatedAt: group.times?.lastModificationTime ?? .distantPast
        )
    }

    func entry(from entry: KDBX.Entry, folderID: UUID) -> PasswordVaultEntry {
        PasswordVaultEntry(
            id: entry.uuid, folderID: folderID,
            title: value("Title", in: entry) ?? "",
            website: value("URL", in: entry) ?? "",
            username: value("UserName", in: entry) ?? "",
            note: value("Notes", in: entry) ?? "",
            createdAt: entry.times?.creationTime ?? .distantPast,
            updatedAt: entry.times?.lastModificationTime ?? .distantPast
        )
    }

    func value(_ key: String, in entry: KDBX.Entry) -> String? {
        entry.strings.first(where: { $0.key == key })?.value.revealedString
    }
}

extension KDBXPasswordVaultStore {
    func encryptedSnapshot() throws -> PasswordVaultEncryptedSnapshot {
        let data = try readLocalData()
        return PasswordVaultEncryptedSnapshot(data: data, digest: PasswordVaultDigest.hex(data))
    }

    func mergeRemoteSnapshot(
        _ remoteData: Data,
        remoteMasterPassword: String?
    ) throws -> PasswordVaultMergeApplication {
        guard state == .unlocked, content != nil, let localUnlock = unlockData else {
            throw PasswordVaultError.vaultLocked
        }
        let remoteContent = try readRemoteContent(
            remoteData,
            localUnlock: localUnlock,
            remoteMasterPassword: remoteMasterPassword
        )
        let persistence: (merge: KDBXVaultMergeResult, data: Data, revision: Data)
        do {
            persistence = try withLocalTransaction {
                let diskData = try readLocalDataWithinTransaction()
                let diskContent = try KDBXReader.parse(diskData, unlockData: localUnlock)
                let mergeResult = merger.merge(local: diskContent, remote: remoteContent)
                let bytes = try encoded(mergeResult.content, unlockData: localUnlock)
                try localStorage.writeAtomically(bytes)
                return (mergeResult, bytes, coordinator.revision(of: bytes))
            }
        } catch let error as PasswordVaultError {
            throw error
        } catch {
            state = .readOnlyWarning("save")
            throw PasswordVaultError.saveFailed
        }
        content = persistence.merge.content
        lastRevision = persistence.revision
        state = .unlocked
        publishCommit(data: persistence.data, origin: .syncMerge)
        sessionBinding().onStateChange?()
        return PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: persistence.data,
                digest: PasswordVaultDigest.hex(persistence.data)
            ),
            conflictCopyCount: persistence.merge.conflictCopyCount
        )
    }

    func setCommitObserver(_ observer: @escaping (PasswordVaultCommit) -> Void) {
        commitObserver = observer
    }

    private func readRemoteContent(
        _ data: Data,
        localUnlock: UnlockData,
        remoteMasterPassword: String?
    ) throws -> KDBXContent {
        do {
            return try KDBXReader.parse(data, unlockData: localUnlock)
        } catch KDBXReader.Error.wrongCredentials {
            guard let remoteMasterPassword, !remoteMasterPassword.isEmpty else {
                throw PasswordVaultSyncFailure.remoteCredentialsRequired
            }
            do {
                let remoteUnlock = UnlockData(masterPassword: remoteMasterPassword)
                return try KDBXReader.parse(data, unlockData: remoteUnlock)
            } catch KDBXReader.Error.wrongCredentials {
                throw PasswordVaultSyncFailure.remoteCredentialsRequired
            } catch {
                throw PasswordVaultSyncFailure.remoteCorrupted
            }
        } catch {
            throw PasswordVaultSyncFailure.remoteCorrupted
        }
    }

    private func readLocalData() throws -> Data {
        try withLocalTransaction { try readLocalDataWithinTransaction() }
    }

    private func readLocalDataWithinTransaction() throws -> Data {
        guard try localStorage.containsVault() else {
            throw PasswordVaultError.databaseNotConfigured
        }
        do {
            return try localStorage.read()
        } catch let error as PasswordVaultError {
            throw error
        } catch {
            guard try localStorage.containsVault() else {
                throw PasswordVaultError.databaseNotConfigured
            }
            throw PasswordVaultError.corruptedData
        }
    }

    private func withLocalTransaction<Value>(_ operation: () throws -> Value) throws -> Value {
        try localStorage.withExclusiveTransaction(operation)
    }

    private func localReadFailureState(for error: PasswordVaultError) -> PasswordVaultState {
        switch error {
        case .databaseNotConfigured:
            .notConfigured
        case .corruptedData:
            .failed("corrupted")
        default:
            .failed("read")
        }
    }

    private func publishCommit(data: Data, origin: PasswordVaultCommitOrigin) {
        commitObserver(PasswordVaultCommit(
            origin: origin,
            encryptedDigest: PasswordVaultDigest.hex(data)
        ))
    }

    func enableQuickUnlock() throws {
        guard state == .unlocked || state.isReadableWarning, content != nil, let unlockData else {
            throw PasswordVaultError.vaultLocked
        }
        try remember(unlockData)
    }

    func disableQuickUnlock() throws {
        try unlockKeyStore.delete()
    }

    func refreshAutoLockSchedule() {
        guard state == .unlocked || state.isReadableWarning, content != nil else { return }
        sessionController.touch()
    }

    private func remember(_ unlock: UnlockData) throws {
        let data = unlock.keyDataBytes.withUnsafeBytes { Data($0) }
        try unlockKeyStore.save(data)
    }

    func changeMasterPassword(
        currentPassword: String,
        newPassword: String,
        keepQuickUnlockEnabled: Bool
    ) throws -> PasswordVaultMasterPasswordChangeResult {
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            throw PasswordVaultError.invalidPassword
        }
        let originalState = state
        let originalContent = content
        let originalUnlockData = unlockData
        let originalRevision = lastRevision
        let mainURL = localStorage.paths.vaultURL
        let oldUnlock = UnlockData(masterPassword: currentPassword)

        do {
            let change = try withLocalTransaction { () -> (
                result: PasswordVaultMasterPasswordChangeResult,
                data: Data
            ) in
                let diskData = try readLocalDataWithinTransaction()
                let diskContent: KDBXContent
                do {
                    diskContent = try KDBXReader.parse(diskData, unlockData: oldUnlock)
                } catch KDBXReader.Error.wrongCredentials {
                    throw PasswordVaultError.wrongMasterPassword
                } catch {
                    throw PasswordVaultError.corruptedData
                }
                var merged = originalContent.map { merger.merge(local: $0, remote: diskContent) }
                    ?? KDBXVaultMergeResult(content: diskContent, conflictCopyCount: 0)
                let immediateConflicts = try coordinator.conflictFiles(alongside: mainURL)
                var parsedContents = [URL: KDBXContent]()
                for url in try rekeyTransaction.managedArtifactURLs(in: localStorage.paths) where url != mainURL {
                    let artifact = try KDBXReader.parse(try coordinator.read(from: url), unlockData: oldUnlock)
                    parsedContents[url] = artifact
                    guard immediateConflicts.contains(url),
                          artifact.database.meta.databaseName == "Pastera"
                            || artifact.database.root.group.name == "Pastera" else { continue }
                    let result = merger.merge(local: merged.content, remote: artifact)
                    merged = KDBXVaultMergeResult(
                        content: result.content,
                        conflictCopyCount: merged.conflictCopyCount + result.conflictCopyCount
                    )
                }

                let newUnlock = UnlockData(masterPassword: newPassword)
                let artifacts = try rekeyTransaction.managedArtifactURLs(in: localStorage.paths)
                let replacements = try artifacts.map { url -> VaultArtifactRekeyReplacement in
                    let artifactContent = url == mainURL
                        ? merged.content
                        : try requiredArtifactContent(url, from: parsedContents)
                    return VaultArtifactRekeyReplacement(
                        url: url,
                        data: try encoded(artifactContent, unlockData: newUnlock)
                    )
                }
                let rekeyResult = try rekeyTransaction.replace(replacements) { _, data in
                    _ = try KDBXReader.parse(data, unlockData: newUnlock)
                }

                var warnings = refreshCredentials(
                    with: newUnlock,
                    keepQuickUnlockEnabled: keepQuickUnlockEnabled
                )
                if rekeyResult.hasPendingCleanup {
                    warnings.append(.rekeyArtifactCleanupPending)
                }
                for conflictURL in immediateConflicts {
                    do {
                        try coordinator.archiveResolvedConflict(conflictURL, alongside: mainURL)
                    } catch {
                        warnings.append(.conflictArchivePending)
                    }
                }

                if originalContent != nil, originalUnlockData != nil {
                    content = merged.content
                    unlockData = newUnlock
                    lastRevision = coordinator.revision(of: replacements[0].data)
                    if case .readOnlyWarning = originalState {
                        state = originalState
                    } else {
                        state = merged.hasConflictCopies ? .readOnlyWarning("conflict-copy") : .unlocked
                    }
                    sessionController.touch()
                } else {
                    sessionController.cancel()
                    content = nil
                    unlockData = nil
                    lastRevision = nil
                    state = .locked
                }
                let uniqueWarnings = Array(Set(warnings)).sorted { $0.rawValue < $1.rawValue }
                return (
                    PasswordVaultMasterPasswordChangeResult(warnings: uniqueWarnings),
                    replacements[0].data
                )
            }
            publishCommit(data: change.data, origin: .userMutation)
            return change.result
        } catch let error as PasswordVaultError {
            restoreRekeyState(originalState, content: originalContent, unlockData: originalUnlockData, revision: originalRevision)
            throw error
        } catch KDBXReader.Error.wrongCredentials {
            restoreRekeyState(originalState, content: originalContent, unlockData: originalUnlockData, revision: originalRevision)
            throw PasswordVaultError.externalConflict
        } catch {
            restoreRekeyState(originalState, content: originalContent, unlockData: originalUnlockData, revision: originalRevision)
            throw PasswordVaultError.saveFailed
        }
    }

    private func requiredArtifactContent(_ url: URL, from contents: [URL: KDBXContent]) throws -> KDBXContent {
        guard let content = contents[url] else { throw PasswordVaultError.externalConflict }
        return content
    }

    private func restoreRekeyState(
        _ originalState: PasswordVaultState,
        content originalContent: KDBXContent?,
        unlockData originalUnlockData: UnlockData?,
        revision originalRevision: Data?
    ) {
        state = originalState
        content = originalContent
        unlockData = originalUnlockData
        lastRevision = originalRevision
    }

    private func refreshCredentials(
        with unlock: UnlockData,
        keepQuickUnlockEnabled: Bool
    ) -> [PasswordVaultMasterPasswordChangeWarning] {
        let rawKey = unlock.keyDataBytes.withUnsafeBytes { Data($0) }
        let hadAutomationUnlock = automationUnlockKeyStore.containsKey
        var warnings = [PasswordVaultMasterPasswordChangeWarning]()

        if keepQuickUnlockEnabled {
            do {
                try unlockKeyStore.save(rawKey)
            } catch {
                warnings.append(.quickUnlockDisabled)
                do {
                    try unlockKeyStore.delete()
                } catch {
                    warnings.append(.credentialCleanupFailed)
                }
            }
        } else if unlockKeyStore.containsKey {
            do {
                try unlockKeyStore.delete()
            } catch {
                warnings.append(.credentialCleanupFailed)
            }
        }

        if hadAutomationUnlock {
            do {
                try automationUnlockKeyStore.save(rawKey)
            } catch {
                warnings.append(.automationUnlockDisabled)
                do {
                    try automationUnlockKeyStore.delete()
                } catch {
                    warnings.append(.credentialCleanupFailed)
                }
            }
        }
        return warnings
    }
}

private extension PasswordVaultState {
    var isReadableWarning: Bool {
        if case .readOnlyWarning = self { return true }
        return false
    }
}

extension KDBXPasswordVaultStore {
    func prepareLocalCopy(using migrator: PasswordVaultMigrating) {
        let onStateChange = sessionBinding().onStateChange
        state = .preparingLocalCopy
        onStateChange?()
        do {
            switch try migrator.migrateLegacyVaultIfNeeded() {
            case .notNeeded:
                state = try localStorage.containsVault() ? .locked : .notConfigured
            case .migrated:
                if let data = try? localStorage.read() {
                    state = .locked
                    publishCommit(data: data, origin: .migration)
                } else {
                    state = .localCopyUnavailable(.localWriteFailed)
                }
            case .waitingForOneDrive:
                state = .localCopyUnavailable(.oneDriveUnavailable)
            case let .failed(failure):
                state = .localCopyUnavailable(failure)
            }
        } catch {
            state = .localCopyUnavailable(.localWriteFailed)
        }
        onStateChange?()
    }

    func enableAutomationUnlock() throws {
        guard state == .unlocked || state.isReadableWarning, content != nil, let unlock = unlockData else {
            throw PasswordVaultError.vaultLocked
        }
        let data = unlock.keyDataBytes.withUnsafeBytes { Data($0) }
        guard data.count == 32 else { throw PasswordVaultError.keychainUnavailable }
        try automationUnlockKeyStore.save(data)
    }

    func unlockForAutomation() throws {
        sessionController.cancel()
        content = nil
        unlockData = nil
        lastRevision = nil
        state = .unlocking
        do {
            let key = try automationUnlockKeyStore.load()
            guard key.count == 32 else { throw PasswordVaultError.keychainUnavailable }
            let unlock = UnlockData(rawKeyData: key)
            let data = try readLocalData()
            content = try KDBXReader.parse(data, unlockData: unlock)
            lastRevision = coordinator.revision(of: data)
            unlockData = unlock
            state = .unlocked
            sessionController.touch()
        } catch KDBXReader.Error.wrongCredentials {
            state = .locked
            throw PasswordVaultError.keychainUnavailable
        } catch let error as PasswordVaultError {
            if error == .keychainUnavailable {
                state = .locked
            } else {
                state = localReadFailureState(for: error)
            }
            throw error
        } catch {
            state = .failed("corrupted")
            throw PasswordVaultError.corruptedData
        }
    }

    func disableAutomationUnlock() throws {
        try automationUnlockKeyStore.delete()
    }

    func bindSessionExecutor(_ executor: VaultAgentSerialExecutor, onStateChange: @escaping () -> Void) {
        sessionExecutorLock.lock()
        sessionExecutor = executor
        sessionStateChange = onStateChange
        sessionExecutorLock.unlock()
    }

    func reorderFolders(_ folderIDs: [UUID]) throws {
        var content = try requiredContent()
        let groups = content.database.root.group.groups
        guard folderIDs.count == groups.count, Set(folderIDs) == Set(groups.map(\.uuid)) else {
            throw PasswordVaultError.folderNotFound
        }
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.uuid, $0) })
        content.database.root.group.groups = try folderIDs.map { id in
            guard let group = groupsByID[id] else { throw PasswordVaultError.folderNotFound }
            return group
        }
        try save(content)
    }

    func moveEntry(id: UUID, to folderID: UUID) throws {
        let content = try requiredContent()
        guard let sourceGroup = content.database.root.group.groups.first(where: { group in
            group.entries.contains { $0.uuid == id }
        }) else {
            throw PasswordVaultError.entryNotFound
        }
        var ordered = [UUID: [UUID]]()
        ordered[sourceGroup.uuid] = sourceGroup.entries.filter { $0.uuid != id }.map(\.uuid)
        guard let destinationGroup = content.database.root.group.groups.first(where: { $0.uuid == folderID }) else {
            throw PasswordVaultError.folderNotFound
        }
        ordered[folderID] = destinationGroup.entries.filter { $0.uuid != id }.map(\.uuid) + [id]
        try moveEntry(id: id, to: folderID, orderedEntryIDsByFolder: ordered)
    }

    func moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws {
        var content = try requiredContent()
        guard let destination = content.database.root.group.groups.firstIndex(where: { $0.uuid == folderID }) else {
            throw PasswordVaultError.folderNotFound
        }
        guard let source = content.database.root.group.groups.firstIndex(where: { group in
            group.entries.contains { $0.uuid == id }
        }), let entryIndex = content.database.root.group.groups[source].entries.firstIndex(where: { $0.uuid == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        let sourceFolderID = content.database.root.group.groups[source].uuid
        let affectedFolderIDs: Set<UUID> = [sourceFolderID, folderID]
        guard Set(orderedEntryIDsByFolder.keys) == affectedFolderIDs else {
            throw PasswordVaultError.entryNotFound
        }
        for affectedFolderID in affectedFolderIDs {
            guard let group = content.database.root.group.groups.first(where: { $0.uuid == affectedFolderID }),
                  let orderedIDs = orderedEntryIDsByFolder[affectedFolderID],
                  orderedIDs.count == Set(orderedIDs).count else {
                throw PasswordVaultError.entryNotFound
            }
            var expectedIDs = Set(group.entries.map(\.uuid))
            if sourceFolderID == affectedFolderID { expectedIDs.remove(id) }
            if folderID == affectedFolderID { expectedIDs.insert(id) }
            guard Set(orderedIDs) == expectedIDs else { throw PasswordVaultError.entryNotFound }
        }
        var entry = content.database.root.group.groups[source].entries.remove(at: entryIndex)
        entry.previousParentGroup = sourceFolderID
        entry.times?.locationChanged = now()
        entry.times?.lastModificationTime = now()
        content.database.root.group.groups[destination].entries.append(entry)
        for affectedFolderID in affectedFolderIDs {
            guard let groupIndex = content.database.root.group.groups.firstIndex(where: { $0.uuid == affectedFolderID }),
                  let orderedIDs = orderedEntryIDsByFolder[affectedFolderID] else {
                throw PasswordVaultError.folderNotFound
            }
            let entriesByID = Dictionary(uniqueKeysWithValues: content.database.root.group.groups[groupIndex].entries.map {
                ($0.uuid, $0)
            })
            content.database.root.group.groups[groupIndex].entries = try orderedIDs.map { entryID in
                guard let orderedEntry = entriesByID[entryID] else { throw PasswordVaultError.entryNotFound }
                return orderedEntry
            }
        }
        try save(content)
    }
}
