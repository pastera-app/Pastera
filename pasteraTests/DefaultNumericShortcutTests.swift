//
//  DefaultNumericShortcutTests.swift
//
//  Clipy
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct DefaultNumericShortcutTests {
    @Test
    func legacyDisabledNumericShortcutPreferenceIsIgnored() throws {
        try withRegisteredDefaultEnvironment { defaults in
            defaults.set(false, forKey: Constants.UserDefaults.addNumericKeyEquivalents)

            let detail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: PasteboardHistory.ID("legacy-disabled-history"),
                    title: "Legacy Disabled",
                    pasteboardTypes: [.string],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: nil
            )
            let row = MenuManager().makeHistoryRowViewForTesting(detail, index: 0)

            #expect(row.textValuesForTesting.contains("1"))
        }
    }

    @Test
    func historyRowsUseRegisteredNumericShortcutDefault() throws {
        try withRegisteredDefaultEnvironment { _ in
            let manager = MenuManager()
            let firstDetail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: PasteboardHistory.ID("history-1"),
                    title: "First History",
                    pasteboardTypes: [.string],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: nil
            )
            let tenthDetail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: PasteboardHistory.ID("history-10"),
                    title: "Tenth History",
                    pasteboardTypes: [.string],
                    updateAt: 2,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: nil
            )

            let firstRow = manager.makeHistoryRowViewForTesting(firstDetail, index: 0)
            let tenthRow = manager.makeHistoryRowViewForTesting(tenthDetail, index: 9)

            #expect(firstRow.textValuesForTesting.contains("First History"))
            #expect(firstRow.textValuesForTesting.contains("1"))
            #expect(!firstRow.textValuesForTesting.contains("1. First History"))
            #expect(tenthRow.textValuesForTesting.contains("Tenth History"))
            #expect(tenthRow.textValuesForTesting.contains("0"))
            #expect(!tenthRow.textValuesForTesting.contains("0. Tenth History"))
        }
    }

    @Test
    func snippetRowsUseRegisteredNumericShortcutDefault() throws {
        try withRegisteredDefaultEnvironment { _ in
            let folderID = SnippetFolder.ID(rawValue: UUID())
            let snippets = (0..<10).map { index in
                Snippet(
                    id: Snippet.ID(rawValue: UUID()),
                    folderID: folderID,
                    title: "Snippet \(index + 1)",
                    content: "Content \(index + 1)",
                    index: index,
                    isEnabled: true
                )
            }
            let detail = SnippetFolderDetail(
                folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: snippets
            )
            let controller = SnippetBrowserPanelController(
                fetchFolders: { [detail.folder] },
                fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
                selectSnippet: { _, _ in }
            )

            controller.show(
                folderID: folderID,
                attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220)
            )
            defer { controller.close() }

            #expect(controller.rowTitlesForTesting.first == "Snippet 1")
            #expect(controller.rowTitlesForTesting.last == "Snippet 10")
            #expect(controller.rowShortcutTextsForTesting == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        }
    }

    private func withRegisteredDefaultEnvironment(
        operation: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "DefaultNumericShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        AppEnvironment.push(
            clipboardScriptCoordinator: ScriptRowCoordinator(hasScripts: false),
            defaults: defaults
        )
        defer {
            _ = AppEnvironment.popLast()
            defaults.removePersistentDomain(forName: suiteName)
        }

        CPYUtilities.registerUserDefaultKeys()
        try withDependencies {
            $0.pasteboardHistoryRepository = NumericShortcutEmptyHistoryRepository()
        } operation: {
            try operation(defaults)
        }
    }
}

private struct NumericShortcutEmptyHistoryRepository: PasteboardHistoryRepositoryProtocol {
    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> { Just([]).eraseToAnyPublisher() }
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
