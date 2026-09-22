//
//  SyncPreferenceTopSectionTests.swift
//
//  Pastera
//

import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct SyncPreferenceTopSectionTests {
    private struct PreferenceTextFieldFrame {
        let text: String
        let frame: NSRect
        let intrinsicWidth: CGFloat
    }

    @Test
    func syncPaneOwnsTheNativePageAndApprovedAnchors() throws {
        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { .notFound })
            controller.loadView()
            controller.viewDidLoad()

            let page = try #require(controller as? any PasteraPreferencePage)
            #expect(page.paneID == .sync)
            for anchorID in [
                "sync.oneDriveStatus",
                "sync.rootFolder",
                "sync.passwordVault",
                "sync.fileTypes",
                "sync.actions"
            ] {
                #expect(page.revealSetting(anchorID: anchorID, animated: false))
            }

            let labels = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(labels.contains(pasteraPreferenceString("Sync")))
            #expect(labels.contains(pasteraPreferenceString("OneDrive Status")))
            #expect(labels.contains(pasteraPreferenceString("Sync Location")))
            #expect(labels.contains(pasteraPreferenceString("Password Vault Sync")))
            #expect(labels.contains(pasteraPreferenceString("File Types")))
            #expect(labels.contains(pasteraPreferenceString("Manual Sync")))
            #expect(!labels.contains("同步口令"))
            #expect(!labels.contains("状态摘要"))
        }
    }

    @Test
    func syncPaneReloadDoesNotDuplicateControls() throws {
        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { .notFound })
            controller.loadView()
            controller.viewDidLoad()
            controller.loadView()
            controller.viewDidLoad()

            let buttons = preferenceButtons(in: controller.view)
            #expect(buttons.filter { $0.title == pasteraPreferenceString("Sync Now") }.count == 1)
            #expect(buttons.filter {
                $0.accessibilityLabel() == pasteraPreferenceString("Upload History")
            }.count == 1)
            #expect(buttons.filter {
                $0.accessibilityLabel() == pasteraPreferenceString("Import History")
            }.count == 1)
            #expect(buttons.filter {
                $0.accessibilityLabel() == pasteraPreferenceString("Upload Snippets")
            }.count == 1)
            #expect(buttons.filter {
                $0.accessibilityLabel() == pasteraPreferenceString("Import Snippets")
            }.count == 1)
            #expect(buttons.filter {
                $0.accessibilityLabel() == pasteraPreferenceString("Images")
            }.count == 1)
            #expect(buttons.filter {
                $0.accessibilityLabel() == pasteraPreferenceString("Common Document Types")
            }.count == 1)
        }
    }

    @Test
    func syncPaneUsesSharedGroupsAndKeepsAllExistingControlsVisible() throws {
        try withPreservedSyncDefaults {
            let controller = CPYPreferencesWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.showPreferencePaneForTesting(title: "Sync")
            let contentView = try #require(controller.window?.contentView)
            contentView.layoutSubtreeIfNeeded()

            let texts = Set(preferenceTextFieldFrames(in: contentView).map(\.text))
            let buttons = preferenceButtons(in: contentView)
            let switchLabels: Set<String> = [
                pasteraPreferenceString("Upload History"),
                pasteraPreferenceString("Import History"),
                pasteraPreferenceString("Upload Snippets"),
                pasteraPreferenceString("Import Snippets")
            ]
            let fileTypeLabels: Set<String> = [
                pasteraPreferenceString("Images"),
                pasteraPreferenceString("Common Document Types")
            ]

            #expect([
                pasteraPreferenceString("Sync"),
                pasteraPreferenceString("OneDrive"),
                pasteraPreferenceString("Password Vault"),
                pasteraPreferenceString("Sync Scope"),
                pasteraPreferenceString("Actions")
            ].allSatisfy(texts.contains))
            #expect(buttons.filter { switchLabels.contains($0.accessibilityLabel() ?? "") }.count == 4)
            #expect(buttons.filter { fileTypeLabels.contains($0.accessibilityLabel() ?? "") }.count == 2)
            #expect(buttons.contains { $0.title == pasteraPreferenceString("Change") })
            #expect(buttons.contains { $0.title == pasteraPreferenceString("Show in Finder") })
            #expect(buttons.contains { $0.title == pasteraPreferenceString("Sync Now") })
            #expect(controller.visiblePreferenceScrollViewCountForTesting == 1)
            #expect(controller.preferencePaneHasVerticalScrollerForTesting)
        }
    }

    @Test
    func syncPaneManualSyncPromptsToInstallOneDriveWhenDefaultLocationIsMissing() throws {
        let defaults = AppEnvironment.current.defaults
        let syncKeys = [
            Constants.UserDefaults.syncAutomaticUploadEnabled,
            Constants.UserDefaults.syncAutomaticEnabled,
            Constants.UserDefaults.syncRootPath,
            Constants.UserDefaults.syncHistoryUploadEnabled,
            Constants.UserDefaults.syncHistoryImportEnabled,
            Constants.UserDefaults.syncSnippetUploadEnabled,
            Constants.UserDefaults.syncSnippetImportEnabled,
            Constants.UserDefaults.syncFileUploadEnabled,
            Constants.UserDefaults.syncFileImportEnabled,
            Constants.UserDefaults.syncFileTypes
        ]
        let previousValues = syncKeys.reduce(into: [String: Any]()) { values, key in
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        defer {
            syncKeys.forEach { key in
                if let value = previousValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.synchronize()
        }

        syncKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()

        let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { .notFound })
        controller.loadView()
        controller.viewDidLoad()
        controller.view.layoutSubtreeIfNeeded()
        let syncButton = try #require(preferenceButtons(in: controller.view).first { $0.title == "立即同步" })

        syncButton.performClick(nil)
        controller.view.layoutSubtreeIfNeeded()

        let visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
        #expect(visibleTexts.contains("未检测到 OneDrive"))
        #expect(visibleTexts.contains("OneDrive 状态"))
        #expect(!visibleTexts.contains("请先安装并登录 OneDrive。"))
    }

    @Test
    func syncPaneManualRedetectDiscoversDefaultOneDriveLocation() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }
        var resolution = SyncDefaultFolderResolution.notFound

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: { resolution })
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("未检测到 OneDrive"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == nil)

            resolution = .found(SyncDefaultFolderCandidate(
                oneDriveRootURL: oneDriveRootURL,
                syncRootURL: defaultRootURL,
                displayName: "OneDrive",
                isOneDriveBacked: true
            ))
            let redetectButton = try #require(preferenceButtons(in: controller.view).first {
                $0.accessibilityLabel() == "重新检测 OneDrive"
            })

            redetectButton.performClick(nil)
            controller.view.layoutSubtreeIfNeeded()

            visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
            #expect(FileManager.default.fileExists(atPath: defaultRootURL.path))
        }
    }

    @Test
    func visibleSyncPaneRefreshesWhenOneDriveProcessStatusChanges() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = SyncDefaultFolderResolver.defaultFolderURL(oneDriveRootURL: oneDriveRootURL)
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }
        var resolution = SyncDefaultFolderResolution.notFound
        let processStatusService = SyncPreferenceOneDriveProcessStatusService()

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { resolution },
                oneDriveProcessStatusService: processStatusService
            )
            let window = SyncTopSectionVisibilityWindow()
            window.contentView = controller.view
            window.testIsVisible = true
            defer { window.contentView = nil }
            controller.view.layoutSubtreeIfNeeded()

            var texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(texts.contains("未检测到 OneDrive"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == nil)

            resolution = .found(SyncDefaultFolderCandidate(
                oneDriveRootURL: oneDriveRootURL,
                syncRootURL: defaultRootURL,
                displayName: "OneDrive",
                isOneDriveBacked: true
            ))
            processStatusService.sendLifecycleChange()
            controller.view.layoutSubtreeIfNeeded()

            texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(texts.contains("OneDrive 可用"))
            #expect(defaults.string(forKey: Constants.UserDefaults.syncRootPath) == defaultRootURL.standardizedFileURL.path)
        }
    }

    @Test
    func syncPaneDoesNotSilentlyChooseNamedOneDriveAccount() throws {
        let oneDriveRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneDrive-公司名称", isDirectory: true)
        let candidate = SyncDefaultFolderCandidate(
            oneDriveRootURL: oneDriveRootURL,
            syncRootURL: SyncDefaultFolderResolver.defaultFolderURL(oneDriveRootURL: oneDriveRootURL),
            displayName: "OneDrive-公司名称",
            isOneDriveBacked: true
        )

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .multiple([candidate]) }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.syncRootPath) == nil)
            #expect(texts.contains("请选择 OneDrive 文件夹"))
        }
    }

    @Test
    func syncPaneDoesNotSaveAnAutomaticallyPreparedRootWhenTheProbeFails() throws {
        try withPreservedSyncDefaults {
            let homeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: homeURL) }
            let oneDriveRootURL = homeURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("CloudStorage", isDirectory: true)
                .appendingPathComponent("OneDrive", isDirectory: true)
            try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
            let candidate = SyncDefaultFolderCandidate(
                oneDriveRootURL: oneDriveRootURL,
                syncRootURL: SyncDefaultFolderResolver.defaultFolderURL(oneDriveRootURL: oneDriveRootURL),
                displayName: "OneDrive",
                isOneDriveBacked: true
            )
            var probedURL: URL?
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .found(candidate) },
                syncRootProbe: { rootURL in
                    probedURL = rootURL
                    return false
                }
            )

            controller.loadView()
            controller.viewDidLoad()

            #expect(probedURL == candidate.syncRootURL.standardizedFileURL)
            #expect(UserDefaultsSyncSettingsStore().settings().rootURL == nil)
        }
    }

    @Test
    func hiddenSyncPaneDoesNotRefreshSavedFolderStatusOnApplicationActivation() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oneDriveRootURL = cloudStorageURL(homeURL: homeURL).appendingPathComponent("OneDrive", isDirectory: true)
        let defaultRootURL = oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(defaultRootURL.path, forKey: Constants.UserDefaults.syncRootPath)
            let controller = CPYSyncPreferenceViewController(defaultFolderResolutionProvider: {
                .found(SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: defaultRootURL,
                    displayName: "OneDrive",
                    isOneDriveBacked: true
                ))
            })
            let window = SyncTopSectionVisibilityWindow()
            window.contentView = controller.view
            window.testIsVisible = true
            defer { window.contentView = nil }

            var visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("OneDrive 可用"))

            window.testIsVisible = false
            try FileManager.default.removeItem(at: defaultRootURL)
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            controller.view.layoutSubtreeIfNeeded()

            visibleTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(visibleTexts.contains("OneDrive 可用"))
            #expect(!visibleTexts.contains("OneDrive 不可用"))
        }
    }

    private func preferenceTextFieldFrames(
        in view: NSView,
        root: NSView? = nil
    ) -> [PreferenceTextFieldFrame] {
        let rootView = root ?? view
        var values = [PreferenceTextFieldFrame]()
        guard view.isHidden == false, view.alphaValue > 0 else { return [] }
        if let textField = view as? NSTextField, textField.stringValue.isEmpty == false {
            values.append(PreferenceTextFieldFrame(
                text: textField.stringValue,
                frame: rootView.convert(textField.frame, from: textField.superview),
                intrinsicWidth: ceil(textField.intrinsicContentSize.width)
            ))
        }
        view.subviews.forEach {
            values.append(contentsOf: preferenceTextFieldFrames(in: $0, root: rootView))
        }
        return values
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceViewFrame(
        in view: NSView,
        identifier: String,
        root: NSView? = nil
    ) -> NSRect? {
        let rootView = root ?? view
        guard view.isHidden == false, view.alphaValue > 0 else { return nil }
        if view.identifier?.rawValue == identifier {
            return rootView.convert(view.frame, from: view.superview)
        }
        for subview in view.subviews {
            if let frame = preferenceViewFrame(in: subview, identifier: identifier, root: rootView) {
                return frame
            }
        }
        return nil
    }

    private func preferenceSwitches(in view: NSView) -> [NSSwitch] {
        var switches = view.subviews.compactMap { $0 as? NSSwitch }
        view.subviews.forEach { switches.append(contentsOf: preferenceSwitches(in: $0)) }
        return switches
    }

    private func preferenceSwitchButtons(in view: NSView, labels: Set<String>) -> [NSButton] {
        preferenceButtons(in: view).filter {
            labels.contains($0.accessibilityLabel() ?? "")
        }
    }

    private func cloudStorageURL(homeURL: URL) -> URL {
        homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
    }

    private func withPreservedSyncDefaults(_ work: () throws -> Void) throws {
        let defaults = AppEnvironment.current.defaults
        let syncKeys = [
            Constants.UserDefaults.syncAutomaticUploadEnabled,
            Constants.UserDefaults.syncAutomaticEnabled,
            Constants.UserDefaults.syncRootPath,
            Constants.UserDefaults.syncHistoryUploadEnabled,
            Constants.UserDefaults.syncHistoryImportEnabled,
            Constants.UserDefaults.syncSnippetUploadEnabled,
            Constants.UserDefaults.syncSnippetImportEnabled,
            Constants.UserDefaults.syncFileUploadEnabled,
            Constants.UserDefaults.syncFileImportEnabled,
            Constants.UserDefaults.syncFileTypes
        ]
        let previousValues = syncKeys.reduce(into: [String: Any]()) { values, key in
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        syncKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()
        defer {
            syncKeys.forEach { key in
                if let value = previousValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.synchronize()
        }
        try work()
    }
}

extension SyncPreferenceTopSectionTests {
    @Test
    func runningOneDriveDistinguishesAnUnavailableFolderFromAStoppedClient() throws {
        let defaults = AppEnvironment.current.defaults
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unavailableRootURL = cloudStorageURL(homeURL: homeURL)
            .appendingPathComponent("OneDrive", isDirectory: true)
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try withPreservedSyncDefaults {
            defaults.set(unavailableRootURL.path, forKey: Constants.UserDefaults.syncRootPath)
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .notFound },
                oneDriveProcessStatusService: SyncPreferenceOneDriveProcessStatusService()
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(texts.contains("OneDrive 已启动 · 文件夹不可用"))
            #expect(!texts.contains("OneDrive 不可用"))
        }
    }

    @Test
    func passwordVaultSummaryIsIndependentFromHistoryAndSnippetSyncControls() throws {
        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .notFound },
                passwordVaultSyncSnapshotProvider: {
                    PasswordVaultSyncSnapshot(
                        mode: .localOnly,
                        phase: .disabled,
                        localVaultAvailable: true,
                        remoteVaultAvailable: nil,
                        pendingChangeCount: 0,
                        conflictCopyCount: 0,
                        lastSyncAt: nil
                    )
                }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            let buttons = preferenceButtons(in: controller.view)
            let historyAndSnippetLabels: Set<String> = [
                pasteraPreferenceString("Upload History"),
                pasteraPreferenceString("Import History"),
                pasteraPreferenceString("Upload Snippets"),
                pasteraPreferenceString("Import Snippets")
            ]

            #expect(texts.contains(pasteraPreferenceString("Password Vault")))
            #expect(texts.contains(pasteraPreferenceString("OneDrive sync is off")))
            #expect(texts.contains(
                pasteraPreferenceString("Password vault sync is independent from history and snippet sync.")
            ))
            #expect(buttons.filter { historyAndSnippetLabels.contains($0.accessibilityLabel() ?? "") }.count == 4)
            #expect(buttons.filter { $0.title == pasteraPreferenceString("Enable OneDrive Sync") }.count == 1)
        }
    }

    @Test
    func passwordVaultSummaryShowsDisconnectedPendingChangesWithoutDuplicateRecoveryControls() throws {
        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .notFound },
                passwordVaultSyncSnapshotProvider: {
                    PasswordVaultSyncSnapshot(
                        mode: .oneDrive,
                        phase: .disconnected(.oneDriveNotRunning),
                        localVaultAvailable: true,
                        remoteVaultAvailable: false,
                        pendingChangeCount: 3,
                        conflictCopyCount: 0,
                        lastSyncAt: nil
                    )
                }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            let buttons = preferenceButtons(in: controller.view)
            let disconnectedSummary = String(
                format: pasteraPreferenceString("OneDrive is disconnected; %lld changes are waiting"),
                Int64(3)
            )

            #expect(texts.contains(disconnectedSummary))
            #expect(buttons.first {
                $0.title == pasteraPreferenceString("Enable OneDrive Sync")
            }?.isHidden == true)
            #expect(!buttons.contains { $0.title == pasteraPreferenceString("Start OneDrive") })
            #expect(!buttons.contains { $0.title == pasteraPreferenceString("Try Again") })
        }
    }

    @Test(arguments: [
        PasswordVaultSyncFailure.remoteCredentialsRequired,
        PasswordVaultSyncFailure.remoteUnavailable
    ])
    func passwordVaultSummaryShowsSpecificFailureDetails(failure: PasswordVaultSyncFailure) throws {
        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .notFound },
                passwordVaultSyncSnapshotProvider: {
                    PasswordVaultSyncSnapshot(
                        mode: .oneDrive,
                        phase: .failed(failure),
                        localVaultAvailable: true,
                        remoteVaultAvailable: true,
                        pendingChangeCount: 2,
                        conflictCopyCount: 0,
                        lastSyncAt: nil
                    )
                }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(texts.contains(passwordVaultSyncFailureMessage(failure)))
        }
    }

    @Test
    func visiblePasswordVaultSummaryUpdatesWhenSyncRecovers() throws {
        let syncService = SyncPreferencePasswordVaultSyncService()
        AppEnvironment.push(passwordVaultSyncService: syncService)
        defer { AppEnvironment.popLast() }

        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .notFound },
                oneDriveProcessStatusService: SyncPreferenceOneDriveProcessStatusService()
            )
            let window = SyncTopSectionVisibilityWindow()
            window.contentView = controller.view
            window.testIsVisible = true
            defer { window.contentView = nil }
            controller.view.layoutSubtreeIfNeeded()
            let failureMessage = passwordVaultSyncFailureMessage(.remoteUnavailable)
            let initialTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(initialTexts.contains(failureMessage))

            syncService.publish(phase: .synced)
            controller.view.layoutSubtreeIfNeeded()

            let updatedTexts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            #expect(updatedTexts.contains(pasteraPreferenceString("OneDrive is connected")))
            #expect(!updatedTexts.contains(failureMessage))
        }
    }

    @Test
    func passwordVaultSummaryObservationIsReplacedOnReloadAndRemovedOnDeinit() throws {
        let syncService = SyncPreferencePasswordVaultSyncService()
        AppEnvironment.push(passwordVaultSyncService: syncService)
        defer { AppEnvironment.popLast() }

        try withPreservedSyncDefaults {
            weak var releasedController: CPYSyncPreferenceViewController?
            let initialObserverCount = syncService.observerCount
            autoreleasepool {
                let controller = CPYSyncPreferenceViewController(
                    defaultFolderResolutionProvider: { .notFound },
                    oneDriveProcessStatusService: SyncPreferenceOneDriveProcessStatusService()
                )
                releasedController = controller
                for _ in 0..<3 {
                    controller.loadView()
                    controller.viewDidLoad()
                    #expect(syncService.observerCount == initialObserverCount + 1)
                }
            }

            #expect(releasedController == nil)
            #expect(syncService.observerCount == initialObserverCount)
        }
    }

    @Test
    func passwordVaultSummaryShowsLastVerifiedSyncTime() throws {
        try withPreservedSyncDefaults {
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .notFound },
                passwordVaultSyncSnapshotProvider: {
                    PasswordVaultSyncSnapshot(
                        mode: .oneDrive,
                        phase: .synced,
                        localVaultAvailable: true,
                        remoteVaultAvailable: true,
                        pendingChangeCount: 0,
                        conflictCopyCount: 0,
                        lastSyncAt: Date(timeIntervalSince1970: 1_800_000_000)
                    )
                }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()

            let texts = Set(preferenceTextFieldFrames(in: controller.view).map(\.text))
            let lastSyncPrefix = pasteraPreferenceString("Last synced: %@")
                .components(separatedBy: "%@")
                .first ?? ""
            #expect(texts.contains(pasteraPreferenceString("OneDrive is connected")))
            #expect(texts.contains { $0.hasPrefix(lastSyncPrefix) })
        }
    }

    @Test
    func enablePasswordVaultSyncUsesTheConfiguredOneDriveFolder() throws {
        try withPreservedSyncDefaults {
            let oneDriveRootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("CloudStorage", isDirectory: true)
                .appendingPathComponent("OneDrive", isDirectory: true)
            let syncRootURL = SyncDefaultFolderResolver.defaultFolderURL(oneDriveRootURL: oneDriveRootURL)
            try FileManager.default.createDirectory(at: syncRootURL, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(
                    at: oneDriveRootURL
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                )
            }
            AppEnvironment.current.defaults.set(
                syncRootURL.standardizedFileURL.path,
                forKey: Constants.UserDefaults.syncRootPath
            )
            var enabledRootURL: URL?
            let controller = CPYSyncPreferenceViewController(
                defaultFolderResolutionProvider: { .notFound },
                passwordVaultSyncSnapshotProvider: {
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
                enablePasswordVaultSync: { rootURL, completion in
                    enabledRootURL = rootURL
                    completion(.success(()))
                }
            )
            controller.loadView()
            controller.viewDidLoad()
            controller.view.layoutSubtreeIfNeeded()
            let enableButton = try #require(preferenceButtons(in: controller.view).first {
                $0.title == pasteraPreferenceString("Enable OneDrive Sync")
            })

            enableButton.performClick(nil)

            #expect(enabledRootURL == syncRootURL.standardizedFileURL)
        }
    }
}

private final class SyncPreferencePasswordVaultSyncService: PasswordVaultSyncControlling {
    private(set) var snapshot = PasswordVaultSyncSnapshot(
        mode: .oneDrive,
        phase: .failed(.remoteUnavailable),
        localVaultAvailable: true,
        remoteVaultAvailable: true,
        pendingChangeCount: 2,
        conflictCopyCount: 0,
        lastSyncAt: nil
    )
    private var observers = [UUID: (PasswordVaultSyncSnapshot) -> Void]()

    var observerCount: Int { observers.count }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        observers[identifier] = observer
        observer(snapshot)
        return identifier
    }

    func removeObserver(_ identifier: UUID) {
        observers.removeValue(forKey: identifier)
    }

    func record(_: PasswordVaultCommit) {}
    func synchronize(reason _: SyncCoordinator.Reason) {}

    func enableOneDrive(
        rootURL _: URL,
        remoteMasterPassword _: String?, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        completion(.success(()))
    }

    func publish(phase: PasswordVaultSyncPhase) {
        snapshot = PasswordVaultSyncSnapshot(
            mode: .oneDrive,
            phase: phase,
            localVaultAvailable: true,
            remoteVaultAvailable: true,
            pendingChangeCount: 0,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
        Array(observers.values).forEach { $0(snapshot) }
    }
}

private final class SyncTopSectionVisibilityWindow: NSWindow {
    var testIsVisible = false
    private(set) var didClose = false

    override var isVisible: Bool {
        testIsVisible
    }

    override func close() {
        didClose = true
    }
}

private final class SyncPreferenceOneDriveProcessStatusService: OneDriveProcessStatusServicing {
    private var onChange: (() -> Void)?

    func currentStatus() -> OneDriveProcessStatus {
        .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
    }

    func isMainApplicationRunning() -> Bool { true }

    func openOneDrive() -> Bool { true }

    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation {
        self.onChange = onChange
        return OneDriveProcessStatusObservation { [weak self] in
            self?.onChange = nil
        }
    }

    func sendLifecycleChange() {
        onChange?()
    }
}
