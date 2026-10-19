import Foundation
import Testing
@testable import Pastera

@Suite("Password vault sync migration commits", .serialized)
struct PasswordVaultSyncMigrationCommitTests {
    @Test("migration commit reloads the metadata written by migration before publishing")
    func migrationCommitReloadsPersistedModeAndBaselines() throws {
        let fixture = try makeSyncServiceFixture()
        var migrated = PasswordVaultSyncMetadata.defaultLocalOnly
        migrated.mode = .oneDrive
        migrated.localRevision = 4
        migrated.lastSyncedLocalRevision = 4
        migrated.lastObservedRemoteDigest = "remote-baseline"
        migrated.migrationVersion = 1
        fixture.metadata.value = migrated

        fixture.service.record(PasswordVaultCommit(origin: .migration, encryptedDigest: "local-baseline"))
        fixture.drain()

        #expect(fixture.metadata.value.mode == .oneDrive)
        #expect(fixture.metadata.value.localRevision == 4)
        #expect(fixture.metadata.value.lastSyncedLocalRevision == 4)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-baseline")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-baseline")
        #expect(fixture.metadata.value.migrationVersion == 1)
        #expect(fixture.service.snapshot.mode == .oneDrive)
    }
}

@MainActor
@Suite("Password vault first connection", .serialized)
struct PasswordVaultFirstConnectionTests {
    @Test("enabling OneDrive on another Mac prepares the existing encrypted vault without replacing it")
    func enablingOneDriveImportsExistingVault() throws {
        let fixture = try FirstConnectionFixture()
        defer { fixture.remove() }
        let remoteData = try fixture.installRemoteVault()
        var completed = false

        fixture.service.enableOneDrive(rootURL: fixture.syncRoot, remoteMasterPassword: nil) { result in
            if case .success = result { completed = true }
        }
        fixture.drain()

        #expect(completed)
        #expect(fixture.store.state == .locked)
        #expect(fixture.controller.state == .locked)
        #expect(fixture.service.snapshot.localVaultAvailable)
        #expect(fixture.service.snapshot.phase == .synced)
        try #require(try fixture.storage.containsVault())
        #expect(try fixture.storage.read() == remoteData)
        #expect(try Data(contentsOf: fixture.remoteURL) == remoteData)
        #expect(try fixture.metadataStore.load().migrationVersion == 1)
        try fixture.store.unlock(masterPassword: "shared test master", rememberQuickUnlock: false)
        #expect(try fixture.store.listFolders().map(\.name) == ["From Other Mac"])
    }

    @Test("a cloud copy that becomes available after first connection is imported by the next sync")
    func unavailableCloudCopyCanRecoverWithoutRestart() throws {
        let fixture = try FirstConnectionFixture()
        defer { fixture.remove() }

        fixture.service.enableOneDrive(rootURL: fixture.syncRoot, remoteMasterPassword: nil) { _ in }
        fixture.drain()

        #expect(try !fixture.storage.containsVault())
        #expect(fixture.service.snapshot.mode == .oneDrive)
        #expect(fixture.store.state == .localCopyUnavailable(.oneDriveUnavailable))
        #expect(fixture.service.snapshot.phase == .failed(.remoteUnavailable))
        let remoteData = try fixture.installRemoteVault()

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.store.state == .locked)
        #expect(fixture.controller.state == .locked)
        #expect(fixture.service.snapshot.phase == .synced)
        try #require(try fixture.storage.containsVault())
        #expect(try fixture.storage.read() == remoteData)
        #expect(try Data(contentsOf: fixture.remoteURL) == remoteData)
    }

    @Test("an unavailable cloud download can retry on the next sync without restarting")
    func cloudDownloadFailureCanRecoverWithoutRestart() throws {
        let fixture = try FirstConnectionFixture()
        defer { fixture.remove() }
        let remoteData = try fixture.installRemoteVault()
        fixture.reader.isUnavailable = true

        fixture.service.enableOneDrive(rootURL: fixture.syncRoot, remoteMasterPassword: nil) { _ in }
        fixture.drain()

        #expect(try !fixture.storage.containsVault())
        #expect(fixture.store.state == .localCopyUnavailable(.oneDriveUnavailable))
        #expect(fixture.service.snapshot.phase == .failed(.remoteUnavailable))
        #expect(try Data(contentsOf: fixture.remoteURL) == remoteData)
        fixture.reader.isUnavailable = false

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.controller.state == .locked)
        #expect(fixture.service.snapshot.phase == .synced)
        try #require(try fixture.storage.containsVault())
        #expect(try fixture.storage.read() == remoteData)
    }

    @Test("a corrupt cloud copy fails first connection without creating local data or replacing the cloud file")
    func corruptCloudCopyIsPreservedForRecovery() throws {
        let fixture = try FirstConnectionFixture()
        defer { fixture.remove() }
        let corruptData = Data("not a KDBX vault".utf8)
        try FileManager.default.createDirectory(
            at: fixture.remoteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try corruptData.write(to: fixture.remoteURL)
        var failure: PasswordVaultSyncFailure?

        fixture.service.enableOneDrive(rootURL: fixture.syncRoot, remoteMasterPassword: nil) { result in
            if case let .failure(error) = result { failure = error }
        }
        fixture.drain()

        #expect(failure == .remoteCorrupted)
        #expect(fixture.store.state == .localCopyUnavailable(.remoteCorrupted))
        #expect(fixture.service.snapshot.phase == .failed(.remoteCorrupted))
        #expect(try !fixture.storage.containsVault())
        #expect(try Data(contentsOf: fixture.remoteURL) == corruptData)
    }

    @Test("first connection preserves an existing unlocked local vault while merging the cloud copy")
    func existingLocalVaultKeepsItsUnlockedSession() throws {
        let fixture = try FirstConnectionFixture(createLocalVault: true)
        defer { fixture.remove() }
        _ = try fixture.installRemoteVault()
        var completed = false

        fixture.service.enableOneDrive(rootURL: fixture.syncRoot, remoteMasterPassword: nil) { result in
            if case .success = result { completed = true }
        }
        fixture.drain()

        #expect(completed)
        #expect(fixture.store.state == .unlocked)
        #expect(fixture.service.snapshot.phase == .synced)
        #expect(Set(try fixture.store.listFolders().map(\.name)) == ["Local Work", "From Other Mac"])
        #expect(Set(try fixture.controller.folders().map(\.name)) == ["Local Work", "From Other Mac"])
        #expect(Set(try fixture.controller.entries().map(\.title)) == ["Local Entry", "Remote Entry"])
    }
}

private final class FirstConnectionFixture {
    let root: URL
    let syncRoot: URL
    let storage: FilePasswordVaultLocalStorage
    let metadataStore: JSONPasswordVaultSyncMetadataStore
    let store: KDBXPasswordVaultStore
    let service: PasswordVaultSyncService
    let controller: PasswordVaultUIController
    let reader = FirstConnectionLegacyReader()
    let queue = DispatchQueue(label: "PasswordVaultFirstConnectionTests")

    var remoteURL: URL { VaultFileCoordinator.vaultURL(for: syncRoot) }

    init(createLocalVault: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        syncRoot = root.appendingPathComponent("OneDrive", isDirectory: true)
        try FileManager.default.createDirectory(at: syncRoot, withIntermediateDirectories: true)
        storage = Self.makeStorage(at: root.appendingPathComponent("Local", isDirectory: true))
        metadataStore = JSONPasswordVaultSyncMetadataStore(url: storage.paths.metadataURL)
        store = KDBXPasswordVaultStore(localStorage: storage)
        if createLocalVault {
            try store.createDatabase(masterPassword: "shared test master", rememberQuickUnlock: false)
            let folder = try store.createFolder(name: "Local Work")
            _ = try store.create(.init(
                folderID: folder.id, title: "Local Entry", website: "", username: "",
                note: "", password: "local test secret"
            ))
        }
        let migrator = PasswordVaultMigrationService(
            localStorage: storage,
            metadataStore: metadataStore,
            legacySyncRootProvider: { [syncRoot] in syncRoot },
            legacyReader: reader
        )
        service = try PasswordVaultSyncService(
            access: store,
            metadataStore: metadataStore,
            cloudReplica: OneDrivePasswordVaultCloudReplica(),
            processStatus: FakeOneDriveProcessStatusService(),
            rootURLProvider: { [syncRoot] in syncRoot },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            prepareLocalCopy: { [store] in store.prepareLocalCopy(using: migrator) },
            queue: queue,
            callbackDispatcher: { $0() }
        )
        controller = PasswordVaultUIController(store: store, syncController: service, storeQueue: queue)
    }

    func installRemoteVault() throws -> Data {
        let source = KDBXPasswordVaultStore(
            localStorage: Self.makeStorage(at: root.appendingPathComponent("RemoteSource", isDirectory: true))
        )
        try source.createDatabase(masterPassword: "shared test master", rememberQuickUnlock: false)
        let folder = try source.createFolder(name: "From Other Mac")
        _ = try source.create(.init(
            folderID: folder.id, title: "Remote Entry", website: "", username: "",
            note: "", password: "remote test secret"
        ))
        let data = try source.encryptedSnapshot().data
        try FileManager.default.createDirectory(at: remoteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: remoteURL)
        return data
    }

    func drain() {
        queue.sync {}
        queue.sync {}
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func makeStorage(at directory: URL) -> FilePasswordVaultLocalStorage {
        FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
            directoryURL: directory,
            vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
            backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
            metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
        ))
    }
}

private final class FirstConnectionLegacyReader: PasswordVaultLegacyReading {
    var isUnavailable = false

    func readCompleteFile(at url: URL) throws -> Data {
        if isUnavailable { throw PasswordVaultLocalPreparationFailure.oneDriveUnavailable }
        return try CoordinatedPasswordVaultLegacyReader().readCompleteFile(at: url)
    }
}
