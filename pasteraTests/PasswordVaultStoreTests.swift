import Foundation
import KDBXKit
import LocalAuthentication
import Security
import Testing
@testable import Pastera

@Suite("Password vault store")
struct PasswordVaultStoreTests {
    @Test("password vault lifecycle exposes locked and recovery states")
    func passwordVaultLifecycleStatesAreStable() {
        let states: [PasswordVaultState] = [
            .notConfigured,
            .locked,
            .unlocking,
            .unlocked,
            .readOnlyWarning("conflict"),
            .failed("corrupted")
        ]

        #expect(states.count == 6)
        #expect(states[3] == .unlocked)
    }

    @Test("local vault remains fully usable without any OneDrive working path")
    func localVaultWorkflowDoesNotNeedOneDrive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let missingOneDriveRoot = root.appendingPathComponent("OneDrive-not-running", isDirectory: true)
        let localStorage = makeLocalStorage(at: root)
        let quickUnlock = InMemoryVaultUnlockKeyStore()
        let automationUnlock = InMemoryVaultAutomationUnlockKeyStore()
        let store = KDBXPasswordVaultStore(
            localStorage: localStorage,
            unlockKeyStore: quickUnlock,
            automationUnlockKeyStore: automationUnlock
        )

        try store.createDatabase(masterPassword: "local master", rememberQuickUnlock: true)
        try store.enableAutomationUnlock()
        let work = try store.createFolder(name: "Work")
        let archive = try store.createFolder(name: "Archive")
        let first = try store.create(.init(
            folderID: work.id,
            title: "Mail",
            website: "https://mail.example.com",
            username: "alice",
            note: "local-only",
            password: "secret-one"
        ))
        let second = try store.create(.init(
            folderID: work.id,
            title: "Chat",
            website: "",
            username: "alice",
            note: "",
            password: "secret-two"
        ))
        _ = try store.update(id: first.id, draft: .init(
            folderID: work.id,
            title: "Mail Updated",
            website: "https://mail.example.com",
            username: "alice",
            note: "saved locally",
            password: "secret-one-updated"
        ))
        try store.reorderFolders([archive.id, work.id])
        try store.moveEntry(id: second.id, to: archive.id)
        try store.delete(id: second.id, reason: "test")

        store.lock()
        try store.unlockWithQuickKey(reason: "test")
        store.lock()
        try store.unlockForAutomation()
        _ = try store.changeMasterPassword(
            currentPassword: "local master",
            newPassword: "new local master",
            keepQuickUnlockEnabled: true
        )
        store.lock()
        try store.unlock(masterPassword: "new local master", rememberQuickUnlock: false)

        #expect(try store.listFolders().map(\.id) == [archive.id, work.id])
        #expect(try store.listEntries().map(\.title) == ["Mail Updated"])
        #expect(try store.revealPassword(id: first.id, reason: "test") == "secret-one-updated")
        #expect(try localStorage.containsVault())
        #expect(!FileManager.default.fileExists(atPath: missingOneDriveRoot.path))
    }

    @Test("missing local KDBX is not a wrong-password failure")
    func missingLocalVaultReturnsNotConfigured() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: root))

        #expect(throws: PasswordVaultError.databaseNotConfigured) {
            try store.unlock(masterPassword: "anything", rememberQuickUnlock: false)
        }
        #expect(store.state == .notConfigured)
    }

    @Test("local storage inspection failure is a recovery state rather than not configured")
    func localStorageInspectionFailureIsFailClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("blocks-vault-directory".utf8).write(
            to: root.appendingPathComponent("PasswordVault")
        )

        let store = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: root))

        #expect(store.state == .localCopyUnavailable(.localWriteFailed))
    }

    @Test("only KDBX wrong credentials become wrong-master-password")
    func invalidCredentialsRequireReadableLocalKDBX() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: root))
        try store.createDatabase(masterPassword: "correct", rememberQuickUnlock: false)
        store.lock()

        #expect(throws: PasswordVaultError.wrongMasterPassword) {
            try store.unlock(masterPassword: "incorrect", rememberQuickUnlock: false)
        }
        #expect(store.state == .locked)
    }

    @Test("invalid signatures and malformed KDBX bodies are corrupted local data", arguments: [
        Data("not-a-kdbx".utf8),
        Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5, 0x00, 0x01])
    ])
    func corruptedLocalVaultIsNotWrongPassword(data: Data) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let localStorage = makeLocalStorage(at: root)
        try FileManager.default.createDirectory(at: localStorage.paths.directoryURL, withIntermediateDirectories: true)
        try data.write(to: localStorage.paths.vaultURL, options: .atomic)
        let store = KDBXPasswordVaultStore(localStorage: localStorage)

        #expect(throws: PasswordVaultError.corruptedData) {
            try store.unlock(masterPassword: "anything", rememberQuickUnlock: false)
        }
        #expect(store.state == .failed("corrupted"))
    }

    @Test("KDBX vault creates, locks, unlocks, and persists credentials")
    func kdbxVaultLifecycleRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: root))

        try store.createDatabase(masterPassword: "correct horse battery staple", rememberQuickUnlock: false)
        let folder = try store.createFolder(name: "Work")
        let entry = try store.create(PasswordVaultDraft(
            folderID: folder.id,
            title: "Mail",
            website: "https://mail.example.com",
            username: "alice",
            note: "Primary",
            password: "secret-value"
        ))
        #expect(try store.revealPassword(id: entry.id, reason: "test") == "secret-value")

        store.lock()
        #expect(store.state == .locked)
        #expect(throws: PasswordVaultError.vaultLocked) { try store.listEntries() }

        try store.unlock(masterPassword: "correct horse battery staple", rememberQuickUnlock: false)
        #expect(try store.listEntries().map(\.title) == ["Mail"])
        #expect(try store.revealPassword(id: entry.id, reason: "test") == "secret-value")
    }

    @Test("quick unlock stores only the 32 byte KDBX pre-hash")
    func quickUnlockStoresPreHash() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let keys = InMemoryVaultUnlockKeyStore()
        let store = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: root), unlockKeyStore: keys)

        try store.createDatabase(masterPassword: "correct horse battery staple", rememberQuickUnlock: true)
        #expect(keys.data?.count == 32)
        #expect(keys.data != Data("correct horse battery staple".utf8))

        store.lock()
        try store.unlockWithQuickKey(reason: "test")
        #expect(store.state == .unlocked)
    }

    @Test("automation key restores a locked KDBX without reading the interactive key")
    func automationKeyRestoresLockedStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let interactive = InMemoryVaultUnlockKeyStore()
        let automation = InMemoryVaultAutomationUnlockKeyStore()
        let store = KDBXPasswordVaultStore(
            localStorage: makeLocalStorage(at: root),
            unlockKeyStore: interactive,
            automationUnlockKeyStore: automation
        )

        try store.createDatabase(masterPassword: "master", rememberQuickUnlock: true)
        try store.enableAutomationUnlock()
        store.lock()
        try store.unlockForAutomation()

        #expect(store.state == .unlocked)
        #expect(interactive.loadCallCount == 0)
        #expect(automation.loadCallCount == 1)
    }

    @Test("malformed automation key fails safely while the vault stays locked")
    func malformedAutomationKeyFailsSafely() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = Data(repeating: 0x11, count: 31)
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
    }

    @Test("automation key is validated before reading a missing database")
    func automationKeyIsValidatedFirst() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = Data(repeating: 0x11, count: 31)
        try FileManager.default.removeItem(at: fixture.localStorage.paths.vaultURL)
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
    }

    @Test("a missing automation key fails safely while the vault stays locked")
    func missingAutomationKeyFailsSafely() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = nil
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
        #expect(!fixture.store.canAutomationUnlock)
    }

    @Test("wrong automation credential maps to unavailable and stays locked")
    func wrongAutomationCredentialFailsSafely() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = Data(repeating: 0x7F, count: 32)
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
    }

    @Test("disabling automation unlock preserves interactive quick unlock and current state")
    func disablingAutomationUnlockIsIsolated() throws {
        let fixture = try makeAutomationVault(rememberQuickUnlock: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try fixture.store.disableAutomationUnlock()

        #expect(fixture.store.state == .unlocked)
        #expect(fixture.interactive.containsKey)
        #expect(!fixture.automation.containsKey)
        #expect(fixture.automation.deleteCallCount == 1)
    }

    @Test("automation unlock preserves not-configured and corrupted database errors")
    func automationUnlockPreservesDatabaseErrors() throws {
        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        let absent = KDBXPasswordVaultStore(
            localStorage: makeLocalStorage(at: emptyRoot),
            automationUnlockKeyStore: InMemoryVaultAutomationUnlockKeyStore(data: Data(repeating: 1, count: 32))
        )
        #expect(throws: PasswordVaultError.databaseNotConfigured) {
            try absent.unlockForAutomation()
        }
        #expect(absent.state == .notConfigured)

        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("not-a-kdbx".utf8).write(to: fixture.localStorage.paths.vaultURL, options: .atomic)
        fixture.store.lock()
        #expect(throws: PasswordVaultError.corruptedData) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .failed("corrupted"))
    }

    @Test("quick-unlock availability lookup cannot present authentication UI")
    func quickUnlockAvailabilityQuerySuppressesAuthenticationUI() {
        let query = VaultUnlockKeyStore.availabilityQuery

        let context = query[kSecUseAuthenticationContext as String] as? LAContext
        #expect(context?.interactionNotAllowed == true)
        #expect(query[kSecReturnData as String] == nil)
    }

    @Test("a local quick-unlock Keychain failure does not block the KDBX database")
    func quickUnlockFailureDoesNotBlockDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(
            localStorage: makeLocalStorage(at: root),
            unlockKeyStore: FailingVaultUnlockKeyStore()
        )

        try store.createDatabase(masterPassword: "correct horse battery staple", rememberQuickUnlock: true)

        #expect(store.state == .unlocked)
        #expect(FileManager.default.fileExists(atPath: makeLocalStorage(at: root).paths.vaultURL.path))
        #expect(try store.listEntries().isEmpty)
    }

    @Test("encrypted snapshots work while locked and commits expose only origin and digest")
    func encryptedSnapshotsAndAnonymousCommits() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: root))
        var commits = [PasswordVaultCommit]()
        store.setCommitObserver { commits.append($0) }

        try store.createDatabase(masterPassword: "master", rememberQuickUnlock: false)
        let folder = try store.createFolder(name: "Private Folder")
        _ = try store.create(.init(
            folderID: folder.id,
            title: "Private Title",
            website: "https://private.example.com",
            username: "private-user",
            note: "private-note",
            password: "private-password"
        ))
        store.lock()
        let snapshot = try store.encryptedSnapshot()

        #expect(commits.count == 3)
        #expect(commits.allSatisfy { $0.origin == .userMutation })
        #expect(commits.last?.encryptedDigest == snapshot.digest)
        let labels = Set(Mirror(reflecting: try #require(commits.last)).children.compactMap(\.label))
        #expect(labels == ["origin", "encryptedDigest"])
        #expect(!String(describing: commits).contains("Private Title"))
        #expect(PasswordVaultDigest.hex(snapshot.data) == snapshot.digest)
    }

    @Test("remote password is single-use and merge commits use the sync origin")
    func remotePasswordMergeStaysInSyncDomain() throws {
        let localRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let remoteRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: localRoot)
            try? FileManager.default.removeItem(at: remoteRoot)
        }
        let local = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: localRoot))
        try local.createDatabase(masterPassword: "local password", rememberQuickUnlock: false)
        let localFolder = try local.createFolder(name: "Local")
        _ = try local.create(.init(
            folderID: localFolder.id,
            title: "Local Entry",
            website: "",
            username: "local",
            note: "",
            password: "local secret"
        ))
        let before = try local.encryptedSnapshot()

        let remote = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: remoteRoot))
        try remote.createDatabase(masterPassword: "remote password", rememberQuickUnlock: false)
        let remoteFolder = try remote.createFolder(name: "Remote")
        _ = try remote.create(.init(
            folderID: remoteFolder.id,
            title: "Remote Entry",
            website: "",
            username: "remote",
            note: "",
            password: "remote secret"
        ))
        let remoteSnapshot = try remote.encryptedSnapshot()

        #expect(throws: PasswordVaultSyncFailure.remoteCredentialsRequired) {
            try local.mergeRemoteSnapshot(remoteSnapshot.data, remoteMasterPassword: nil)
        }
        #expect(throws: PasswordVaultSyncFailure.remoteCredentialsRequired) {
            try local.mergeRemoteSnapshot(remoteSnapshot.data, remoteMasterPassword: "wrong remote password")
        }
        #expect(local.state == .unlocked)
        #expect(try local.encryptedSnapshot().digest == before.digest)

        var commits = [PasswordVaultCommit]()
        local.setCommitObserver { commits.append($0) }
        let application = try local.mergeRemoteSnapshot(
            remoteSnapshot.data,
            remoteMasterPassword: "remote password"
        )

        #expect(Set(try local.listEntries().map(\.title)) == ["Local Entry", "Remote Entry"])
        #expect(application.conflictCopyCount == 0)
        #expect(commits == [PasswordVaultCommit(
            origin: .syncMerge,
            encryptedDigest: application.encryptedSnapshot.digest
        )])
        #expect(canOpenKDBX(application.encryptedSnapshot.data, password: "local password"))
        #expect(!canOpenKDBX(application.encryptedSnapshot.data, password: "remote password"))
        local.lock()
        try local.unlock(masterPassword: "local password", rememberQuickUnlock: false)
        #expect(throws: PasswordVaultError.wrongMasterPassword) {
            try local.unlock(masterPassword: "remote password", rememberQuickUnlock: false)
        }
    }
}

extension PasswordVaultStoreTests {
    @Test("merger keeps distinct folder and entry UUIDs")
    func mergerKeepsDistinctUUIDs() {
        let localFolderID = UUID()
        let remoteFolderID = UUID()
        let localEntryID = UUID()
        let remoteEntryID = UUID()
        let local = makeKDBXContent(groups: [
            makeKDBXGroup(
                id: localFolderID,
                name: "Local",
                modifiedAt: Date(timeIntervalSince1970: 20),
                entries: [makeKDBXEntry(id: localEntryID, title: "Local", modifiedAt: Date(timeIntervalSince1970: 20))]
            )
        ])
        let remote = makeKDBXContent(groups: [
            makeKDBXGroup(
                id: remoteFolderID,
                name: "Remote",
                modifiedAt: Date(timeIntervalSince1970: 30),
                entries: [makeKDBXEntry(id: remoteEntryID, title: "Remote", modifiedAt: Date(timeIntervalSince1970: 30))]
            )
        ])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)

        #expect(Set(result.content.database.root.group.groups.map(\.uuid)) == [localFolderID, remoteFolderID])
        #expect(Set(result.content.database.root.group.groups.flatMap(\.entries).map(\.uuid)) == [localEntryID, remoteEntryID])
        #expect(result.conflictCopyCount == 0)
    }

    @Test("folder UUID identity keeps the newer folder metadata")
    func mergerUsesFolderUUIDAndModificationTime() throws {
        let folderID = UUID()
        let local = makeKDBXContent(groups: [
            makeKDBXGroup(id: folderID, name: "New Name", modifiedAt: Date(timeIntervalSince1970: 20))
        ])
        let remote = makeKDBXContent(groups: [
            makeKDBXGroup(id: folderID, name: "Old Name", modifiedAt: Date(timeIntervalSince1970: 10))
        ])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)

        let folder = try #require(result.content.database.root.group.groups.first)
        #expect(result.content.database.root.group.groups.count == 1)
        #expect(folder.uuid == folderID)
        #expect(folder.name == "New Name")
    }

    @Test("newer entry wins while the older version enters KDBX history")
    func mergerPreservesOlderEntryInHistory() throws {
        let folderID = UUID()
        let entryID = UUID()
        let local = makeKDBXContent(groups: [makeKDBXGroup(
            id: folderID,
            name: "Shared",
            modifiedAt: Date(timeIntervalSince1970: 20),
            entries: [makeKDBXEntry(id: entryID, title: "New", modifiedAt: Date(timeIntervalSince1970: 20))]
        )])
        let remote = makeKDBXContent(groups: [makeKDBXGroup(
            id: folderID,
            name: "Shared",
            modifiedAt: Date(timeIntervalSince1970: 10),
            entries: [makeKDBXEntry(id: entryID, title: "Old", modifiedAt: Date(timeIntervalSince1970: 10))]
        )])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entry = try #require(result.content.database.root.group.groups.first?.entries.first)

        #expect(kdbxTitle(entry) == "New")
        #expect(entry.uuid == entryID)
        #expect(entry.history.map(kdbxTitle) == ["Old"])
        #expect(result.conflictCopyCount == 0)
    }

    @Test("same-time content conflicts count every generated conflict copy")
    func mergerCountsConflictCopies() {
        let folderID = UUID()
        let modifiedAt = Date(timeIntervalSince1970: 20)
        let firstID = UUID()
        let secondID = UUID()
        let local = makeKDBXContent(groups: [makeKDBXGroup(
            id: folderID,
            name: "Shared",
            modifiedAt: modifiedAt,
            entries: [
                makeKDBXEntry(id: firstID, title: "Local One", modifiedAt: modifiedAt),
                makeKDBXEntry(id: secondID, title: "Local Two", modifiedAt: modifiedAt)
            ]
        )])
        let remote = makeKDBXContent(groups: [makeKDBXGroup(
            id: folderID,
            name: "Shared",
            modifiedAt: modifiedAt,
            entries: [
                makeKDBXEntry(id: firstID, title: "Remote One", modifiedAt: modifiedAt),
                makeKDBXEntry(id: secondID, title: "Remote Two", modifiedAt: modifiedAt)
            ]
        )])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entries = result.content.database.root.group.groups.flatMap(\.entries)

        #expect(result.conflictCopyCount == 2)
        #expect(entries.count == 4)
        #expect(entries.filter { kdbxTitle($0).contains("Conflict") }.count == 2)
    }

    @Test("sorting differences never generate conflict copies")
    func mergerIgnoresOrderingDifferences() {
        let folderID = UUID()
        let modifiedAt = Date(timeIntervalSince1970: 20)
        let first = makeKDBXEntry(id: UUID(), title: "First", modifiedAt: modifiedAt)
        let second = makeKDBXEntry(id: UUID(), title: "Second", modifiedAt: modifiedAt)
        let local = makeKDBXContent(groups: [makeKDBXGroup(
            id: folderID,
            name: "Shared",
            modifiedAt: modifiedAt,
            entries: [first, second]
        )])
        let remote = makeKDBXContent(groups: [makeKDBXGroup(
            id: folderID,
            name: "Shared",
            modifiedAt: modifiedAt,
            entries: [second, first]
        )])

        let result = KDBXVaultMerger().merge(local: local, remote: remote)

        #expect(result.conflictCopyCount == 0)
        #expect(Set(result.content.database.root.group.groups.flatMap(\.entries).map(\.uuid)) == [first.uuid, second.uuid])
    }

    @Test("older tombstones preserve newer entries")
    func mergerAppliesOnlyLaterTombstones() {
        let folderID = UUID()
        let deletedEntryID = UUID()
        let survivingEntryID = UUID()
        let local = makeKDBXContent(groups: [makeKDBXGroup(
            id: folderID,
            name: "Shared",
            modifiedAt: Date(timeIntervalSince1970: 20),
            entries: [
                makeKDBXEntry(id: deletedEntryID, title: "Deleted", modifiedAt: Date(timeIntervalSince1970: 20)),
                makeKDBXEntry(id: survivingEntryID, title: "Survives", modifiedAt: Date(timeIntervalSince1970: 20))
            ]
        )])
        let remote = makeKDBXContent(
            groups: [makeKDBXGroup(id: folderID, name: "Shared", modifiedAt: Date(timeIntervalSince1970: 20))],
            deletedObjects: [
                .init(uuid: deletedEntryID, deletionTime: Date(timeIntervalSince1970: 30)),
                .init(uuid: survivingEntryID, deletionTime: Date(timeIntervalSince1970: 10))
            ]
        )

        let result = KDBXVaultMerger().merge(local: local, remote: remote)
        let entryIDs = Set(result.content.database.root.group.groups.flatMap(\.entries).map(\.uuid))

        #expect(entryIDs == [survivingEntryID])
    }
}

extension PasswordVaultStoreTests {
    @Test("legacy entries migrate into the unfiled folder")
    func legacyEntriesMigrateIntoUnfiledFolder() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        let legacyID = UUID()
        client.metadata = try JSONEncoder().encode([
            LegacyPasswordVaultEntryFixture(
                id: legacyID,
                title: "Mail",
                website: "mail.example.com",
                username: "alice",
                note: "",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        ])
        let store = KeychainPasswordVaultStore(client: client)

        let folders = try store.listFolders()
        let entries = try store.listEntries()

        #expect(folders.count == 1)
        #expect(folders[0].name == "Unfiled")
        #expect(entries.count == 1)
        #expect(entries[0].id == legacyID)
        #expect(entries[0].folderID == folders[0].id)
        let savedMetadata = try #require(client.metadata)
        #expect(try JSONDecoder().decode(PasswordVaultMetadata.self, from: savedMetadata).version == 2)
    }

    @Test("legacy Keychain folders protect contained passwords from deletion")
    func folderLifecycleProtectsContainedPasswords() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        let store = KeychainPasswordVaultStore(client: client)
        let folder = try store.createFolder(name: "Work")
        _ = try store.create(PasswordVaultDraft(
            folderID: folder.id,
            title: "Mail",
            website: "",
            username: "alice",
            note: "",
            password: "secret-value"
        ))

        #expect(throws: PasswordVaultError.folderNotEmpty) {
            try store.deleteFolder(id: folder.id)
        }
        let archive = try store.createFolder(name: "Archive")
        let entry = try #require(store.listEntries().first)
        try store.moveEntry(id: entry.id, to: archive.id)
        try store.deleteFolder(id: folder.id)

        #expect(try store.listFolders().map(\.name) == ["Archive"])
    }

    @Test("manual folder and entry order persists in Keychain metadata")
    func keychainStorePersistsManualOrder() throws {
        let store = KeychainPasswordVaultStore(client: InMemoryPasswordVaultKeychainClient())
        try assertManualOrderPersists(in: store)
    }

    @Test("manual folder and entry order persists in KDBX")
    func kdbxStorePersistsManualOrder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(localStorage: makeLocalStorage(at: root))
        try store.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)

        try assertManualOrderPersists(in: store)
    }

    private func assertManualOrderPersists(in store: PasswordVaultStore) throws {
        let work = try store.createFolder(name: "Work")
        let archive = try store.createFolder(name: "Archive")
        let first = try store.create(.init(
            folderID: work.id, title: "First", website: "", username: "a", note: "", password: "1"
        ))
        let second = try store.create(.init(
            folderID: work.id, title: "Second", website: "", username: "b", note: "", password: "2"
        ))
        let archived = try store.create(.init(
            folderID: archive.id, title: "Archived", website: "", username: "c", note: "", password: "3"
        ))

        try store.reorderFolders([archive.id, work.id])
        #expect(try store.listFolders().map(\.id) == [archive.id, work.id])

        try store.moveEntry(
            id: second.id,
            to: archive.id,
            orderedEntryIDsByFolder: [
                work.id: [first.id],
                archive.id: [second.id, archived.id]
            ]
        )
        #expect(try store.listEntries().filter { $0.folderID == work.id }.map(\.id) == [first.id])
        #expect(try store.listEntries().filter { $0.folderID == archive.id }.map(\.id) == [second.id, archived.id])
    }

    @Test("metadata search excludes secrets")
    func metadataSearchExcludesSecrets() throws {
        let entry = PasswordVaultEntry(
            id: UUID(),
            folderID: UUID(),
            title: "Production",
            website: "https://example.com",
            username: "alice",
            note: "Primary account",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        #expect(entry.matches("example"))
        #expect(entry.matches("ALICE"))
        #expect(!entry.matches("secret-value"))
    }

    @Test("encrypted vault digests use lowercase SHA-256")
    func encryptedVaultDigestUsesSHA256() {
        let data = Data("abc".utf8)

        #expect(PasswordVaultDigest.hex(data) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(PasswordVaultEncryptedSnapshot(data: data, digest: PasswordVaultDigest.hex(data)).data == data)
        #expect(PasswordVaultCommit(origin: .userMutation, encryptedDigest: PasswordVaultDigest.hex(data)).origin == .userMutation)
    }

    @Test("secret query is local-only and requires user presence")
    func secretQueryUsesProtectedLocalKeychainItem() throws {
        let id = UUID()
        let query = try KeychainPasswordVaultStore.secretAddQuery(
            id: id,
            secret: Data("secret-value".utf8)
        )

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == KeychainPasswordVaultStore.secretService)
        #expect(query[kSecAttrAccount as String] as? String == id.uuidString)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecValueData as String] as? Data == Data("secret-value".utf8))
        #expect(query[kSecAttrAccessControl as String] != nil)
    }

    @Test("metadata round-trips without a database")
    func metadataRoundTripsThroughKeychainClient() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        let store = KeychainPasswordVaultStore(client: client, now: { Date(timeIntervalSince1970: 100) })
        let draft = PasswordVaultDraft(
            folderID: nil,
            title: "Mail",
            website: "https://mail.example.com",
            username: "alice",
            note: "Work",
            password: "secret-value"
        )

        let created = try store.create(draft)
        let listed = try store.listEntries()

        #expect(listed == [created])
        #expect(client.secret(for: created.id) == "secret-value")
    }

    @Test("failed secret creation does not leave metadata")
    func failedSecretCreationRollsBackMetadata() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        client.nextSecretWriteError = PasswordVaultError.keychainUnavailable
        let store = KeychainPasswordVaultStore(client: client)

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try store.create(PasswordVaultDraft(
                folderID: nil,
                title: "Mail",
                website: "",
                username: "alice",
                note: "",
                password: "secret-value"
            ))
        }
        #expect(try store.listEntries().isEmpty)
    }
}

private struct AutomationVaultFixture {
    let root: URL
    let localStorage: FilePasswordVaultLocalStorage
    let store: KDBXPasswordVaultStore
    let interactive: InMemoryVaultUnlockKeyStore
    let automation: InMemoryVaultAutomationUnlockKeyStore
}

private func makeLocalStorage(at root: URL) -> FilePasswordVaultLocalStorage {
    let directory = root.appendingPathComponent("PasswordVault", isDirectory: true)
    return FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
        directoryURL: directory,
        vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
        backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
        metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
    ))
}

private func makeAutomationVault(
    rememberQuickUnlock: Bool = false
) throws -> AutomationVaultFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let interactive = InMemoryVaultUnlockKeyStore()
    let automation = InMemoryVaultAutomationUnlockKeyStore()
    let localStorage = makeLocalStorage(at: root)
    let store = KDBXPasswordVaultStore(
        localStorage: localStorage,
        unlockKeyStore: interactive,
        automationUnlockKeyStore: automation
    )
    try store.createDatabase(masterPassword: "master", rememberQuickUnlock: rememberQuickUnlock)
    try store.enableAutomationUnlock()
    return AutomationVaultFixture(
        root: root,
        localStorage: localStorage,
        store: store,
        interactive: interactive,
        automation: automation
    )
}

private func makeKDBXContent(
    groups: [KDBX.Group],
    deletedObjects: [KDBX.DeletedObject] = []
) -> KDBXContent {
    var content = KDBXContent.makeEmpty(databaseName: "Pastera", generator: "PasteraTests")
    content.database.root.group.groups = groups
    content.database.root.deletedObjects = deletedObjects
    return content
}

private func makeKDBXGroup(
    id: UUID,
    name: String,
    modifiedAt: Date,
    entries: [KDBX.Entry] = []
) -> KDBX.Group {
    var group = KDBX.Group(
        uuid: id,
        name: name,
        times: .init(creationTime: modifiedAt, lastModificationTime: modifiedAt),
        isExpanded: true
    )
    group.entries = entries
    return group
}

private func makeKDBXEntry(id: UUID, title: String, modifiedAt: Date) -> KDBX.Entry {
    var entry = KDBX.Entry(uuid: id)
    entry.times = .init(creationTime: modifiedAt, lastModificationTime: modifiedAt)
    entry.strings = [
        .init(key: "Title", value: .regular(title)),
        .init(key: "Password", value: .protectedInMemory("fixture-secret"))
    ]
    return entry
}

private func kdbxTitle(_ entry: KDBX.Entry) -> String {
    entry.strings.first(where: { $0.key == "Title" })?.value.revealedString ?? ""
}

private func canOpenKDBX(_ data: Data, password: String) -> Bool {
    do {
        _ = try KDBXReader.parse(data, unlockData: UnlockData(masterPassword: password))
        return true
    } catch {
        return false
    }
}

private final class InMemoryVaultUnlockKeyStore: VaultUnlockKeyStoring {
    var data: Data?
    private(set) var loadCallCount = 0
    var containsKey: Bool { data != nil }

    func save(_ data: Data) throws { self.data = data }
    func load(reason: String) throws -> Data {
        loadCallCount += 1
        return try #require(data)
    }
    func delete() throws { data = nil }
}

private final class InMemoryVaultAutomationUnlockKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    private(set) var loadCallCount = 0
    private(set) var deleteCallCount = 0
    var containsKey: Bool { data != nil }

    init(data: Data? = nil) {
        self.data = data
    }

    func save(_ data: Data) throws { self.data = data }
    func load() throws -> Data {
        loadCallCount += 1
        guard let data else { throw PasswordVaultError.keychainUnavailable }
        return data
    }
    func delete() throws {
        deleteCallCount += 1
        data = nil
    }
}

private final class FailingVaultUnlockKeyStore: VaultUnlockKeyStoring {
    var containsKey: Bool { false }

    func save(_ data: Data) throws { throw PasswordVaultError.keychainUnavailable }
    func load(reason: String) throws -> Data { throw PasswordVaultError.keychainUnavailable }
    func delete() throws {}
}

private struct LegacyPasswordVaultEntryFixture: Codable {
    let id: UUID
    let title: String
    let website: String
    let username: String
    let note: String
    let createdAt: Date
    let updatedAt: Date
}

private final class InMemoryPasswordVaultKeychainClient: PasswordVaultKeychainClient {
    var metadata: Data?
    private var secrets = [UUID: Data]()
    var nextSecretWriteError: Error?

    func readMetadata() throws -> Data? { metadata }
    func writeMetadata(_ data: Data) throws { metadata = data }

    func readSecret(id: UUID, reason: String) throws -> Data {
        guard let data = secrets[id] else { throw PasswordVaultError.entryNotFound }
        return data
    }

    func writeSecret(id: UUID, data: Data) throws {
        if let nextSecretWriteError {
            self.nextSecretWriteError = nil
            throw nextSecretWriteError
        }
        secrets[id] = data
    }

    func deleteSecret(id: UUID, reason: String?) throws {
        secrets[id] = nil
    }

    func secret(for id: UUID) -> String? {
        secrets[id].flatMap { String(data: $0, encoding: .utf8) }
    }
}
