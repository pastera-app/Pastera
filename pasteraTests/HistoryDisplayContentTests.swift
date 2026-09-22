//
//  HistoryDisplayContentTests.swift
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
struct HistoryDisplayContentTests {
    @Test
    func historyPanelRowsHonorConfiguredMenuTitleLength() throws {
        try withRegisteredDefaultEnvironment { defaults in
            defaults.set(20, forKey: Constants.UserDefaults.maxMenuItemTitleLength)
            let longCommand = "curl --request 'GET' https://example.com/api/v1/clipboard/history/search"
            let detail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: PasteboardHistory.ID("long-command"),
                    title: longCommand,
                    pasteboardTypes: [.string],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: nil
            )

            let row = MenuManager().makeHistoryRowViewForTesting(detail, index: 0)

            #expect(row.textValuesForTesting.contains("curl --request 'G..."))
            #expect(!row.textValuesForTesting.contains("curl --request 'GET' https://example.com/api/v1/clipboard..."))
        }
    }

    @Test
    func historyItemPresentationProvidesPreviewOnlyForShortenedText() throws {
        try withRegisteredDefaultEnvironment { _ in
            let manager = MenuManager()
            let longText = Array(repeating: "Long clipboard text", count: 8).joined(separator: " ")
            let longPresentation = manager.makeHistoryItemPresentation(
                PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("long-history"),
                        title: longText,
                        pasteboardTypes: [.string],
                        updateAt: 1,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                ),
                listNumber: 1,
                usesLeadingNumber: false
            )
            let shortPresentation = manager.makeHistoryItemPresentation(
                PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("short-history"),
                        title: "Short clipboard text",
                        pasteboardTypes: [.string],
                        updateAt: 2,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                ),
                listNumber: 2,
                usesLeadingNumber: false
            )

            #expect(longPresentation.title.hasSuffix("..."))
            #expect(longPresentation.previewText == longText)
            #expect(shortPresentation.previewText == nil)
        }
    }

    @Test
    func fileURLHistoryPresentationUsesFileNameIconAndTextPreviewWhenAvailable() throws {
        try withRegisteredDefaultEnvironment { _ in
            let presentation = MenuManager().makeHistoryItemPresentation(
                PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("file-url-text"),
                        title: "script.swift\nprint(\"Hello\")",
                        pasteboardTypes: [.fileURL],
                        updateAt: 1,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                ),
                listNumber: 1,
                usesLeadingNumber: false
            )

            #expect(presentation.title == "script.swift")
            #expect(presentation.image != nil)
            #expect(presentation.previewText == "print(\"Hello\")")
        }
    }

    @Test
    func fileURLHistoryPresentationUsesCategoryIconWithoutTextPreviewForArchives() throws {
        try withRegisteredDefaultEnvironment { _ in
            let presentation = MenuManager().makeHistoryItemPresentation(
                PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("file-url-archive"),
                        title: "backup.zip",
                        pasteboardTypes: [.fileURL],
                        updateAt: 1,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                ),
                listNumber: 1,
                usesLeadingNumber: false
            )

            #expect(presentation.title == "backup.zip")
            #expect(presentation.image != nil)
            #expect(presentation.previewText == nil)
        }
    }

    @Test
    func fileURLHistoryPresentationFallsBackToOtherFileForEmptyLegacyTitles() throws {
        try withRegisteredDefaultEnvironment { _ in
            let presentation = MenuManager().makeHistoryItemPresentation(
                PasteboardHistoryDetail(
                    history: PasteboardHistory(
                        id: PasteboardHistory.ID("file-url-empty"),
                        title: "",
                        pasteboardTypes: [.fileURL],
                        updateAt: 1,
                        deviceID: CPYUtilities.deviceID
                    ),
                    thumbnailAsset: nil
                ),
                listNumber: 1,
                usesLeadingNumber: false
            )

            #expect(presentation.title == "其他文件")
            #expect(presentation.image != nil)
            #expect(presentation.previewText == nil)
        }
    }

    @Test
    func imageHistoryRowShowsThumbnailWhenRetiredImagePreferenceWasDisabled() throws {
        try withRegisteredDefaultEnvironment { defaults in
            defaults.set(false, forKey: Constants.UserDefaults.showImageInTheMenu)
            let historyID = PasteboardHistory.ID("legacy-disabled-image")
            let image = NSImage.create(with: .red, size: NSSize(width: 24, height: 18))
            let imageData = try #require(image.tiffRepresentation)
            let detail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: historyID,
                    title: "Screenshot",
                    pasteboardTypes: [.tiff],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: PasteboardHistoryThumbnailAsset(
                    pasteboardHistoryID: historyID,
                    kind: .image,
                    data: imageData
                )
            )

            let row = MenuManager().makeHistoryRowViewForTesting(detail, index: 0)

            #expect(row.frame.height > 28)
            #expect(row.textValuesForTesting.contains("(Image)"))
        }
    }

    @Test
    func compactMainMenuImageHistoryUsesLocalizedLabelWithoutParentheses() throws {
        try withRegisteredDefaultEnvironment { defaults in
            defaults.set(false, forKey: Constants.UserDefaults.showImageInTheMenu)
            let historyID = PasteboardHistory.ID("compact-image")
            let image = NSImage.create(with: .blue, size: NSSize(width: 24, height: 18))
            let imageData = try #require(image.tiffRepresentation)
            let detail = PasteboardHistoryDetail(
                history: PasteboardHistory(
                    id: historyID,
                    title: "Screenshot",
                    pasteboardTypes: [.tiff],
                    updateAt: 1,
                    deviceID: CPYUtilities.deviceID
                ),
                thumbnailAsset: PasteboardHistoryThumbnailAsset(
                    pasteboardHistoryID: historyID,
                    kind: .image,
                    data: imageData
                )
            )

            let row = MenuManager().makeHistoryRowView(
                detail,
                index: 0,
                layoutStyle: .compactMainMenu
            ) {}

            #expect(row.frame.height == MainMenuPanelLayout.compactImageRowHeight)
            #expect(!row.textValuesForTesting.contains("(Image)"))
            #expect(row.textValuesForTesting.contains(String(localized: "Image")))
        }
    }

    private func withRegisteredDefaultEnvironment(
        operation: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "HistoryDisplayContentTests.\(UUID().uuidString)"
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
            $0.pasteboardHistoryRepository = HistoryDisplayEmptyRepository()
        } operation: {
            try operation(defaults)
        }
    }
}

private struct HistoryDisplayEmptyRepository: PasteboardHistoryRepositoryProtocol {
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
