import AppKit
import Foundation
import PasteraAgentProtocol
import Testing
@testable import Pastera

// Runtime integration coverage stays beside the real AppKit password-vault action matrix.
// swiftlint:disable file_length

@MainActor
@Suite("Password vault menu", .serialized)
// swiftlint:disable:next type_body_length
struct PasswordVaultMenuTests {
    @Test("preparing a local copy never presents password controls")
    func preparingLocalCopyHidesPasswordForm() {
        var unlockAttempts = 0
        let controller = makeVaultController(
            state: { .preparingLocalCopy },
            folders: { [] },
            unlock: { _, _ in unlockAttempts += 1 }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 0)
        #expect(controller.vaultInlinePageTextsForTesting.contains(String(localized: "Preparing the Local Vault")))
        #expect(unlockAttempts == 0)
    }

    @Test("OneDrive migration unavailability is recovery state and never a password error")
    func unavailableLocalCopyHidesPasswordForm() {
        var unlockAttempts = 0
        var quickUnlockAttempts = 0
        let controller = makeVaultController(
            state: { .localCopyUnavailable(.oneDriveUnavailable) },
            canQuickUnlock: { true },
            folders: { [] },
            unlock: { _, _ in unlockAttempts += 1 },
            unlockWithQuickKey: { _ in quickUnlockAttempts += 1 }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 0)
        #expect(controller.vaultInlinePageTextsForTesting.contains(
            String(localized: "The local password vault could not be prepared.")
        ))
        #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains(String(localized: "The master password is incorrect.")))
        #expect(unlockAttempts == 0)
        #expect(quickUnlockAttempts == 0)
    }

    @Test("local copy recovery stays inline and requires a data-branch warning before replacement")
    func localCopyRecoveryStaysInline() {
        let oneDriveService = PasswordVaultMenuOneDriveProcessStatusService(status: .notRunning(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        var retryCount = 0
        let controller = makeVaultController(
            state: { .localCopyUnavailable(.oneDriveUnavailable) },
            folders: { [] },
            retryLocalPreparation: { retryCount += 1 },
            syncDataSource: menuSyncDataSource(startOneDrive: {
                oneDriveService.openOneDrive()
            }),
            oneDriveStatusService: oneDriveService
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultPageForTesting == "localCopyRecovery")
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 0)
        #expect(controller.vaultInlinePageTextsForTesting.contains(
            String(localized: "The local password vault could not be prepared.")
        ))
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-vault-local-recovery.png")
        )
        #expect(controller.vaultInlineActionsFitViewportForTesting)

        controller.performMainMenuButtonClickForTesting(identifier: "passwordVaultRecoveryStartOneDrive")
        #expect(oneDriveService.openCallCount == 1)

        controller.performMainMenuButtonClickForTesting(identifier: "passwordVaultRecoveryRetry")
        #expect(retryCount == 1)
        #expect(controller.passwordVaultPageForTesting == "localCopyRecovery")

        controller.performMainMenuButtonClickForTesting(identifier: "passwordVaultRecoveryContinueLocal")
        #expect(controller.vaultInlinePageTextsForTesting.contains(
            String(localized: "Creating a new local vault starts a separate data branch.")
        ))
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 0)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-vault-local-branch-warning.png")
        )

        controller.performMainMenuButtonClickForTesting(identifier: "passwordVaultRecoveryConfirmReplacement")
        #expect(controller.passwordVaultPageForTesting == "vault")
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 2)
    }

    @Test("running OneDrive recovery explains cloud download without offering to start it again")
    func runningOneDriveRecoveryExplainsPendingCloudDownload() {
        let oneDriveService = PasswordVaultMenuOneDriveProcessStatusService(status: .running(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        var retryCount = 0
        let controller = makeVaultController(
            state: { .localCopyUnavailable(.oneDriveUnavailable) },
            folders: { [] },
            retryLocalPreparation: { retryCount += 1 },
            oneDriveStatusService: oneDriveService
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains(
            "passwordVaultRecoveryStartOneDrive"
        ))
        #expect(controller.vaultInlinePageTextsForTesting.contains(
            String(localized: "OneDrive is running, but the cloud vault has not finished downloading. Wait for OneDrive to finish syncing, then try again. Your cloud copy remains unchanged.")
        ))

        controller.performMainMenuButtonClickForTesting(identifier: "passwordVaultRecoveryRetry")
        #expect(retryCount == 1)
    }

    @Test("a locked vault unlocks inside the main content area")
    func lockedVaultUsesEmbeddedUnlockForm() {
        let folder = PasswordVaultFolder(id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast)
        var state = PasswordVaultState.locked
        let controller = makeVaultController(
            state: { state },
            folders: { state == .unlocked ? [folder] : [] },
            unlock: { password, completion in
                if password == "correct-password" {
                    state = .unlocked
                    completion(.success(()))
                } else {
                    completion(.failure(.wrongMasterPassword))
                }
            }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 1)
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuPreparePasswordVaultButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuWorkspaceEditButton"))

        controller.setPasswordVaultAccessValuesForTesting(password: "correct-password")
        controller.submitPasswordVaultAccessForTesting()

        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 0)
    }

    @Test("a pending cloud unlock immediately replaces the stale form with busy feedback")
    func pendingCloudUnlockShowsBusyStateImmediately() {
        let folder = PasswordVaultFolder(id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast)
        var state = PasswordVaultState.locked
        var pendingCompletion: ((Result<Void, PasswordVaultError>) -> Void)?
        let controller = makeVaultController(
            state: { state },
            folders: { state == .unlocked ? [folder] : [] },
            unlock: { _, completion in pendingCompletion = completion }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.setPasswordVaultAccessValuesForTesting(password: "correct-password")
        controller.submitPasswordVaultAccessForTesting()

        #expect(controller.mainMenuButtonTitlesForTesting.contains(String(localized: "Unlocking…")))
        #expect(!controller.mainMenuButtonTitlesForTesting.contains(String(localized: "Unlock Vault")))
        #expect(!controller.passwordVaultAccessCredentialControlsEnabledForTesting)
        #expect(!controller.passwordVaultAccessPrimaryButtonEnabledForTesting)

        state = .unlocked
        pendingCompletion?(.success(()))

        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
        #expect(!controller.mainMenuButtonTitlesForTesting.contains(String(localized: "Unlocking…")))
    }

    @Test("an internal vault failure never leaks its raw state code")
    func internalVaultFailureUsesLocalizedFeedback() {
        let controller = makeVaultController(state: { .failed("corrupted") }, folders: { [] })
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains(
            String(localized: "The password database cannot be read.")
        ))
        #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains("corrupted"))
    }

    @Test("a cold quick-unlock capability check cannot block the first locked form")
    func coldQuickUnlockCheckDoesNotBlockFirstOpen() {
        let controller = makeVaultController(
            state: { .locked },
            canQuickUnlock: {
                Thread.sleep(forTimeInterval: 0.25)
                return false
            },
            folders: { [] }
        )

        let start = ContinuousClock.now
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        let elapsed = start.duration(to: .now)
        defer { _ = controller.close() }

        #expect(elapsed < .milliseconds(100))
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 1)
    }

    @Test("the unlock form keeps its credential controls in one compact group")
    func unlockFormUsesCompactCredentialLayout() {
        let controller = makeVaultController(state: { .locked }, folders: { [] })
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        let layout = controller.passwordVaultAccessLayoutForTesting
        #expect(layout?.title == String(localized: "Unlock Vault"))
        #expect(layout?.fieldLabel == String(localized: "Master Password"))
        #expect(layout?.titleFontSize == 15)
        #expect(layout?.verticalGapFromFieldToButton ?? .greatestFiniteMagnitude <= 24)
        #expect(layout?.primaryButtonWidth ?? 0 >= 250)
        #expect(layout?.controlsFitBounds == true)
    }

    @Test("first-time setup permanently warns that the master password cannot be recovered elsewhere")
    func createFormShowsNoRecoveryWarningBeforeInput() {
        let controller = makeVaultController(state: { .notConfigured }, folders: { [] })
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultAccessLayoutForTesting?.explanation == String(
            localized: "The master password encrypts your password vault. If forgotten, it cannot be recovered by any other means."
        ))
        #expect(controller.passwordVaultAccessLayoutForTesting?.explanationWrapsWithoutTruncation == true)
    }

    @Test("first-time setup defaults to local-only even when OneDrive is detected")
    func createFormDefaultsToLocalOnly() {
        var enableCallCount = 0
        let controller = makeVaultController(
            state: { .notConfigured },
            folders: { [] },
            syncDataSource: menuSyncDataSource(
                enableConfiguredOneDrive: { _, _ in enableCallCount += 1 }
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.vaultCreateStorageTitlesForTesting == [
            String(localized: "Keep on This Mac"),
            String(localized: "Sync with OneDrive")
        ])
        #expect(controller.vaultCreateStorageSelectionForTesting == "localOnly")
        #expect(enableCallCount == 0)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-create-local-only.png")
        )
    }

    @Test("choosing OneDrive creates the local vault first and enables the configured account")
    func oneDriveChoiceCreatesLocalVaultBeforeSync() {
        var state = PasswordVaultState.notConfigured
        var enableCallCount = 0
        let controller = makeVaultController(
            state: { state },
            folders: { [] },
            createDatabase: { _, completion in
                state = .unlocked
                completion(.success(()))
            },
            syncDataSource: menuSyncDataSource(
                enableConfiguredOneDrive: { _, completion in
                    enableCallCount += 1
                    completion(.success(()))
                }
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.selectPasswordVaultCreateStorageForTesting("oneDrive")
        controller.setPasswordVaultAccessValuesForTesting(
            password: "new-master-password",
            confirmation: "new-master-password"
        )
        controller.submitPasswordVaultAccessForTesting()

        #expect(state == .unlocked)
        #expect(controller.passwordVaultPageForTesting == "vault")
        #expect(enableCallCount == 1)
    }

    @Test("the footer opens OneDrive status and keeps the current vault content")
    func footerOpensOneDriveStatusWithoutNavigation() {
        let folder = PasswordVaultFolder(id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast)
        let oneDriveService = PasswordVaultMenuOneDriveProcessStatusService(status: .running(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        var didOpenOneDriveStatus = false
        let controller = makeVaultController(
            state: { .unlocked },
            folders: { [folder] },
            syncDataSource: menuSyncDataSource(),
            oneDriveStatusService: oneDriveService,
            onOpenOneDriveStatus: { didOpenOneDriveStatus = true }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
        controller.performMainMenuOneDriveStatusClickForTesting()

        #expect(controller.passwordVaultPageForTesting == "vault")
        #expect(oneDriveService.openCallCount == 0)
        #expect(didOpenOneDriveStatus)
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
    }

    @Test("sync snapshot refresh does not clear a master password being typed")
    func syncSnapshotRefreshPreservesCredentialInput() {
        let controller = makeVaultController(
            state: { .locked },
            folders: { [] },
            syncDataSource: menuSyncDataSource()
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }
        controller.setPasswordVaultAccessValuesForTesting(password: "still-being-typed")

        controller.refreshPasswordVaultSyncPresentationIfVisible(snapshot: PasswordVaultSyncSnapshot(
            mode: .oneDrive,
            phase: .disconnected(.oneDriveNotRunning),
            localVaultAvailable: true,
            remoteVaultAvailable: true,
            pendingChangeCount: 2,
            conflictCopyCount: 0,
            lastSyncAt: nil
        ))

        #expect(controller.passwordVaultAccessPasswordValueForTesting == "still-being-typed")
    }

    @Test("remote credentials use one transient secure field and never show a local password error")
    func remoteCredentialsAreTransient() {
        let snapshot = PasswordVaultSyncSnapshot(
            mode: .oneDrive,
            phase: .failed(.remoteCredentialsRequired),
            localVaultAvailable: true,
            remoteVaultAvailable: true,
            pendingChangeCount: 1,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
        var receivedPassword: String?
        let controller = makeVaultController(
            state: { .unlocked },
            folders: { [] },
            syncDataSource: menuSyncDataSource(
                snapshot: { snapshot },
                retryWithRemotePassword: { password, completion in
                    receivedPassword = password
                    completion(.failure(.remoteCredentialsRequired))
                }
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultPageForTesting == "remoteCredentials")
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 1)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-vault-remote-credentials.png")
        )
        #expect(controller.vaultInlineActionsFitViewportForTesting)

        controller.setPasswordVaultRemoteCredentialForTesting("remote-only-secret")
        controller.submitPasswordVaultRemoteCredentialForTesting()

        #expect(receivedPassword == "remote-only-secret")
        #expect(controller.vaultRemoteCredentialValueForTesting == "")
        #expect(controller.passwordVaultPageForTesting == "remoteCredentials")
        #expect(controller.vaultInlinePageTextsForTesting.contains(
            String(localized: "The OneDrive vault master password is incorrect.")
        ))
        #expect(!controller.vaultInlinePageTextsForTesting.contains(
            String(localized: "The master password is incorrect.")
        ))

        controller.performPasswordVaultContextBackForTesting()
        #expect(controller.passwordVaultPageForTesting == "vault")
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 0)
    }

    @Test("conflict summary is optional and can filter conflict copies in the unlocked vault")
    func conflictSummaryCanFilterConflictCopies() {
        let folder = PasswordVaultFolder(id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast)
        var snapshot = PasswordVaultSyncSnapshot(
            mode: .oneDrive,
            phase: .failed(.remoteCredentialsRequired),
            localVaultAvailable: true,
            remoteVaultAvailable: true,
            pendingChangeCount: 1,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
        let controller = makeVaultController(
            state: { .unlocked },
            folders: { [folder] },
            syncDataSource: menuSyncDataSource(
                snapshot: { snapshot },
                retryWithRemotePassword: { _, completion in
                    snapshot = PasswordVaultSyncSnapshot(
                        mode: .oneDrive,
                        phase: .conflicts(2),
                        localVaultAvailable: true,
                        remoteVaultAvailable: true,
                        pendingChangeCount: 1,
                        conflictCopyCount: 2,
                        lastSyncAt: .distantPast
                    )
                    completion(.success(()))
                }
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }
        controller.setPasswordVaultRemoteCredentialForTesting("remote-master-password")
        controller.submitPasswordVaultRemoteCredentialForTesting()
        #expect(controller.passwordVaultPageForTesting == "conflictSummary")
        #expect(controller.vaultInlinePageTextsForTesting.contains(
            String(format: String(localized: "%lld conflict copies were kept for review."), Int64(2))
        ))
        #expect(controller.vaultInlinePageTextsForTesting.contains(
            String(format: String(localized: "%lld local changes are still waiting."), Int64(1))
        ))
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-vault-conflict-summary.png")
        )
        #expect(controller.vaultInlineActionsFitViewportForTesting)

        controller.performMainMenuButtonClickForTesting(identifier: "passwordVaultConflictViewCopies")
        #expect(controller.passwordVaultPageForTesting == "vault")
        #expect(controller.passwordVaultSearchQueryForTesting == "(Conflict)")
    }

    @Test("master password visibility toggle preserves the entered value")
    func accessPasswordVisibilityTogglePreservesValue() {
        let controller = makeVaultController(state: { .locked }, folders: { [] })
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.setPasswordVaultAccessValuesForTesting(password: "visibility-value")
        #expect(!controller.passwordVaultAccessPasswordIsVisibleForTesting)

        controller.togglePasswordVaultAccessPasswordVisibilityForTesting()

        #expect(controller.passwordVaultAccessPasswordIsVisibleForTesting)
        #expect(controller.passwordVaultAccessPasswordValueForTesting == "visibility-value")
    }

    @Test("Return in the confirmation field creates the database inline")
    func createDatabaseAcceptsRealFieldEditorReturn() {
        var state = PasswordVaultState.notConfigured
        let controller = makeVaultController(
            state: { state }, folders: { [] },
            createDatabase: { password, completion in
                guard password == "new-master-password" else {
                    completion(.failure(.invalidPassword))
                    return
                }
                state = .unlocked
                completion(.success(()))
            }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 2)
        #expect(controller.submitPasswordVaultAccessUsingReturnForTesting(
            password: "new-master-password", confirmation: "new-master-password"
        ))

        #expect(state == .unlocked)
        controller.toggleWorkspaceEditingForTesting()
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordFolderButton"))
    }

    @Test("quick unlock is attempted once and cancellation stays on the embedded form")
    func quickUnlockCancellationDoesNotLoop() async {
        var attempts = 0
        let controller = makeVaultController(
            state: { .locked }, canQuickUnlock: { true }, folders: { [] },
            unlockWithQuickKey: { completion in
                attempts += 1
                completion(.failure(.userCancelled))
            }
        )

        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }
        controller.reloadContentIfVisible()

        await waitUntil { attempts == 1 }
        #expect(attempts == 1)
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 1)
    }

    @Test("relocking an open vault returns to the inline form without automatic retry")
    func relockReturnsToEmbeddedForm() {
        let folder = PasswordVaultFolder(id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast)
        var state = PasswordVaultState.unlocked
        var quickUnlockAttempts = 0
        let controller = makeVaultController(
            state: { state }, canQuickUnlock: { true },
            folders: { state == .unlocked ? [folder] : [] },
            unlockWithQuickKey: { completion in
                quickUnlockAttempts += 1
                completion(.failure(.userCancelled))
            }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))

        state = .locked
        controller.reloadContentIfVisible()

        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 1)
        #expect(quickUnlockAttempts == 0)
    }

    @Test("the lifecycle facade creates and unlocks KDBX without presenting password UI")
    func lifecycleFacadeUsesExplicitPasswords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(localStorage: makeMenuLocalStorage(at: root))
        let vaultController = PasswordVaultUIController(store: store, authorizer: AllowPasswordVaultAuthorizer())
        var createResult: Result<Void, PasswordVaultError>?

        let startedAt = ContinuousClock.now
        vaultController.createDatabase(masterPassword: "inline-password", completion: { createResult = $0 })
        #expect(ContinuousClock.now - startedAt < .milliseconds(50))
        #expect(vaultController.state == .unlocking)
        await waitUntil { createResult != nil }

        #expect(try createResult?.get() != nil)
        #expect(vaultController.state == .unlocked)
        store.lock()
        var unlockResult: Result<Void, PasswordVaultError>?

        vaultController.unlock(masterPassword: "inline-password", completion: { unlockResult = $0 })
        await waitUntil { unlockResult != nil }

        #expect(try unlockResult?.get() != nil)
        #expect(vaultController.state == .unlocked)
    }

    @Test("environment and MenuManager share one password vault graph")
    func environmentAndMenuShareController() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(localStorage: makeMenuLocalStorage(at: root))
        let menuManager = MenuManager()
        let syncController = LocalOnlyPasswordVaultSyncController(localVaultAvailable: true)
        let environment = Environment(
            passwordVaultStore: store,
            passwordVaultSyncService: syncController,
            secureClipboard: PasswordVaultClipboardProbe(),
            menuManager: menuManager
        )
        let controller = environment.passwordVaultUIController
        AppEnvironment.push(environment: environment)
        defer { AppEnvironment.popLast() }

        #expect(environment.passwordVaultUIController === controller)
        #expect(environment.passwordVaultSyncService === syncController)
        #expect(menuManager.passwordVaultUIController === controller)
        #expect(menuManager.passwordVaultSyncService === syncController)
        #expect(menuManager.passwordVaultSyncSnapshot == syncController.snapshot)
        #expect(AppEnvironment.current.passwordVaultUIController === controller)
        #expect(AppEnvironment.current.passwordVaultSyncService === syncController)
    }

    @Test("an unlocked empty vault exposes folder creation in edit mode")
    func emptyVaultShowsFolderCreation() {
        let controller = makeVaultController(folders: [], entries: [])
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordFolderButton"))
        controller.toggleWorkspaceEditingForTesting()
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordFolderButton"))
        #expect(!controller.mainMenuButtonTitlesForTesting.contains(String(localized: "+ New Folder")))

        controller.beginCreatingPasswordVaultFolderForTesting()
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordFolderButton"))
        #expect(controller.passwordVaultControlsFitVisibleContentForTesting)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-empty.png")
        )
    }

    @Test("password vault access controls stay inside the visible content width")
    func accessControlsFitVisibleContent() {
        let controller = makeVaultController(state: { .locked }, folders: { [] })
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultControlsFitVisibleContentForTesting)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-access.png")
        )
    }

    @Test("an unlocked folder exposes password creation after expanding in edit mode")
    func folderShowsPasswordCreation() throws {
        let work = PasswordVaultFolder(id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast)
        let personal = PasswordVaultFolder(id: UUID(), name: "Personal", createdAt: .distantPast, updatedAt: .distantPast)
        let entry = PasswordVaultEntry(
            id: UUID(), folderID: work.id, title: "Mail", website: "", username: "alice", note: "",
            createdAt: .distantPast, updatedAt: .distantPast
        )
        let controller = makeVaultController(folders: [work, personal], entries: [entry])
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.toggleWorkspaceEditingForTesting()
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordFolderButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordButton"))
        let rootCreateFrame = try #require(controller.mainMenuButtonFrameForTesting(
            identifier: "mainMenuContentCreatePasswordFolderButton"
        ))
        let personalRowFrame = try #require(controller.mainMenuSnippetRowFrameForTesting(title: "Personal"))
        let personalNumberFrame = try #require(controller.mainMenuRowItemNumberFrameForTesting(title: "Personal"))
        #expect(rootCreateFrame.maxY <= personalRowFrame.minY)
        #expect(abs(rootCreateFrame.minX - (personalRowFrame.minX + personalNumberFrame.minX)) < 1)
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains(String(localized: "New Password")))
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuCreatePasswordInFolderButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordFolderButton"))
        let entryCreateFrame = try #require(controller.mainMenuButtonFrameForTesting(
            identifier: "mainMenuContentCreatePasswordButton"
        ))
        let mailRowFrame = try #require(controller.mainMenuActionRowFrameForTesting(title: "Mail"))
        let mailNumberFrame = try #require(controller.mainMenuRowItemNumberFrameForTesting(title: "Mail"))
        let nextFolderFrame = try #require(controller.mainMenuSnippetRowFrameForTesting(title: "Personal"))
        #expect(entryCreateFrame.maxY <= mailRowFrame.minY)
        #expect(entryCreateFrame.minY >= nextFolderFrame.maxY)
        #expect(abs(entryCreateFrame.minX - (mailRowFrame.minX + mailNumberFrame.minX)) < 1)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-child-create-button.png")
        )
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordFolderButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordButton"))
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-single-create-button.png")
        )
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        controller.performMainMenuButtonClickForTesting(identifier: "mainMenuContentCreatePasswordButton")
        #expect(controller.passwordVaultEditorStepForTesting == "title")
    }

    @Test("the AppKit flow writes and copies a real KDBX password entry")
    // swiftlint:disable:next function_body_length
    func appKitFlowUsesRealKDBXStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(localStorage: makeMenuLocalStorage(at: root))
        try store.createDatabase(masterPassword: "ui-flow-password", rememberQuickUnlock: false)
        let clipboard = PasswordVaultClipboardProbe()
        let usernamePasteboard = NSPasteboard(
            name: NSPasteboard.Name("PasswordVaultMenuTests.appKitFlow.\(UUID().uuidString)")
        )
        defer { usernamePasteboard.clearContents() }
        var pasteCommands = 0
        let pasteService = PasteService(
            inputPasteCommandEnabledProvider: { true },
            accessibilityEnabledProvider: { true },
            pasteCommandSender: { pasteCommands += 1 },
            secureEventInputEnabledProvider: { false },
            clipboardScriptCoordinatorProvider: { nil },
            pasteboardProvider: { usernamePasteboard },
            scheduleAfter: { _, work in work() }
        )
        let vaultController = PasswordVaultUIController(
            store: store, clipboard: clipboard, authorizer: AllowPasswordVaultAuthorizer(), pasteService: pasteService
        )
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                state: { vaultController.state },
                checkQuickUnlockAvailability: vaultController.checkQuickUnlockAvailability,
                createDatabase: vaultController.createDatabase,
                unlock: vaultController.unlock,
                unlockWithQuickKey: vaultController.unlockWithQuickKey,
                fetchFolders: vaultController.folders,
                fetchEntries: vaultController.entries,
                copyPassword: vaultController.copyPassword,
                loadDraft: vaultController.loadDraft,
                createEntry: vaultController.createEntry,
                updateEntry: vaultController.updateEntry,
                deleteEntry: vaultController.deleteEntry,
                createFolder: { _ in throw PasswordVaultError.saveFailed },
                renameFolder: { _, _ in throw PasswordVaultError.saveFailed },
                deleteFolder: { _ in throw PasswordVaultError.saveFailed },
                createFolderAsync: vaultController.createFolder,
                renameFolderAsync: vaultController.renameFolder,
                deleteFolderAsync: vaultController.deleteFolder
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.toggleWorkspaceEditingForTesting()
        controller.beginCreatingPasswordVaultFolderForTesting()
        #expect(controller.submitVisiblePasswordVaultReturnFieldForTesting("Work"))
        await waitUntil("folder persisted") { (try? store.listFolders().isEmpty == false) == true }
        await waitUntil("folder editor dismissed") { !controller.passwordVaultFolderEditorIsVisibleForTesting }
        let folder = try #require(store.listFolders().first)

        controller.beginCreatingPasswordVaultEntryForTesting(in: folder.id)
        #expect(controller.submitVisiblePasswordVaultReturnFieldForTesting("Mail"))
        #expect(controller.submitVisiblePasswordVaultReturnFieldForTesting("alice"))
        #expect(controller.submitVisiblePasswordVaultReturnFieldForTesting("secret-value"))
        await waitUntil("entry persisted") { (try? store.listEntries().isEmpty == false) == true }
        await waitUntil("entry row visible") { controller.mainMenuVisibleRowTitlesForTesting.contains("Mail") }

        let entry = try #require(store.listEntries().first)
        #expect(entry.title == "Mail")
        let usernamePasteResult = await withCheckedContinuation { continuation in
            vaultController.pasteUsername(id: entry.id, targetContext: nil) { continuation.resume(returning: $0) }
        }
        try usernamePasteResult.get()
        await waitUntil("username paste command sent") { pasteCommands == 1 }
        #expect(usernamePasteboard.string(forType: .string) == "alice")

        let passwordPasteResult = await withCheckedContinuation { continuation in
            vaultController.pastePassword(id: entry.id, targetContext: nil) { continuation.resume(returning: $0) }
        }
        try passwordPasteResult.get()
        await waitUntil("password paste command sent") { pasteCommands == 2 }
        #expect(clipboard.value == "secret-value")

        controller.performMainMenuRowConfirmForTesting(title: "Mail")
        await waitUntil("row confirmation copied password") { clipboard.value != nil }
        #expect(clipboard.value == "secret-value")

        controller.performMainMenuRowDoubleClickForTesting(title: "Mail")
        await waitUntil("entry editor opened") { controller.passwordVaultEditorStepForTesting == "title" }
        controller.updatePasswordVaultStepValueForTesting("Mail Updated")
        controller.commitPasswordVaultStepForTesting()
        controller.updatePasswordVaultStepValueForTesting("bob")
        controller.commitPasswordVaultStepForTesting()
        controller.updatePasswordVaultStepValueForTesting("updated-secret")
        controller.commitPasswordVaultStepForTesting()
        await waitUntil("entry update persisted") { (try? store.listEntries().first?.title) == "Mail Updated" }

        store.lock()
        controller.reloadContentIfVisible()
        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 1)
        controller.setPasswordVaultAccessValuesForTesting(password: "ui-flow-password")
        controller.submitPasswordVaultAccessForTesting()
        await waitUntil("vault unlocked") { vaultController.state == .unlocked }
        await waitUntil("folder visible after unlock") { controller.mainMenuVisibleRowTitlesForTesting.contains("Work") }
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
        #expect(try store.listEntries().map(\.title) == ["Mail Updated"])

        controller.performMainMenuRowDeleteForTesting(title: "Mail Updated")
        #expect((try? store.listEntries().isEmpty) == false)
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Delete again to confirm."))
        controller.performMainMenuRowDeleteForTesting(title: "Mail Updated")
        await waitUntil("entry deletion persisted") { (try? store.listEntries().isEmpty) == true }
        controller.performMainMenuRowDeleteForTesting(title: "Work")
        #expect((try? store.listFolders().isEmpty) == false)
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Delete again to confirm."))
        controller.performMainMenuRowDeleteForTesting(title: "Work")
        await waitUntil("folder deletion persisted") { (try? store.listFolders().isEmpty) == true }
    }

    @Test("an unconfigured vault shows a creation action instead of an unavailable dead end")
    func unconfiguredVaultIsActionable() {
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: { throw PasswordVaultError.databaseNotConfigured },
                fetchEntries: { throw PasswordVaultError.databaseNotConfigured },
                copyPassword: { _, completion in completion(.failure(.databaseNotConfigured)) },
                loadDraft: { _, completion in completion(.failure(.databaseNotConfigured)) },
                createEntry: { _, completion in completion(.failure(.databaseNotConfigured)) },
                updateEntry: { _, _, completion in completion(.failure(.databaseNotConfigured)) },
                deleteEntry: { _, completion in completion(.failure(.databaseNotConfigured)) },
                createFolder: { _ in throw PasswordVaultError.databaseNotConfigured },
                renameFolder: { _, _ in throw PasswordVaultError.databaseNotConfigured },
                deleteFolder: { _ in throw PasswordVaultError.databaseNotConfigured }
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(controller.passwordVaultAccessSecureFieldCountForTesting == 2)
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuPreparePasswordVaultButton"))
        #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains("Password Vault Unavailable"))
    }

    @Test("snippet mode matches vault folder styling and creates items inline")
    func snippetModeCreatesInlineWithoutRowIcons() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        var details = [SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "Work", index: 0, isEnabled: true),
            snippets: []
        )]
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: NSImage(),
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: { details },
                fetchFolderDetail: { id in details.first { $0.folder.id == id } },
                selectSnippet: { _, _ in },
                createFolder: { title in
                    let folder = SnippetFolder(id: .init(rawValue: UUID()), title: title, index: details.count, isEnabled: true)
                    details.append(SnippetFolderDetail(folder: folder, snippets: []))
                    return folder
                },
                createSnippet: { id, title, content in
                    let snippet = Snippet(id: .init(rawValue: UUID()), folderID: id, title: title, content: content, index: 0, isEnabled: true)
                    details[0] = SnippetFolderDetail(folder: details[0].folder, snippets: details[0].snippets + [snippet])
                    return snippet
                }
            )
        )
        controller.openSnippetsFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContextCreateButton"))
        #expect(controller.mainMenuRowHasImageForTesting(title: "Work"))

        controller.performMainMenuRowDoubleClickForTesting(title: "Work")
        #expect(controller.mainMenuEditorTitleForTesting == nil)
        controller.toggleWorkspaceEditingForTesting()
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetFolderButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetButton"))
        controller.selectMainMenuItemForTesting(title: "Work")
        #expect(!controller.mainMenuRowVisibleButtonIdentifiersForTesting(title: "Work").contains("mainMenuRowEditButton"))
        controller.performMainMenuRowDoubleClickForTesting(title: "Work")
        #expect(controller.mainMenuEditorTitleForTesting == "Work")
        #expect(controller.mainMenuRenderedRowCountForTesting(title: "Work") == 0)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-snippet-inline-edit.png")
        )
        controller.discardMainMenuEditorForTesting()
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetFolderButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuCreateSnippetInFolderButton"))
        #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains(String(localized: "New Snippet")))
        controller.performMainMenuButtonClickForTesting(identifier: "mainMenuContentCreateSnippetButton")
        #expect(controller.mainMenuEditorTitleForTesting == "")
        controller.discardMainMenuEditorForTesting()

        controller.updateMainMenuSearchQueryForTesting("Work")
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetFolderButton"))
        controller.updateMainMenuSearchQueryForTesting("")

        controller.performMainMenuRowConfirmForTesting(title: "Work")
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetFolderButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetButton"))
        controller.performMainMenuRowConfirmForTesting(title: "Work")

        controller.beginCreatingSnippetForTesting()
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
        controller.updateMainMenuEditorDraftForTesting(title: "Deploy", content: "make release")
        #expect(controller.commitMainMenuEditorForTesting())
        #expect(details[0].snippets.map(\.title) == ["Deploy"])

        controller.beginCreatingSnippetFolderForTesting()
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreateSnippetFolderButton"))
        controller.updateMainMenuEditorDraftForTesting(title: "Personal")
        #expect(controller.commitMainMenuEditorForTesting())
        #expect(details.map { $0.folder.title } == ["Work", "Personal"])
    }

    @Test("vault rows edit by double-click without pencil buttons or duplicate rows")
    func vaultRowsUseInlineDoubleClickEditing() {
        let folderID = UUID()
        let entry = PasswordVaultEntry(
            id: UUID(), folderID: folderID, title: "Mail", website: "", username: "alice", note: "",
            createdAt: .distantPast, updatedAt: .distantPast
        )
        let controller = makeVaultController(
            folders: [.init(id: folderID, name: "Work", createdAt: .distantPast, updatedAt: .distantPast)],
            entries: [entry]
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.performMainMenuRowDoubleClickForTesting(title: "Work")
        #expect(!controller.passwordVaultFolderEditorIsVisibleForTesting)

        controller.toggleWorkspaceEditingForTesting()
        controller.selectMainMenuItemForTesting(title: "Work")
        #expect(!controller.mainMenuRowVisibleButtonIdentifiersForTesting(title: "Work").contains("mainMenuRowEditButton"))
        controller.performMainMenuRowDoubleClickForTesting(title: "Work")
        #expect(controller.passwordVaultFolderEditorIsVisibleForTesting)
        #expect(controller.mainMenuRenderedRowCountForTesting(title: "Work") == 0)
        try? controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-inline-edit.png")
        )

        controller.discardPasswordVaultFolderEditorForTesting()
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        controller.selectMainMenuItemForTesting(title: "Mail")
        #expect(!controller.mainMenuRowVisibleButtonIdentifiersForTesting(title: "Mail").contains("mainMenuRowEditButton"))
        controller.performMainMenuRowDoubleClickForTesting(title: "Mail")
        #expect(controller.mainMenuPasswordEditorIsVisibleForTesting)
        #expect(controller.mainMenuRenderedRowCountForTesting(title: "Mail") == 0)
    }

    @Test("single-line Return saves and Escape cancels")
    func singleLineKeyboardActions() throws {
        var saved = 0
        var cancelled = 0
        let field = PasswordVaultReturnTextField()
        field.onReturn = { saved += 1 }
        field.onEscape = { cancelled += 1 }

        field.keyDown(with: try #require(keyEvent(keyCode: 36, characters: "\r")))
        field.keyDown(with: try #require(keyEvent(keyCode: 53, characters: "\u{1b}")))

        #expect(saved == 1)
        #expect(cancelled == 1)
    }

    @Test("folder creation uses one compact inline row")
    func folderCreationUsesCompactInlineRow() {
        let editor = PasswordVaultFolderEditorView(name: "", onSave: { _ in }, onCancel: {})

        #expect(editor.frame.height == MainMenuPanelLayout.rowHeight)
        #expect(editor.subviews.compactMap { $0 as? NSButton }.isEmpty)
        #expect(editor.subviews.contains { $0 is NSImageView })
        #expect(editor.subviews.contains { $0 is PasswordVaultReturnTextField })
    }

    @Test("Return from the AppKit field editor creates the folder")
    func folderCreationAcceptsRealFieldEditorReturn() throws {
        var savedName: String?
        let editor = PasswordVaultFolderEditorView(name: "", onSave: { savedName = $0 }, onCancel: {})
        let window = NSWindow(contentRect: editor.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let field = try #require(editor.subviews.compactMap { $0 as? PasswordVaultReturnTextField }.first)
        field.stringValue = "Work"
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(window.fieldEditor(true, for: field) as? NSTextView)

        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        #expect(savedName == "Work")
    }

    @Test("folder creation does not show a redundant empty-password message")
    func folderCreationHidesEmptyPasswordMessage() throws {
        let controller = makeVaultController(folders: [], entries: [])
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.beginCreatingPasswordVaultFolderForTesting()

        #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains(String(localized: "No Passwords")))
        #expect(controller.passwordVaultFolderEditorIsVisibleForTesting)
        try controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-folder-editor.png")
        )
    }

    @Test("footer settings navigation preserves unfinished password fields", arguments: [
        "mainMenuOneDriveStatusButton", "mainMenuPreferencesButton"
    ], ["title", "username", "password"])
    func footerSettingsNavigationPreservesUncommittedVaultFields(buttonIdentifier: String, step: String) throws {
        let folderID = UUID()
        var savedDraft: PasswordVaultDraft?
        var settingsOpened = false
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: { [PasswordVaultFolder(id: folderID, name: "Work", createdAt: .distantPast, updatedAt: .distantPast)] },
                fetchEntries: { [] },
                copyPassword: { _, completion in completion(.success(())) },
                loadDraft: { _, completion in completion(.failure(.entryNotFound)) },
                createEntry: { draft, completion in savedDraft = draft; completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { _ in throw PasswordVaultError.keychainUnavailable },
                renameFolder: { _, _ in throw PasswordVaultError.keychainUnavailable },
                deleteFolder: { _ in }
            ),
            oneDriveStatusService: PasswordVaultMenuOneDriveProcessStatusService(status: .running(
                appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
            )),
            onOpenPreferences: { settingsOpened = true },
            onOpenOneDriveStatus: { settingsOpened = true }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }
        controller.toggleWorkspaceEditingForTesting()
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        controller.beginCreatingPasswordVaultEntryForTesting(in: folderID)
        try #require(controller.passwordVaultEditorStepForTesting == "title")
        if step != "title" {
            controller.updatePasswordVaultStepValueForTesting("Unfinished mail title")
            controller.commitPasswordVaultStepForTesting()
        }
        if step == "password" {
            controller.updatePasswordVaultStepValueForTesting("alice")
            controller.commitPasswordVaultStepForTesting()
        }
        let unfinishedValue = switch step {
        case "title": "Unfinished mail title"
        case "username": "alice"
        default: "test-secret"
        }
        controller.updatePasswordVaultStepValueForTesting(unfinishedValue)

        controller.performMainMenuButtonClickForTesting(identifier: buttonIdentifier)
        #expect(settingsOpened)
        #expect(!controller.isVisibleForTesting)
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        #expect(savedDraft == nil)
        try #require(controller.passwordVaultEditorStepForTesting == step)
        controller.commitPasswordVaultStepForTesting()

        if step == "title" {
            try #require(controller.passwordVaultEditorStepForTesting == "username")
            controller.updatePasswordVaultStepValueForTesting("alice")
            controller.commitPasswordVaultStepForTesting()
        }
        if step != "password" {
            try #require(controller.passwordVaultEditorStepForTesting == "password")
            controller.updatePasswordVaultStepValueForTesting("test-secret")
            controller.commitPasswordVaultStepForTesting()
        }
        #expect(savedDraft?.title == "Unfinished mail title")
        #expect(savedDraft?.username == "alice")
        #expect(savedDraft?.password == "test-secret")
    }

    @Test("footer settings navigation preserves an unfinished folder name", arguments: [
        "mainMenuOneDriveStatusButton", "mainMenuPreferencesButton"
    ], [false, true])
    func footerSettingsNavigationPreservesUncommittedFolderName(buttonIdentifier: String, renaming: Bool) throws {
        let folder = PasswordVaultFolder(id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast)
        var savedNames = [String]()
        var settingsOpened = false
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: { [folder] }, fetchEntries: { [] },
                copyPassword: { _, completion in completion(.success(())) },
                loadDraft: { _, completion in completion(.failure(.entryNotFound)) },
                createEntry: { _, completion in completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { name in savedNames.append(name); return folder },
                renameFolder: { _, name in savedNames.append(name); return folder },
                deleteFolder: { _ in }
            ),
            oneDriveStatusService: PasswordVaultMenuOneDriveProcessStatusService(status: .running(
                appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
            )),
            onOpenPreferences: { settingsOpened = true },
            onOpenOneDriveStatus: { settingsOpened = true }
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }
        if renaming {
            controller.toggleWorkspaceEditingForTesting()
            controller.performMainMenuRowDoubleClickForTesting(title: "Work")
        } else {
            controller.beginCreatingPasswordVaultFolderForTesting()
        }
        let panel = try #require(NSApp.windows.first { $0.delegate === controller })
        let contentView = try #require(panel.contentView)
        let editor = try #require(findVaultFolderEditor(in: contentView))
        let field = try #require(editor.subviews.compactMap { $0 as? PasswordVaultReturnTextField }.first)
        field.stringValue = "Unfinished folder name"

        controller.performMainMenuButtonClickForTesting(identifier: buttonIdentifier)
        #expect(settingsOpened)
        #expect(!controller.isVisibleForTesting)
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)

        #expect(savedNames.isEmpty)
        let restoredEditor = try #require(findVaultFolderEditor(in: contentView))
        let restoredField = try #require(restoredEditor.subviews.compactMap { $0 as? PasswordVaultReturnTextField }.first)
        #expect(restoredField.stringValue == "Unfinished folder name")
        restoredField.keyDown(with: try #require(keyEvent(keyCode: 36, characters: "\r")))
        #expect(savedNames == ["Unfinished folder name"])
    }

    @Test("password creation stays inside its folder and advances one compact field at a time")
    func passwordCreationUsesFolderScopedSteps() {
        let folderID = UUID()
        var savedDraft: PasswordVaultDraft?
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: { [PasswordVaultFolder(id: folderID, name: "Work", createdAt: .distantPast, updatedAt: .distantPast)] },
                fetchEntries: { [] },
                copyPassword: { _, completion in completion(.success(())) },
                loadDraft: { _, completion in completion(.failure(.entryNotFound)) },
                createEntry: { draft, completion in savedDraft = draft; completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { _ in throw PasswordVaultError.keychainUnavailable },
                renameFolder: { _, _ in throw PasswordVaultError.keychainUnavailable },
                deleteFolder: { _ in }
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        controller.toggleWorkspaceEditingForTesting()
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        controller.beginCreatingPasswordVaultEntryForTesting(in: folderID)
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
        #expect(controller.passwordVaultEditorStepForTesting == "title")
        #expect(controller.passwordVaultEditorHeightForTesting == MainMenuPanelLayout.rowHeight)

        controller.updatePasswordVaultStepValueForTesting("Mail")
        controller.commitPasswordVaultStepForTesting()
        #expect(controller.passwordVaultEditorStepForTesting == "username")

        controller.updatePasswordVaultStepValueForTesting("alice")
        controller.commitPasswordVaultStepForTesting()
        #expect(controller.passwordVaultEditorStepForTesting == "password")

        controller.updatePasswordVaultStepValueForTesting("test-secret")
        controller.commitPasswordVaultStepForTesting()
        #expect(savedDraft?.folderID == folderID)
        #expect(savedDraft?.title == "Mail")
        #expect(savedDraft?.username == "alice")
        #expect(savedDraft?.password == "test-secret")
        #expect(!controller.mainMenuPasswordEditorIsVisibleForTesting)
    }

    @Test("password step can reveal and hide its value without changing it")
    func passwordStepVisibilityTogglePreservesValue() {
        let editor = PasswordVaultStepEditorView(
            step: .password,
            value: "test-secret",
            onCommit: { _ in },
            onEscape: {}
        )

        #expect(!editor.isPasswordVisibleForTesting)
        #expect(editor.passwordVisibilityButtonForTesting?.accessibilityLabel() == String(localized: "Show Password"))

        editor.togglePasswordVisibilityForTesting()

        #expect(editor.isPasswordVisibleForTesting)
        #expect(editor.visiblePasswordValueForTesting == "test-secret")
        #expect(editor.value == "test-secret")

        editor.togglePasswordVisibilityForTesting()

        #expect(!editor.isPasswordVisibleForTesting)
        #expect(editor.value == "test-secret")
    }

    @Test("password quick actions and numeric shortcuts paste the corresponding field")
    func selectedEntryPasteShortcuts() throws {
        let numberKey = Constants.UserDefaults.menuItemsTitleStartWithZero
        let previousNumberSetting = AppEnvironment.current.defaults.object(forKey: numberKey)
        AppEnvironment.current.defaults.set(false, forKey: numberKey)
        defer { AppEnvironment.current.defaults.set(previousNumberSetting, forKey: numberKey) }
        let coachmarkKey = "kPasteraPasswordVaultQuickActionsCoachmarkShown"
        AppEnvironment.current.defaults.removeObject(forKey: coachmarkKey)
        defer { AppEnvironment.current.defaults.removeObject(forKey: coachmarkKey) }
        let folderID = UUID()
        let entry = PasswordVaultEntry(
            id: UUID(), folderID: folderID, title: "Mail", website: "", username: "alice", note: "",
            createdAt: .distantPast, updatedAt: .distantPast
        )
        var pastedUsername = 0
        var pastedPassword = 0
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: { [.init(id: folderID, name: "Work", createdAt: .distantPast, updatedAt: .distantPast)] },
                fetchEntries: { [entry] },
                copyPassword: { _, completion in completion(.success(())) },
                pasteUsername: { _, _, completion in pastedUsername += 1; completion(.success(())) },
                pastePassword: { _, _, completion in pastedPassword += 1; completion(.success(())) },
                loadDraft: { _, completion in completion(.failure(.entryNotFound)) },
                createEntry: { _, completion in completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { _ in throw PasswordVaultError.saveFailed },
                renameFolder: { _, _ in throw PasswordVaultError.saveFailed },
                deleteFolder: { _ in throw PasswordVaultError.saveFailed }
            )
        )
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        controller.selectMainMenuItemForTesting(title: "Mail")

        #expect(!controller.mainMenuNonNavigatingHintTitlesForTesting.contains {
            $0.contains(String(localized: "Quick paste")) || $0.contains("快捷粘贴")
        })
        #expect(controller.mainMenuNonNavigatingHintTitlesForTesting.contains(
            String(localized: "Quick paste is available here")
        ))
        #expect(controller.mainMenuRowVisibleButtonIdentifiersForTesting(title: "Mail").contains(
            "mainMenuPasswordPasteUsernameButton"
        ))
        #expect(controller.mainMenuRowVisibleButtonIdentifiersForTesting(title: "Mail").contains(
            "mainMenuPasswordPastePasswordButton"
        ))
        #expect(controller.mainMenuRowVisibleButtonIdentifiersForTesting(title: "Mail").contains(
            "mainMenuPasswordMoreButton"
        ))
        try controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-quick-actions-coachmark.png")
        )
        #expect(controller.mainMenuRowContextMenuTitlesForTesting(title: "Mail").prefix(2) == [
            String(localized: "Paste Username"), String(localized: "Paste Password")
        ])
        let rowHelp = try #require(controller.mainMenuRowToolTipForTesting(title: "Mail"))
        #expect(rowHelp.contains("⌃1"))
        #expect(rowHelp.contains(String(localized: "Paste Password")))
        #expect(!rowHelp.contains("⇧↩"))
        controller.performMainMenuButtonClickForTesting(identifier: "mainMenuPasswordPasteUsernameButton")
        #expect(pastedUsername == 1)
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        controller.selectMainMenuItemForTesting(title: "Mail")
        controller.performMainMenuButtonClickForTesting(identifier: "mainMenuPasswordPastePasswordButton")
        #expect(pastedPassword == 1)
        pastedUsername = 0
        pastedPassword = 0
        try controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-contextual-actions.png")
        )
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        controller.selectMainMenuItemForTesting(title: "Mail")
        #expect(!controller.handleMainMenuNavigationForTesting(
            try #require(keyEvent(keyCode: 32, characters: "u", modifiers: .command))
        ))
        #expect(pastedUsername == 0)
        #expect(!controller.handleMainMenuNavigationForTesting(
            try #require(keyEvent(keyCode: 32, characters: "u", modifiers: [.option, .command]))
        ))
        #expect(controller.handleMainMenuNavigationForTesting(
            try #require(keyEvent(keyCode: 18, characters: "1", modifiers: .control))
        ))
        #expect(pastedUsername == 1)

        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        controller.selectMainMenuItemForTesting(title: "Mail")
        #expect(!controller.handleMainMenuNavigationForTesting(
            try #require(keyEvent(keyCode: 35, characters: "p", modifiers: .command))
        ))
        #expect(pastedPassword == 0)
        #expect(!controller.handleMainMenuNavigationForTesting(
            try #require(keyEvent(keyCode: 35, characters: "p", modifiers: [.option, .command]))
        ))
        #expect(controller.handleMainMenuNavigationForTesting(
            try #require(keyEvent(keyCode: 18, characters: "1"))
        ))
        #expect(pastedPassword == 1)

        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        controller.toggleWorkspaceEditingForTesting()
        controller.selectMainMenuItemForTesting(title: "Mail")
        let editButtons = controller.mainMenuRowVisibleButtonIdentifiersForTesting(title: "Mail")
        #expect(!editButtons.contains("mainMenuPasswordPasteUsernameButton"))
        #expect(!editButtons.contains("mainMenuPasswordPastePasswordButton"))
        #expect(!editButtons.contains("mainMenuPasswordMoreButton"))
        #expect(editButtons.contains("mainMenuRowDeleteButton"))
        try controller.mainMenuSnapshotPNGForTesting().write(
            to: URL(fileURLWithPath: "/tmp/pastera-password-vault-contextual-actions-edit.png")
        )
    }

    @Test("note Return inserts a newline and Command-Return saves")
    func noteKeyboardActions() throws {
        var saved = 0
        let note = PasswordVaultNoteTextView()
        note.onSave = { saved += 1 }

        note.keyDown(with: try #require(keyEvent(keyCode: 36, characters: "\r")))
        #expect(note.string == "\n")
        #expect(saved == 0)

        note.keyDown(with: try #require(keyEvent(keyCode: 36, characters: "\r", modifiers: .command)))
        #expect(note.string == "\n")
        #expect(saved == 1)
    }

    @Test("vault is an independent searchable main-menu mode")
    func vaultIsIndependentSearchableMode() {
        let entries = [
            PasswordVaultEntry(
                id: UUID(), folderID: UUID(), title: "Mail", website: "mail.example.com", username: "alice", note: "",
                createdAt: .distantPast, updatedAt: .distantPast
            ),
            PasswordVaultEntry(
                id: UUID(), folderID: UUID(), title: "Cloud", website: "cloud.example.com", username: "bob", note: "",
                createdAt: .distantPast, updatedAt: .distantPast
            )
        ]
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: {
                    [PasswordVaultFolder(id: entries[0].folderID, name: "Work", createdAt: .distantPast, updatedAt: .distantPast)]
                },
                fetchEntries: { entries },
                copyPassword: { _, completion in completion(.success(())) },
                loadDraft: { _, completion in
                    completion(.success(PasswordVaultDraft(
                        folderID: entries[0].folderID, title: "Mail", website: "mail.example.com",
                        username: "alice", note: "", password: "test-password"
                    )))
                },
                createEntry: { _, completion in completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { _ in throw PasswordVaultError.keychainUnavailable },
                renameFolder: { _, _ in throw PasswordVaultError.keychainUnavailable },
                deleteFolder: { _ in }
            )
        )

        controller.openPasswordVaultFromMainMenu()
        controller.updateMainMenuSearchQueryForTesting("alice")
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)

        #expect(controller.mainMenuSelectedModeForTesting == "passwordVault")
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContextCreateButton"))
        controller.updateMainMenuSearchQueryForTesting("")
        controller.toggleWorkspaceEditingForTesting()
        controller.performMainMenuRowConfirmForTesting(title: "Work")
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContentCreatePasswordButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuCreatePasswordInFolderButton"))
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["Work", "Mail"])
        #expect(controller.mainMenuRowContextMenuTitlesForTesting(title: "Work").contains(String(localized: "Edit")))
        controller.performMainMenuRowDoubleClickForTesting(title: "Mail")
        #expect(controller.mainMenuPasswordEditorIsVisibleForTesting)
        controller.openHistoryFromMainMenu()
        #expect(controller.mainMenuSelectedModeForTesting == "history")
        #expect(controller.mainMenuVisibleRowTitlesForTesting == [String(localized: "No History")])
        _ = controller.close()
    }

    @Test("runtime composes interactive renewal ownership and excludes every Agent action")
    // swiftlint:disable:next function_body_length
    func runtimeInteractiveRenewalLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(localStorage: makeMenuLocalStorage(at: root))
        try store.createDatabase(masterPassword: "runtime-renewal", rememberQuickUnlock: false)
        let folder = try store.createFolder(name: "Work")
        let originalEntry = try store.create(.init(
            folderID: folder.id,
            title: "Original",
            website: "https://example.test",
            username: "alice",
            note: "",
            password: "secret"
        ))
        let pasteService = PasteService(
            inputPasteCommandEnabledProvider: { false },
            accessibilityEnabledProvider: { false },
            pasteCommandSender: {},
            secureEventInputEnabledProvider: { false },
            clipboardScriptCoordinatorProvider: { nil },
            scheduleAfter: { _, work in work() }
        )
        let controller = PasswordVaultUIController(
            store: store,
            clipboard: PasswordVaultClipboardProbe(),
            authorizer: AllowPasswordVaultAuthorizer(),
            pasteService: pasteService,
            storeQueue: DispatchQueue(label: "PasswordVaultMenuTests.runtime-renewal")
        )
        let callbackCount = LockedInt()
        controller.onInteractiveSensitiveUse = { callbackCount.increment() }

        let dateBox = MenuRuntimeDateBox(Date(timeIntervalSince1970: 2_000_000))
        let grantStore = MenuRuntimeGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(
            store: grantStore,
            executor: controller.vaultAgentExecutor
        )
        for client in VaultAgentClientKind.allCases {
            try policy.authorize(identity: menuIdentity(client), authenticatedAt: dateBox.value)
        }
        let tickets = VaultAgentTicketStore(
            randomBytes: { Data(repeating: 0x33, count: 32) },
            commandBuilder: { client, mode, token in
                VaultAgentRuntime.helperCommand(
                    applicationURL: URL(fileURLWithPath: "/Applications/Pastera.app"),
                    client: client,
                    mode: mode,
                    token: token
                )
            }
        )
        var runtime: VaultAgentRuntime? = try VaultAgentRuntime(
            executor: controller.vaultAgentExecutor,
            authorizationPolicy: policy,
            vault: controller,
            pasteTargetTracker: MenuRuntimeTargetTracker(),
            ticketStore: tickets,
            auditLogger: MenuRuntimeAuditLogger(),
            now: { dateBox.value },
            cursorKey: Data(repeating: 0x44, count: 32)
        )
        #expect(runtime != nil)
        #expect(controller.sensitiveObserverCountForTesting == 1)

        func assertAllRenewed(after previous: [VaultAgentClientKind: Date]) {
            for client in VaultAgentClientKind.allCases {
                let expiry = policy.grantSnapshot(for: client)?.idleExpiresAt
                #expect(expiry != nil)
                #expect(expiry.map { $0 > previous[client]! } == true)
            }
        }

        func snapshotExpiries() -> [VaultAgentClientKind: Date] {
            Dictionary(uniqueKeysWithValues: VaultAgentClientKind.allCases.compactMap { client in
                policy.grantSnapshot(for: client).map { (client, $0.idleExpiresAt) }
            })
        }

        var expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { completion in
            controller.createEntry(.init(
                folderID: folder.id,
                title: "Created",
                website: "https://created.test",
                username: "bob",
                note: "",
                password: "created-secret"
            ), completion: completion)
        }
        assertAllRenewed(after: expiries)
        #expect(callbackCount.value == 1)
        let createdEntry = try #require(try store.listEntries().first { $0.title == "Created" })

        expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { completion in
            controller.updateEntry(id: createdEntry.id, draft: .init(
                folderID: folder.id,
                title: "Updated",
                website: "https://updated.test",
                username: "bob",
                note: "",
                password: "updated-secret"
            ), completion: completion)
        }
        assertAllRenewed(after: expiries)
        #expect(callbackCount.value == 2)

        expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { controller.copyPassword(id: createdEntry.id, completion: $0) }
        assertAllRenewed(after: expiries)
        #expect(callbackCount.value == 3)

        expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { controller.pasteUsername(id: createdEntry.id, targetContext: nil, completion: $0) }
        assertAllRenewed(after: expiries)
        #expect(callbackCount.value == 4)

        expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { controller.pastePassword(id: createdEntry.id, targetContext: nil, completion: $0) }
        assertAllRenewed(after: expiries)
        #expect(callbackCount.value == 5)

        expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { controller.deleteEntry(id: createdEntry.id, completion: $0) }
        assertAllRenewed(after: expiries)
        #expect(callbackCount.value == 6)

        expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { controller.agentCopy(entryID: originalEntry.id, field: .password, completion: $0) }
        try await awaitVaultAction {
            controller.agentPaste(
                entryID: originalEntry.id,
                field: .username,
                target: .init(
                    processIdentifier: 42,
                    bundleIdentifier: "com.example.target",
                    application: nil,
                    focusedElement: nil
                ),
                completion: $0
            )
        }
        #expect(snapshotExpiries() == expiries)
        #expect(callbackCount.value == 6)

        runtime = nil
        #expect(controller.sensitiveObserverCountForTesting == 0)
        expiries = snapshotExpiries()
        dateBox.advance(by: 60)
        try await awaitVaultAction { controller.copyPassword(id: originalEntry.id, completion: $0) }
        #expect(snapshotExpiries() == expiries)
        #expect(callbackCount.value == 7)
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func awaitVaultAction(
        _ operation: (@escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            operation { continuation.resume(with: $0) }
        }
    }

    private func menuIdentity(_ client: VaultAgentClientKind) -> VaultAgentPeerIdentity {
        VaultAgentPeerIdentity(
            client: client,
            helperRequirement: "identifier com.pastera.helper",
            helperCDHash: Data([1]),
            helperIsAdHoc: false,
            helperPath: "/Applications/Pastera.app/Contents/Helpers/helper",
            hostRequirement: client == .cli ? nil : "identifier com.example.host",
            hostCDHash: client == .cli ? nil : Data([2]),
            hostIsAdHoc: client == .cli ? nil : false,
            hostPath: client == .cli ? nil : "/Applications/Host.app/Contents/MacOS/Host"
        )
    }

    private func makeVaultController(
        folders: [PasswordVaultFolder],
        entries: [PasswordVaultEntry]
    ) -> MainMenuPanelController {
        MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: { folders }, fetchEntries: { entries },
                copyPassword: { _, completion in completion(.success(())) },
                loadDraft: { id, completion in
                    guard let entry = entries.first(where: { $0.id == id }) else {
                        completion(.failure(.entryNotFound))
                        return
                    }
                    completion(.success(PasswordVaultDraft(
                        folderID: entry.folderID,
                        title: entry.title,
                        website: entry.website,
                        username: entry.username,
                        note: entry.note,
                        password: "secret"
                    )))
                },
                createEntry: { _, completion in completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { name in
                    PasswordVaultFolder(id: UUID(), name: name, createdAt: .now, updatedAt: .now)
                },
                renameFolder: { id, name in
                    PasswordVaultFolder(id: id, name: name, createdAt: .distantPast, updatedAt: .now)
                },
                deleteFolder: { _ in }
            )
        )
    }

    private func makeVaultController(
        state: @escaping () -> PasswordVaultState,
        canQuickUnlock: @escaping () -> Bool = { false },
        folders: @escaping () throws -> [PasswordVaultFolder],
        createDatabase: @escaping (String, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, completion in
            completion(.failure(.saveFailed))
        },
        unlock: @escaping (String, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, completion in
            completion(.failure(.wrongMasterPassword))
        },
        unlockWithQuickKey: @escaping (@escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { completion in
            completion(.failure(.keychainUnavailable))
        },
        retryLocalPreparation: @escaping () -> Void = {},
        syncDataSource: MainMenuPasswordVaultSyncDataSource? = nil,
        oneDriveStatusService: OneDriveProcessStatusServicing = PasswordVaultMenuOneDriveProcessStatusService(
            status: .notInstalled
        ),
        onOpenOneDriveStatus: (() -> Void)? = nil
    ) -> MainMenuPanelController {
        MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                state: state,
                checkQuickUnlockAvailability: { completion in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let isAvailable = canQuickUnlock()
                        DispatchQueue.main.async { completion(isAvailable) }
                    }
                },
                createDatabase: createDatabase,
                unlock: unlock, unlockWithQuickKey: unlockWithQuickKey,
                retryLocalPreparation: retryLocalPreparation,
                fetchFolders: folders, fetchEntries: { [] },
                copyPassword: { _, completion in completion(.success(())) },
                loadDraft: { _, completion in completion(.failure(.entryNotFound)) },
                createEntry: { _, completion in completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { name in
                    PasswordVaultFolder(id: UUID(), name: name, createdAt: .now, updatedAt: .now)
                },
                renameFolder: { id, name in
                    PasswordVaultFolder(id: id, name: name, createdAt: .distantPast, updatedAt: .now)
                },
                deleteFolder: { _ in }
            ),
            passwordVaultSyncDataSource: syncDataSource,
            oneDriveStatusService: oneDriveStatusService,
            onOpenOneDriveStatus: onOpenOneDriveStatus
        )
    }
}

@MainActor
private func findVaultFolderEditor(in view: NSView) -> PasswordVaultFolderEditorView? {
    if let editor = view as? PasswordVaultFolderEditorView { return editor }
    for subview in view.subviews {
        if let editor = findVaultFolderEditor(in: subview) { return editor }
    }
    return nil
}

private func menuSyncDataSource(
    snapshot: @escaping () -> PasswordVaultSyncSnapshot = {
        PasswordVaultSyncSnapshot(
            mode: .localOnly,
            phase: .disabled,
            localVaultAvailable: true,
            remoteVaultAvailable: nil,
            pendingChangeCount: 0,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
    },
    enableConfiguredOneDrive: @escaping (
        String?,
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void = { _, completion in completion(.success(())) },
    retryWithRemotePassword: @escaping (
        String,
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void = { _, completion in completion(.success(())) },
    startOneDrive: @escaping () -> Bool = { false }
) -> MainMenuPasswordVaultSyncDataSource {
    MainMenuPasswordVaultSyncDataSource(
        snapshot: snapshot,
        enableConfiguredOneDrive: enableConfiguredOneDrive,
        retryWithRemotePassword: retryWithRemotePassword,
        startOneDrive: startOneDrive
    )
}

private final class PasswordVaultMenuOneDriveProcessStatusService: OneDriveProcessStatusServicing {
    var status: OneDriveProcessStatus
    private(set) var openCallCount = 0

    init(status: OneDriveProcessStatus) {
        self.status = status
    }

    func currentStatus() -> OneDriveProcessStatus { status }

    func isMainApplicationRunning() -> Bool { status.isRunning }

    func openOneDrive() -> Bool {
        openCallCount += 1
        return status.appURL != nil
    }

    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation {
        OneDriveProcessStatusObservation {}
    }
}

private func makeMenuLocalStorage(at root: URL) -> FilePasswordVaultLocalStorage {
    let directory = root.appendingPathComponent("PasswordVault", isDirectory: true)
    return FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
        directoryURL: directory,
        vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
        backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
        metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
    ))
}

@MainActor
private func waitUntil(
    _ label: String = "condition",
    timeout: TimeInterval = 5,
    condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), Comment(rawValue: label))
}

private final class AllowPasswordVaultAuthorizer: PasswordVaultAuthorizing {
    func authorize(reason: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        completion(.success(()))
    }
}

private final class PasswordVaultClipboardProbe: SecureClipboardWriting {
    var value: String?

    func copySecret(_ secret: String, clearAfter: Duration) { value = secret }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class MenuRuntimeDateBox: @unchecked Sendable {
    var value: Date

    init(_ value: Date) { self.value = value }
    func advance(by interval: TimeInterval) { value = value.addingTimeInterval(interval) }
}

private final class MenuRuntimeGrantStore: VaultAgentGrantStoring {
    private var grants: [VaultAgentClientKind: VaultAgentGrant] = [:]

    func load() -> [VaultAgentClientKind: VaultAgentGrant] { grants }
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) { self.grants = grants }
}

private final class MenuRuntimeTargetTracker: VaultAgentPasteTargetTracking {
    func resolve() throws -> PasteTargetContext { throw VaultAgentPasteTargetError.unavailable }
}

private final class MenuRuntimeAuditLogger: VaultAgentAuditLogging {
    // swiftlint:disable:next function_parameter_count
    func record(
        client _: VaultAgentClientKind,
        action _: VaultAgentAuditAction,
        entryID _: UUID?,
        result _: VaultAgentErrorCode?,
        latencyBucket _: VaultAgentLatencyBucket,
        at _: Date
    ) {}
}
