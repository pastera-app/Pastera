//
//  Environment.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2017/08/10.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

struct Environment {

    // MARK: - Properties
    let clipService: ClipService
    let hotKeyService: HotKeyService
    let pasteService: PasteService
    let excludeAppService: ExcludeAppService
    let accessibilityService: AccessibilityService
    let oneDriveProcessStatusService: OneDriveProcessStatusServicing
    let passwordVaultStore: PasswordVaultStore
    let passwordVaultSyncService: PasswordVaultSyncControlling
    let retryPasswordVaultLocalPreparation: () -> Void
    let secureClipboard: SecureClipboardWriting
    let passwordVaultUIController: PasswordVaultUIController
    let vaultAgentApplicationRuntime: VaultAgentApplicationRuntimeServicing
    let clipboardScriptCoordinator: ClipboardScriptCoordinating
    let promptOptimizationService: PromptOptimizationServicing
    let menuManager: MenuManager

    let defaults: UserDefaults

    // MARK: - Initialize
    init(clipService: ClipService? = nil,
         hotKeyService: HotKeyService = HotKeyService(),
         pasteService: PasteService? = nil,
         excludeAppService: ExcludeAppService = ExcludeAppService(applications: []),
         accessibilityService: AccessibilityService = AccessibilityService(),
         oneDriveProcessStatusService: OneDriveProcessStatusServicing = OneDriveProcessStatusService(),
         passwordVaultStore: PasswordVaultStore? = nil,
         passwordVaultSyncService: PasswordVaultSyncControlling? = nil,
         passwordVaultMigrator: PasswordVaultMigrating? = nil,
         retryPasswordVaultLocalPreparation: (() -> Void)? = nil,
         prepareProductionPasswordVault: Bool = false,
         secureClipboard: SecureClipboardWriting = SecureClipboardService(),
         passwordVaultUIController: PasswordVaultUIController? = nil,
         vaultAgentApplicationRuntime: VaultAgentApplicationRuntimeServicing? = nil,
         vaultAgentApplicationRuntimeFactory: ((PasswordVaultUIController) ->
             VaultAgentApplicationRuntimeServicing)? = nil,
         clipboardScriptCoordinator: ClipboardScriptCoordinating = ClipboardScriptCoordinator(
             repository: ScriptRepository(),
             executor: ScriptExecutionService()
         ),
         promptOptimizationService: PromptOptimizationServicing? = nil,
         menuManager: MenuManager = MenuManager(),
         defaults: UserDefaults = .standard) {

        self.clipService = clipService ?? ClipService(
            clipboardScriptCoordinatorProvider: { clipboardScriptCoordinator }
        )
        self.hotKeyService = hotKeyService
        let resolvedPasteService = pasteService ?? PasteService(
            clipboardScriptCoordinatorProvider: { clipboardScriptCoordinator }
        )
        self.pasteService = resolvedPasteService
        self.excludeAppService = excludeAppService
        self.accessibilityService = accessibilityService
        self.oneDriveProcessStatusService = oneDriveProcessStatusService
        let vaultQueue = DispatchQueue(
            label: "com.pastera.password-vault.store",
            qos: .userInitiated
        )
        let localStorage = FilePasswordVaultLocalStorage.live()
        let metadataStore = JSONPasswordVaultSyncMetadataStore(url: localStorage.paths.metadataURL)
        let usesProductionVaultStore = passwordVaultStore == nil
        let resolvedPasswordVaultStore = passwordVaultStore ?? KDBXPasswordVaultStore(
            localStorage: localStorage,
            autoLockTimeoutProvider: { VaultSessionController.resolvedTimeout(defaults: defaults) }
        )
        self.passwordVaultStore = resolvedPasswordVaultStore
        let syncSettingsStore = UserDefaultsSyncSettingsStore(defaults: defaults)
        let resolvedPasswordVaultMigrator = passwordVaultMigrator ?? (usesProductionVaultStore
            && prepareProductionPasswordVault
            ? PasswordVaultMigrationService(
                localStorage: localStorage,
                metadataStore: metadataStore,
                legacySyncRootProvider: { syncSettingsStore.settings().rootURL }
            )
            : nil)
        let resolvedPasswordVaultSyncService: PasswordVaultSyncControlling
        if let passwordVaultSyncService {
            resolvedPasswordVaultSyncService = passwordVaultSyncService
        } else if usesProductionVaultStore,
                  let access = resolvedPasswordVaultStore as? PasswordVaultSyncAccess {
            do {
                resolvedPasswordVaultSyncService = try PasswordVaultSyncService(
                    access: access,
                    metadataStore: metadataStore,
                    cloudReplica: OneDrivePasswordVaultCloudReplica(),
                    processStatus: oneDriveProcessStatusService,
                    rootURLProvider: { syncSettingsStore.settings().rootURL },
                    rootURLSetter: { syncSettingsStore.setRootURL($0) },
                    rootValidator: Self.validatePasswordVaultSyncRoot,
                    prepareLocalCopy: {
                        guard let resolvedPasswordVaultMigrator else { return }
                        resolvedPasswordVaultStore.prepareLocalCopy(using: resolvedPasswordVaultMigrator)
                    },
                    queue: vaultQueue
                )
            } catch {
                resolvedPasswordVaultSyncService = LocalOnlyPasswordVaultSyncController(
                    localVaultAvailable: Self.isLocalVaultAvailable(resolvedPasswordVaultStore.state),
                    failure: .remoteUnavailable
                )
            }
        } else {
            resolvedPasswordVaultSyncService = LocalOnlyPasswordVaultSyncController(
                localVaultAvailable: Self.isLocalVaultAvailable(resolvedPasswordVaultStore.state)
            )
        }
        self.passwordVaultSyncService = resolvedPasswordVaultSyncService
        self.secureClipboard = secureClipboard
        let resolvedPasswordVaultUIController = passwordVaultUIController ?? PasswordVaultUIController(
            store: resolvedPasswordVaultStore,
            syncController: resolvedPasswordVaultSyncService,
            clipboard: secureClipboard,
            pasteService: resolvedPasteService,
            defaults: defaults,
            storeQueue: vaultQueue
        )
        self.passwordVaultUIController = resolvedPasswordVaultUIController
        let retryLocalPreparation = retryPasswordVaultLocalPreparation ?? {
            guard let resolvedPasswordVaultMigrator else { return }
            resolvedPasswordVaultUIController.vaultAgentExecutor.async {
                resolvedPasswordVaultStore.prepareLocalCopy(using: resolvedPasswordVaultMigrator)
            }
        }
        self.retryPasswordVaultLocalPreparation = retryLocalPreparation
        if resolvedPasswordVaultMigrator != nil {
            retryLocalPreparation()
        }
        self.vaultAgentApplicationRuntime = vaultAgentApplicationRuntime ??
            vaultAgentApplicationRuntimeFactory?(resolvedPasswordVaultUIController) ??
            UnavailableVaultAgentApplicationRuntime()
        self.clipboardScriptCoordinator = clipboardScriptCoordinator
        self.promptOptimizationService = promptOptimizationService ?? PromptOptimizationService(
            settingsStore: PromptOptimizationSettingsStore(defaults: defaults),
            apiKeyStore: PromptOptimizationAPIKeyStore()
        )
        self.menuManager = menuManager
        self.defaults = defaults
    }

    static func validatePasswordVaultSyncRoot(_ url: URL) -> PasswordVaultSyncFailure? {
        validatePasswordVaultSyncRoot(
            url,
            fileProviderIdentityChecker: SyncDefaultFolderResolver.isFileProviderBacked
        )
    }

    static func validatePasswordVaultSyncRoot(
        _ url: URL,
        fileProviderIdentityChecker: SyncDefaultFolderResolver.FileProviderIdentityChecker
    ) -> PasswordVaultSyncFailure? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .folderUnavailable
        }
        guard SyncDefaultFolderResolver.isUsableOneDriveBackedURL(
            url,
            fileProviderIdentityChecker: fileProviderIdentityChecker
        ) else {
            return .folderUnavailable
        }
        return FileManager.default.isWritableFile(atPath: url.path) ? nil : .folderNotWritable
    }

    private static func isLocalVaultAvailable(_ state: PasswordVaultState) -> Bool {
        switch state {
        case .notConfigured, .preparingLocalCopy, .localCopyUnavailable:
            false
        case .locked, .unlocking, .unlocked, .readOnlyWarning, .recoveryRequired, .failed:
            true
        }
    }

}
