//
//  MainMenuPinFooterTests.swift
//
//  Clipy
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

// These serialized suites exercise the complete footer interaction surface.
// swiftlint:disable file_length

@MainActor
@Suite(.serialized)
struct MainMenuVaultSyncFooterTests {
    @Test
    func missingOneDriveWithVaultSyncDisabledUsesNeutralPresentationWithoutBadge() {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: makePasswordVaultSyncSnapshot(mode: .localOnly, phase: .disabled),
            processStatus: .notInstalled
        )

        #expect(presentation.badge == .none)
        #expect(presentation.tintColor.isEqual(NSColor.tertiaryLabelColor))
        #expect(presentation.accessibilityLabel == String(
            localized: "OneDrive is not installed; password vault sync is not enabled"
        ))
    }

    @Test
    func runningOneDriveStaysBlueWhenPasswordVaultSyncIsDisabled() {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: makePasswordVaultSyncSnapshot(mode: .localOnly, phase: .disabled),
            processStatus: .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )

        #expect(presentation.badge == .none)
        #expect(presentation.tintColor.isEqual(NSColor.systemBlue))
        #expect(presentation.accessibilityLabel == String(
            localized: "OneDrive is running; password vault sync is not enabled"
        ))
    }

    @Test
    func passwordVaultSyncedUsesBluePresentationWithoutBadge() {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: makePasswordVaultSyncSnapshot(mode: .oneDrive, phase: .synced),
            processStatus: .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )

        #expect(presentation.badge == .none)
        #expect(presentation.tintColor.isEqual(NSColor.systemBlue))
        #expect(presentation.accessibilityLabel == String(localized: "OneDrive is synced"))
    }

    @Test
    func passwordVaultSyncingUsesStaticProgressShapeAndTextSemantics() {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: makePasswordVaultSyncSnapshot(
                mode: .oneDrive,
                phase: .syncing(.uploading),
                pendingChangeCount: 1
            ),
            processStatus: .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )

        #expect(presentation.badge == .progress)
        #expect(presentation.tintColor.isEqual(NSColor.systemBlue))
        #expect(presentation.accessibilityLabel == String(
            format: String(localized: "OneDrive is syncing: %@"),
            String(localized: "Uploading encrypted replica")
        ))
    }

    @Test
    func enabledPasswordVaultSyncDisconnectedUsesRedShapeAndPendingText() {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: makePasswordVaultSyncSnapshot(
                mode: .oneDrive,
                phase: .synced,
                pendingChangeCount: 3
            ),
            processStatus: .notRunning(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )

        #expect(presentation.badge == .disconnected)
        #expect(presentation.badgeColor.isEqual(NSColor.systemRed))
        #expect(presentation.pendingChangeCount == 3)
        #expect(presentation.accessibilityLabel == String(
            format: String(localized: "OneDrive is disconnected; %lld changes are waiting"),
            Int64(3)
        ))
    }

    @Test
    func runningOneDriveRemainsVisiblyRunningWhenPasswordVaultSyncFails() {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: makePasswordVaultSyncSnapshot(
                mode: .oneDrive,
                phase: .failed(.remoteUnavailable)
            ),
            processStatus: .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )

        #expect(presentation.badge == .failed)
        #expect(presentation.badgeColor.isEqual(NSColor.systemOrange))
        #expect(presentation.tintColor.isEqual(NSColor.systemBlue))
        #expect(presentation.accessibilityLabel == String(localized: "OneDrive sync failed"))

        let button = MainMenuOneDriveStatusButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        button.configure(
            snapshot: makePasswordVaultSyncSnapshot(
                mode: .oneDrive,
                phase: .failed(.remoteUnavailable)
            ),
            processStatus: .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )
        #expect(button.syncBadgeSymbolForTesting == "exclamationmark")
    }

    @Test
    func passwordVaultConflictsUseYellowQuantityBadgeAndTextSemantics() {
        let presentation = MainMenuOneDriveStatusPresentation(
            snapshot: makePasswordVaultSyncSnapshot(
                mode: .oneDrive,
                phase: .conflicts(2),
                conflictCopyCount: 2
            ),
            processStatus: .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )

        #expect(presentation.badge == .conflicts(2))
        #expect(presentation.badgeColor.isEqual(NSColor.systemYellow))
        #expect(presentation.accessibilityLabel == String(
            format: String(localized: "OneDrive has %lld conflict copies"),
            Int64(2)
        ))
    }

    @Test
    func statusButtonRendersDisconnectedShapeWithoutEncodingSecretsInAccessibility() {
        let button = MainMenuOneDriveStatusButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        button.configure(
            snapshot: makePasswordVaultSyncSnapshot(
                mode: .oneDrive,
                phase: .disconnected(.oneDriveNotRunning),
                pendingChangeCount: 4
            ),
            processStatus: .notRunning(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
        )

        #expect(button.syncBadgeForTesting == .disconnected)
        #expect(button.accessibilityLabel() == String(
            format: String(localized: "OneDrive is disconnected; %lld changes are waiting"),
            Int64(4)
        ))
        #expect(button.syncBadgeSymbolForTesting == "bolt.slash.fill")
        #expect(button.hitTest(NSPoint(x: 21, y: 21)) === button)
    }

    private func makePasswordVaultSyncSnapshot(
        mode: PasswordVaultSyncMode,
        phase: PasswordVaultSyncPhase,
        pendingChangeCount: Int = 0,
        conflictCopyCount: Int = 0
    ) -> PasswordVaultSyncSnapshot {
        PasswordVaultSyncSnapshot(
            mode: mode,
            phase: phase,
            localVaultAvailable: true,
            remoteVaultAvailable: mode == .oneDrive,
            pendingChangeCount: pendingChangeCount,
            conflictCopyCount: conflictCopyCount,
            lastSyncAt: nil
        )
    }
}

@MainActor
@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct MainMenuOneDriveFooterTests {
    @Test
    func mainMenuPanelPlacesOneDriveStatusInFooterWithoutQuitOrPin() throws {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notRunning(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil, shortcutText: "⌃⌥⌘1") { _ in },
                    .separator,
                    .action(title: "Preferences", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuPinButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuQuitButton"))
        let statusFrames = controller.mainMenuOneDriveStatusButtonFramesForTesting
        #expect(statusFrames.count == 1)
        let statusFrame = try #require(statusFrames.first)
        let folderRowFrame = try #require(controller.mainMenuSnippetRowFrameForTesting(title: "AI Prompt"))
        let folderTitleFrame = try #require(controller.mainMenuSnippetTitleFrameForTesting(title: "AI Prompt"))
        let preferencesRowFrame = try #require(controller.mainMenuActionRowFrameForTesting(title: "Preferences"))

        #expect(statusFrame.maxX <= MainMenuPanelLayout.width - MainMenuPanelLayout.oneDriveStatusTrailingInset)
        #expect(abs(statusFrame.midY - (
            MainMenuPanelLayout.bottomInset + MainMenuPanelLayout.toolbarHeight / 2
        )) <= 1)
        #expect(preferencesRowFrame.minY >= MainMenuPanelLayout.bottomInset + MainMenuPanelLayout.toolbarHeight)
        #expect(MainMenuPanelLayout.headerHeight == 38)
        #expect(MainMenuPanelLayout.snippetFolderRowHeight == 32)
        #expect(folderRowFrame.height == MainMenuPanelLayout.snippetFolderRowHeight)
        #expect(preferencesRowFrame.height == MainMenuPanelLayout.rowHeight)
        #expect(abs(folderTitleFrame.midY - MainMenuPanelLayout.snippetFolderRowHeight / 2) <= 1)
        #expect(controller.visibleFrame?.size == NSSize(
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.fixedHeight
        ))
    }

    @Test
    func mainMenuKeepsReadableFolderTitleAtCompactWidth() throws {
        let folderImage = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            historyShortcutText: "⌃⌘V",
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: folderImage, shortcutText: "⌃⌥⌘1") { _ in },
                    .separator,
                    .action(title: "Preferences", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        let titleAvailableWidth = try #require(
            controller.mainMenuSnippetTitleAvailableWidthForTesting(title: "AI Prompt")
        )
        let preferencesTitleAvailableWidth = try #require(
            controller.mainMenuActionTitleAvailableWidthForTesting(title: "Preferences")
        )

        #expect(MainMenuPanelLayout.width == 300)
        #expect(titleAvailableWidth >= menuTitleWidth("AI Prompt"))
        #expect(preferencesTitleAvailableWidth >= menuTitleWidth("Preferences"))
    }

    @Test
    func visibleMainMenuPanelBackgroundTracksOpacityChange() throws {
        let suiteName = "MainMenuOneDriveFooterTests.opacity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.94, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        try withDependencies {
            $0.mainQueue = .immediate
            $0.pasteboardHistoryRepository = MainMenuEmptyHistoryRepository()
            $0.snippetRepository = MainMenuEmptySnippetRepository()
        } operation: {
            let manager = MenuManager()
            manager.setup()
            manager.showMainMenuPanelForTesting(at: NSPoint(x: 180, y: 700))
            defer {
                manager.closeMainMenuPanelForTesting()
                manager.removeStatusItemForTesting()
            }

            #expect(abs((manager.mainMenuPanelBackgroundAlphaForTesting ?? 0) - 0.94) < 0.001)

            CPYWindowAppearance.setOpacity(0.82, defaults: defaults)

            #expect(abs((manager.mainMenuPanelBackgroundAlphaForTesting ?? 0) - 0.82) < 0.001)
        }
    }

    @Test
    func mainMenuDoesNotShowClearHistoryAction() throws {
        let suiteName = "MainMenuOneDriveFooterTests.clearHistory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: Constants.UserDefaults.addClearHistoryMenuItem)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let titles = withDependencies {
            $0.snippetRepository = MainMenuEmptySnippetRepository()
        } operation: {
            MenuManager().mainMenuPanelActionTitlesForTesting
        }

        #expect(!titles.contains(String(localized: "Clear History")))
        #expect(!titles.contains(String(localized: "Quit Pastera")))
        #expect(!titles.contains(String(localized: "Edit Snippets")))
    }

    @Test
    func mainMenuOneDriveStatusButtonReflectsOfflineAndRunningStates() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notRunning(
            appURL: appURL
        ))
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [.action(title: "Preferences", image: nil) {}]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuOneDriveStatusToolTipForTesting?.contains("未运行") == true)
        #expect(controller.mainMenuOneDriveStatusTintColorForTesting?.isEqual(NSColor.secondaryLabelColor) == true)

        oneDriveService.status = .running(appURL: appURL)
        controller.reloadOneDriveStatusIfVisible()

        #expect(controller.mainMenuOneDriveStatusToolTipForTesting?.contains("正在运行") == true)
        #expect(controller.mainMenuOneDriveStatusTintColorForTesting?.isEqual(NSColor.systemBlue) == true)
    }

    @Test
    func downArrowFromHoveredHistorySelectsSnippetFolderAndOpensIt() throws {
        var openHistoryCount = 0
        var openedSnippetTitles = [String]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetTitles.append("AI Prompt")
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "History")

        #expect(controller.handleMainMenuNavigationForTesting(try makeArrowEvent(keyCode: 125)))

        #expect(controller.selectedMainMenuTitleForTesting == "AI Prompt")
        #expect(openHistoryCount == 0)
        #expect(openedSnippetTitles == ["AI Prompt"])
    }

    @Test
    func upArrowFromHoveredSnippetFolderSelectsHistoryAndOpensIt() throws {
        var openHistoryCount = 0
        var openedSnippetCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetCount += 1
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "AI Prompt")

        #expect(controller.handleMainMenuNavigationForTesting(try makeArrowEvent(keyCode: 126)))

        #expect(controller.selectedMainMenuTitleForTesting == "History")
        #expect(openHistoryCount == 1)
        #expect(openedSnippetCount == 0)
    }

    @Test
    func returnKeyConfirmsSelectedHistoryRow() throws {
        var openHistoryCount = 0
        var openedSnippetCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetCount += 1
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "History")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 36, characters: "\r")))

        #expect(openHistoryCount == 1)
        #expect(openedSnippetCount == 0)
        #expect(controller.selectedMainMenuTitleForTesting == "History")
    }

    @Test
    func spaceKeyConfirmsSelectedSnippetFolderRow() throws {
        var openHistoryCount = 0
        var openedSnippetTitles = [String]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetTitles.append("AI Prompt")
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "AI Prompt")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 49, characters: " ")))

        #expect(openHistoryCount == 0)
        #expect(openedSnippetTitles == ["AI Prompt"])
        #expect(controller.selectedMainMenuTitleForTesting == "AI Prompt")
    }

    @Test
    func returnKeyConfirmsSelectedActionRow() throws {
        var didOpenHistory = false
        var didOpenSnippet = false
        var didSelectAction = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        didOpenSnippet = true
                    },
                    .separator,
                    .action(title: "Preferences", image: nil) {
                        didSelectAction = true
                    }
                ]
            },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "Preferences")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 36, characters: "\r")))

        #expect(didSelectAction)
        #expect(!didOpenHistory)
        #expect(!didOpenSnippet)
    }

    @Test
    func commandFExpandsMainMenuSearch() throws {
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {}
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(
            keyCode: 3,
            characters: "f",
            modifierFlags: .command
        )))
    }

    private func expectedMainMenuHeight(
        snippetFolderCount: Int,
        actionRowCount: Int,
        separatorCount: Int
    ) -> CGFloat {
        MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + CGFloat(snippetFolderCount) * MainMenuPanelLayout.snippetFolderRowHeight
            + CGFloat(actionRowCount) * MainMenuPanelLayout.rowHeight
            + CGFloat(separatorCount - 1) * (
                MainMenuPanelLayout.separatorHeight
                    + MainMenuPanelLayout.separatorVerticalInset * 2
            )
            + MainMenuPanelLayout.toolbarHeight
            + MainMenuPanelLayout.bottomInset
    }

    private func menuTitleWidth(_ title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .medium)
        ]).width)
    }

    private func makeArrowEvent(keyCode: UInt16) throws -> NSEvent {
        let characters: String
        switch keyCode {
        case 125:
            characters = "\u{F701}"
        case 126:
            characters = "\u{F700}"
        default:
            characters = ""
        }
        return try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeKeyboardEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

}

@MainActor
@Suite(.serialized)
struct MainMenuOneDriveInstallationFooterTests {
    @Test
    func mainMenuShowsOneDriveStatusButtonWhenOneDriveIsNotInstalled() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notInstalled)
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [.action(title: "Preferences", image: nil) {}]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuOneDriveStatusButton"))
        #expect(controller.mainMenuOneDriveStatusButtonFramesForTesting.count == 1)
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuPinButton"))
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuQuitButton"))
    }
}

@Suite(.serialized)
struct MainMenuOneDriveStatusAssetTests {
    @Test
    func oneDriveStatusTemplateAssetKeepsSuppliedLogoMaskWithoutBlueBackground() throws {
        let assetURL = mainMenuProjectRoot()
            .appendingPathComponent(
                "pastera/Resources/Assets.xcassets/StatusIcon/" +
                    "onedrive_status_template.imageset/onedrive_status_template@2x.png"
            )
        let data = try Data(contentsOf: assetURL)
        let image = try #require(NSBitmapImageRep(data: data))

        #expect(image.pixelsWide == 36)
        #expect(image.pixelsHigh == 36)
        #expect(image.hasAlpha)

        var visiblePixels = 0
        var interiorTransparentPixels = 0
        var blueBackgroundPixels = 0
        var minColumn = image.pixelsWide
        var maxColumn = 0
        var minRow = image.pixelsHigh
        var maxRow = 0

        for row in 0..<image.pixelsHigh {
            for column in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent > 0.08 {
                    visiblePixels += 1
                    minColumn = min(minColumn, column)
                    maxColumn = max(maxColumn, column)
                    minRow = min(minRow, row)
                    maxRow = max(maxRow, row)
                    if color.blueComponent > color.redComponent + 0.1,
                       color.blueComponent > color.greenComponent + 0.1 {
                        blueBackgroundPixels += 1
                    }
                }
            }
        }

        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                guard let color = image.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent < 0.04 {
                    interiorTransparentPixels += 1
                }
            }
        }

        #expect(visiblePixels > 250)
        #expect(maxColumn - minColumn + 1 >= 30)
        #expect(maxRow - minRow + 1 >= 21)
        #expect(blueBackgroundPixels == 0)
        #expect(interiorTransparentPixels > 40)
    }

    private func mainMenuProjectRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pastera.xcodeproj").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

@MainActor
@Suite(.serialized)
struct MainMenuFooterButtonActionTests {
    @Test(arguments: ["mainMenuOneDriveStatusButton", "mainMenuPreferencesButton"])
    func pinnedMainMenuHidesBeforeOpeningSettingsFromFooter(buttonIdentifier: String) {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .running(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        weak var presentedController: MainMenuPanelController?
        var panelWasVisibleWhenSettingsOpened: Bool?
        let openSettings = {
            panelWasVisibleWhenSettingsOpened = presentedController?.isVisibleForTesting
        }
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService,
            onOpenPreferences: openSettings,
            onOpenOneDriveStatus: openSettings
        )
        presentedController = controller
        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        #expect(controller.isVisibleForTesting)

        controller.performMainMenuButtonClickForTesting(identifier: buttonIdentifier)

        #expect(panelWasVisibleWhenSettingsOpened == false)
    }

    @Test
    func mainMenuFooterOneDriveStatusStartsInstalledOneDriveWithoutNavigating() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notRunning(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        var didOpenHistory = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        controller.performMainMenuOneDriveStatusClickForTesting()

        #expect(oneDriveService.openCallCount == 1)
        #expect(controller.mainMenuSelectedModeForTesting == "history")
        #expect(controller.passwordVaultPageForTesting == "vault")
        #expect(!didOpenHistory)
    }

    @Test
    func mainMenuFooterOneDriveStatusDoesNotReactivateRunningOneDrive() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .running(
            appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
        ))
        var didOpenOneDriveStatus = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService,
            onOpenOneDriveStatus: { didOpenOneDriveStatus = true }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        controller.performMainMenuOneDriveStatusClickForTesting()

        #expect(oneDriveService.openCallCount == 0)
        #expect(didOpenOneDriveStatus)
        #expect(controller.mainMenuSelectedModeForTesting == "history")
        #expect(controller.passwordVaultPageForTesting == "vault")
    }

    @Test
    func mainMenuFooterStartsMainOneDriveWhenOnlyFileProviderIsRunning() {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        var openedURL: URL?
        let oneDriveService = OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive-mac" ? appURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { path in
                URL(fileURLWithPath: path).standardizedFileURL.path == appURL.standardizedFileURL.path
            },
            runningApplicationsProvider: {
                [
                    OneDriveRunningApplicationSnapshot(
                        bundleIdentifier: "com.microsoft.OneDrive-mac.FileProvider",
                        executableURL: appURL.appendingPathComponent(
                            "Contents/PlugIns/OneDrive File Provider.appex/Contents/MacOS/OneDrive File Provider"
                        ),
                        localizedName: "OneDrive File Provider"
                    )
                ]
            },
            openApplication: { url in
                openedURL = url
                return true
            },
            notificationCenter: NotificationCenter()
        )
        var didOpenOneDriveStatus = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService,
            onOpenOneDriveStatus: { didOpenOneDriveStatus = true }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        controller.performMainMenuOneDriveStatusClickForTesting()

        #expect(openedURL == appURL)
        #expect(!didOpenOneDriveStatus)
    }

    @Test
    func mainMenuFooterOneDriveStatusDoesNotOpenAnythingWhenOneDriveIsMissing() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notInstalled)
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        controller.performMainMenuOneDriveStatusClickForTesting()

        #expect(oneDriveService.openCallCount == 0)
        #expect(controller.mainMenuSelectedModeForTesting == "history")
        #expect(controller.passwordVaultPageForTesting == "vault")
    }

    @Test
    func mainMenuFooterDoesNotExposeQuitButton() {
        let oneDriveService = MainMenuFakeOneDriveProcessStatusService(status: .notInstalled)
        var didOpenHistory = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {},
            oneDriveStatusService: oneDriveService
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuQuitButton"))
        #expect(oneDriveService.openCallCount == 0)
        #expect(!didOpenHistory)
    }
}

@MainActor
@Suite(.serialized)
struct OneDriveProcessStatusServiceTests {
    @Test
    func reportsRunningWhenMainOneDriveProcessIsPresent() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = makeService(
            applicationURL: appURL,
            runningApplications: [
                OneDriveRunningApplicationSnapshot(
                    bundleIdentifier: "com.microsoft.OneDrive-mac",
                    executableURL: appURL.appendingPathComponent("Contents/MacOS/OneDrive"),
                    localizedName: "OneDrive"
                )
            ]
        )

        guard case let .running(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected OneDrive to be running")
            return
        }
        #expect(statusAppURL == appURL)
        #expect(service.isMainApplicationRunning())
    }

    @Test
    func fileProviderProcessAloneCountsAsRunning() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = makeService(
            applicationURL: appURL,
            runningApplications: [
                OneDriveRunningApplicationSnapshot(
                    bundleIdentifier: "com.microsoft.OneDrive-mac.FileProvider",
                    executableURL: appURL.appendingPathComponent(
                        "Contents/PlugIns/OneDrive File Provider.appex/Contents/MacOS/OneDrive File Provider"
                    ),
                    localizedName: "OneDrive File Provider"
                )
            ]
        )

        guard case let .running(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected the official OneDrive File Provider to be running")
            return
        }
        #expect(statusAppURL == appURL)
        #expect(!service.isMainApplicationRunning())
    }

    @Test
    func fileProviderProcessRecoversAppURLWhenBundleLookupMisses() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = makeService(
            applicationURL: nil,
            runningApplications: [
                OneDriveRunningApplicationSnapshot(
                    bundleIdentifier: "com.microsoft.OneDrive-mac.FileProvider",
                    executableURL: appURL.appendingPathComponent(
                        "Contents/PlugIns/OneDrive File Provider.appex/Contents/MacOS/OneDrive File Provider"
                    ),
                    localizedName: "OneDrive File Provider"
                )
            ]
        )

        guard case let .running(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected the File Provider executable to resolve OneDrive.app")
            return
        }
        #expect(statusAppURL == appURL)
    }

    @Test
    func installedOneDriveWithoutProcessIsNotRunningAndKeepsAppURL() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = makeService(applicationURL: appURL, runningApplications: [])

        guard case let .notRunning(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected installed OneDrive to be offline")
            return
        }
        #expect(statusAppURL == appURL)
    }

    @Test
    func installedOneDriveOpensTheResolvedApplicationURL() {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        var openedURL: URL?
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive-mac" ? appURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { path in
                appURL.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
            },
            runningApplicationsProvider: { [] },
            openApplication: { url in
                openedURL = url
                return true
            },
            notificationCenter: NotificationCenter()
        )

        #expect(service.openOneDrive())
        #expect(openedURL == appURL)
    }

    @Test
    func staleBundleIdentifierApplicationURLIsTreatedAsNotInstalled() {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive-mac" ? appURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { _ in false },
            runningApplicationsProvider: { [] },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter()
        )

        guard case .notInstalled = service.currentStatus() else {
            Issue.record("Expected stale OneDrive application URL to be ignored")
            return
        }
        #expect(!service.openOneDrive())
    }

    @Test
    func missingOneDriveIsNotInstalledAndCannotOpen() {
        let service = makeService(applicationURL: nil, runningApplications: [])

        guard case .notInstalled = service.currentStatus() else {
            Issue.record("Expected missing OneDrive to be not installed")
            return
        }
        #expect(!service.openOneDrive())
    }

    @Test
    func supportsLegacyOneDriveBundleIdentifierLookup() throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive" ? appURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { path in
                URL(fileURLWithPath: path).standardizedFileURL.path == appURL.standardizedFileURL.path
            },
            runningApplicationsProvider: { [] },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter()
        )

        guard case let .notRunning(statusAppURL) = service.currentStatus() else {
            Issue.record("Expected legacy bundle id lookup to find installed OneDrive")
            return
        }
        #expect(statusAppURL == appURL)
    }

    @Test
    func monitoringPollsOffMainThreadAndDeliversChangesOnMainThread() async throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let runtimeApplication = OneDriveRunningApplicationSnapshot(
            bundleIdentifier: "com.microsoft.OneDrive-mac",
            executableURL: appURL.appendingPathComponent("Contents/MacOS/OneDrive"),
            localizedName: "OneDrive"
        )
        let lock = NSLock()
        var initialSnapshotRead = false
        var pollingThreads = [Bool]()
        var callbackThreads = [Bool]()
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { $0 == "com.microsoft.OneDrive-mac" ? appURL : nil },
            fallbackApplicationURLs: [],
            fileExists: { $0 == appURL.path },
            runningApplicationsProvider: {
                lock.withLock {
                    guard initialSnapshotRead else {
                        initialSnapshotRead = true
                        return []
                    }
                    pollingThreads.append(Thread.isMainThread)
                    return [runtimeApplication]
                }
            },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter(),
            monitoringPollInterval: 0.01
        )
        let observation = service.startMonitoring {
            lock.withLock { callbackThreads.append(Thread.isMainThread) }
        }
        defer { observation.cancel() }

        for _ in 0..<100 {
            if lock.withLock({ !callbackThreads.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let observedThreads = lock.withLock { (pollingThreads, callbackThreads) }
        #expect(!observedThreads.0.isEmpty)
        #expect(observedThreads.0.allSatisfy { !$0 })
        #expect(observedThreads.1 == [true])
    }

    @Test
    func cancellationSuppressesPendingPollCallback() async throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let runtimeApplication = OneDriveRunningApplicationSnapshot(
            bundleIdentifier: "com.microsoft.OneDrive-mac",
            executableURL: appURL.appendingPathComponent("Contents/MacOS/OneDrive"),
            localizedName: "OneDrive"
        )
        let lock = NSLock()
        var snapshotCount = 0
        var callbackCount = 0
        var didCancel = false
        var observation: OneDriveProcessStatusObservation?
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { $0 == "com.microsoft.OneDrive-mac" ? appURL : nil },
            fallbackApplicationURLs: [],
            fileExists: { $0 == appURL.path },
            runningApplicationsProvider: {
                let count = lock.withLock {
                    snapshotCount += 1
                    return snapshotCount
                }
                guard count > 1 else { return [] }
                if count == 2 {
                    // Cancellation is queued ahead of the poll result's main-thread delivery.
                    DispatchQueue.main.async {
                        observation?.cancel()
                        didCancel = true
                    }
                }
                return [runtimeApplication]
            },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter(),
            monitoringPollInterval: 0.01
        )
        observation = service.startMonitoring { callbackCount += 1 }
        defer { observation?.cancel() }

        for _ in 0..<100 {
            if didCancel { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(30))

        #expect(didCancel)
        #expect(callbackCount == 0)
    }

    @Test(arguments: [false, true])
    func workspaceNotificationSupersedesPendingPollSnapshot(notificationMatchesBaseline: Bool) async throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let notificationCenter = NotificationCenter()
        let runtimeApplication = OneDriveRunningApplicationSnapshot(
            bundleIdentifier: "com.microsoft.OneDrive-mac",
            executableURL: appURL.appendingPathComponent("Contents/MacOS/OneDrive"),
            localizedName: "OneDrive"
        )
        let lock = NSLock()
        var snapshotCount = 0
        var callbackCount = 0
        var didDeliverNotification = false
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { $0 == "com.microsoft.OneDrive-mac" ? appURL : nil },
            fallbackApplicationURLs: [],
            fileExists: { $0 == appURL.path },
            runningApplicationsProvider: {
                let count = lock.withLock {
                    snapshotCount += 1
                    return snapshotCount
                }
                guard count > 1 else { return [] }
                if count == 2 {
                    DispatchQueue.main.async {
                        notificationCenter.post(
                            name: notificationMatchesBaseline
                                ? NSWorkspace.didTerminateApplicationNotification
                                : NSWorkspace.didLaunchApplicationNotification,
                            object: nil
                        )
                        didDeliverNotification = true
                    }
                    return notificationMatchesBaseline ? [runtimeApplication] : []
                }
                return notificationMatchesBaseline ? [] : [runtimeApplication]
            },
            openApplication: { _ in true },
            notificationCenter: notificationCenter,
            applicationSnapshotFromNotification: { _ in runtimeApplication },
            monitoringPollInterval: 0.01
        )
        let observation = service.startMonitoring { callbackCount += 1 }
        defer { observation.cancel() }

        for _ in 0..<100 {
            if didDeliverNotification { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(30))

        #expect(didDeliverNotification)
        #expect(callbackCount == (notificationMatchesBaseline ? 0 : 1))
    }

    @Test
    func monitoringPollsForRuntimeMilestonesWhenWorkspaceNotificationIsMissing() async throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let runningApplicationsLock = NSLock()
        var runningApplications = [OneDriveRunningApplicationSnapshot]()
        var callbackCount = 0
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive-mac" ? appURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { path in
                URL(fileURLWithPath: path).standardizedFileURL.path == appURL.standardizedFileURL.path
            },
            runningApplicationsProvider: { runningApplicationsLock.withLock { runningApplications } },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter(),
            monitoringPollInterval: 0.01
        )
        let observation = service.startMonitoring {
            callbackCount += 1
        }
        defer { observation.cancel() }

        runningApplicationsLock.withLock {
            runningApplications = [
                OneDriveRunningApplicationSnapshot(
                    bundleIdentifier: "com.microsoft.OneDrive-mac",
                    executableURL: appURL.appendingPathComponent("Contents/MacOS/OneDrive"),
                    localizedName: "OneDrive"
                )
            ]
        }
        try await Task.sleep(for: .milliseconds(80))

        #expect(callbackCount == 1)

        runningApplicationsLock.withLock {
            runningApplications.append(
                OneDriveRunningApplicationSnapshot(
                    bundleIdentifier: "com.microsoft.OneDrive-mac.FileProvider",
                    executableURL: appURL.appendingPathComponent(
                        "Contents/PlugIns/OneDrive File Provider.appex/Contents/MacOS/OneDrive File Provider"
                    ),
                    localizedName: "OneDrive File Provider"
                )
            )
        }
        try await Task.sleep(for: .milliseconds(80))

        #expect(callbackCount == 2)

        runningApplicationsLock.withLock { runningApplications = [] }
        try await Task.sleep(for: .milliseconds(80))

        #expect(callbackCount == 3)
    }

    @Test
    func monitoringDeduplicatesNotificationsAndStopsAfterCancellation() async throws {
        let appURL = URL(fileURLWithPath: "/Applications/OneDrive.app")
        let notificationCenter = NotificationCenter()
        let runningApplicationsLock = NSLock()
        var runningApplications = [OneDriveRunningApplicationSnapshot]()
        var callbackCount = 0
        let runtimeApplication = OneDriveRunningApplicationSnapshot(
            bundleIdentifier: "com.microsoft.OneDrive-mac",
            executableURL: appURL.appendingPathComponent("Contents/MacOS/OneDrive"),
            localizedName: "OneDrive"
        )
        let service = OneDriveProcessStatusService(
            applicationURLProvider: { $0 == "com.microsoft.OneDrive-mac" ? appURL : nil },
            fallbackApplicationURLs: [],
            fileExists: { path in
                URL(fileURLWithPath: path).standardizedFileURL.path == appURL.standardizedFileURL.path
            },
            runningApplicationsProvider: { runningApplicationsLock.withLock { runningApplications } },
            openApplication: { _ in true },
            notificationCenter: notificationCenter,
            applicationSnapshotFromNotification: { _ in runtimeApplication },
            monitoringPollInterval: 0.01
        )
        let observation = service.startMonitoring {
            callbackCount += 1
        }

        runningApplicationsLock.withLock { runningApplications = [runtimeApplication] }
        notificationCenter.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        #expect(callbackCount == 1)

        notificationCenter.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        try await Task.sleep(for: .milliseconds(80))
        #expect(callbackCount == 1)

        observation.cancel()
        runningApplicationsLock.withLock { runningApplications = [] }
        notificationCenter.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        try await Task.sleep(for: .milliseconds(30))
        #expect(callbackCount == 1)
    }

    private func makeService(
        applicationURL: URL?,
        runningApplications: [OneDriveRunningApplicationSnapshot]
    ) -> OneDriveProcessStatusService {
        OneDriveProcessStatusService(
            applicationURLProvider: { bundleIdentifier in
                bundleIdentifier == "com.microsoft.OneDrive-mac" ? applicationURL : nil
            },
            fallbackApplicationURLs: [],
            fileExists: { path in
                applicationURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
            },
            runningApplicationsProvider: { runningApplications },
            openApplication: { _ in true },
            notificationCenter: NotificationCenter()
        )
    }
}

private final class MainMenuFakeOneDriveProcessStatusService: OneDriveProcessStatusServicing {
    var status: OneDriveProcessStatus
    var openCallCount = 0

    init(status: OneDriveProcessStatus) {
        self.status = status
    }

    func currentStatus() -> OneDriveProcessStatus {
        status
    }

    func isMainApplicationRunning() -> Bool {
        status.isRunning
    }

    func openOneDrive() -> Bool {
        openCallCount += 1
        return true
    }

    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation {
        OneDriveProcessStatusObservation {}
    }
}

private struct MainMenuEmptyHistoryRepository: PasteboardHistoryRepositoryProtocol {
    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { false }
    func fetchHistoryDetails(ascending: Bool, includesThumbnailAsset: Bool, limit: Int, offset: Int) -> [PasteboardHistoryDetail] { [] }
    func searchHistoryDetails(query: HistorySearchQuery, includesThumbnailAsset: Bool, limit: Int, offset: Int) throws -> [PasteboardHistoryDetail] { [] }
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { nil }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private struct MainMenuEmptySnippetRepository: SnippetRepositoryProtocol {
    func observeFolders() -> AnyPublisher<[SnippetFolder], Never> {
        Empty().eraseToAnyPublisher()
    }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func fetchFolders() -> [SnippetFolder] { [] }
    func fetchFolderDetails() -> [SnippetFolderDetail] { [] }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { nil }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func removeDuplicateFoldersAndSnippets() -> Int { 0 }
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool { true }
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool { true }
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}

// swiftlint:enable file_length
