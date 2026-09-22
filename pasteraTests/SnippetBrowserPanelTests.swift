//
//  SnippetBrowserPanelTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/04.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import Carbon
import Combine
import Dependencies
import Magnet
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct SnippetBrowserPanelTests {
    @Test
    func displaysEnabledFoldersBeforeSnippetSelection() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let disabledSnippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "Ask GPT",
                    content: "Summarize this",
                    index: 0,
                    isEnabled: true
                ),
                Snippet(
                    id: disabledSnippetID,
                    folderID: folderID,
                    title: "Disabled",
                    content: "Hidden",
                    index: 1,
                    isEnabled: false
                )
            ]
        )
        var selectedSnippetID: Snippet.ID?
        let controller = SnippetBrowserPanelController(
            fetchFolders: { [detail.folder] },
            fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
            selectSnippet: { snippetID, _ in selectedSnippetID = snippetID }
        )

        controller.show(attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220))
        defer { controller.close() }

        #expect(controller.rowTitlesForTesting == ["AI Prompt"])

        controller.confirmFirstSnippetForTesting()

        #expect(selectedSnippetID == nil)
        #expect(controller.isVisibleForTesting)
    }

    @Test
    func opensFolderBeforeConfirmingSnippetSelection() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            let folderID = SnippetFolder.ID(rawValue: UUID())
            let snippetID = Snippet.ID(rawValue: UUID())
            let detail = SnippetFolderDetail(
                folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(
                        id: snippetID,
                        folderID: folderID,
                        title: "Ask GPT",
                        content: "Summarize this",
                        index: 0,
                        isEnabled: true
                    )
                ]
            )
            var selectedSnippetID: Snippet.ID?
            let controller = SnippetBrowserPanelController(
                fetchFolders: { [detail.folder] },
                fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
                selectSnippet: { snippetID, _ in selectedSnippetID = snippetID }
            )

            controller.show(folderID: folderID, attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220))
            defer { controller.close() }

            #expect(controller.rowTitlesForTesting == ["Ask GPT"])
            #expect(controller.rowShortcutTextsForTesting == ["1"])
            #expect(controller.rowShortcutStylesForTesting == [.itemNumber])
            #expect(controller.rowTextValuesForTesting == [["1", "Ask GPT"]])
            #expect(!controller.rowTextValuesForTesting.flatMap { $0 }.contains("Summarize this"))
            #expect(SnippetBrowserLayout.rowHeight == 24)
            #expect(controller.visibleFrame?.height == 36)

            controller.confirmFirstSnippetForTesting()

            #expect(selectedSnippetID == snippetID)
            #expect(!controller.isVisibleForTesting)
        }
    }

    @Test
    func mainMenuShowsEnabledSnippetFolders() {
        let enabledFolderID = SnippetFolder.ID(rawValue: UUID())
        let disabledFolderID = SnippetFolder.ID(rawValue: UUID())
        let repository = StaticSnippetRepository(details: [
            SnippetFolderDetail(
                folder: SnippetFolder(id: enabledFolderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: []
            ),
            SnippetFolderDetail(
                folder: SnippetFolder(id: disabledFolderID, title: "Disabled", index: 1, isEnabled: false),
                snippets: []
            )
        ])

        let titles = withDependencies {
            $0.snippetRepository = repository
        } operation: {
            MenuManager().mainMenuSnippetTitlesForTesting
        }

        #expect(titles == ["AI Prompt"])
    }

    @Test
    func mainMenuHeaderDisplaysRightAlignedShortcutText() throws {
        let menuItemView = MainMenuHeaderItemView(title: "History", image: nil, shortcutText: "⌃⌘V")

        let shortcutBadge = try #require(menuItemView.subviews.compactMap { $0 as? PasteraShortcutBadgeView }
            .first { $0.shortcutTextForTesting == "⌃⌘V" })

        #expect(!shortcutBadge.isHidden)
        #expect(shortcutBadge.layer?.cornerRadius == PasteraShortcutBadgeView.Metrics.cornerRadius)
        #expect(shortcutBadge.intrinsicContentSize.width > shortcutBadge.labelWidthForTesting)
    }

    @Test
    func shortcutBadgeUsesCompactRoundedRectStylingAndHidesEmptyText() {
        let badge = PasteraShortcutBadgeView(shortcutText: "⇧⌘V")
        let label = badge.subviews.compactMap { $0 as? NSTextField }.first

        #expect(badge.shortcutTextForTesting == "⇧⌘V")
        #expect(!badge.isHidden)
        #expect(badge.layer?.cornerRadius == PasteraShortcutBadgeView.Metrics.cornerRadius)
        #expect(badge.intrinsicContentSize.height == PasteraShortcutBadgeView.Metrics.height)
        #expect(PasteraShortcutBadgeView.Metrics.horizontalPadding == 3)
        #expect(PasteraShortcutBadgeView.Metrics.height == 15)
        #expect(PasteraShortcutBadgeView.Metrics.minWidth == 20)
        #expect(PasteraShortcutBadgeView.Metrics.cornerRadius == 4)
        #expect(PasteraShortcutBadgeView.Metrics.cornerRadius < PasteraShortcutBadgeView.Metrics.height / 2)
        #expect(badge.intrinsicContentSize.width > badge.labelWidthForTesting)
        #expect(label?.font?.pointSize == 10.5)

        badge.shortcutText = nil

        #expect(badge.isHidden)
        #expect(badge.shortcutTextForTesting == "")
    }

    @Test
    func itemNumberShortcutBadgeUsesCompactStyle() {
        let commandBadge = PasteraShortcutBadgeView(shortcutText: "⇧⌘V")
        let itemBadge = PasteraShortcutBadgeView(shortcutText: "1", style: .itemNumber)

        #expect(commandBadge.styleForTesting == .command)
        #expect(itemBadge.styleForTesting == .itemNumber)
        #expect(PasteraShortcutBadgeView.Metrics.itemHorizontalPadding == 4)
        #expect(PasteraShortcutBadgeView.Metrics.itemHeight == 18)
        #expect(PasteraShortcutBadgeView.Metrics.itemMinWidth == 20)
        #expect(PasteraShortcutBadgeView.Metrics.itemCornerRadius == 5)
        #expect(commandBadge.intrinsicContentSize.height == PasteraShortcutBadgeView.Metrics.height)
        #expect(itemBadge.intrinsicContentSize.height == PasteraShortcutBadgeView.Metrics.itemHeight)
        #expect(itemBadge.subviews.compactMap { ($0 as? NSTextField)?.font?.pointSize }.first == 11.5)
        #expect(itemBadge.intrinsicContentSize.width <= commandBadge.intrinsicContentSize.width)
    }

    @Test
    func mainMenuItemsExposeConfiguredShortcutTexts() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folderKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | shiftKey))
        let hotKeyService = AppEnvironment.current.hotKeyService
        let previousFolderCombo = hotKeyService.snippetKeyCombo(forIdentifier: folderID.uuidString)
        hotKeyService.registerSnippetHotKey(with: folderID.uuidString, keyCombo: folderKeyCombo)
        defer {
            if let previousFolderCombo {
                hotKeyService.registerSnippetHotKey(with: folderID.uuidString, keyCombo: previousFolderCombo)
            } else {
                hotKeyService.unregisterSnippetHotKey(with: folderID.uuidString)
            }
        }

        let shortcuts = withDependencies {
            $0.snippetRepository = StaticSnippetRepository(details: [
                SnippetFolderDetail(
                    folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
                    snippets: []
                )
            ])
        } operation: {
            MenuManager().mainMenuPanelShortcutTextsForTesting
        }

        #expect(shortcuts[String(localized: "Clear History")] == nil)
        #expect(shortcuts["AI Prompt"] == "⇧⌘B")
        #expect(shortcuts[String(localized: "Edit Snippets")] == nil)
        #expect(shortcuts[String(localized: "Preferences")] == nil)
        #expect(shortcuts[String(localized: "Quit Pastera")] == nil)
    }

    @Test
    func historyRowKeepsNumericBadgeWhenRetiredShortcutPreferenceWasDisabled() throws {
        try withNumericShortcutDefaults(enabled: false, startsAtZero: false) {
            withDependencies {
                $0.pasteboardHistoryRepository = EmptyHistoryRepository()
            } operation: {
                let defaults = AppEnvironment.current.defaults
                let markKey = Constants.UserDefaults.menuItemsAreMarkedWithNumbers
                let previousMarkValue = defaults.object(forKey: markKey)
                defaults.set(true, forKey: markKey)
                defer { restoreDefault(previousMarkValue, forKey: markKey) }

                let manager = MenuManager()
                let detail = PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("history-1"),
                        title: "First History",
                        pasteboardTypes: [.string],
                        updateAt: 1,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                )

                let row = manager.makeHistoryRowViewForTesting(detail, index: 0)

                #expect(row.textValuesForTesting.contains("First History"))
                #expect(!row.textValuesForTesting.contains("1. First History"))
                #expect(row.textValuesForTesting.contains("1"))
            }
        }
    }

    @Test
    func imageHistoryRowDoesNotShowLeadingNumberPrefix() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            withDependencies {
                $0.pasteboardHistoryRepository = EmptyHistoryRepository()
            } operation: {
                let manager = MenuManager()
                let detail = PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("history-image"),
                        title: "Screenshot",
                        pasteboardTypes: [.tiff],
                        updateAt: 1,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                )

                let row = manager.makeHistoryRowViewForTesting(detail, index: 0)

                #expect(row.textValuesForTesting.contains("(Image)"))
                #expect(row.textValuesForTesting.contains("1"))
                #expect(!row.textValuesForTesting.contains("1. (Image)"))
            }
        }
    }

    @Test
    func showingHistoryBrowserPanelFromTransientMenuKeepsMainMenuVisible() {
        withDependencies {
            $0.pasteboardHistoryRepository = EmptyHistoryRepository()
            $0.snippetRepository = StaticSnippetRepository(details: [])
        } operation: {
            let manager = MenuManager()
            manager.popUpMenu(.main)
            defer { manager.closeMainMenuPanelForTesting() }

            manager.showHistoryBrowserPanelForTesting(at: NSPoint(x: 120, y: 480))

            #expect(manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.historyBrowserPanelFrameForTesting != nil)
        }
    }

    @Test
    func showingSnippetBrowserPanelFromTransientMenuKeepsMainMenuVisible() {
        withDependencies {
            $0.pasteboardHistoryRepository = EmptyHistoryRepository()
            $0.snippetRepository = StaticSnippetRepository(details: [])
        } operation: {
            let manager = MenuManager()
            manager.popUpMenu(.main)
            defer { manager.closeMainMenuPanelForTesting() }

            manager.showSnippetBrowserPanelForTesting()

            #expect(manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.snippetBrowserPanelFrameForTesting != nil)
        }
    }

    @Test
    func clickingOutsideSnippetFolderPanelDismissesTransientMenuPanels() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        try withSnippetFolderPanel(folderID: folderID) { manager in
            let mainMenuFrame = try #require(manager.mainMenuPanelFrameForTesting)
            let snippetFrame = try #require(manager.snippetBrowserPanelFrameForTesting)
            let outsidePoint = NSPoint(
                x: min(mainMenuFrame.minX, snippetFrame.minX) - 24,
                y: min(mainMenuFrame.minY, snippetFrame.minY) - 24
            )

            manager.handlePanelDismissMouseDownForTesting(at: outsidePoint)

            #expect(!manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.snippetBrowserPanelFrameForTesting == nil)
        }
    }

    @Test
    func clickingParentMenuWhileSnippetFolderPanelIsOpenDismissesOnlySnippetPanel() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        try withSnippetFolderPanel(folderID: folderID) { manager in
            let mainMenuFrame = try #require(manager.mainMenuPanelFrameForTesting)
            let parentMenuPoint = NSPoint(x: mainMenuFrame.midX, y: mainMenuFrame.midY)

            manager.handlePanelDismissMouseDownForTesting(at: parentMenuPoint)

            #expect(manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.snippetBrowserPanelFrameForTesting == nil)
        }
    }

    @Test
    func folderRowsDisplayConfiguredFolderShortcut() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let keyCombo = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | shiftKey))
        let hotKeyService = AppEnvironment.current.hotKeyService
        let previousFolderCombo = hotKeyService.snippetKeyCombo(forIdentifier: folderID.uuidString)
        hotKeyService.registerSnippetHotKey(with: folderID.uuidString, keyCombo: keyCombo)
        defer {
            if let previousFolderCombo {
                hotKeyService.registerSnippetHotKey(with: folderID.uuidString, keyCombo: previousFolderCombo)
            } else {
                hotKeyService.unregisterSnippetHotKey(with: folderID.uuidString)
            }
        }
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: []
        )
        let controller = SnippetBrowserPanelController(
            fetchFolders: { [detail.folder] },
            fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
            selectSnippet: { _, _ in }
        )

        controller.show(attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220))
        defer { controller.close() }

        #expect(controller.rowTitlesForTesting == ["AI Prompt"])
        #expect(controller.rowShortcutTextsForTesting == ["⇧⌘B"])
        #expect(controller.rowShortcutStylesForTesting == [.command])
        #expect(SnippetBrowserLayout.folderHeight == 28)
        #expect(controller.visibleFrame?.height == 40)
    }

    @Test
    func snippetRowsKeepNumericBadgeWhenRetiredShortcutPreferenceWasDisabled() throws {
        try withNumericShortcutDefaults(enabled: false, startsAtZero: false) {
            let defaults = AppEnvironment.current.defaults
            let markKey = Constants.UserDefaults.menuItemsAreMarkedWithNumbers
            let previousMarkValue = defaults.object(forKey: markKey)
            defaults.set(true, forKey: markKey)
            defer { restoreDefault(previousMarkValue, forKey: markKey) }

            let folderID = SnippetFolder.ID(rawValue: UUID())
            let detail = SnippetFolderDetail(
                folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(
                        id: Snippet.ID(rawValue: UUID()),
                        folderID: folderID,
                        title: "Ask GPT",
                        content: "Summarize this",
                        index: 0,
                        isEnabled: true
                    )
                ]
            )
            let controller = SnippetBrowserPanelController(
                fetchFolders: { [detail.folder] },
                fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
                selectSnippet: { _, _ in }
            )

            controller.show(folderID: folderID, attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220))
            defer { controller.close() }

            #expect(controller.rowTitlesForTesting == ["Ask GPT"])
            #expect(controller.rowShortcutTextsForTesting == ["1"])
        }
    }

    @Test
    func legacySnippetMenuItemKeepsNumericKeyEquivalentWithoutLeadingTitleNumber() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            let snippet = Snippet(
                id: Snippet.ID(rawValue: UUID()),
                folderID: SnippetFolder.ID(rawValue: UUID()),
                title: "Ask GPT",
                content: "Summarize this",
                index: 0,
                isEnabled: true
            )

            let item = MenuManager().makeSnippetMenuItemForTesting(snippet, listNumber: 1, rowIndex: 0)

            #expect(item.title == "Ask GPT")
            #expect(item.keyEquivalent == "1")
            #expect(item.keyEquivalentModifierMask.isEmpty)
        }
    }

    private func withNumericShortcutDefaults(
        enabled: Bool,
        startsAtZero: Bool,
        operation: () throws -> Void
    ) rethrows {
        AppEnvironment.push(clipboardScriptCoordinator: ScriptRowCoordinator(hasScripts: false))
        defer { _ = AppEnvironment.popLast() }
        let defaults = AppEnvironment.current.defaults
        let shortcutKey = Constants.UserDefaults.addNumericKeyEquivalents
        let startKey = Constants.UserDefaults.menuItemsTitleStartWithZero
        let previousShortcutValue = defaults.object(forKey: shortcutKey)
        let previousStartValue = defaults.object(forKey: startKey)
        defaults.set(enabled, forKey: shortcutKey)
        defaults.set(startsAtZero, forKey: startKey)
        defer {
            restoreDefault(previousShortcutValue, forKey: shortcutKey)
            restoreDefault(previousStartValue, forKey: startKey)
        }
        try operation()
    }

    private func restoreDefault(_ value: Any?, forKey key: String) {
        let defaults = AppEnvironment.current.defaults
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

}

extension SnippetBrowserPanelTests {
    @Test
    func historyRowDisplaysNumericShortcutOnLeftWithoutTitlePrefix() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            try withDependencies {
                $0.pasteboardHistoryRepository = EmptyHistoryRepository()
            } operation: {
                let manager = MenuManager()
                let detail = PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("history-1"),
                        title: "First History",
                        pasteboardTypes: [.string],
                        updateAt: 1,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                )

                let row = manager.makeHistoryRowViewForTesting(detail, index: 0)
                row.layoutSubtreeIfNeeded()
                let titleLabel = try #require(row.subviews.compactMap { $0 as? NSTextField }
                    .first { $0.stringValue == "First History" })
                let shortcutBadge = try #require(row.subviews.compactMap { $0 as? PasteraShortcutBadgeView }
                    .first { $0.shortcutTextForTesting == "1" })

                #expect(row.textValuesForTesting.contains("First History"))
                #expect(row.textValuesForTesting.contains("1"))
                #expect(!row.textValuesForTesting.contains("1. First History"))
                #expect(shortcutBadge.frame.minX < titleLabel.frame.minX)
            }
        }
    }

    @Test
    func historyRowDeleteButtonDeletesHistoryFromRightEdge() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            let historyID = PasteboardHistory.ID("history-delete")
            let detail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: historyID,
                    title: "Delete Me",
                    pasteboardTypes: [.string],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: nil
            )
            let repository = RecordingHistoryDeletionRepository(details: [detail])

            let managerAndRow = withDependencies {
                $0.pasteboardHistoryRepository = repository
            } operation: {
                let manager = MenuManager()
                return (manager, manager.makeHistoryRowViewForTesting(detail, index: 0))
            }
            let row = managerAndRow.1
            row.layoutSubtreeIfNeeded()
            let titleLabel = try #require(row.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "Delete Me" })
            let deleteButton = try #require(row.subviews.compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == "historyRowDeleteButton" })

            #expect(deleteButton.image != nil)
            #expect(deleteButton.frame.minX > titleLabel.frame.maxX)
            #expect(deleteButton.toolTip?.contains("⌘D") == true)

            withExtendedLifetime(managerAndRow.0) {
                deleteButton.performClick(nil)
            }

            #expect(repository.deletedHistoryIDs == [historyID])
        }
    }

    @Test
    func deletingHistoryDoesNotReloadVisiblePanelBeforeRepositoryChange() throws {
        AppEnvironment.push(clipboardScriptCoordinator: ScriptRowCoordinator(hasScripts: false))
        defer { _ = AppEnvironment.popLast() }
        let historyID = PasteboardHistory.ID("history-delete-no-reload")
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: historyID,
                title: "Delete Without Extra Reload",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: CPYUtilities.deviceID
            ),
            thumbnailAsset: nil
        )
        let repository = RecordingHistoryDeletionRepository(details: [detail])

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let manager = MenuManager()
            manager.showHistoryBrowserPanelForTesting(at: NSPoint(x: 200, y: 500))
            defer { manager.closeHistoryBrowserPanelForTesting() }

            let initialSearchCount = repository.searchHistoryDetailsCallCount

            manager.deleteHistory(historyID)

            #expect(repository.deletedHistoryIDs == [historyID])
            #expect(repository.searchHistoryDetailsCallCount == initialSearchCount)
        }
    }
}

@MainActor
private func withSnippetFolderPanel(
    folderID: SnippetFolder.ID,
    operation: (MenuManager) throws -> Void
) throws {
    let detail = SnippetFolderDetail(
        folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
        snippets: [
            Snippet(
                id: Snippet.ID(rawValue: UUID()),
                folderID: folderID,
                title: "Ask GPT",
                content: "Summarize this",
                index: 0,
                isEnabled: true
            )
        ]
    )
    try withDependencies {
        $0.pasteboardHistoryRepository = EmptyHistoryRepository()
        $0.snippetRepository = StaticSnippetRepository(details: [detail])
    } operation: {
        let manager = MenuManager()
        manager.popUpMenu(.main)
        manager.showSnippetFolderPanelForTesting(folderID)
        defer { manager.closeMainMenuPanelForTesting() }

        #expect(manager.isMainMenuPanelVisibleForTesting)
        #expect(manager.snippetBrowserPanelFrameForTesting != nil)
        try operation(manager)
    }
}

private struct EmptyHistoryRepository: PasteboardHistoryRepositoryProtocol {
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

private final class RecordingHistoryDeletionRepository: PasteboardHistoryRepositoryProtocol {
    let details: [PasteboardHistoryDetail]
    private(set) var deletedHistoryIDs = [PasteboardHistory.ID]()
    private(set) var searchHistoryDetailsCallCount = 0

    init(details: [PasteboardHistoryDetail]) {
        self.details = details
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just(details.map(\.history)).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { !details.isEmpty }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail] {
        Array(details.dropFirst(offset).prefix(limit))
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        searchHistoryDetailsCallCount += 1
        return fetchHistoryDetails(
            ascending: true,
            includesThumbnailAsset: includesThumbnailAsset,
            limit: limit,
            offset: offset
        )
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? {
        details.first { $0.history.id == id }?.history
    }

    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) { deletedHistoryIDs.append(id) }
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private struct StaticSnippetRepository: SnippetRepositoryProtocol {
    let details: [SnippetFolderDetail]

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just(details).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { details }

    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? {
        details.first { $0.folder.id == id }
    }

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
