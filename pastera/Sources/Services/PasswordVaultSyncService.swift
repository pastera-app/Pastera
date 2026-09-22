import Foundation

// The sync state machine and its transactional helpers intentionally remain co-located.
// swiftlint:disable file_length

protocol PasswordVaultSyncControlling: AnyObject {
    var snapshot: PasswordVaultSyncSnapshot { get }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID
    func removeObserver(_ identifier: UUID)
    func record(_ commit: PasswordVaultCommit)
    func synchronize(reason: SyncCoordinator.Reason)
    // swiftlint:disable inclusive_language
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    )
    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    )
    // swiftlint:enable inclusive_language
}

extension PasswordVaultSyncControlling {
    // swiftlint:disable inclusive_language
    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        completion(.failure(.remoteUnavailable))
    }
    // swiftlint:enable inclusive_language
}

final class PasswordVaultSyncService: PasswordVaultSyncControlling {
    typealias CallbackDispatcher = (@escaping () -> Void) -> Void

    private let access: PasswordVaultSyncAccess
    private let metadataStore: PasswordVaultSyncMetadataStoring
    private let cloudReplica: PasswordVaultCloudReplica
    private let processStatus: OneDriveProcessStatusServicing
    private let rootURLProvider: () -> URL?
    private let rootURLSetter: (URL) -> Void
    private let rootValidator: (URL) -> PasswordVaultSyncFailure?
    private let queue: DispatchQueue
    private let callbackDispatcher: CallbackDispatcher
    private let now: () -> Date

    private let stateLock = NSLock()
    private var metadata: PasswordVaultSyncMetadata
    private var currentSnapshot: PasswordVaultSyncSnapshot
    private var observers = [UUID: (PasswordVaultSyncSnapshot) -> Void]()
    private var hasQueuedSynchronization = false

    init(
        access: PasswordVaultSyncAccess,
        metadataStore: PasswordVaultSyncMetadataStoring,
        cloudReplica: PasswordVaultCloudReplica,
        processStatus: OneDriveProcessStatusServicing,
        rootURLProvider: @escaping () -> URL?,
        rootURLSetter: @escaping (URL) -> Void,
        rootValidator: @escaping (URL) -> PasswordVaultSyncFailure?,
        queue: DispatchQueue = DispatchQueue(label: "com.pastera.password-vault-sync"),
        callbackDispatcher: CallbackDispatcher? = nil,
        now: @escaping () -> Date = Date.init
    ) throws {
        let metadata = try metadataStore.load()
        self.access = access
        self.metadataStore = metadataStore
        self.cloudReplica = cloudReplica
        self.processStatus = processStatus
        self.rootURLProvider = rootURLProvider
        self.rootURLSetter = rootURLSetter
        self.rootValidator = rootValidator
        self.queue = queue
        self.callbackDispatcher = callbackDispatcher ?? { callback in
            DispatchQueue.main.async(execute: callback)
        }
        self.now = now
        self.metadata = metadata
        self.currentSnapshot = Self.makeSnapshot(
            metadata: metadata,
            phase: metadata.mode == .localOnly ? .disabled : .syncing(.checking),
            localVaultAvailable: Self.isLocalVaultAvailable(access.state),
            remoteVaultAvailable: nil
        )
    }

    var snapshot: PasswordVaultSyncSnapshot {
        stateLock.withLock { currentSnapshot }
    }
}

extension PasswordVaultSyncService {
    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        let initialSnapshot = stateLock.withLock {
            observers[identifier] = observer
            return currentSnapshot
        }
        callbackDispatcher { observer(initialSnapshot) }
        return identifier
    }

    func removeObserver(_ identifier: UUID) {
        stateLock.withLock { observers.removeValue(forKey: identifier) }
    }

    func record(_ commit: PasswordVaultCommit) {
        queue.async { [weak self] in
            self?.recordOnQueue(commit)
        }
    }

    func synchronize(reason: SyncCoordinator.Reason) {
        let shouldEnqueue = stateLock.withLock {
            guard !hasQueuedSynchronization else { return false }
            hasQueuedSynchronization = true
            return true
        }
        guard shouldEnqueue else { return }
        queue.async { [weak self] in
            guard let self else { return }
            // Keep at most one follow-up while cloud I/O occupies the shared vault queue.
            self.stateLock.withLock { self.hasQueuedSynchronization = false }
            self.synchronizeOnQueue(remotePassword: nil, completion: nil)
        }
    }

    // swiftlint:disable inclusive_language
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            if let failure = self.rootValidator(rootURL) {
                self.complete(.failure(failure), completion: completion)
                return
            }
            self.rootURLSetter(rootURL)
            var candidate = self.metadata
            candidate.mode = .oneDrive
            candidate.lastFailure = nil
            do {
                try self.save(candidate)
            } catch {
                self.complete(.failure(.remoteWriteFailed), completion: completion)
                return
            }
            self.publish(phase: .syncing(.checking), remoteVaultAvailable: nil)
            self.synchronizeOnQueue(
                remotePassword: remoteMasterPassword,
                completion: completion
            )
        }
    }
    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        queue.async { [weak self] in
            self?.synchronizeOnQueue(
                remotePassword: remoteMasterPassword,
                completion: completion
            )
        }
    }
    // swiftlint:enable inclusive_language

}

private extension PasswordVaultSyncService {
    private func recordOnQueue(_ commit: PasswordVaultCommit) {
        var candidate: PasswordVaultSyncMetadata
        if commit.origin == .migration {
            guard let persisted = try? metadataStore.load() else { return }
            candidate = persisted
        } else {
            candidate = metadata
        }
        switch commit.origin {
        case .userMutation:
            candidate.localRevision &+= 1
            if candidate.mode == .oneDrive {
                candidate.pendingChangeCount += 1
            }
        case .syncMerge where candidate.pendingMergedRemoteDigest != nil:
            break
        case .syncMerge, .migration:
            candidate.lastSyncedLocalDigest = commit.encryptedDigest
        }
        do {
            try save(candidate)
            publishCurrentState()
        } catch {
            return
        }
    }

    private func synchronizeOnQueue(
        remotePassword: String?,
        completion: ((Result<Void, PasswordVaultSyncFailure>) -> Void)?
    ) {
        guard metadata.mode == .oneDrive else {
            publish(phase: .disabled, remoteVaultAvailable: nil)
            completeIfPresent(.success(()), completion: completion)
            return
        }
        publish(phase: .syncing(.checking), remoteVaultAvailable: nil)
        let rootURL: URL
        do {
            rootURL = try resolvedRootURL()
        } catch {
            let failure = Self.syncFailure(from: error)
            fail(failure, remoteVaultAvailable: nil)
            completeIfPresent(.failure(failure), completion: completion)
            return
        }

        do {
            let local = try access.encryptedSnapshot()
            let remote = try cloudReplica.read(rootURL: rootURL)
            let localChanged = metadata.localRevision != metadata.lastSyncedLocalRevision
                || metadata.lastSyncedLocalDigest != local.digest
                || metadata.pendingChangeCount > 0
            let remoteChanged: Bool
            if let remote {
                remoteChanged = remote.digest != metadata.lastObservedRemoteDigest
            } else {
                remoteChanged = false
            }
            let remoteWasAlreadyMerged = metadata.pendingChangeCount > 0
                && metadata.pendingMergedRemoteDigest == remote?.digest
            let decision = remoteWasAlreadyMerged
                ? PasswordVaultSyncDecision.uploadLocal
                : passwordVaultSyncDecision(
                    localChanged: localChanged || remote == nil,
                    remoteChanged: remoteChanged
                )
            try apply(
                decision,
                local: local,
                remote: remote,
                rootURL: rootURL,
                remotePassword: remotePassword
            )
            completeIfPresent(.success(()), completion: completion)
        } catch {
            let failure = Self.syncFailure(from: error)
            fail(failure, remoteVaultAvailable: nil)
            completeIfPresent(.failure(failure), completion: completion)
        }
    }
    private func resolvedRootURL() throws -> URL {
        switch processStatus.currentStatus() {
        case .notInstalled:
            throw PasswordVaultSyncFailure.oneDriveNotInstalled
        case .notRunning:
            throw PasswordVaultSyncFailure.oneDriveNotRunning
        case .running:
            break
        }
        guard let rootURL = rootURLProvider() else {
            throw PasswordVaultSyncFailure.folderUnavailable
        }
        if let failure = rootValidator(rootURL) { throw failure }
        return rootURL
    }

    private func apply(
        _ decision: PasswordVaultSyncDecision,
        local: PasswordVaultEncryptedSnapshot,
        remote: PasswordVaultCloudSnapshot?,
        rootURL: URL,
        remotePassword: String?
    ) throws {
        switch decision {
        case .noChange:
            publish(phase: .synced, remoteVaultAvailable: remote != nil)
        case .uploadLocal:
            try upload(local, replacing: remote, rootURL: rootURL)
        case .applyRemote:
            guard let remote else {
                try upload(local, replacing: nil, rootURL: rootURL)
                return
            }
            try mergeRemote(
                remote,
                rootURL: rootURL,
                remotePassword: remotePassword,
                uploadMergedResult: false
            )
        case .mergeBoth:
            guard let remote else {
                try upload(local, replacing: nil, rootURL: rootURL)
                return
            }
            try mergeRemote(
                remote,
                rootURL: rootURL,
                remotePassword: remotePassword,
                uploadMergedResult: true
            )
        }
    }
    private func upload(
        _ local: PasswordVaultEncryptedSnapshot,
        replacing remote: PasswordVaultCloudSnapshot?,
        rootURL: URL
    ) throws {
        publish(phase: .syncing(.uploading), remoteVaultAvailable: remote != nil)
        let expectation: PasswordVaultRemoteExpectation = remote.map {
            .digest($0.digest)
        } ?? .absent
        let verifiedDigest = try cloudReplica.writeAtomically(
            local.data,
            rootURL: rootURL,
            expecting: expectation
        )
        publish(phase: .syncing(.verifying), remoteVaultAvailable: true)
        var candidate = metadata
        candidate.lastSyncedLocalRevision = candidate.localRevision
        candidate.lastSyncedLocalDigest = local.digest
        candidate.lastObservedRemoteDigest = verifiedDigest
        candidate.pendingMergedRemoteDigest = nil
        candidate.lastSyncAt = now()
        candidate.pendingChangeCount = 0
        candidate.lastFailure = nil
        try save(candidate)
        let phase: PasswordVaultSyncPhase = candidate.conflictCopyCount > 0
            ? .conflicts(candidate.conflictCopyCount)
            : .synced
        publish(phase: phase, remoteVaultAvailable: true)
    }

    private func mergeRemote(
        _ remote: PasswordVaultCloudSnapshot,
        rootURL: URL,
        remotePassword: String?,
        uploadMergedResult: Bool
    ) throws {
        guard access.state == .unlocked else {
            publish(phase: .waitingForUnlock, remoteVaultAvailable: true)
            return
        }
        publish(phase: .syncing(.downloading), remoteVaultAvailable: true)
        publish(phase: .syncing(.merging), remoteVaultAvailable: true)
        let application = try access.mergeRemoteSnapshot(
            remote.data,
            remoteMasterPassword: remotePassword
        )
        publish(phase: .syncing(.savingLocal), remoteVaultAvailable: true)

        if uploadMergedResult {
            var pending = metadata
            pending.pendingChangeCount = max(1, pending.pendingChangeCount)
            pending.pendingMergedRemoteDigest = remote.digest
            pending.conflictCopyCount += application.conflictCopyCount
            try save(pending)
            try upload(application.encryptedSnapshot, replacing: remote, rootURL: rootURL)
        } else {
            var candidate = metadata
            candidate.lastSyncedLocalRevision = candidate.localRevision
            candidate.lastSyncedLocalDigest = application.encryptedSnapshot.digest
            candidate.lastObservedRemoteDigest = remote.digest
            candidate.pendingMergedRemoteDigest = nil
            candidate.lastSyncAt = now()
            candidate.pendingChangeCount = 0
            candidate.conflictCopyCount += application.conflictCopyCount
            candidate.lastFailure = nil
            try save(candidate)
            let phase: PasswordVaultSyncPhase = candidate.conflictCopyCount > 0
                ? .conflicts(candidate.conflictCopyCount)
                : .synced
            publish(phase: phase, remoteVaultAvailable: true)
        }
    }
}

private extension PasswordVaultSyncService {
    private func save(_ candidate: PasswordVaultSyncMetadata) throws {
        try metadataStore.save(candidate)
        metadata = candidate
    }

    private func fail(
        _ failure: PasswordVaultSyncFailure,
        remoteVaultAvailable: Bool?
    ) {
        var candidate = metadata
        candidate.lastFailure = failure
        if (try? metadataStore.save(candidate)) != nil {
            metadata = candidate
        }
        let phase: PasswordVaultSyncPhase
        switch failure {
        case .oneDriveNotInstalled, .oneDriveNotRunning, .folderUnavailable, .folderNotWritable:
            phase = .disconnected(failure)
        default:
            phase = .failed(failure)
        }
        publish(phase: phase, remoteVaultAvailable: remoteVaultAvailable)
    }

    private func publishCurrentState() {
        let previous = snapshot
        publish(
            phase: metadata.mode == .localOnly ? .disabled : previous.phase,
            remoteVaultAvailable: previous.remoteVaultAvailable
        )
    }

    private func publish(
        phase: PasswordVaultSyncPhase,
        remoteVaultAvailable: Bool?
    ) {
        let next = Self.makeSnapshot(
            metadata: metadata,
            phase: phase,
            localVaultAvailable: Self.isLocalVaultAvailable(access.state),
            remoteVaultAvailable: remoteVaultAvailable
        )
        let callbacks = stateLock.withLock {
            currentSnapshot = next
            return Array(observers.values)
        }
        callbacks.forEach { observer in
            callbackDispatcher { observer(next) }
        }
    }

    private func complete(
        _ result: Result<Void, PasswordVaultSyncFailure>,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        callbackDispatcher { completion(result) }
    }

    private func completeIfPresent(
        _ result: Result<Void, PasswordVaultSyncFailure>,
        completion: ((Result<Void, PasswordVaultSyncFailure>) -> Void)?
    ) {
        guard let completion else { return }
        complete(result, completion: completion)
    }
}

private extension PasswordVaultSyncService {
    static func makeSnapshot(
        metadata: PasswordVaultSyncMetadata,
        phase: PasswordVaultSyncPhase,
        localVaultAvailable: Bool,
        remoteVaultAvailable: Bool?
    ) -> PasswordVaultSyncSnapshot {
        PasswordVaultSyncSnapshot(
            mode: metadata.mode,
            phase: phase,
            localVaultAvailable: localVaultAvailable,
            remoteVaultAvailable: remoteVaultAvailable,
            pendingChangeCount: metadata.mode == .oneDrive ? metadata.pendingChangeCount : 0,
            conflictCopyCount: metadata.conflictCopyCount,
            lastSyncAt: metadata.lastSyncAt
        )
    }

    static func isLocalVaultAvailable(_ state: PasswordVaultState) -> Bool {
        switch state {
        case .locked, .unlocking, .unlocked, .readOnlyWarning:
            return true
        case .notConfigured, .preparingLocalCopy, .localCopyUnavailable, .recoveryRequired, .failed:
            return false
        }
    }

    static func syncFailure(from error: Error) -> PasswordVaultSyncFailure {
        (error as? PasswordVaultSyncFailure) ?? .remoteWriteFailed
    }
}

// swiftlint:enable file_length
