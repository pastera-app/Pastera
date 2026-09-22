import Foundation
import Testing
@testable import Pastera

// Integration coverage mirrors the full sync state machine in one suite.
// swiftlint:disable file_length

@Suite("Password vault sync service", .serialized)
struct PasswordVaultSyncServiceTests {
    @Test("sync decision covers all local and remote change combinations")
    func syncDecisionMatrix() {
        #expect(passwordVaultSyncDecision(localChanged: false, remoteChanged: false) == .noChange)
        #expect(passwordVaultSyncDecision(localChanged: true, remoteChanged: false) == .uploadLocal)
        #expect(passwordVaultSyncDecision(localChanged: false, remoteChanged: true) == .applyRemote)
        #expect(passwordVaultSyncDecision(localChanged: true, remoteChanged: true) == .mergeBoth)
    }

    @Test("local-only mode is disabled and never inspects OneDrive")
    func localOnlyNeverTouchesCloud() throws {
        let fixture = try makeSyncServiceFixture()

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.mode == .localOnly)
        #expect(fixture.service.snapshot.phase == .disabled)
        #expect(fixture.processStatus.readCount == 0)
        #expect(fixture.root.urlReadCount == 0)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("offline OneDrive disconnects before resolving or reading its folder")
    func offlineOneDriveNeverTouchesCloud() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.processStatus.status = .notRunning(appURL: fixture.oneDriveAppURL)

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .disconnected(.oneDriveNotRunning))
        #expect(fixture.processStatus.readCount == 1)
        #expect(fixture.root.urlReadCount == 0)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("missing OneDrive reports installation failure without cloud access")
    func missingOneDriveNeverTouchesCloud() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.processStatus.status = .notInstalled

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .disconnected(.oneDriveNotInstalled))
        #expect(fixture.root.urlReadCount == 0)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("unavailable root fails before invoking the cloud replica")
    func unavailableRootNeverTouchesCloud() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.root.validationFailure = .folderUnavailable

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .disconnected(.folderUnavailable))
        #expect(fixture.root.validationCount == 1)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("user mutations accumulate revisions and only enabled sync accumulates pending changes")
    func userMutationsAccumulatePendingOnlyForOneDrive() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let enabled = try makeSyncServiceFixture(metadata: metadata)

        enabled.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "one"))
        enabled.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "two"))
        enabled.drain()

        #expect(enabled.metadata.value.localRevision == 2)
        #expect(enabled.metadata.value.pendingChangeCount == 2)
        #expect(enabled.service.snapshot.pendingChangeCount == 2)

        let localOnly = try makeSyncServiceFixture()
        localOnly.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "local"))
        localOnly.drain()
        #expect(localOnly.metadata.value.localRevision == 1)
        #expect(localOnly.metadata.value.pendingChangeCount == 0)
        #expect(localOnly.service.snapshot.pendingChangeCount == 0)
    }

    @Test("sync-merge and migration commits refresh the digest without adding pending work")
    func nonUserCommitsDoNotAddPendingChanges() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.pendingChangeCount = 2
        let fixture = try makeSyncServiceFixture(metadata: metadata)

        fixture.service.record(PasswordVaultCommit(origin: .syncMerge, encryptedDigest: "merged"))
        fixture.service.record(PasswordVaultCommit(origin: .migration, encryptedDigest: "migrated"))
        fixture.drain()

        #expect(fixture.metadata.value.localRevision == 0)
        #expect(fixture.metadata.value.pendingChangeCount == 2)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "migrated")
    }

    @Test("metadata save failure never publishes a revision that was not persisted")
    func recordSaveFailureIsNotPublished() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.metadata.saveError = SyncServiceFixtureError.metadataWrite

        fixture.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "lost"))
        fixture.drain()

        #expect(fixture.metadata.value.localRevision == 0)
        #expect(fixture.service.snapshot.pendingChangeCount == 0)
    }

    @Test("local upload uses absent CAS and publishes the required phase order")
    func localUploadCreatesRemoteWithCAS() throws {
        let localData = Data("local-encrypted".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 1
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: localData)
        var phases = [PasswordVaultSyncPhase]()
        let observer = fixture.service.addObserver { phases.append($0.phase) }
        phases.removeAll()

        fixture.service.synchronize(reason: .manual)
        fixture.drain()
        fixture.service.removeObserver(observer)

        #expect(fixture.cloud.writes.count == 1)
        #expect(fixture.cloud.writes.first?.expectation == .absent)
        #expect(fixture.cloud.writes.first?.data == localData)
        #expect(fixture.metadata.value.pendingChangeCount == 0)
        #expect(fixture.metadata.value.lastSyncedLocalRevision == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(localData))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(localData))
        #expect(phases == [.syncing(.checking), .syncing(.uploading), .syncing(.verifying), .synced])
    }

    @Test("an unchanged revision with a changed encrypted digest still uploads")
    func digestChangeCannotBeMissedByRevision() throws {
        let previous = Data("previous-encrypted".utf8)
        let current = Data("current-encrypted".utf8)
        let remote = Data("remote-encrypted".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(previous)
        metadata.lastObservedRemoteDigest = PasswordVaultDigest.hex(remote)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: current)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.writes.count == 1)
        #expect(fixture.cloud.writes.first?.expectation == .digest(PasswordVaultDigest.hex(remote)))
    }

    @Test("a missing remote is rebuilt even when the local digest already has a baseline")
    func missingRemoteCannotBeReportedAsSynced() throws {
        let local = Data("local-with-baseline".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.writes.count == 1)
        #expect(fixture.cloud.writes.first?.expectation == .absent)
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(local))
        #expect(fixture.service.snapshot.phase == .synced)
    }

    @Test("no changes do not write either side")
    func noChangesAreNoOp() throws {
        let local = Data("local".utf8)
        let remote = Data("remote".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = PasswordVaultDigest.hex(remote)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.service.snapshot.phase == .synced)
    }

    @Test("repeated sync requests waiting on the vault queue coalesce into one cloud read")
    func queuedSynchronizationsCoalesceIntoSingleRun() throws {
        let local = Data("unchanged-local".utf8)
        let remote = Data("unchanged-remote".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = PasswordVaultDigest.hex(remote)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.queue.suspend()
        for _ in 0..<20 {
            fixture.service.synchronize(reason: .manual)
        }
        fixture.queue.resume()
        fixture.drain()

        #expect(fixture.cloud.readCount == 1)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.service.snapshot.phase == .synced)
    }

    @Test("repeated requests during active sync retain only one follow-up cloud read")
    func activeSynchronizationsCoalesceIntoSingleFollowUp() throws {
        let local = Data("unchanged-local".utf8)
        let remote = Data("unchanged-remote".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = PasswordVaultDigest.hex(remote)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )
        var checkingNotifications = 0
        let observer = fixture.service.addObserver { snapshot in
            guard snapshot.phase == .syncing(.checking) else { return }
            checkingNotifications += 1
            // The first delivery is the initial snapshot; the next starts the first actual sync.
            guard checkingNotifications == 2 else { return }
            for _ in 0..<20 {
                fixture.service.synchronize(reason: .manual)
            }
        }
        defer { fixture.service.removeObserver(observer) }

        fixture.service.synchronize(reason: .manual)
        fixture.drain()
        // The active run may schedule its one follow-up behind the first queue barrier.
        fixture.drain()

        #expect(fixture.cloud.readCount == 2)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.service.snapshot.phase == .synced)
    }

    @Test("remote-only change waits for unlock without modifying either replica")
    func remoteChangeWaitsForUnlock() throws {
        let local = Data("local".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = "remote-old"
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .locked
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .waitingForUnlock)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
    }

    @Test("remote-only change merges locally when unlocked")
    func remoteChangeMergesWhenUnlocked() throws {
        let local = Data("local".utf8)
        let remote = Data("remote-new".utf8)
        let merged = Data("merged-local".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.conflictCopyCount = 2
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: merged,
                digest: PasswordVaultDigest.hex(merged)
            ),
            conflictCopyCount: 1
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 1)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(merged))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(remote))
        #expect(fixture.metadata.value.conflictCopyCount == 3)
        #expect(fixture.service.snapshot.phase == .conflicts(3))
    }
}

extension PasswordVaultSyncServiceTests {
    @Test("remote credential retry passes the password to one merge only")
    func remoteCredentialRetryIsOneShot() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )
        var result: Result<Void, PasswordVaultSyncFailure>?

        fixture.service.retry(remoteMasterPassword: "remote-only-secret") { result = $0 }
        fixture.drain()

        #expect(try result?.get() != nil)
        #expect(fixture.access.receivedRemotePasswords == ["remote-only-secret"])

        fixture.service.synchronize(reason: .manual)
        fixture.drain()
        #expect(fixture.access.receivedRemotePasswords == ["remote-only-secret"])
    }

    @Test("concurrent changes stay untouched while the local vault is locked")
    func concurrentChangesWaitForUnlock() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .locked
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .waitingForUnlock)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.pendingChangeCount == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
    }

    @Test("remote credentials failure preserves the unlocked local replica and pending work")
    func remoteCredentialsFailurePreservesLocalState() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeError = PasswordVaultSyncFailure.remoteCredentialsRequired
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .failed(.remoteCredentialsRequired))
        #expect(fixture.access.state == .unlocked)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.pendingChangeCount == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
    }

    @Test("enabling sync passes remote credentials only to the current merge")
    func enablingSyncPassesTransientRemoteCredentials() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        let merged = Data("merged".utf8)
        let fixture = try makeSyncServiceFixture(localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: merged,
                digest: PasswordVaultDigest.hex(merged)
            ),
            conflictCopyCount: 0
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )
        var completed = false

        fixture.service.enableOneDrive(
            rootURL: try #require(fixture.root.url),
            remoteMasterPassword: "ephemeral-remote-secret"
        ) { result in
            if case .success = result { completed = true }
        }
        fixture.drain()

        #expect(completed)
        #expect(fixture.access.receivedRemotePasswords.count == 1)
        #expect(fixture.access.receivedRemotePasswords[0] == "ephemeral-remote-secret")
        #expect(fixture.metadata.value.mode == .oneDrive)
        #expect(fixture.metadata.value.pendingChangeCount == 0)
    }

    @Test("cloud failure persists the merge marker and retries without merging twice")
    func mergeUploadFailureRetriesIdempotently() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        let merged = Data("merged".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: merged,
                digest: PasswordVaultDigest.hex(merged)
            ),
            conflictCopyCount: 1
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )
        fixture.cloud.writeError = .remoteVerificationFailed

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 1)
        #expect(fixture.cloud.writes.first?.expectation == .digest(PasswordVaultDigest.hex(remote)))
        #expect(fixture.metadata.value.pendingChangeCount >= 1)
        #expect(fixture.metadata.value.pendingMergedRemoteDigest == PasswordVaultDigest.hex(remote))
        #expect(fixture.metadata.value.conflictCopyCount == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
        #expect(fixture.service.snapshot.phase == .failed(.remoteVerificationFailed))

        fixture.service.record(PasswordVaultCommit(
            origin: .syncMerge,
            encryptedDigest: PasswordVaultDigest.hex(merged)
        ))
        fixture.drain()
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")

        fixture.cloud.writeError = nil
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 1)
        #expect(fixture.cloud.writes.count == 2)
        #expect(fixture.metadata.value.pendingMergedRemoteDigest == nil)
        #expect(fixture.metadata.value.pendingChangeCount == 0)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(merged))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(merged))
        #expect(fixture.metadata.value.conflictCopyCount == 1)
        #expect(fixture.service.snapshot.phase == .conflicts(1))
    }

    @Test("a newer remote digest after upload failure is merged before retrying")
    func changedRemoteAfterFailureIsMergedAgain() throws {
        let local = Data("local-new".utf8)
        let firstRemote = Data("remote-one".utf8)
        let secondRemote = Data("remote-two".utf8)
        let firstMerge = Data("merged-one".utf8)
        let secondMerge = Data("merged-two".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: firstMerge,
                digest: PasswordVaultDigest.hex(firstMerge)
            ),
            conflictCopyCount: 0
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: firstRemote,
            digest: PasswordVaultDigest.hex(firstRemote)
        )
        fixture.cloud.writeError = .remoteVerificationFailed

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: secondRemote,
            digest: PasswordVaultDigest.hex(secondRemote)
        )
        fixture.cloud.writeError = nil
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: secondMerge,
                digest: PasswordVaultDigest.hex(secondMerge)
            ),
            conflictCopyCount: 0
        )
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 2)
        #expect(fixture.cloud.writes.count == 2)
        #expect(fixture.cloud.writes.last?.expectation == .digest(PasswordVaultDigest.hex(secondRemote)))
        #expect(fixture.metadata.value.pendingMergedRemoteDigest == nil)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(secondMerge))
    }

    @Test("observer delivery uses the main thread by default")
    func observersUseMainThread() async throws {
        let fixture = try makeSyncServiceFixture(callbackDispatcher: nil)
        let deliveredOnMain = await withCheckedContinuation { continuation in
            _ = fixture.service.addObserver { _ in
                continuation.resume(returning: Thread.isMainThread)
            }
        }
        #expect(deliveredOnMain)
    }
}

// swiftlint:enable file_length
