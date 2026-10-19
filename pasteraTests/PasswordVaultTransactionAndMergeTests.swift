import Foundation
import KDBXKit
import Testing
@testable import Pastera

extension PasswordVaultStoreTests {
    @Test("KDBX folder deletion removes its passwords in one commit and survives stale merges")
    func kdbxFolderDeletionIncludesPasswordsAndTombstones() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KDBXPasswordVaultStore(
            localStorage: makeReviewLocalStorage(at: root),
            now: { Date(timeIntervalSince1970: 100.1) }
        )
        try store.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        let removedFolder = try store.createFolder(name: "Remove")
        let retainedFolder = try store.createFolder(name: "Keep")
        let removedEntries = try ["Mail", "Bank"].map { title in
            try store.create(.init(
                folderID: removedFolder.id, title: title, website: "",
                username: "alice", note: "", password: "secret"
            ))
        }
        let retainedEntry = try store.create(.init(
            folderID: retainedFolder.id, title: "Retained", website: "",
            username: "bob", note: "", password: "retained-secret"
        ))
        let staleSnapshot = try store.encryptedSnapshot()
        var commits = [PasswordVaultCommit]()
        store.setCommitObserver { commits.append($0) }

        try store.deleteFolder(id: removedFolder.id)

        #expect(commits.count == 1)
        #expect(commits.first?.origin == .userMutation)
        let persisted = try KDBXReader.parse(
            store.encryptedSnapshot().data,
            unlockData: UnlockData(masterPassword: "shared password")
        )
        #expect(Set(persisted.database.root.deletedObjects.map(\.uuid)) ==
            Set([removedFolder.id] + removedEntries.map(\.id)))
        store.lock()
        try store.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        _ = try store.mergeRemoteSnapshot(staleSnapshot.data, remoteMasterPassword: nil)

        #expect(try store.listFolders().map(\.id) == [retainedFolder.id])
        #expect(try store.listEntries().map(\.id) == [retainedEntry.id])
        #expect(try store.revealPassword(id: retainedEntry.id, reason: "test") == "retained-secret")
    }

    @Test("same-second deletions survive merging a stale encrypted snapshot after reopening")
    func sameSecondDeletionsSurviveStaleSnapshotMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var timestamp = Date(timeIntervalSince1970: 100.1)
        let store = KDBXPasswordVaultStore(
            localStorage: makeReviewLocalStorage(at: root),
            now: { timestamp }
        )
        try store.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        let removedFolder = try store.createFolder(name: "Remove")
        let retainedFolder = try store.createFolder(name: "Keep")
        let entry = try store.create(.init(
            folderID: retainedFolder.id, title: "Remove Password", website: "",
            username: "alice", note: "", password: "secret"
        ))
        let staleSnapshot = try store.encryptedSnapshot()

        timestamp = Date(timeIntervalSince1970: 100.2)
        try store.deleteFolder(id: removedFolder.id)
        try store.delete(id: entry.id, reason: "test")
        store.lock()
        try store.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        _ = try store.mergeRemoteSnapshot(staleSnapshot.data, remoteMasterPassword: nil)

        #expect(try store.listFolders().map(\.id) == [retainedFolder.id])
        #expect(try store.listEntries().isEmpty)
        store.lock()
        try store.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        #expect(try store.listFolders().map(\.id) == [retainedFolder.id])
        #expect(try store.listEntries().isEmpty)
    }

    @Test("remote same-second tombstones delete stale in-memory folders and passwords")
    func sameSecondRemoteDeletionsRemoveStaleMemory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var timestamp = Date(timeIntervalSince1970: 100.1)
        let active = KDBXPasswordVaultStore(
            localStorage: makeReviewLocalStorage(at: root),
            now: { timestamp }
        )
        try active.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        let removedFolder = try active.createFolder(name: "Remove")
        let retainedFolder = try active.createFolder(name: "Keep")
        let entry = try active.create(.init(
            folderID: retainedFolder.id, title: "Remove Password", website: "",
            username: "alice", note: "", password: "secret"
        ))
        let deleting = KDBXPasswordVaultStore(
            localStorage: makeReviewLocalStorage(at: root),
            now: { timestamp }
        )
        try deleting.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        timestamp = Date(timeIntervalSince1970: 100.2)
        try deleting.deleteFolder(id: removedFolder.id)
        try deleting.delete(id: entry.id, reason: "test")

        try active.reloadAndMerge()

        #expect(try active.listFolders().map(\.id) == [retainedFolder.id])
        #expect(try active.listEntries().isEmpty)
    }

    @Test("folder tombstones preserve modifications in a later KDBX second")
    func folderTombstonesPreserveLaterModifications() throws {
        let folderID = UUID()
        let local = makeReviewContent(groupID: folderID, modifiedAt: 100.6, entries: [])
        var remote = local
        remote.database.root.group.groups = []
        remote.database.root.deletedObjects = [
            .init(uuid: folderID, deletionTime: Date(timeIntervalSince1970: 100.2))
        ]

        let result = KDBXVaultMerger().merge(local: local, remote: remote)

        #expect(result.content.database.root.group.groups.map(\.uuid) == [folderID])
    }

    @Test("a second store cannot read the same path until the first write transaction releases")
    func concurrentVaultWritersMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try seed.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)

        let firstWriteEntered = DispatchSemaphore(value: 0)
        let releaseFirstWrite = DispatchSemaphore(value: 0)
        let secondReadEntered = DispatchSemaphore(value: 0)
        let firstStorage = CoordinatedReviewLocalStorage(backing: makeReviewLocalStorage(at: root))
        let secondStorage = CoordinatedReviewLocalStorage(backing: makeReviewLocalStorage(at: root))
        let first = KDBXPasswordVaultStore(localStorage: firstStorage)
        let second = KDBXPasswordVaultStore(localStorage: secondStorage)
        try first.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        try second.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        firstStorage.blockNextWrite(entered: firstWriteEntered, release: releaseFirstWrite)
        secondStorage.observeNextRead { secondReadEntered.signal() }

        let secondStarted = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        let outcomes = LockedReviewResults<PasswordVaultFolder>()
        finished.enter()
        Thread.detachNewThread {
            outcomes.append(Result { try first.createFolder(name: "First") })
            finished.leave()
        }
        #expect(firstWriteEntered.wait(timeout: .now() + 30) == .success)

        finished.enter()
        Thread.detachNewThread {
            secondStarted.signal()
            outcomes.append(Result { try second.createFolder(name: "Second") })
            finished.leave()
        }
        #expect(secondStarted.wait(timeout: .now() + 30) == .success)
        let secondReadBeforeRelease = secondReadEntered.wait(timeout: .now() + 1)
        releaseFirstWrite.signal()
        if secondReadBeforeRelease == .timedOut {
            #expect(secondReadEntered.wait(timeout: .now() + 30) == .success)
        }
        #expect(finished.wait(timeout: .now() + 30) == .success)
        #expect(secondReadBeforeRelease == .timedOut)
        for outcome in outcomes.values {
            _ = try outcome.get()
        }

        let verifier = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try verifier.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        #expect(Set(try verifier.listFolders().map(\.name)) == ["First", "Second"])
    }

    @Test("a stale store merges a remote snapshot with the latest local disk revision")
    func staleRemoteMergePreservesLatestLocalDiskChange() throws {
        let localRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let remoteRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: localRoot)
            try? FileManager.default.removeItem(at: remoteRoot)
        }
        let active = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: localRoot))
        let stale = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: localRoot))
        try active.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        try stale.unlock(masterPassword: "shared password", rememberQuickUnlock: false)

        let latestFolder = try active.createFolder(name: "Latest")
        _ = try active.create(.init(
            folderID: latestFolder.id, title: "Latest Disk Entry", website: "",
            username: "latest", note: "", password: "latest-secret"
        ))

        let remote = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: remoteRoot))
        try remote.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        let remoteFolder = try remote.createFolder(name: "Remote")
        _ = try remote.create(.init(
            folderID: remoteFolder.id, title: "Remote Entry", website: "",
            username: "remote", note: "", password: "remote-secret"
        ))

        _ = try stale.mergeRemoteSnapshot(remote.encryptedSnapshot().data, remoteMasterPassword: nil)

        let verifier = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: localRoot))
        try verifier.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        #expect(Set(try verifier.listEntries().map(\.title)) == ["Latest Disk Entry", "Remote Entry"])
    }

    @Test("commit observers run outside the shared local transaction lock")
    func commitObserverCanReenterThroughAnotherStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        let second = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try first.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        try second.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        let outcomes = LockedReviewResults<Void>()
        let completed = DispatchSemaphore(value: 0)
        first.setCommitObserver { _ in
            outcomes.append(Result { _ = try second.createFolder(name: "Observer") })
        }

        Thread.detachNewThread {
            outcomes.append(Result { _ = try first.createFolder(name: "Primary") })
            completed.signal()
        }

        #expect(completed.wait(timeout: .now() + 30) == .success)
        for outcome in outcomes.values {
            _ = try outcome.get()
        }
        let verifier = KDBXPasswordVaultStore(localStorage: makeReviewLocalStorage(at: root))
        try verifier.unlock(masterPassword: "shared password", rememberQuickUnlock: false)
        #expect(Set(try verifier.listFolders().map(\.name)) == ["Primary", "Observer"])
    }

    @Test("same current content merges and deduplicates history from both sides")
    func mergerPreservesBothHistoriesForSameCurrentContent() throws {
        let folderID = UUID()
        let entryID = UUID()
        let shared = makeReviewEntry(id: entryID, title: "Shared History", modifiedAt: 5)
        let localEntry = makeReviewEntry(
            id: entryID, title: "Current", modifiedAt: 30,
            history: [shared, makeReviewEntry(id: entryID, title: "Local History", modifiedAt: 10)]
        )
        let remoteEntry = makeReviewEntry(
            id: entryID, title: "Current", modifiedAt: 40,
            history: [shared, makeReviewEntry(id: entryID, title: "Remote History", modifiedAt: 20)]
        )
        let local = makeReviewContent(groupID: folderID, modifiedAt: 30, entries: [localEntry])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 40, entries: [remoteEntry])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entry = try #require(result.content.database.root.group.groups.first?.entries.first)

        #expect(reviewTitle(entry) == "Current")
        #expect(entry.history.map(reviewTitle) == ["Shared History", "Local History", "Remote History"])
    }

    @Test("different current content retains both existing histories and the losing current version")
    func mergerPreservesBothHistoriesForDifferentContent() throws {
        let folderID = UUID()
        let entryID = UUID()
        let localEntry = makeReviewEntry(
            id: entryID, title: "New", modifiedAt: 50,
            history: [makeReviewEntry(id: entryID, title: "Local History", modifiedAt: 10)]
        )
        let remoteEntry = makeReviewEntry(
            id: entryID, title: "Old", modifiedAt: 40,
            history: [makeReviewEntry(id: entryID, title: "Remote History", modifiedAt: 20)]
        )
        let local = makeReviewContent(groupID: folderID, modifiedAt: 50, entries: [localEntry])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 40, entries: [remoteEntry])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entry = try #require(result.content.database.root.group.groups.first?.entries.first)

        #expect(reviewTitle(entry) == "New")
        #expect(Set(entry.history.map(reviewTitle)) == ["Local History", "Remote History", "Old"])
        #expect(entry.history.count == 3)
    }

    @Test("merged entry history keeps the ten most recent unique versions")
    func mergerCapsCombinedHistoryAtTen() throws {
        let folderID = UUID()
        let entryID = UUID()
        let localHistory = (15 ... 21).map {
            makeReviewEntry(id: entryID, title: "Local \($0)", modifiedAt: TimeInterval($0))
        }
        let remoteHistory = (1 ... 13).map {
            makeReviewEntry(id: entryID, title: "Remote \($0)", modifiedAt: TimeInterval($0))
        }
        let localEntry = makeReviewEntry(
            id: entryID, title: "Current", modifiedAt: 30, history: localHistory
        )
        let remoteEntry = makeReviewEntry(
            id: entryID, title: "Remote Current", modifiedAt: 14, history: remoteHistory
        )
        let local = makeReviewContent(groupID: folderID, modifiedAt: 30, entries: [localEntry])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 14, entries: [remoteEntry])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entry = try #require(result.content.database.root.group.groups.first?.entries.first)

        #expect(entry.history.count == 10)
        #expect(entry.history.map(reviewTitle) == [
            "Remote 12", "Remote 13", "Remote Current",
            "Local 15", "Local 16", "Local 17", "Local 18", "Local 19", "Local 20", "Local 21"
        ])
    }

    @Test("merge rebuilds the exact preferred entry UUID order")
    func mergerPreservesPreferredEntryOrder() throws {
        let folderID = UUID()
        let entries = (0 ..< 8).map {
            makeReviewEntry(id: UUID(), title: "Entry \($0)", modifiedAt: 20)
        }
        let localOnly = makeReviewEntry(id: UUID(), title: "Local Only", modifiedAt: 20)
        let local = makeReviewContent(groupID: folderID, modifiedAt: 20, entries: entries + [localOnly])
        let remote = makeReviewContent(groupID: folderID, modifiedAt: 20, entries: Array(entries.reversed()))

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let merged = try #require(result.content.database.root.group.groups.first?.entries)

        #expect(result.conflictCopyCount == 0)
        #expect(merged.map(\.uuid) == Array(entries.reversed()).map(\.uuid) + [localOnly.uuid])
    }
}

private func makeReviewLocalStorage(at root: URL) -> FilePasswordVaultLocalStorage {
    let directory = root.appendingPathComponent("PasswordVault", isDirectory: true)
    return FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
        directoryURL: directory,
        vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
        backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
        metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
    ))
}

private func makeReviewContent(
    groupID: UUID,
    modifiedAt: TimeInterval,
    entries: [KDBX.Entry]
) -> KDBXContent {
    var content = KDBXContent.makeEmpty(databaseName: "Pastera", generator: "PasteraTests")
    var group = KDBX.Group(
        uuid: groupID,
        name: "Shared",
        times: .init(
            creationTime: Date(timeIntervalSince1970: modifiedAt),
            lastModificationTime: Date(timeIntervalSince1970: modifiedAt)
        ),
        isExpanded: true
    )
    group.entries = entries
    content.database.root.group.groups = [group]
    return content
}

private func makeReviewEntry(
    id: UUID,
    title: String,
    modifiedAt: TimeInterval,
    history: [KDBX.Entry] = []
) -> KDBX.Entry {
    var entry = KDBX.Entry(uuid: id)
    let date = Date(timeIntervalSince1970: modifiedAt)
    entry.times = .init(creationTime: date, lastModificationTime: date)
    entry.strings = [
        .init(key: "Title", value: .regular(title)),
        .init(key: "Password", value: .protectedInMemory("fixture-secret"))
    ]
    entry.history = history
    return entry
}

private func reviewTitle(_ entry: KDBX.Entry) -> String {
    entry.strings.first(where: { $0.key == "Title" })?.value.revealedString ?? ""
}

private final class LockedReviewResults<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [Result<Value, Error>]()

    var values: [Result<Value, Error>] {
        lock.withLock { storage }
    }

    func append(_ result: Result<Value, Error>) {
        lock.withLock { storage.append(result) }
    }
}

private final class CoordinatedReviewLocalStorage: PasswordVaultLocalStoring, @unchecked Sendable {
    let paths: PasswordVaultLocalPaths

    private let backing: FilePasswordVaultLocalStorage
    private let coordinationLock = NSLock()
    private var nextReadObserver: (() -> Void)?
    private var nextWriteBarrier: (entered: DispatchSemaphore, release: DispatchSemaphore)?

    init(backing: FilePasswordVaultLocalStorage) {
        self.backing = backing
        paths = backing.paths
    }

    func observeNextRead(_ observer: @escaping () -> Void) {
        coordinationLock.withLock { nextReadObserver = observer }
    }

    func blockNextWrite(entered: DispatchSemaphore, release: DispatchSemaphore) {
        coordinationLock.withLock { nextWriteBarrier = (entered, release) }
    }

    func containsVault() throws -> Bool {
        try backing.containsVault()
    }

    func withExclusiveTransaction<Value>(_ operation: () throws -> Value) throws -> Value {
        try backing.withExclusiveTransaction(operation)
    }

    func read() throws -> Data {
        let observer = coordinationLock.withLock {
            defer { nextReadObserver = nil }
            return nextReadObserver
        }
        observer?()
        return try backing.read()
    }

    func writeAtomically(_ data: Data) throws {
        let barrier = coordinationLock.withLock {
            defer { nextWriteBarrier = nil }
            return nextWriteBarrier
        }
        if let barrier {
            barrier.entered.signal()
            guard barrier.release.wait(timeout: .now() + 30) == .success else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try backing.writeAtomically(data)
    }

    func removeVaultCreatedByFailedMigration(expectedDigest: String) throws -> Bool {
        try backing.removeVaultCreatedByFailedMigration(expectedDigest: expectedDigest)
    }

    func readBackup() throws -> Data {
        try backing.readBackup()
    }
}
