//
//  PasteboardHistoryRepositoryTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/28.
//
//  Copyright © 2015-2026 Clipy Project.
//

// swiftlint:disable file_length

import AppKit
import Combine
import Dependencies
import DependenciesTestSupport
import SQLiteData
import Testing
@testable import Pastera

@MainActor
@Suite
struct HistoryRepositoryBootstrapTests {
    @Test
    func repositoryCreatedBeforeBootstrapUsesBootstrappedDatabaseAtCallTime() throws {
        let repository = PasteboardHistoryRepository()

        try withDependencies {
            try $0.bootstrapDatabase()
        } operation: {
            let content = PasteboardContent("Bootstrap after init")
            let id = PasteboardHistory.ID(rawValue: content.hash)
            let history = PasteboardHistory(id: id, title: "Bootstrap after init", updateAt: 1)

            repository.save(id: id, content: content, updateAt: 1)

            #expect(repository.fetchHistory(id: id) == history)
            #expect(repository.fetchContent(id: id) == content)
        }
    }
}

@MainActor
@Suite
struct ClipServiceCaptureTests {
    @Test
    func textWithoutCopyScriptsKeepsSynchronousCapturePath() {
        let repository = RecordingPasteboardHistoryRepository()
        let coordinator = RecordingClipboardScriptCoordinator(hasCopyScripts: false, outcome: .transformed("unused"))
        let pasteboard = makeTextPasteboard("Original")
        defer { pasteboard.clearContents() }

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService(clipboardScriptCoordinatorProvider: { coordinator })
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])

            #expect(service.createForTesting(from: pasteboard))
            #expect(repository.savedContents.map(\.stringValue) == ["Original"])
            #expect(coordinator.receivedTexts.isEmpty)
        }
    }

    @Test
    func concealedPasswordClipboardContentIsNeverCaptured() {
        let repository = RecordingPasteboardHistoryRepository()
        let pasteboard = NSPasteboard(name: .init("ClipServiceCaptureTests.secret.\(UUID().uuidString)"))
        let item = NSPasteboardItem()
        item.setString("secret-value", forType: .string)
        item.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        item.setString("", forType: .init("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        defer { pasteboard.clearContents() }

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])

            #expect(service.createForTesting(from: pasteboard))
        }

        #expect(repository.savedContents.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func successfulCopyTransformWritesAndSavesOnlyFinalText() async throws {
        let repository = RecordingPasteboardHistoryRepository()
        let coordinator = RecordingClipboardScriptCoordinator(hasCopyScripts: true, outcome: .transformed("FINAL"))
        let pasteboard = makeTextPasteboard("Original")
        defer { pasteboard.clearContents() }

        try await withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService(clipboardScriptCoordinatorProvider: { coordinator })
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])

            #expect(service.createForTesting(from: pasteboard))
            #expect(repository.savedContents.isEmpty)
            try await waitUntil { repository.savedContents.count == 1 }

            #expect(repository.savedContents.map(\.stringValue) == ["FINAL"])
            #expect(pasteboard.string(forType: .string) == "FINAL")
            #expect(coordinator.receivedTexts == ["Original"])
            #expect(service.createForTesting(from: pasteboard))
            #expect(repository.savedContents.count == 1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func failedCopyTransformSavesOriginalWithoutWritingPasteboard() async throws {
        let repository = RecordingPasteboardHistoryRepository()
        let scriptID = UUID()
        let coordinator = RecordingClipboardScriptCoordinator(
            hasCopyScripts: true,
            outcome: .failed(.javaScriptException(scriptID: scriptID))
        )
        let pasteboard = makeTextPasteboard("Original")
        let originalChangeCount = pasteboard.changeCount
        defer { pasteboard.clearContents() }

        try await withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService(clipboardScriptCoordinatorProvider: { coordinator })
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])

            #expect(service.createForTesting(from: pasteboard))
            try await waitUntil { repository.savedContents.count == 1 }

            #expect(repository.savedContents.map(\.stringValue) == ["Original"])
            #expect(pasteboard.changeCount == originalChangeCount)
        }
    }

    @Test
    func nonTextCaptureDoesNotConsultScripts() throws {
        let repository = RecordingPasteboardHistoryRepository()
        let coordinator = RecordingClipboardScriptCoordinator(hasCopyScripts: true, outcome: .transformed("unused"))
        let pasteboard = NSPasteboard(name: .init("ClipServiceCaptureTests.image.\(UUID().uuidString)"))
        let image = NSImage.create(with: .blue, size: NSSize(width: 8, height: 8))
        let data = try #require(image.tiffRepresentation)
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .tiff)
        defer { pasteboard.clearContents() }

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService(clipboardScriptCoordinatorProvider: { coordinator })
            service.setStoreTypesForTesting(["TIFF": NSNumber(value: true)])

            #expect(service.createForTesting(from: pasteboard))
        }

        #expect(coordinator.receivedTexts.isEmpty)
        #expect(repository.savedContents.count == 1)
    }

    @Test
    func emptyPasteboardChangeRetriesUntilTypesAreAvailable() {
        let repository = RecordingPasteboardHistoryRepository()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipServiceCaptureTests.retry.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])

            #expect(!service.createForTesting(from: pasteboard))

            let item = NSPasteboardItem()
            item.setString("Ready after clear", forType: .string)
            pasteboard.writeObjects([item])

            #expect(service.createForTesting(from: pasteboard))
        }

        #expect(repository.savedContents.map(\.stringValue) == ["Ready after clear"])
    }

    @Test
    func savingImageContentEnqueuesOCRIndexing() {
        let repository = RecordingPasteboardHistoryRepository()
        let ocrIndexer = RecordingOCRIndexer()
        let image = NSImage.create(with: .orange, size: NSSize(width: 24, height: 16))

        withDependencies {
            $0.pasteboardHistoryRepository = repository
            $0.pasteboardHistoryOCRIndexer = ocrIndexer
        } operation: {
            let service = ClipService()

            service.create(with: image)
        }

        #expect(repository.savedContents.count == 1)
        #expect(ocrIndexer.enqueuedHistoryIDs == repository.savedIDs)
    }
}

private func makeTextPasteboard(_ text: String) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: .init("ClipServiceCaptureTests.text.\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    return pasteboard
}

private final class RecordingClipboardScriptCoordinator: ClipboardScriptCoordinating {
    let hasCopyScripts: Bool
    let outcome: ScriptTransformOutcome
    private(set) var receivedTexts = [String]()

    init(hasCopyScripts: Bool, outcome: ScriptTransformOutcome) {
        self.hasCopyScripts = hasCopyScripts
        self.outcome = outcome
    }

    func hasEnabledScripts(for trigger: ScriptTrigger) -> Bool {
        trigger == .copy && hasCopyScripts
    }

    func transform(
        text: String,
        sourceAppBundleIdentifier: String?,
        trigger: ScriptTrigger
    ) async -> ScriptTransformOutcome {
        receivedTexts.append(text)
        return outcome
    }

    func availableHistoryScripts() -> [ScriptTransform] { [] }

    func transformHistoryText(
        _ text: String,
        using scriptID: UUID,
        sourceAppBundleIdentifier: String?
    ) async -> ScriptTransformOutcome {
        .unchanged
    }

    func writeHistoryTransformResult(_ text: String) {}

    func runManualTransform() async {}
    func consumeSuppression(changeCount: Int) -> Bool { false }
}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
// swiftlint:disable:next type_body_length
struct PasteboardHistoryRepositoryTests {
    let repository: PasteboardHistoryRepository

    init() {
        self.repository = PasteboardHistoryRepository()
    }

    @Test(.timeLimit(.minutes(1)))
    func observeHistories() async throws {
        var histories = [[PasteboardHistory]]()
        let cancellable = repository.observeHistories().sink { value in
            histories.append(value)
        }
        defer { _ = cancellable }

        try await waitUntil { histories.count >= 1 }

        let content = PasteboardContent("First")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        repository.save(id: id, content: content, updateAt: 1)
        try await waitUntil { histories.count >= 2 }

        let content2 = PasteboardContent("Second")
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)
        repository.save(id: id2, content: content2, updateAt: 2)
        try await waitUntil { histories.count >= 3 }

        repository.deleteHistory(id: id)
        try await waitUntil { histories.count >= 4 }

        #expect(
            histories == [
                [],
                [PasteboardHistory(id: id, title: "First", updateAt: 1)],
                [PasteboardHistory(id: id2, title: "Second", updateAt: 2), PasteboardHistory(id: id, title: "First", updateAt: 1)],
                [PasteboardHistory(id: id2, title: "Second", updateAt: 2)]
            ]
        )
    }

    @Test
    func saveAndFetchHistory() throws {
        #expect(!repository.hasHistories())

        let content = PasteboardContent("Hello")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let history = PasteboardHistory(id: id, title: "Hello", updateAt: 1)

        repository.save(id: id, content: content, updateAt: 1)

        #expect(repository.hasHistories())
        #expect(repository.fetchHistory(id: id) == history)
        #expect(repository.fetchContent(id: id) == content)
        #expect(
            repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10) == [
                PasteboardHistoryDetail(history: history, thumbnailAsset: nil)
            ]
        )
    }

    @Test
    func createDerivedTextHistoryPreservesSourceImage() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .blue, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: "source-image")
        repository.save(id: imageID, content: imageContent, updateAt: 1)

        let derivedID = try #require(repository.createDerivedTextHistory(text: "Recognized text", updateAt: 2))

        #expect(derivedID != imageID)
        #expect(repository.fetchContent(id: derivedID)?.stringValue == "Recognized text")
        #expect(repository.fetchContent(id: imageID) == imageContent)
    }

    @Test
    func createDerivedTextHistoryRejectsBlankText() {
        #expect(repository.createDerivedTextHistory(text: "  \n", updateAt: 2) == nil)
        #expect(!repository.hasHistories())
    }

    @Test
    func updateTextHistoryReplacesStoredPlainTextContent() throws {
        let content = PasteboardContent("#ff0000")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        repository.save(id: id, content: content, updateAt: 1)
        #expect(repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1).first?.thumbnailAsset?.kind == .colorCode)

        #expect(repository.updateTextHistory(id: id, text: "Updated text", updateAt: 20))

        #expect(repository.fetchHistory(id: id) == PasteboardHistory(
            id: id,
            title: "Updated text",
            pasteboardTypes: [.string],
            updateAt: 20,
            deviceID: CPYUtilities.deviceID
        ))
        #expect(repository.fetchContent(id: id) == PasteboardContent("Updated text"))
        #expect(repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1).first?.thumbnailAsset == nil)
    }

    @Test
    func updateTextHistoryRejectsUnsupportedOrEmptyContent() throws {
        let text = PasteboardContent("Original")
        let textID = PasteboardHistory.ID(rawValue: text.hash)
        repository.save(id: textID, content: text, updateAt: 1)

        let image = PasteboardContent(assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))])
        let imageID = PasteboardHistory.ID(rawValue: image.hash)
        repository.save(id: imageID, content: image, updateAt: 2)

        #expect(!repository.updateTextHistory(id: textID, text: "   \n", updateAt: 20))
        #expect(!repository.updateTextHistory(id: imageID, text: "Changed", updateAt: 20))
        #expect(!repository.updateTextHistory(id: PasteboardHistory.ID(rawValue: "missing"), text: "Changed", updateAt: 20))

        #expect(repository.fetchHistory(id: textID)?.title == "Original")
        #expect(repository.fetchContent(id: textID) == text)
        #expect(repository.fetchHistory(id: imageID)?.pasteboardTypes == [.png])
        #expect(repository.fetchContent(id: imageID) == image)
    }

    @Test
    func fetchHistoryDetailsOrdersAndLimitsHistories() throws {
        let content = PasteboardContent("First")
        let content2 = PasteboardContent("Second")
        let content3 = PasteboardContent("Third")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)
        let id3 = PasteboardHistory.ID(rawValue: content3.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id2, content: content2, updateAt: 2)
        repository.save(id: id3, content: content3, updateAt: 3)

        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 2)
                .map(\.history.id) == [id3, id2]
        )
        #expect(
            repository
                .fetchHistoryDetails(ascending: true, includesThumbnailAsset: false, limit: 2)
                .map(\.history.id) == [id, id2]
        )
    }

    @Test
    func fetchHistoryDetailsOffsetsHistoriesForMenuPages() throws {
        let contents = (1...5).map { PasteboardContent("Item \($0)") }
        let ids = contents.map { PasteboardHistory.ID(rawValue: $0.hash) }

        for (index, content) in contents.enumerated() {
            repository.save(id: ids[index], content: content, updateAt: index + 1)
        }

        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 2, offset: 2)
                .map(\.history.id) == [ids[2], ids[1]]
        )
    }

    @Test
    func fetchHistoryDetailsIncludesThumbnailAssetsOnlyWhenRequested() throws {
        let textContent = PasteboardContent("Hello")
        let colorContent = PasteboardContent("#ff0000")
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .blue, size: NSSize(width: 20, height: 20)))
        )
        let textID = PasteboardHistory.ID(rawValue: textContent.hash)
        let colorID = PasteboardHistory.ID(rawValue: colorContent.hash)
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)

        repository.save(id: textID, content: textContent, updateAt: 1)
        repository.save(id: colorID, content: colorContent, updateAt: 2)
        repository.save(id: imageID, content: imageContent, updateAt: 3)

        let details = repository.fetchHistoryDetails(
            ascending: false,
            includesThumbnailAsset: true,
            limit: 10
        )
        #expect(details.map(\.history.id) == [imageID, colorID, textID])
        #expect(details[0].thumbnailAsset?.pasteboardHistoryID == imageID)
        #expect(details[0].thumbnailAsset?.kind == .image)
        #expect(details[0].thumbnailAsset?.data.isEmpty == false)
        #expect(details[1].thumbnailAsset?.pasteboardHistoryID == colorID)
        #expect(details[1].thumbnailAsset?.kind == .colorCode)
        #expect(details[1].thumbnailAsset?.data.isEmpty == false)
        #expect(details[2].thumbnailAsset == nil)

        let detailsWithoutThumbnailAssets = repository.fetchHistoryDetails(
            ascending: false,
            includesThumbnailAsset: false,
            limit: 10
        )
        #expect(detailsWithoutThumbnailAssets.map(\.history.id) == [imageID, colorID, textID])
        #expect(detailsWithoutThumbnailAssets.allSatisfy { $0.thumbnailAsset == nil })
    }

    @Test
    func compactOversizedThumbnailAssetsRebuildsImageThumbnailsFromStoredAssets() throws {
        let image = try makeRepositoryNoisyImage(width: 1200, height: 800)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .tiff, data: try #require(image.tiffRepresentation))
            ]
        )
        let id = PasteboardHistory.ID(rawValue: content.hash)
        repository.save(id: id, content: content, updateAt: 1)

        @Dependency(\.defaultDatabase) var database
        try database.write { database in
            try PasteboardHistoryThumbnailAsset.upsert {
                PasteboardHistoryThumbnailAsset(
                    pasteboardHistoryID: id,
                    kind: .image,
                    data: Data(repeating: 0x7F, count: 512 * 1024)
                )
            }
            .execute(database)
        }

        let rebuiltCount = repository.compactOversizedThumbnailAssets(maxBytes: Constants.Thumbnail.maxEncodedBytes)
        let thumbnail = try #require(repository
            .fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1)
            .first?
            .thumbnailAsset)
        let bitmap = try #require(NSBitmapImageRep(data: thumbnail.data))

        #expect(rebuiltCount == 1)
        #expect(thumbnail.kind == .image)
        #expect(thumbnail.data.count < Constants.Thumbnail.maxEncodedBytes)
        #expect(bitmap.pixelsWide <= Constants.Thumbnail.hoverPreviewPixelWidth)
        #expect(bitmap.pixelsHigh <= Constants.Thumbnail.hoverPreviewPixelHeight)
        #expect(bitmap.pixelsWide > 100)
        #expect(bitmap.pixelsHigh > 32)
    }

    @Test
    func compactOversizedThumbnailAssetsRefreshesUndersizedImageThumbnails() throws {
        let image = try makeRepositoryScreenshotLikeImage(width: 1200, height: 800)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .tiff, data: try #require(image.tiffRepresentation))
            ]
        )
        let id = PasteboardHistory.ID(rawValue: content.hash)
        repository.save(id: id, content: content, updateAt: 1)
        let imageData = try #require(image.tiffRepresentation)
        let decodedImage = try #require(NSImage(data: imageData))
        let undersizedThumbnail = try #require(decodedImage.resizeImage(100, 32))
        let undersizedData = try #require(PasteraImageEncoding.pngData(from: undersizedThumbnail))

        @Dependency(\.defaultDatabase) var database
        try database.write { database in
            try PasteboardHistoryThumbnailAsset.upsert {
                PasteboardHistoryThumbnailAsset(
                    pasteboardHistoryID: id,
                    kind: .image,
                    data: undersizedData
                )
            }
            .execute(database)
        }

        let rebuiltCount = repository.compactOversizedThumbnailAssets(maxBytes: Constants.Thumbnail.maxEncodedBytes)
        let thumbnail = try #require(repository
            .fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1)
            .first?
            .thumbnailAsset)
        let bitmap = try #require(NSBitmapImageRep(data: thumbnail.data))

        #expect(rebuiltCount == 1)
        #expect(thumbnail.data.count < Constants.Thumbnail.maxEncodedBytes)
        #expect(bitmap.pixelsWide >= 800)
        #expect(bitmap.pixelsHigh >= 530)
    }

    @Test
    func saveExistingHistoryUpdatesStoredHistory() throws {
        let content = PasteboardContent("Same")
        let id = PasteboardHistory.ID(rawValue: content.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id, content: content, updateAt: 2)

        #expect(
            repository.fetchHistory(id: id) == PasteboardHistory(
                id: id,
                title: "Same",
                updateAt: 2
            )
        )
        #expect(
            repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10).map(\.history.id) == [id]
        )
    }

    @Test
    func screenshotImportsKeepSeparateHistoryEntriesEvenWhenImageBytesMatch() throws {
        let defaults = AppEnvironment.current.defaults
        let previousOverwriteSameHistory = defaults.object(forKey: Constants.UserDefaults.overwriteSameHistory)
        let previousCopySameHistory = defaults.object(forKey: Constants.UserDefaults.copySameHistory)
        let previousStoredHistoryLimit = defaults.object(forKey: Constants.UserDefaults.storedHistoryLimit)
        defer {
            restore(previousOverwriteSameHistory, forKey: Constants.UserDefaults.overwriteSameHistory, defaults: defaults)
            restore(previousCopySameHistory, forKey: Constants.UserDefaults.copySameHistory, defaults: defaults)
            restore(previousStoredHistoryLimit, forKey: Constants.UserDefaults.storedHistoryLimit, defaults: defaults)
        }
        defaults.set(true, forKey: Constants.UserDefaults.overwriteSameHistory)
        defaults.set(true, forKey: Constants.UserDefaults.copySameHistory)
        defaults.set(10, forKey: Constants.UserDefaults.storedHistoryLimit)

        let service = ClipService()
        let image = NSImage.create(with: .green, size: NSSize(width: 16, height: 16))

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            service.create(with: image)
            service.create(with: image)
        }

        let details = repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
        #expect(details.count == 2)
        #expect(Set(details.map(\.history.id)).count == 2)
        #expect(details.allSatisfy { $0.history.pasteboardTypes == [.tiff] })
    }

    @Test
    func recopyingImportedPlainTextReusesItsRemoteIdentity() throws {
        let defaults = AppEnvironment.current.defaults
        let previousOverwrite = defaults.object(forKey: Constants.UserDefaults.overwriteSameHistory)
        let previousCopySame = defaults.object(forKey: Constants.UserDefaults.copySameHistory)
        defer {
            restore(previousOverwrite, forKey: Constants.UserDefaults.overwriteSameHistory, defaults: defaults)
            restore(previousCopySame, forKey: Constants.UserDefaults.copySameHistory, defaults: defaults)
        }
        defaults.set(true, forKey: Constants.UserDefaults.overwriteSameHistory)
        defaults.set(true, forKey: Constants.UserDefaults.copySameHistory)
        let remoteID = PasteboardHistory.ID(rawValue: "remote-history-recopy")
        #expect(try repository.upsertSyncPayload(PasteboardHistorySyncPayload(
            id: remoteID.rawValue,
            text: "Imported text",
            updateAt: 10,
            deviceID: "remote-device",
            sourceKind: .plainText
        )))
        let pasteboard = makeTextPasteboard("Imported text")
        defer { pasteboard.clearContents() }

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])
            #expect(service.createForTesting(from: pasteboard))
        }

        let histories = repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
        #expect(histories.map(\.history.id) == [remoteID])
        let recopied = try #require(repository.fetchHistory(id: remoteID))
        #expect(recopied.updateAt > 10)
        #expect(repository.fetchContent(id: remoteID)?.assets == [
            .init(type: .string, data: Data("Imported text".utf8))
        ])
    }

    @Test
    func recopyingOriginalTextAfterEditingPreservesBothContents() throws {
        let defaults = AppEnvironment.current.defaults
        let previousOverwrite = defaults.object(forKey: Constants.UserDefaults.overwriteSameHistory)
        let previousCopySame = defaults.object(forKey: Constants.UserDefaults.copySameHistory)
        defer {
            restore(previousOverwrite, forKey: Constants.UserDefaults.overwriteSameHistory, defaults: defaults)
            restore(previousCopySame, forKey: Constants.UserDefaults.copySameHistory, defaults: defaults)
        }
        defaults.set(true, forKey: Constants.UserDefaults.overwriteSameHistory)
        defaults.set(true, forKey: Constants.UserDefaults.copySameHistory)
        let original = PasteboardContent("Original text")
        let editedID = PasteboardHistory.ID(rawValue: original.hash)
        repository.save(id: editedID, content: original, updateAt: 10)
        #expect(repository.updateTextHistory(id: editedID, text: "Edited text", updateAt: 20))
        let pasteboard = makeTextPasteboard("Original text")
        defer { pasteboard.clearContents() }

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])
            #expect(service.createForTesting(from: pasteboard))
        }

        let histories = repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
        #expect(histories.count == 2)
        #expect(repository.fetchHistory(id: editedID)?.title == "Edited text")
        #expect(repository.fetchContent(id: editedID)?.stringValue == "Edited text")
        let recopied = try #require(histories.first { $0.history.id != editedID })
        #expect(recopied.history.title == "Original text")
        #expect(repository.fetchContent(id: recopied.history.id)?.stringValue == "Original text")
    }

    @Test
    func recopyingMatchedHistoryPreservesAnInterleavedRemoteUpdateAndIndexesTheCapturedID() throws {
        let defaults = AppEnvironment.current.defaults
        let previousOverwrite = defaults.object(forKey: Constants.UserDefaults.overwriteSameHistory)
        let previousCopySame = defaults.object(forKey: Constants.UserDefaults.copySameHistory)
        defer {
            restore(previousOverwrite, forKey: Constants.UserDefaults.overwriteSameHistory, defaults: defaults)
            restore(previousCopySame, forKey: Constants.UserDefaults.copySameHistory, defaults: defaults)
        }
        defaults.set(true, forKey: Constants.UserDefaults.overwriteSameHistory)
        defaults.set(true, forKey: Constants.UserDefaults.copySameHistory)
        let remoteID = PasteboardHistory.ID(rawValue: "remote-interleaved-capture")
        try repository.upsertSyncPayload(.init(
            id: remoteID.rawValue, text: "Captured text", updateAt: 10,
            deviceID: "remote-device", sourceKind: .plainText
        ))
        let interleavingRepository = InterleavingCaptureHistoryRepository(repository: repository) {
            try repository.upsertSyncPayload(.init(
                id: remoteID.rawValue, text: "New remote text", updateAt: 20,
                deviceID: "remote-device", sourceKind: .plainText
            ))
        }
        let indexer = RecordingOCRIndexer()
        let pasteboard = makeTextPasteboard("Captured text")
        defer { pasteboard.clearContents() }

        withDependencies {
            $0.pasteboardHistoryRepository = interleavingRepository
            $0.pasteboardHistoryOCRIndexer = indexer
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])
            #expect(service.createForTesting(from: pasteboard))
        }

        #expect(interleavingRepository.interleavingError == nil)
        #expect(repository.fetchHistory(id: remoteID)?.title == "New remote text")
        #expect(repository.fetchHistory(id: remoteID)?.updateAt == 20)
        #expect(repository.fetchContent(id: remoteID)?.stringValue == "New remote text")
        let histories = repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
        #expect(histories.count == 2)
        let captured = try #require(histories.first { $0.history.id != remoteID })
        #expect(captured.history.title == "Captured text")
        #expect(repository.fetchContent(id: captured.history.id)?.stringValue == "Captured text")
        #expect(indexer.enqueuedHistoryIDs == [captured.history.id])
    }

    @Test
    func failedCaptureWriteRetriesWithoutEnqueueingOCR() throws {
        @Dependency(\.defaultDatabase) var database
        try database.write { database in
            try #sql("""
                CREATE TEMP TRIGGER reject_capture
                BEFORE INSERT ON pasteboardHistories
                BEGIN SELECT RAISE(ABORT, 'Simulated capture write failure'); END
                """).execute(database)
        }
        defer { try? database.write { try #sql("DROP TRIGGER reject_capture").execute($0) } }
        let pasteboard = makeTextPasteboard("Retry capture after write failure")
        defer { pasteboard.clearContents() }
        let indexer = RecordingOCRIndexer()
        var captured = true

        withDependencies {
            $0.pasteboardHistoryRepository = repository
            $0.pasteboardHistoryOCRIndexer = indexer
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])
            withKnownIssue("The injected database failure is reported to the application") {
                captured = service.createForTesting(from: pasteboard)
            } matching: { issue in
                issue.description.contains("Simulated capture write failure")
            }
        }

        #expect(!captured)
        #expect(!repository.hasHistories())
        #expect(indexer.enqueuedHistoryIDs.isEmpty)
    }

    @Test(arguments: [true, false])
    func importedTextRecopyHonorsDuplicatePreferences(copySameHistory: Bool) throws {
        let defaults = AppEnvironment.current.defaults
        let previousOverwrite = defaults.object(forKey: Constants.UserDefaults.overwriteSameHistory)
        let previousCopySame = defaults.object(forKey: Constants.UserDefaults.copySameHistory)
        defer {
            restore(previousOverwrite, forKey: Constants.UserDefaults.overwriteSameHistory, defaults: defaults)
            restore(previousCopySame, forKey: Constants.UserDefaults.copySameHistory, defaults: defaults)
        }
        defaults.set(false, forKey: Constants.UserDefaults.overwriteSameHistory)
        defaults.set(copySameHistory, forKey: Constants.UserDefaults.copySameHistory)
        let remoteID = PasteboardHistory.ID(rawValue: "remote-history-preferences")
        #expect(try repository.upsertSyncPayload(PasteboardHistorySyncPayload(
            id: remoteID.rawValue,
            text: "Imported preference text",
            updateAt: 10,
            deviceID: "remote-device",
            sourceKind: .plainText
        )))
        let pasteboard = makeTextPasteboard("Imported preference text")
        defer { pasteboard.clearContents() }

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])
            #expect(service.createForTesting(from: pasteboard))
        }

        let histories = repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
        #expect(histories.count == (copySameHistory ? 2 : 1))
        #expect(repository.fetchHistory(id: remoteID)?.updateAt == 10)
        #expect(histories.allSatisfy {
            repository.fetchContent(id: $0.history.id)?.stringValue == "Imported preference text"
        })
    }

    @Test
    func matchingHistoryRequiresSameFormatsBytesAndAssetOrder() throws {
        let text = PasteboardContent.Asset(type: .string, data: Data("Same text".utf8))
        let rich = PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 Same text}".utf8))
        let otherRich = PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1\\b Same text}".utf8))
        let richContent = PasteboardContent(assets: [text, rich])
        let otherRichContent = PasteboardContent(assets: [text, otherRich])
        let reorderedContent = PasteboardContent(assets: [rich, text])
        let variants: [(String, PasteboardContent)] = [
            ("plain", PasteboardContent(assets: [text])),
            (richContent.hash, richContent),
            (otherRichContent.hash, otherRichContent),
            (reorderedContent.hash, reorderedContent)
        ]
        for (offset, variant) in variants.enumerated() {
            repository.save(id: .init(rawValue: variant.0), content: variant.1, updateAt: offset + 1)
        }

        for (id, content) in variants {
            #expect(repository.fetchHistory(matching: content)?.id.rawValue == id)
        }
        #expect(repository.fetchHistory(matching: PasteboardContent("Different text")) == nil)
    }

    @Test
    func deleteHistory() throws {
        let content = PasteboardContent("Hello")
        let id = PasteboardHistory.ID(rawValue: content.hash)

        repository.save(id: id, content: content, updateAt: 1)
        #expect(repository.fetchHistory(id: id) != nil)

        repository.deleteHistory(id: id)
        #expect(repository.fetchHistory(id: id) == nil)
    }

    @Test
    func deleteAll() throws {
        let content = PasteboardContent("First")
        let content2 = PasteboardContent("Second")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id2, content: content2, updateAt: 2)
        #expect(repository.hasHistories())

        repository.deleteAll()

        #expect(!repository.hasHistories())
    }

    @Test
    func deleteOverflowingHistories() throws {
        let content = PasteboardContent("First")
        let content2 = PasteboardContent("Second")
        let content3 = PasteboardContent("Third")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)
        let id3 = PasteboardHistory.ID(rawValue: content3.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id2, content: content2, updateAt: 2)
        repository.save(id: id3, content: content3, updateAt: 3)

        repository.deleteOverflowingHistories(maxHistorySize: 2)
        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
                .map(\.history.id) == [id3, id2]
        )
        #expect(repository.fetchHistory(id: id) == nil)

        repository.deleteOverflowingHistories(maxHistorySize: 0)
        #expect(!repository.hasHistories())
    }

    @Test
    func retentionSettingsSeparateMenuDisplayFromStoredHistory() throws {
        let settings = HistoryRetentionSettings(
            menuDisplayLimit: 1,
            storedHistoryLimit: 2,
            maxSyncedHistoryTextBytes: 256 * 1024,
            maxHistorySnapshotTextBudgetBytes: 8 * 1024 * 1024,
            maxImageHistorySize: 15,
            maxFileHistorySize: 15
        )
        let first = PasteboardContent("First")
        let second = PasteboardContent("Second")
        let third = PasteboardContent("Third")
        let firstID = PasteboardHistory.ID(rawValue: first.hash)
        let secondID = PasteboardHistory.ID(rawValue: second.hash)
        let thirdID = PasteboardHistory.ID(rawValue: third.hash)

        repository.save(id: firstID, content: first, updateAt: 1)
        repository.save(id: secondID, content: second, updateAt: 2)
        repository.save(id: thirdID, content: third, updateAt: 3)

        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: settings.menuDisplayLimit)
                .map(\.history.id) == [thirdID]
        )

        repository.pruneHistories(settings: settings)

        #expect(repository.fetchHistory(id: thirdID) != nil)
        #expect(repository.fetchHistory(id: secondID) != nil)
        #expect(repository.fetchHistory(id: firstID) == nil)
    }

    @Test
    func plainSearchIsCaseInsensitiveAndPaginates() throws {
        let first = PasteboardContent("alpha")
        let second = PasteboardContent("Beta")
        let third = PasteboardContent("ALPINE")
        let firstID = PasteboardHistory.ID(rawValue: first.hash)
        let secondID = PasteboardHistory.ID(rawValue: second.hash)
        let thirdID = PasteboardHistory.ID(rawValue: third.hash)

        repository.save(id: firstID, content: first, updateAt: 1)
        repository.save(id: secondID, content: second, updateAt: 2)
        repository.save(id: thirdID, content: third, updateAt: 3)

        let firstPage = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "alp", mode: .plain, caseSensitive: false, sortOrder: .newestFirst),
            includesThumbnailAsset: false,
            limit: 1,
            offset: 0
        )
        let secondPage = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "alp", mode: .plain, caseSensitive: false, sortOrder: .newestFirst),
            includesThumbnailAsset: false,
            limit: 1,
            offset: 1
        )

        #expect(firstPage.map(\.history.id) == [thirdID])
        #expect(secondPage.map(\.history.id) == [firstID])
        #expect(repository.fetchHistory(id: secondID) != nil)
    }

    @Test
    func regexSearchFiltersByTypeAndReportsInvalidPatterns() throws {
        let text = PasteboardContent("ticket-123")
        let pdf = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .pdf, data: Data("ticket-456".utf8))
            ]
        )
        let textID = PasteboardHistory.ID(rawValue: text.hash)
        let pdfID = PasteboardHistory.ID(rawValue: pdf.hash)

        repository.save(id: textID, content: text, updateAt: 1)
        repository.save(id: pdfID, content: pdf, updateAt: 2)

        let matches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(
                text: #"ticket-\d+"#,
                mode: .regex,
                caseSensitive: true,
                types: [.string],
                sortOrder: .oldestFirst
            ),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )

        #expect(matches.map(\.history.id) == [textID])

        #expect(throws: HistorySearchError.invalidRegularExpression("["))
        {
            _ = try repository.searchHistoryDetails(
                query: HistorySearchQuery(text: "[", mode: .regex),
                includesThumbnailAsset: false,
                limit: 10,
                offset: 0
            )
        }
    }

}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistoryOCRSearchTests {
    let repository = PasteboardHistoryRepository()

    @Test
    func ocrCandidateIDsAreMissingImagesNewestFirstAndLimited() throws {
        let olderContent = try #require(
            PasteboardContent(image: NSImage.create(with: .red, size: NSSize(width: 8, height: 8)))
        )
        let indexedContent = try #require(
            PasteboardContent(image: NSImage.create(with: .green, size: NSSize(width: 8, height: 8)))
        )
        let newerContent = try #require(
            PasteboardContent(image: NSImage.create(with: .blue, size: NSSize(width: 8, height: 8)))
        )
        let olderID = PasteboardHistory.ID(rawValue: "older-image")
        let indexedID = PasteboardHistory.ID(rawValue: "indexed-image")
        let newerID = PasteboardHistory.ID(rawValue: "newer-image")
        repository.save(id: olderID, content: olderContent, updateAt: 1)
        repository.save(id: indexedID, content: indexedContent, updateAt: 2)
        repository.save(id: newerID, content: newerContent, updateAt: 3)
        #expect(repository.upsertOCRText(
            historyID: indexedID,
            sourceHash: "indexed-source",
            recognizedText: "indexed",
            updatedAt: 4
        ))

        #expect(repository.fetchOCRIndexingCandidateIDs(limit: 1) == [newerID])
        #expect(repository.fetchOCRIndexingCandidateIDs(limit: 10) == [newerID, olderID])
        #expect(repository.fetchOCRIndexingCandidateIDs(limit: 0).isEmpty)
    }

    @Test
    func imageOCRTextParticipatesInPlainSearchAndImageTypeFiltering() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .blue, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)
        let textContent = PasteboardContent("普通文本")
        let textID = PasteboardHistory.ID(rawValue: textContent.hash)

        repository.save(id: imageID, content: imageContent, updateAt: 1)
        repository.save(id: textID, content: textContent, updateAt: 2)
        #expect(repository.upsertOCRText(
            historyID: imageID,
            sourceHash: "image-source",
            recognizedText: "个测试通过",
            updatedAt: 3
        ))

        let allMatches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "通过", mode: .plain, caseSensitive: false, sortOrder: .oldestFirst),
            includesThumbnailAsset: true,
            limit: 10,
            offset: 0
        )
        let imageMatches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(
                text: "通过",
                mode: .plain,
                caseSensitive: false,
                types: NSPasteboard.PasteboardType.clipyImageTypes,
                sortOrder: .oldestFirst
            ),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )
        let missingMatches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "失败", mode: .plain, caseSensitive: false, sortOrder: .oldestFirst),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )

        #expect(allMatches.map(\.history.id) == [imageID])
        #expect(allMatches.first?.thumbnailAsset?.kind == .image)
        #expect(imageMatches.map(\.history.id) == [imageID])
        #expect(!allMatches.map(\.history.id).contains(textID))
        #expect(missingMatches.isEmpty)
    }

    @Test
    func imageOCRTextSearchSupportsRegexAndCaseSensitivity() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .green, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)
        repository.save(id: imageID, content: imageContent, updateAt: 1)
        #expect(repository.upsertOCRText(
            historyID: imageID,
            sourceHash: "image-source",
            recognizedText: "Build Passed\nToken ABC",
            updatedAt: 2
        ))

        let caseSensitiveMatches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "Build Passed", mode: .plain, caseSensitive: true),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )
        let caseSensitiveMisses = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "build passed", mode: .plain, caseSensitive: true),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )
        let regexMatches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: #"Token\s+[A-Z]{3}"#, mode: .regex, caseSensitive: true),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )

        #expect(caseSensitiveMatches.map(\.history.id) == [imageID])
        #expect(caseSensitiveMisses.isEmpty)
        #expect(regexMatches.map(\.history.id) == [imageID])
    }

    @Test
    func deletingHistoryDeletesOCRText() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .purple, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)
        repository.save(id: imageID, content: imageContent, updateAt: 1)
        #expect(repository.upsertOCRText(
            historyID: imageID,
            sourceHash: "image-source",
            recognizedText: "deleted text",
            updatedAt: 2
        ))

        repository.deleteHistory(id: imageID)

        #expect(repository.fetchOCRText(historyID: imageID) == nil)
    }

    @Test
    func ocrIndexerIndexesSavedImageContentWithFakeRecognizer() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .red, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)
        let recognizer = FakeImageTextRecognizer(result: "个测试通过")
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: recognizer,
            scheduler: { $0() },
            now: { 100 }
        )
        repository.save(id: imageID, content: imageContent, updateAt: 1)

        indexer.enqueueIndexing(historyID: imageID)

        let matches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "通过", mode: .plain),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )
        let ocrText = try #require(repository.fetchOCRText(historyID: imageID))
        #expect(matches.map(\.history.id) == [imageID])
        #expect(ocrText.recognizedText == "个测试通过")
        #expect(ocrText.updatedAt == 100)
        #expect(recognizer.recognizedImageDataCount == 1)
    }

    @Test
    func onDemandOCRReusesCachedText() async throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .red, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: "on-demand-cache")
        let recognizer = FakeImageTextRecognizer(result: "should not run")
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: recognizer,
            scheduler: { $0() },
            now: { 300 }
        )
        repository.save(id: imageID, content: imageContent, updateAt: 1)
        let source = try #require(PasteboardHistoryOCRIndexer.imageSource(from: imageContent))
        #expect(repository.upsertOCRText(
            historyID: imageID,
            sourceHash: source.sourceHash,
            recognizedText: "cached text",
            updatedAt: 2
        ))

        let result = await indexer.recognizeText(historyID: imageID, content: imageContent)

        #expect(result == .success("cached text"))
        #expect(recognizer.recognizedImageDataCount == 0)
    }

    @Test
    func onDemandOCRReportsUnsupportedImageSource() async {
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: FakeImageTextRecognizer(result: "unused"),
            scheduler: { $0() }
        )

        let result = await indexer.recognizeText(
            historyID: PasteboardHistory.ID(rawValue: "text"),
            content: PasteboardContent("not an image")
        )

        #expect(result == .failure(.unsupportedImageSource))
    }

    @Test
    func ocrIndexerReusesExistingSourceHashWithoutRecognizingAgain() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .red, size: NSSize(width: 24, height: 16)))
        )
        let firstID = PasteboardHistory.ID(rawValue: "ocr-source-reuse-first")
        let secondID = PasteboardHistory.ID(rawValue: "ocr-source-reuse-second")
        let recognizer = FakeImageTextRecognizer(result: "reused recognized text")
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: recognizer,
            scheduler: { $0() },
            now: { 150 }
        )
        repository.save(id: firstID, content: imageContent, updateAt: 1)
        repository.save(id: secondID, content: imageContent, updateAt: 2)

        indexer.enqueueIndexing(historyID: firstID)
        indexer.enqueueIndexing(historyID: secondID)

        #expect(repository.fetchOCRText(historyID: firstID)?.recognizedText == "reused recognized text")
        #expect(repository.fetchOCRText(historyID: secondID)?.recognizedText == "reused recognized text")
        #expect(recognizer.recognizedImageDataCount == 1)
    }

    @Test
    func ocrIndexerTrimsAndCapsRecognizedTextBeforeSaving() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .orange, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)
        let longResult = "  "
            + String(repeating: "通", count: PasteboardHistoryOCRTextLimits.maxRecognizedTextLength + 40)
            + "\n"
        let recognizer = FakeImageTextRecognizer(result: longResult)
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: recognizer,
            scheduler: { $0() },
            now: { 175 }
        )
        repository.save(id: imageID, content: imageContent, updateAt: 1)

        indexer.enqueueIndexing(historyID: imageID)

        let ocrText = try #require(repository.fetchOCRText(historyID: imageID))
        #expect(ocrText.recognizedText.utf16.count == PasteboardHistoryOCRTextLimits.maxRecognizedTextLength)
        #expect(!ocrText.recognizedText.hasPrefix(" "))
        #expect(!ocrText.recognizedText.hasSuffix("\n"))
    }

    @Test
    func ocrIndexerBackfillsExistingImageHistories() throws {
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .cyan, size: NSSize(width: 24, height: 16)))
        )
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)
        let recognizer = FakeImageTextRecognizer(result: "backfill 通过")
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: recognizer,
            scheduler: { $0() },
            now: { 200 }
        )
        repository.save(id: imageID, content: imageContent, updateAt: 1)

        indexer.backfillMissingImageOCR(limit: 10)

        let matches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "backfill", mode: .plain),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )
        #expect(matches.map(\.history.id) == [imageID])
    }

    @Test
    func ocrBackfillMaterializesOneHistoryPerSchedulerTurn() throws {
        let content = try #require(
            PasteboardContent(image: NSImage.create(with: .cyan, size: NSSize(width: 24, height: 16)))
        )
        let ids = (1...3).map { PasteboardHistory.ID(rawValue: "backfill-\($0)") }
        let repository = RecordingPasteboardHistoryRepository()
        repository.ocrCandidateIDs = ids
        repository.contentsByID = Dictionary(uniqueKeysWithValues: ids.map { ($0, content) })
        let scheduler = ControlledOCRScheduler()
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: FakeImageTextRecognizer(result: "indexed"),
            scheduler: scheduler.schedule
        )

        indexer.backfillMissingImageOCR(limit: 200)

        #expect(repository.fetchedContentIDs.isEmpty)
        scheduler.runNext()
        #expect(repository.fetchedContentIDs == [ids[0]])
        scheduler.runNext()
        #expect(repository.fetchedContentIDs == Array(ids.prefix(2)))
        scheduler.runNext()
        #expect(repository.fetchedContentIDs == ids)
    }

    @Test
    func repeatedOCRBackfillCallsShareOneConsumer() throws {
        let content = try #require(
            PasteboardContent(image: NSImage.create(with: .purple, size: NSSize(width: 24, height: 16)))
        )
        let id = PasteboardHistory.ID(rawValue: "single-backfill")
        let repository = RecordingPasteboardHistoryRepository()
        repository.ocrCandidateIDs = [id]
        repository.contentsByID = [id: content]
        let scheduler = ControlledOCRScheduler()
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: FakeImageTextRecognizer(result: "indexed"),
            scheduler: scheduler.schedule
        )

        indexer.backfillMissingImageOCR(limit: 200)
        indexer.backfillMissingImageOCR(limit: 200)
        scheduler.runAll()

        #expect(repository.ocrCandidateQueryCount == 1)
        #expect(repository.fetchedContentIDs == [id])
    }

    @Test
    func ocrIndexerDeletesOCRTextForNonImageContentAndIgnoresRecognizerFailure() throws {
        let textContent = PasteboardContent("not image")
        let textID = PasteboardHistory.ID(rawValue: textContent.hash)
        repository.save(id: textID, content: textContent, updateAt: 1)
        #expect(repository.upsertOCRText(
            historyID: textID,
            sourceHash: "old",
            recognizedText: "stale",
            updatedAt: 1
        ))
        let failingImageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .yellow, size: NSSize(width: 24, height: 16)))
        )
        let failingImageID = PasteboardHistory.ID(rawValue: failingImageContent.hash)
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: FakeImageTextRecognizer(error: FakeImageTextRecognizer.Failure.failed),
            scheduler: { $0() },
            now: { 300 }
        )
        repository.save(id: failingImageID, content: failingImageContent, updateAt: 2)

        indexer.enqueueIndexing(historyID: textID)
        indexer.enqueueIndexing(historyID: failingImageID)

        #expect(repository.fetchOCRText(historyID: textID) == nil)
        #expect(repository.fetchOCRText(historyID: failingImageID) == nil)
    }

    @Test
    func oversizedImageSourceIsSkippedBeforeOCRRecognition() throws {
        let image = NSImage.create(with: .magenta, size: NSSize(width: 24, height: 16))
        var oversizedPNGData = try #require(PasteraImageEncoding.pngData(from: image))
        oversizedPNGData.append(Data(
            repeating: 0,
            count: PasteboardHistoryOCRIndexer.maxSourceImageBytes - oversizedPNGData.count + 1
        ))
        let imageContent = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .png, data: oversizedPNGData)]
        )
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)
        let recognizer = FakeImageTextRecognizer(result: "should not run")
        let indexer = PasteboardHistoryOCRIndexer(
            repository: repository,
            recognizer: recognizer,
            scheduler: { $0() },
            now: { 325 }
        )
        repository.save(id: imageID, content: imageContent, updateAt: 1)

        indexer.enqueueIndexing(historyID: imageID)

        #expect(repository.fetchOCRText(historyID: imageID) == nil)
        #expect(recognizer.recognizedImageDataCount == 0)
    }
}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistoryRepositoryFileCategorySearchTests {
    let repository = PasteboardHistoryRepository()

    @Test
    func searchFiltersFinderFilesByCategoryWithoutMatchingTextHistory() throws {
        let documentURL = try writeTemporaryFile(name: "report.docx", data: Data("document".utf8))
        let archiveURL = try writeTemporaryFile(name: "backup.zip", data: Data([0x50, 0x4B, 0x03, 0x04]))
        let codeURL = try writeTemporaryFile(name: "main.swift", data: Data("let value = 1".utf8))
        let otherURL = try writeTemporaryFile(name: "payload.unknown", data: Data("payload".utf8))
        defer {
            [documentURL, archiveURL, codeURL, otherURL].forEach {
                try? FileManager.default.removeItem(at: $0.deletingLastPathComponent())
            }
        }

        let document = PasteboardContent(assets: [.init(type: .fileURL, data: documentURL.dataRepresentation)])
        let archive = PasteboardContent(assets: [.init(type: .fileURL, data: archiveURL.dataRepresentation)])
        let code = PasteboardContent(assets: [.init(type: .fileURL, data: codeURL.dataRepresentation)])
        let other = PasteboardContent(assets: [.init(type: .fileURL, data: otherURL.dataRepresentation)])
        let text = PasteboardContent("payload.unknown")

        let documentID = PasteboardHistory.ID(rawValue: document.hash)
        let archiveID = PasteboardHistory.ID(rawValue: archive.hash)
        let codeID = PasteboardHistory.ID(rawValue: code.hash)
        let otherID = PasteboardHistory.ID(rawValue: other.hash)
        let textID = PasteboardHistory.ID(rawValue: text.hash)

        repository.save(id: documentID, content: document, updateAt: 1)
        repository.save(id: archiveID, content: archive, updateAt: 2)
        repository.save(id: codeID, content: code, updateAt: 3)
        repository.save(id: otherID, content: other, updateAt: 4)
        repository.save(id: textID, content: text, updateAt: 5)

        let codeMatches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(
                text: "",
                types: [.fileURL],
                fileCategories: [.code],
                sortOrder: .oldestFirst
            ),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )
        let otherMatches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(
                text: "",
                types: [.fileURL],
                fileCategories: [.other],
                sortOrder: .oldestFirst
            ),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )

        #expect(codeMatches.map(\.history.id) == [codeID])
        #expect(otherMatches.map(\.history.id) == [otherID])
        #expect(repository.fetchHistory(id: textID) != nil)
    }
}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistoryMediaRetentionTests {
    let repository = PasteboardHistoryRepository()

    @Test
    func retentionSettingsClampMediaHistoryLimits() throws {
        let suiteName = "PasteboardHistoryRepositoryTests.retentionMediaClamp.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = HistoryRetentionSettings.current(defaults: defaults)

        #expect(settings.maxImageHistorySize == 15)
        #expect(settings.maxFileHistorySize == 15)

        defaults.set(-3, forKey: Constants.UserDefaults.maxImageHistorySize)
        defaults.set(99, forKey: Constants.UserDefaults.maxFileHistorySize)
        settings = HistoryRetentionSettings.current(defaults: defaults)

        #expect(settings.maxImageHistorySize == 1)
        #expect(settings.maxFileHistorySize == 50)

        defaults.set(1, forKey: Constants.UserDefaults.maxImageHistorySize)
        defaults.set(50, forKey: Constants.UserDefaults.maxFileHistorySize)
        settings = HistoryRetentionSettings.current(defaults: defaults)

        #expect(settings.maxImageHistorySize == 1)
        #expect(settings.maxFileHistorySize == 50)
    }

    @Test
    func pruneHistoriesLimitsImagesAndFilesIndependentlyWithoutDeletingText() throws {
        let imageOne = PasteboardContent(assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47, 1]))])
        let imageTwo = PasteboardContent(assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47, 2]))])
        let imageThree = PasteboardContent(assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47, 3]))])
        let fileOneURL = try writeTemporaryFile(name: "one.txt", data: Data("one".utf8))
        let fileTwoURL = try writeTemporaryFile(name: "two.txt", data: Data("two".utf8))
        defer {
            try? FileManager.default.removeItem(at: fileOneURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: fileTwoURL.deletingLastPathComponent())
        }
        let fileOne = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileOneURL.dataRepresentation)]
        )
        let fileTwo = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileTwoURL.dataRepresentation)]
        )
        let text = PasteboardContent("Text remains")
        let pdf = PasteboardContent(assets: [PasteboardContent.Asset(type: .pdf, data: Data("%PDF-1.7".utf8))])
        let settings = HistoryRetentionSettings(
            menuDisplayLimit: 10,
            storedHistoryLimit: 20,
            maxSyncedHistoryTextBytes: 256 * 1024,
            maxHistorySnapshotTextBudgetBytes: 8 * 1024 * 1024,
            maxImageHistorySize: 2,
            maxFileHistorySize: 1
        )

        repository.save(id: PasteboardHistory.ID(rawValue: imageOne.hash), content: imageOne, updateAt: 1)
        repository.save(id: PasteboardHistory.ID(rawValue: imageTwo.hash), content: imageTwo, updateAt: 2)
        repository.save(id: PasteboardHistory.ID(rawValue: fileOne.hash), content: fileOne, updateAt: 3)
        repository.save(id: PasteboardHistory.ID(rawValue: imageThree.hash), content: imageThree, updateAt: 4)
        repository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 5)
        repository.save(id: PasteboardHistory.ID(rawValue: fileTwo.hash), content: fileTwo, updateAt: 6)
        repository.save(id: PasteboardHistory.ID(rawValue: pdf.hash), content: pdf, updateAt: 7)

        repository.pruneHistories(settings: settings)

        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: imageOne.hash)) == nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: imageTwo.hash)) != nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: imageThree.hash)) != nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: fileOne.hash)) == nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: fileTwo.hash)) != nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: text.hash)) != nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: pdf.hash)) != nil)
    }

    @Test
    func pruneHistoriesDeletesMixedImageAndFileHistoryOnceWhenBothLimitsOverflow() throws {
        let newerImage = PasteboardContent(assets: [
            PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47, 1]))
        ])
        let fileURL = try writeTemporaryFile(name: "newer.txt", data: Data("newer".utf8))
        let mixedFileURL = try writeTemporaryFile(name: "mixed.txt", data: Data("mixed".utf8))
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: mixedFileURL.deletingLastPathComponent())
        }
        let newerFile = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )
        let mixedImageAndFile = PasteboardContent(assets: [
            PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47, 2])),
            PasteboardContent.Asset(type: .fileURL, data: mixedFileURL.dataRepresentation)
        ])
        let text = PasteboardContent("Text remains")
        let settings = HistoryRetentionSettings(
            menuDisplayLimit: 10,
            storedHistoryLimit: 20,
            maxSyncedHistoryTextBytes: 256 * 1024,
            maxHistorySnapshotTextBudgetBytes: 8 * 1024 * 1024,
            maxImageHistorySize: 1,
            maxFileHistorySize: 1
        )

        repository.save(id: PasteboardHistory.ID(rawValue: mixedImageAndFile.hash), content: mixedImageAndFile, updateAt: 1)
        repository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 2)
        repository.save(id: PasteboardHistory.ID(rawValue: newerFile.hash), content: newerFile, updateAt: 3)
        repository.save(id: PasteboardHistory.ID(rawValue: newerImage.hash), content: newerImage, updateAt: 4)

        repository.pruneHistories(settings: settings)

        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: mixedImageAndFile.hash)) == nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: newerFile.hash)) != nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: newerImage.hash)) != nil)
        #expect(repository.fetchHistory(id: PasteboardHistory.ID(rawValue: text.hash)) != nil)
    }
}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistorySyncRepositoryTests {
    let repository = PasteboardHistoryRepository()

    @Test
    func fileSyncSnapshotExportsSupportedNonTextAssetsWithoutAffectingTextHistory() throws {
        let text = PasteboardContent("Text only")
        let webURL = try #require(URL(string: "https://pastera.example"))
        let urlContent = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .URL, data: webURL.dataRepresentation)]
        )
        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))]
        )
        let pdf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data("%PDF-1.7".utf8))]
        )
        let rtf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 file}".utf8))]
        )
        let fileURL = try writeTemporaryFile(name: "report.txt", data: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let file = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )
        let tooLarge = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data(repeating: 1, count: 13))]
        )
        let folderURL = try writeTemporaryFolder(name: "folder")
        defer { try? FileManager.default.removeItem(at: folderURL.deletingLastPathComponent()) }
        let folder = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: folderURL.dataRepresentation)]
        )

        repository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 80)
        repository.save(id: PasteboardHistory.ID(rawValue: urlContent.hash), content: urlContent, updateAt: 70)
        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 60)
        repository.save(id: PasteboardHistory.ID(rawValue: pdf.hash), content: pdf, updateAt: 50)
        repository.save(id: PasteboardHistory.ID(rawValue: rtf.hash), content: rtf, updateAt: 40)
        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 30)
        repository.save(id: PasteboardHistory.ID(rawValue: tooLarge.hash), content: tooLarge, updateAt: 20)
        repository.save(id: PasteboardHistory.ID(rawValue: folder.hash), content: folder, updateAt: 10)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 12
        )

        #expect(snapshot.histories.map(\.historyID) == [
            image.hash,
            pdf.hash,
            rtf.hash
        ])
        #expect(snapshot.assetCount == 3)
        #expect(snapshot.skippedAssetCount == 1)
        #expect(snapshot.histories.flatMap(\.assets).map(\.pasteboardType) == [.png, .pdf, .rtf])
    }

    @Test
    func fileSyncSnapshotIncludesOnlySelectedFileTypes() throws {
        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))]
        )
        let pdf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data("%PDF-1.7".utf8))]
        )
        let rtf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 file}".utf8))]
        )
        let fileURL = try writeTemporaryFile(name: "report.txt", data: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let file = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )
        let tooLarge = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data(repeating: 1, count: 13))]
        )

        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 50)
        repository.save(id: PasteboardHistory.ID(rawValue: pdf.hash), content: pdf, updateAt: 40)
        repository.save(id: PasteboardHistory.ID(rawValue: rtf.hash), content: rtf, updateAt: 30)
        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 20)
        repository.save(id: PasteboardHistory.ID(rawValue: tooLarge.hash), content: tooLarge, updateAt: 10)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 12,
            includedFileTypes: [.pdf]
        )

        #expect(snapshot.histories.map(\.historyID) == [pdf.hash])
        #expect(snapshot.assetCount == 1)
        #expect(snapshot.skippedAssetCount == 1)
        #expect(snapshot.histories.flatMap(\.assets).map(\.pasteboardType) == [.pdf])
    }

    @Test
    func fileSyncSnapshotIgnoresFinderFilesEvenWhenLegacyPreferenceContainsFilenames() throws {
        let fileURL = try writeTemporaryFile(name: "report.txt", data: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let file = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )

        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 20)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 25 * 1024 * 1024,
            includedFileTypes: [.filenames]
        )

        #expect(snapshot.histories.isEmpty)
        #expect(snapshot.assetCount == 0)
        #expect(snapshot.skippedAssetCount == 0)
    }

    @Test
    func fileSyncSnapshotKeepsMultiAssetHistoriesWholeWhenLimitWouldBeExceeded() throws {
        let newest = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .pdf, data: Data("a".utf8)),
                PasteboardContent.Asset(type: .pdf, data: Data("b".utf8))
            ]
        )
        let older = PasteboardContent(
            assets: (0..<9).map { index in
                PasteboardContent.Asset(type: .pdf, data: Data("older-\(index)".utf8))
            }
        )

        repository.save(id: PasteboardHistory.ID(rawValue: newest.hash), content: newest, updateAt: 2)
        repository.save(id: PasteboardHistory.ID(rawValue: older.hash), content: older, updateAt: 1)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 25 * 1024 * 1024
        )

        #expect(snapshot.histories.map(\.historyID) == [newest.hash])
        #expect(snapshot.assetCount == 2)
        #expect(snapshot.skippedAssetCount == 9)
    }

    @Test
    func fileSyncImportRestoresBinaryAssetsAndRejectsFinderFiles() throws {
        let binaryPayload = FileSyncHistoryPayload(
            deviceID: "remote-device",
            historyID: "remote-pdf",
            updatedAt: 20,
            assets: [
                FileSyncAssetPayload(
                    assetIndex: 0,
                    pasteboardType: .pdf,
                    data: Data("%PDF".utf8),
                    originalFilename: nil
                )
            ]
        )
        let finderPayload = FileSyncHistoryPayload(
            deviceID: "remote-device",
            historyID: "remote-file",
            updatedAt: 30,
            assets: [
                FileSyncAssetPayload(
                    assetIndex: 0,
                    pasteboardType: .fileURL,
                    data: Data("cached bytes".utf8),
                    originalFilename: "remote.txt"
                )
            ]
        )

        #expect(repository.upsertFileSyncHistory(binaryPayload))
        #expect(!repository.upsertFileSyncHistory(finderPayload))

        let pdfContent = try #require(repository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-pdf")))
        #expect(pdfContent.assets == [
            PasteboardContent.Asset(type: .pdf, data: Data("%PDF".utf8))
        ])
        #expect(repository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-file")) == nil)
    }

    @Test
    func syncPayloadsExportNewestCurrentDeviceTextAndURLWindowOnly() throws {
        let current = PasteboardContent("Current")
        let old = PasteboardContent("Old")
        let remote = PasteboardContent("Remote")
        let webURL = try #require(URL(string: "https://e.co"))
        let urlContent = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .URL, data: webURL.dataRepresentation)]
        )
        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .tiff, data: Data(repeating: 1, count: 8))]
        )
        let file = PasteboardContent(
            assets: [
                PasteboardContent.Asset(
                    type: .fileURL,
                    data: URL(fileURLWithPath: "/tmp/pastera.txt").dataRepresentation
                )
            ]
        )
        let rtf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 Remote}".utf8))]
        )
        let html = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .html, data: Data("<strong>Remote</strong>".utf8))]
        )
        let large = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .string, data: Data(String(repeating: "A", count: 17).utf8))]
        )
        let currentID = PasteboardHistory.ID(rawValue: current.hash)
        let oldID = PasteboardHistory.ID(rawValue: old.hash)
        let remoteID = PasteboardHistory.ID(rawValue: remote.hash)
        let urlID = PasteboardHistory.ID(rawValue: urlContent.hash)

        repository.save(id: currentID, content: current, updateAt: 10)
        repository.save(id: oldID, content: old, updateAt: 4)
        try repository.upsertSyncPayload(PasteboardHistorySyncPayload(
            id: remoteID.rawValue,
            text: "Remote",
            updateAt: 12,
            deviceID: "remote-device",
            sourceKind: .plainText
        ))
        repository.save(id: urlID, content: urlContent, updateAt: 12)
        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 16)
        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 15)
        repository.save(id: PasteboardHistory.ID(rawValue: rtf.hash), content: rtf, updateAt: 14)
        repository.save(id: PasteboardHistory.ID(rawValue: html.hash), content: html, updateAt: 13)
        repository.save(id: PasteboardHistory.ID(rawValue: large.hash), content: large, updateAt: 13)

        let payloads = repository.fetchSyncPayloads(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 3,
            maxTextBytes: 16,
            snapshotTextBudgetBytes: 128
        )

        #expect(payloads.map(\.id) == [urlID.rawValue, currentID.rawValue, oldID.rawValue])
        #expect(payloads.map(\.sourceKind) == [.url, .plainText, .plainText])
        #expect(payloads.first?.text == "https://e.co")
        #expect(payloads.first?.deviceID == CPYUtilities.deviceID)
    }

    @Test
    func syncPayloadExportStopsAtSnapshotTextBudget() throws {
        let newest = PasteboardContent("First")
        let older = PasteboardContent("Second")
        let newestID = PasteboardHistory.ID(rawValue: newest.hash)
        repository.save(id: newestID, content: newest, updateAt: 2)
        repository.save(id: PasteboardHistory.ID(rawValue: older.hash), content: older, updateAt: 1)

        let payloads = repository.fetchSyncPayloads(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 6
        )

        #expect(payloads.map(\.id) == [newestID.rawValue])
    }

    @Test(.timeLimit(.minutes(1)))
    func observeTextSyncCandidateChangesIgnoresRemoteAndNonTextHistories() async throws {
        var changeCount = 0
        let cancellable = repository
            .observeTextSyncCandidateChanges(currentDeviceID: CPYUtilities.deviceID)
            .sink {
                changeCount += 1
            }
        defer { _ = cancellable }

        try await waitUntil { changeCount >= 1 }

        try repository.upsertSyncPayload(PasteboardHistorySyncPayload(
            id: "remote-history",
            text: "Remote",
            updateAt: 10,
            deviceID: "remote-device",
            sourceKind: .plainText
        ))
        try await Task.sleep(for: .seconds(0.05))
        #expect(changeCount == 1)

        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))]
        )
        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 11)
        try await Task.sleep(for: .seconds(0.05))
        #expect(changeCount == 1)

        let text = PasteboardContent("Local text")
        repository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 12)
        try await waitUntil { changeCount >= 2 }
    }

    @Test
    func syncImportDoesNotReuploadRemoteHistoryAndLocalSuppressionPreventsReimport() throws {
        let id = PasteboardHistory.ID(rawValue: "remote-history")
        let payload = PasteboardHistorySyncPayload(
            id: id.rawValue,
            text: "Remote history",
            updateAt: 20,
            deviceID: "remote-device",
            sourceKind: .plainText
        )

        try repository.upsertSyncPayload(payload)
        #expect(repository.fetchHistory(id: id)?.deviceID == "remote-device")
        #expect(repository.fetchSyncPayloads(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 8 * 1024 * 1024
        ).isEmpty)

        repository.deleteHistory(id: id)
        try repository.upsertSyncPayload(payload)

        #expect(repository.fetchHistory(id: id) == nil)
    }

    @Test
    func syncImportUsesLastWriteWinsAndReportsActualHistoryWrites() throws {
        let id = PasteboardHistory.ID(rawValue: "shared-history")
        let localContent = PasteboardContent("Local newer")
        repository.save(id: id, content: localContent, updateAt: 30)

        let olderRemote = PasteboardHistorySyncPayload(
            id: id.rawValue,
            text: "Remote older",
            updateAt: 20,
            deviceID: "remote-device",
            sourceKind: .plainText
        )
        let newerRemote = PasteboardHistorySyncPayload(
            id: id.rawValue,
            text: "Remote newer",
            updateAt: 40,
            deviceID: "remote-device",
            sourceKind: .url
        )

        #expect(try repository.upsertSyncPayload(olderRemote) == false)
        #expect(repository.fetchHistory(id: id)?.title == "Local newer")
        #expect(repository.fetchContent(id: id) == localContent)

        #expect(try repository.upsertSyncPayload(newerRemote) == true)
        #expect(repository.fetchHistory(id: id)?.title == "Remote newer")
        #expect(repository.fetchContent(id: id) == PasteboardContent("Remote newer"))
        #expect(repository.fetchHistory(id: id)?.pasteboardTypes == [.string])
        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1)
                .first?
                .thumbnailAsset == nil
        )
    }
}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistoryThumbnailByteLimitTests {
    let repository: PasteboardHistoryRepository

    init() {
        self.repository = PasteboardHistoryRepository()
    }

    @Test
    func saveImageThumbnailDoesNotExceedSourceImageBytes() throws {
        let pngData = try makeRepositoryCompactGradientPNGData(width: 900, height: 520)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .png, data: pngData)
            ]
        )
        let id = PasteboardHistory.ID(rawValue: content.hash)

        repository.save(id: id, content: content, updateAt: 1)

        let thumbnail = try #require(repository
            .fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1)
            .first?
            .thumbnailAsset)

        #expect(thumbnail.kind == .image)
        #expect(thumbnail.data.count <= pngData.count)
        #expect(thumbnail.data.count <= Constants.Thumbnail.maxEncodedBytes)
    }

    @Test
    func compactOversizedThumbnailAssetsShrinksThumbnailsThatExceedSourceImageBytes() throws {
        let pngData = try makeRepositoryCompactGradientPNGData(width: 900, height: 520)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .png, data: pngData)
            ]
        )
        let id = PasteboardHistory.ID(rawValue: content.hash)
        repository.save(id: id, content: content, updateAt: 1)
        let inflatedThumbnailData = try #require(content.thumbnailImage.flatMap(PasteraImageEncoding.pngData(from:)))
        #expect(inflatedThumbnailData.count > pngData.count)
        #expect(inflatedThumbnailData.count < Constants.Thumbnail.maxEncodedBytes)

        @Dependency(\.defaultDatabase) var database
        try database.write { database in
            try PasteboardHistoryThumbnailAsset.upsert {
                PasteboardHistoryThumbnailAsset(
                    pasteboardHistoryID: id,
                    kind: .image,
                    data: inflatedThumbnailData
                )
            }
            .execute(database)
        }

        let rebuiltCount = repository.compactOversizedThumbnailAssets(maxBytes: Constants.Thumbnail.maxEncodedBytes)
        let thumbnail = try #require(repository
            .fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1)
            .first?
            .thumbnailAsset)

        #expect(rebuiltCount == 1)
        #expect(thumbnail.kind == .image)
        #expect(thumbnail.data.count <= pngData.count)
    }
}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistoryFilePreviewTests {
    let repository: PasteboardHistoryRepository

    init() {
        self.repository = PasteboardHistoryRepository()
    }

    @Test
    func fileURLHistoryStoresDocumentPreviewTitleAndKeepsOriginalFileURLAsset() throws {
        let fileURL = try writeTemporaryFile(name: "notes.md", data: Data("Hello searchable file".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let content = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )
        let id = PasteboardHistory.ID(rawValue: content.hash)

        repository.save(id: id, content: content, updateAt: 2)

        let history = try #require(repository.fetchHistory(id: id))
        #expect(history.title == "notes.md\nHello searchable file")
        #expect(repository.fetchContent(id: id)?.assets == content.assets)

        let searchResults = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "searchable", mode: .plain),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )
        #expect(searchResults.map(\.history.id).contains(id))
    }

    @Test
    func fileURLHistoryStoresFileNameForFinderFileCategories() throws {
        let cases: [(name: String, data: Data)] = [
            ("backup.zip", Data([0x50, 0x4B, 0x03, 0x04])),
            ("main.swift", Data("let value = 1".utf8)),
            ("report.docx", Data([0x50, 0x4B, 0x03, 0x04])),
            ("payload.unknown", Data([0x01, 0x02, 0x03, 0x04]))
        ]
        let urls = try cases.map { try writeTemporaryFile(name: $0.name, data: $0.data) }
        defer {
            urls.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) }
        }

        for (index, url) in urls.enumerated() {
            let content = PasteboardContent(
                assets: [PasteboardContent.Asset(type: .fileURL, data: url.dataRepresentation)]
            )
            let id = PasteboardHistory.ID(rawValue: "\(content.hash)-\(index)")

            repository.save(id: id, content: content, updateAt: index + 10)

            let history = try #require(repository.fetchHistory(id: id))
            #expect(history.title.components(separatedBy: .newlines).first == cases[index].name)
        }
    }

    @Test
    func fileURLHistoryCreatesThumbnailForImageFilesWithoutImportingFileContent() throws {
        let image = NSImage.create(with: .orange, size: NSSize(width: 24, height: 16))
        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let imageData = try #require(bitmap.representation(using: .png, properties: [:]))
        let fileURL = try writeTemporaryFile(name: "capture.customimage", data: imageData)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let content = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )
        let id = PasteboardHistory.ID(rawValue: content.hash)

        repository.save(id: id, content: content, updateAt: 3)

        let detail = try #require(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 10)
                .first { $0.history.id == id }
        )
        #expect(detail.history.title == "capture.customimage")
        #expect(detail.thumbnailAsset?.kind == .image)
        #expect(repository.fetchContent(id: id)?.assets == content.assets)
    }
}

private final class RecordingPasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
    private(set) var savedContents = [PasteboardContent]()
    private(set) var savedIDs = [PasteboardHistory.ID]()
    var ocrCandidateIDs = [PasteboardHistory.ID]()
    var contentsByID = [PasteboardHistory.ID: PasteboardContent]()
    private(set) var fetchedContentIDs = [PasteboardHistory.ID]()
    private(set) var ocrCandidateQueryCount = 0
    private var ocrJobs = [(id: PasteboardHistory.ID, priority: Int, enqueuedAt: Int)]()

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { false }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail] {
        []
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        []
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { nil }

    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? {
        fetchedContentIDs.append(id)
        return contentsByID[id]
    }

    func fetchOCRIndexingCandidateIDs(limit: Int) -> [PasteboardHistory.ID] {
        ocrCandidateQueryCount += 1
        return Array(ocrCandidateIDs.prefix(max(0, limit)))
    }

    func enqueueOCRJob(historyID: PasteboardHistory.ID, priority: Int, enqueuedAt: Int) {
        ocrJobs.removeAll { $0.id == historyID }
        ocrJobs.append((historyID, priority, enqueuedAt))
    }

    func fetchNextOCRJobID() -> PasteboardHistory.ID? {
        ocrJobs.sorted {
            $0.priority == $1.priority ? $0.enqueuedAt > $1.enqueuedAt : $0.priority > $1.priority
        }.first?.id
    }

    func deleteOCRJob(historyID: PasteboardHistory.ID) {
        ocrJobs.removeAll { $0.id == historyID }
    }

    func countOCRJobs() -> Int { ocrJobs.count }

    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {
        savedIDs.append(id)
        savedContents.append(content)
    }

    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private final class InterleavingCaptureHistoryRepository: PasteboardHistoryRepositoryProtocol {
    private let repository: PasteboardHistoryRepository
    private let afterMatching: () throws -> Void
    private(set) var interleavingError: Error?

    init(repository: PasteboardHistoryRepository, afterMatching: @escaping () throws -> Void) {
        self.repository = repository
        self.afterMatching = afterMatching
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> { repository.observeHistories() }
    func hasHistories() -> Bool { repository.hasHistories() }
    func fetchHistoryDetails(
        ascending: Bool, includesThumbnailAsset: Bool, limit: Int, offset: Int
    ) -> [PasteboardHistoryDetail] {
        repository.fetchHistoryDetails(
            ascending: ascending, includesThumbnailAsset: includesThumbnailAsset, limit: limit, offset: offset
        )
    }
    func searchHistoryDetails(
        query: HistorySearchQuery, includesThumbnailAsset: Bool, limit: Int, offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        try repository.searchHistoryDetails(
            query: query, includesThumbnailAsset: includesThumbnailAsset, limit: limit, offset: offset
        )
    }
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { repository.fetchHistory(id: id) }
    func fetchHistory(matching content: PasteboardContent) -> PasteboardHistory? {
        let history = repository.fetchHistory(matching: content)
        do {
            try afterMatching()
        } catch {
            interleavingError = error
        }
        return history
    }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { repository.fetchContent(id: id) }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {
        repository.save(id: id, content: content, updateAt: updateAt)
    }
    func saveCapturedHistory(
        preferredID: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int
    ) -> PasteboardHistory.ID? {
        repository.saveCapturedHistory(preferredID: preferredID, content: content, updateAt: updateAt)
    }
    func deleteHistory(id: PasteboardHistory.ID) { repository.deleteHistory(id: id) }
    func deleteAll() { repository.deleteAll() }
    func deleteOverflowingHistories(maxHistorySize: Int) {
        repository.deleteOverflowingHistories(maxHistorySize: maxHistorySize)
    }
    func pruneHistories(settings: HistoryRetentionSettings) { repository.pruneHistories(settings: settings) }
}

private final class ControlledOCRScheduler {
    private(set) var pending = [() -> Void]()

    func schedule(_ work: @escaping () -> Void) {
        pending.append(work)
    }

    func runNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }

    func runAll() {
        while !pending.isEmpty {
            runNext()
        }
    }
}

private final class RecordingOCRIndexer: PasteboardHistoryOCRIndexing {
    private(set) var enqueuedHistoryIDs = [PasteboardHistory.ID]()
    private(set) var backfillLimits = [Int]()

    func enqueueIndexing(historyID: PasteboardHistory.ID) {
        enqueuedHistoryIDs.append(historyID)
    }

    func backfillMissingImageOCR(limit: Int) {
        backfillLimits.append(limit)
    }
}

private final class FakeImageTextRecognizer: PasteboardImageTextRecognizing {
    enum Failure: Error {
        case failed
    }

    private let result: String
    private let error: Error?
    private(set) var recognizedImageDataCount = 0

    init(result: String = "", error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func recognizeText(in imageData: Data) throws -> String {
        recognizedImageDataCount += 1
        if let error {
            throw error
        }
        return result
    }
}

private extension PasteboardContent {
    init(_ string: String) {
        self.init(
            assets: [
                PasteboardContent.Asset(type: .string, data: string.data(using: .utf8)!)
            ]
        )
    }
}

private func restore(_ value: Any?, forKey key: String, defaults: UserDefaults) {
    if let value {
        defaults.set(value, forKey: key)
    } else {
        defaults.removeObject(forKey: key)
    }
}

private func writeTemporaryFile(name: String, data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

private func writeTemporaryFolder(name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let folderURL = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    return folderURL
}

private func makeRepositoryNoisyImage(width: Int, height: Int) throws -> NSImage {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let bitmapData = try #require(bitmap.bitmapData)
    for row in 0..<height {
        for column in 0..<width {
            let index = row * bitmap.bytesPerRow + column * 4
            bitmapData[index] = UInt8((column * 37 + row * 17) % 256)
            bitmapData[index + 1] = UInt8((column * 11 + row * 53) % 256)
            bitmapData[index + 2] = UInt8((column * 23 + row * 29) % 256)
            bitmapData[index + 3] = 255
        }
    }
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
}

private func makeRepositoryCompactGradientPNGData(width: Int, height: Int) throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ))
    let bitmapData = try #require(bitmap.bitmapData)
    for row in 0..<height {
        for column in 0..<width {
            let index = row * bitmap.bytesPerRow + column * 4
            bitmapData[index + 0] = UInt8(column % 256)
            bitmapData[index + 1] = UInt8((row * 2) % 256)
            bitmapData[index + 2] = UInt8((column ^ row) % 256)
            bitmapData[index + 3] = 255
        }
    }
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

private func makeRepositoryScreenshotLikeImage(width: Int, height: Int) throws -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.17, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1)
    ]
    for row in 0..<16 {
        let text = "Pastera thumbnail preview line \(row) - 411 tests in 47 suites passed"
        text.draw(at: NSPoint(x: 36, y: height - 70 - row * 44), withAttributes: attributes)
    }
    return image
}

private func makeTabEvent(shift: Bool = false) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: shift ? [.shift] : [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\t",
        charactersIgnoringModifiers: "\t",
        isARepeat: false,
        keyCode: 48
    ))
}

private func makeMouseEnteredEvent(windowNumber: Int = 0) throws -> NSEvent {
    try #require(NSEvent.enterExitEvent(
        with: .mouseEntered,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        eventNumber: 0,
        trackingNumber: 0,
        userData: nil
    ))
}

private func makeMouseMovedEvent(windowNumber: Int = 0) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
        with: .mouseMoved,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 0,
        pressure: 0
    ))
}

private func firstResponder(in window: NSWindow, belongsTo view: NSView) -> Bool {
    if window.firstResponder === view {
        return true
    }
    if let control = view as? NSControl,
       control.currentEditor() === window.firstResponder {
        return true
    }
    guard let responderView = window.firstResponder as? NSView else {
        return false
    }
    return responderView === view || responderView.isDescendant(of: view)
}

private func focusedRowAlpha(_ row: HistoryMenuRowView) -> CGFloat? {
    row.layer?.backgroundColor?.alpha
}

@MainActor
private func makeHistoryMenuTestWindow(width: CGFloat, height: CGFloat) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    return window
}

@MainActor
private func closeHistoryMenuTestWindow(_ window: NSWindow) {
    window.makeFirstResponder(nil)
    let retainedContentView = window.contentView
    window.contentView = nil
    window.orderOut(nil)
    HistoryMenuTestWindowRetainer.retain(window: window, contentView: retainedContentView)
}

private enum HistoryMenuTestWindowRetainer {
    private static var windows = [NSWindow]()
    private static var contentViews = [NSView]()

    static func retain(window: NSWindow, contentView: NSView?) {
        windows.append(window)
        if let contentView { contentViews.append(contentView) }
    }
}

struct HistoryMenuPaginationStateTests {
    @Test
    func queryChangeResetsPageAndNavigationStaysBounded() {
        var state = HistoryMenuPaginationState(pageSize: 10)

        state.goToNextPage(if: true)
        state.goToNextPage(if: true)
        #expect(state.pageIndex == 2)
        #expect(state.offset == 20)

        state.updateQuery("  keyword  ")
        #expect(state.query == "keyword")
        #expect(state.pageIndex == 0)
        #expect(state.offset == 0)

        state.goToPreviousPage()
        #expect(state.pageIndex == 0)

        state.goToNextPage(if: false)
        #expect(state.pageIndex == 0)
    }

    @Test
    func filterChangesResetPageAndExposeQueryOptions() {
        var state = HistoryMenuPaginationState(pageSize: 10)
        state.goToNextPage(if: true)
        state.goToNextPage(if: true)

        state.updateMode(.regex)
        #expect(state.mode == .regex)
        #expect(state.pageIndex == 0)

        state.goToNextPage(if: true)
        state.updateCaseSensitive(true)
        #expect(state.caseSensitive)
        #expect(state.pageIndex == 0)

        state.goToNextPage(if: true)
        state.updateTypeFilter(.images)
        #expect(state.typeFilter == .images)
        #expect(state.selectedTypes == NSPasteboard.PasteboardType.clipyImageTypes)
        #expect(state.selectedFileCategories.isEmpty)
        #expect(state.pageIndex == 0)

        state.goToNextPage(if: true)
        state.updateTypeFilter(.code)
        #expect(state.typeFilter == .code)
        #expect(state.selectedTypes == [.fileURL])
        #expect(state.selectedFileCategories == [.code])
        #expect(state.pageIndex == 0)
    }

    @Test
    func typeFiltersMatchHistorySearchWindowSemantics() {
        #expect(HistoryMenuTypeFilter.all.pasteboardTypes.isEmpty)
        #expect(HistoryMenuTypeFilter.text.pasteboardTypes == [.string, .deprecatedString])
        #expect(HistoryMenuTypeFilter.images.pasteboardTypes == NSPasteboard.PasteboardType.clipyImageTypes)
        #expect(HistoryMenuTypeFilter.documents.pasteboardTypes == [.fileURL])
        #expect(HistoryMenuTypeFilter.archives.pasteboardTypes == [.fileURL])
        #expect(HistoryMenuTypeFilter.code.pasteboardTypes == [.fileURL])
        #expect(HistoryMenuTypeFilter.otherFiles.pasteboardTypes == [.fileURL])
        #expect(HistoryMenuTypeFilter.documents.fileCategories == [.document])
        #expect(HistoryMenuTypeFilter.archives.fileCategories == [.archive])
        #expect(HistoryMenuTypeFilter.code.fileCategories == [.code])
        #expect(HistoryMenuTypeFilter.otherFiles.fileCategories == [.other])
        #expect(HistoryMenuTypeFilter.pdf.pasteboardTypes == [.pdf, .deprecatedPDF])
    }
}

@Suite(.serialized)
struct HistoryMenuHeaderViewTests {
    @Test @MainActor
    func headerUsesReadableTwoRowLayoutAndKeyViewLoop() throws {
        let headerView = HistoryMenuHeaderView()
        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let controls = headerView.subviews.compactMap { $0 as? NSControl }
        let tabChainControls = controls.filter { control in
            guard let segmentedControl = control as? NSSegmentedControl else { return control.isEnabled }
            return control.isEnabled && segmentedControl.segmentCount > 1
        }

        #expect(headerView.frame.height == 64)
        #expect(controls.count >= 5)
        #expect(searchField.nextKeyView != nil)
        #expect(tabChainControls.allSatisfy { $0.nextKeyView != nil })
    }

    @Test @MainActor
    func headerShowsFinderFileCategoryFiltersInsteadOfSingleFileFilter() throws {
        let headerView = HistoryMenuHeaderView()
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )
        let labels = (0..<typeControl.segmentCount).map { typeControl.label(forSegment: $0) ?? "" }

        #expect(labels.contains("Doc"))
        #expect(labels.contains("Zip"))
        #expect(labels.contains("Code"))
        #expect(labels.contains("Other"))
        #expect(!labels.contains("File"))
    }

    @Test @MainActor
    func headerFocusesSearchFieldWhenPresented() async throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 80)
        let headerView = HistoryMenuHeaderView()
        window.contentView = headerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        try await Task.sleep(nanoseconds: 50_000_000)

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        #expect(searchField.currentEditor() != nil)
    }

    @Test @MainActor
    func headerCanExtendTabOrderIntoHistoryRows() {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}

        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])

        #expect(headerView.lastHeaderFocusableView.nextKeyView === firstRow)
        #expect(firstRow.nextKeyView === secondRow)
        #expect(secondRow.nextKeyView === headerView.firstHeaderFocusableView)
    }

    @Test @MainActor
    func headerTabOrderStartsAtRowsThenVisitsPageSearchOptionsAndLoopsBackToRows() throws {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}

        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 1), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let pageButtons = headerView.subviews.compactMap { $0 as? NSButton }
        let previousButton = try #require(pageButtons.first)
        let nextButton = try #require(pageButtons.dropFirst().first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )

        #expect(firstRow.nextKeyView === secondRow)
        #expect(secondRow.nextKeyView === nextButton)
        #expect(nextButton.nextKeyView === previousButton)
        #expect(previousButton.nextKeyView === searchField)
        #expect(searchField.nextKeyView === typeControl)
        #expect(typeControl.nextKeyView === firstRow)
    }

    @Test @MainActor
    func headerTabOrderSkipsDisabledPreviousPageButton() throws {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}

        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let pageButtons = headerView.subviews.compactMap { $0 as? NSButton }
        let previousButton = try #require(pageButtons.first)
        let nextButton = try #require(pageButtons.dropFirst().first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )

        #expect(!previousButton.isEnabled)
        #expect(nextButton.isEnabled)
        #expect(firstRow.nextKeyView === nextButton)
        #expect(nextButton.nextKeyView === searchField)
        #expect(searchField.nextKeyView === typeControl)
    }

    @Test @MainActor
    func headerTabOrderLoopsFromLastTypeSegmentToFirstRow() throws {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}

        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 3), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])

        let segmentedControls = headerView.subviews.compactMap { $0 as? NSSegmentedControl }
        let typeControl = try #require(segmentedControls.first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count })

        #expect(typeControl.nextKeyView === firstRow)
    }

    @Test @MainActor
    func headerFocusesFirstHistoryRowWhenPresented() async throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.frame.origin = NSPoint(x: 0, y: 60)
        firstRow.frame.origin = NSPoint(x: 0, y: 20)
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(window.firstResponder === firstRow)
    }

    @Test @MainActor
    func pendingInitialFocusDoesNotStealSearchFieldFocus() async throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.frame.origin = NSPoint(x: 0, y: 60)
        firstRow.frame.origin = NSPoint(x: 0, y: 20)
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(searchField)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(firstResponder(in: window, belongsTo: searchField))
        #expect(focusedRowAlpha(firstRow) == 0)
    }

    @Test @MainActor
    func headerControlsAdvanceFocusWithTabKeyInsideMenuViews() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 1), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )
        let tabEvent = try makeTabEvent()

        window.makeFirstResponder(searchField)
        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: typeControl))

        for _ in 1..<typeControl.segmentCount {
            #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
            #expect(firstResponder(in: window, belongsTo: typeControl))
        }

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: firstRow))
    }

    @Test @MainActor
    func tabFallsBackToLogicalFocusWhenMenuWindowOwnsFirstResponder() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(containerView)

        #expect(headerView.handleTabKeyFromCurrentResponder(try makeTabEvent()))
        #expect(firstResponder(in: window, belongsTo: searchField))
    }

    @Test @MainActor
    func tabUsesHoveredHistoryRowWhenMenuWindowOwnsFirstResponder() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 170)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let lastRow = HistoryMenuRowView(title: "0. Last", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow, lastRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        containerView.addSubview(lastRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(containerView)
        lastRow.mouseEntered(with: try makeMouseEnteredEvent(windowNumber: window.windowNumber))

        #expect(headerView.handleTabKeyFromCurrentResponder(try makeTabEvent()))
        #expect(firstResponder(in: window, belongsTo: searchField))
    }

    @Test @MainActor
    func hoveringSearchFieldDoesNotStealFocusedHistoryRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(firstRow)

        searchField.mouseEntered(with: try makeMouseEnteredEvent(windowNumber: window.windowNumber))

        #expect(!firstResponder(in: window, belongsTo: searchField))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(focusedRowAlpha(firstRow) == 0.9)
    }

    @Test @MainActor
    func hoveringHeaderBackgroundDoesNotStealFocusedHistoryRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(firstRow)

        headerView.mouseEntered(with: try makeMouseEnteredEvent(windowNumber: window.windowNumber))

        #expect(!firstResponder(in: window, belongsTo: searchField))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(focusedRowAlpha(firstRow) == 0.9)
    }

    @Test @MainActor
    func movingInsideSearchFieldDoesNotStealFocusedHistoryRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(firstRow)

        searchField.mouseMoved(with: try makeMouseMovedEvent(windowNumber: window.windowNumber))

        #expect(!firstResponder(in: window, belongsTo: searchField))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(focusedRowAlpha(firstRow) == 0.9)
    }

    @Test @MainActor
    func tabMovesBetweenRowsWithoutLeavingPreviousRowsSelected() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 110)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 110))
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}
        firstRow.frame.origin = NSPoint(x: 0, y: 40)
        secondRow.frame.origin = NSPoint(x: 0, y: 5)
        firstRow.nextKeyView = secondRow
        containerView.addSubview(firstRow)
        containerView.addSubview(secondRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        window.makeFirstResponder(firstRow)
        #expect(focusedRowAlpha(firstRow) == 0.9)

        window.makeFirstResponder(secondRow)

        #expect(focusedRowAlpha(firstRow) == 0)
        #expect(focusedRowAlpha(secondRow) == 0.9)
    }

    @Test @MainActor
    func tabCyclesFromLastRowToSearchOptionsAndBackToFirstRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 170)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}
        headerView.frame.origin = NSPoint(x: 0, y: 90)
        firstRow.frame.origin = NSPoint(x: 0, y: 55)
        secondRow.frame.origin = NSPoint(x: 0, y: 20)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 1), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        containerView.addSubview(secondRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let pageButtons = headerView.subviews.compactMap { $0 as? NSButton }
        let previousButton = try #require(pageButtons.first)
        let nextButton = try #require(pageButtons.dropFirst().first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )
        let tabEvent = try makeTabEvent()

        window.makeFirstResponder(firstRow)
        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: secondRow))
        #expect(focusedRowAlpha(firstRow) == 0)
        #expect(focusedRowAlpha(secondRow) == 0.9)

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: nextButton))
        #expect(focusedRowAlpha(secondRow) == 0)

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: previousButton))

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: searchField))

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: typeControl))
        let selectedTypeSegment = typeControl.selectedSegment

        for _ in 1..<typeControl.segmentCount {
            #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
            #expect(firstResponder(in: window, belongsTo: typeControl))
            #expect(typeControl.selectedSegment == selectedTypeSegment)
        }

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(typeControl.selectedSegment == selectedTypeSegment)
    }

    @Test @MainActor
    func historyRowConfirmsWithReturnKey() throws {
        var didConfirm = false
        let row = HistoryMenuRowView(title: "1. Confirm", image: nil) {
            didConfirm = true
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))

        row.keyDown(with: event)

        #expect(didConfirm)
    }

    @Test @MainActor
    func historyRowUsesUnifiedImagePreviewSlot() throws {
        let image = NSImage(size: NSSize(width: 320, height: 180))
        let row = HistoryMenuRowView(title: "1. Screenshot", image: image) {}

        row.layoutSubtreeIfNeeded()

        let imageView = try #require(row.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(row.frame.height == 52)
        #expect(imageView.frame.width == 56)
        #expect(imageView.frame.height == 36)
    }

    @Test @MainActor
    func historyRowWithoutImageUsesReadableHeight() {
        let row = HistoryMenuRowView(title: "1. Text", image: nil) {}

        #expect(row.frame.height == 36)
    }

    @Test @MainActor
    func imagePreviewPanelUsesNonActivatingPreviewWindow() throws {
        let controller = HistoryMenuImagePreviewController()
        let image = NSImage(size: NSSize(width: 640, height: 360))

        controller.show(image: image, relativeTo: NSRect(x: 40, y: 40, width: 48, height: 30), in: nil)

        let panel = try #require(controller.panel)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .popUpMenu)
        #expect(panel.contentView?.frame.size == NSSize(width: 370, height: 248))
        controller.hide()
    }

}

@Suite(.serialized)
struct HistoryMenuTextPreviewTests {
    @Test @MainActor
    func textPreviewPanelUsesCompactReadableSize() throws {
        let controller = HistoryMenuTextPreviewController()

        controller.show(
            text: "A compact preview should feel attached to the hovered row.",
            relativeTo: NSRect(x: 40, y: 40, width: 120, height: 25),
            in: nil
        )

        let panel = try #require(controller.panel)
        #expect(panel.contentView?.frame.size == NSSize(width: 298, height: 112))
        controller.hide()
    }

    @Test @MainActor
    func historyRowRequestsTextPreviewAfterStableHoverDelay() throws {
        let previewText = "A longer clipboard history entry that has been shortened in the row but should be readable on hover."
        let row = HistoryMenuRowView(
            title: "A longer clipboard history...",
            image: nil,
            previewText: previewText
        ) {}
        let window = makeHistoryMenuTestWindow(width: 352, height: 40)
        window.contentView = row
        window.orderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        var observedPreview = false
        HistoryMenuRowView.scheduleTextPreviewWorkItemsForTesting { workItem in
            workItem.perform()
        }
        HistoryMenuRowView.observeTextPreviewRequestsForTesting { text in
            if text == previewText {
                observedPreview = true
            }
        }
        defer {
            HistoryMenuRowView.scheduleTextPreviewWorkItemsForTesting(nil)
            HistoryMenuRowView.observeTextPreviewRequestsForTesting(nil)
        }

        row.mouseEntered(with: try makeMouseEnteredEvent())

        #expect(observedPreview)

        row.mouseExited(with: try makeMouseEnteredEvent())

        #expect(!HistoryMenuRowView.isTextPreviewVisibleForTesting)
    }

    @Test @MainActor
    func historyRowCancelsTextPreviewWhenHoverEndsBeforeDelay() async throws {
        let row = HistoryMenuRowView(
            title: "Shortened...",
            image: nil,
            previewText: "Full text should not appear after the pointer leaves."
        ) {}
        let window = makeHistoryMenuTestWindow(width: 352, height: 40)
        window.contentView = row
        window.orderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        row.mouseEntered(with: try makeMouseEnteredEvent())
        try await Task.sleep(for: .seconds(0.2))
        row.mouseExited(with: try makeMouseEnteredEvent())
        try await Task.sleep(for: .seconds(0.4))

        #expect(!HistoryMenuRowView.isTextPreviewVisibleForTesting)
    }

}

private extension PasteboardHistory {
    init(id: PasteboardHistory.ID, title: String, updateAt: Int) {
        self.init(
            id: id,
            title: title,
            pasteboardTypes: [.string],
            updateAt: updateAt,
            deviceID: CPYUtilities.deviceID
        )
    }
}

private func waitUntil(condition: @escaping @MainActor () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: .seconds(0.01))
    }
    Issue.record("Timed out waiting for condition.")
}

// MARK: - Non-destructive history display grouping

@MainActor
@Suite(.dependencies {
    try $0.bootstrapDatabase()
})
struct HistoryDisplayGroupingTests {
    let repository = PasteboardHistoryRepository()

    @Test(arguments: ["", "same"])
    func equivalentPlainAndRichTextDisplayOnceWithoutChangingStoredAssets(searchText: String) throws {
        let plain = [PasteboardContent.Asset(type: .string, data: Data("same text".utf8))]
        let rich = plain + [PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 same text}".utf8))]
        let html = plain + [PasteboardContent.Asset(type: .html, data: Data("<b>same text</b>".utf8))]
        let plainID = try insertLegacyHistory("plain", assets: plain, updateAt: 10)
        let richID = try insertLegacyHistory("rich", assets: rich, updateAt: 20)
        let htmlID = try insertLegacyHistory("html", assets: html, updateAt: 30)

        let results = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: searchText), includesThumbnailAsset: false, limit: 10, offset: 0
        )

        #expect(results.map(\.history.id) == [htmlID])
        #expect(repository.fetchContent(id: plainID)?.assets == plain)
        #expect(repository.fetchContent(id: richID)?.assets == rich)
        #expect(repository.fetchContent(id: htmlID)?.assets == html)
        #expect(repository.fetchHistory(id: plainID)?.updateAt == 10)
        #expect(repository.fetchHistory(id: richID)?.updateAt == 20)
    }

    @Test(arguments: [HistorySearchQuery.SortOrder.newestFirst, .oldestFirst])
    func groupingPrecedesPaginationAndOrdersGroupsByLatestCopy(sortOrder: HistorySearchQuery.SortOrder) throws {
        _ = try insertLegacyHistory("old-copy", text: "shared", updateAt: 10)
        let middleID = try insertLegacyHistory("middle", text: "middle", updateAt: 30)
        let latestCopyID = try insertLegacyHistory("latest-copy", text: "shared", updateAt: 50)
        let newestID = try insertLegacyHistory("newest", text: "newest", updateAt: 60)
        let query = HistorySearchQuery(text: "", sortOrder: sortOrder)

        let firstPage = try repository.matchingHistoryIDs(query: query, limit: 2, offset: 0)
        let secondPage = try repository.matchingHistoryIDs(query: query, limit: 2, offset: 2)

        if sortOrder == .newestFirst {
            #expect(firstPage == [newestID, latestCopyID])
            #expect(secondPage == [middleID])
        } else {
            #expect(firstPage == [middleID, latestCopyID])
            #expect(secondPage == [newestID])
        }
    }

    @Test
    func typeFilteringKeepsTheMatchingRichVersionWhenTheLatestCopyIsPlain() throws {
        let richAssets = [
            PasteboardContent.Asset(type: .string, data: Data("same text".utf8)),
            PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 same text}".utf8))
        ]
        let richID = try insertLegacyHistory("rich", assets: richAssets, updateAt: 10)
        let plainID = try insertLegacyHistory("plain", text: "same text", updateAt: 20)

        let richResults = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "same", types: [.rtf]),
            includesThumbnailAsset: false, limit: 10, offset: 0
        )
        let allResults = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "same"), includesThumbnailAsset: false, limit: 10, offset: 0
        )

        #expect(richResults.map(\.history.id) == [richID])
        #expect(allResults.map(\.history.id) == [plainID])
        #expect(repository.fetchContent(id: richID)?.assets == richAssets)
    }

    @Test
    func identicalTruncatedTitlesDoNotHideDifferentCompleteText() throws {
        let prefix = String(repeating: "x", count: 10_001)
        _ = try insertLegacyHistory("old-a", text: prefix + "A", updateAt: 10)
        let differentID = try insertLegacyHistory("different-b", text: prefix + "B", updateAt: 20)
        let latestID = try insertLegacyHistory("latest-a", text: prefix + "A", updateAt: 30)

        let results = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: ""), includesThumbnailAsset: false, limit: 10, offset: 0
        )

        #expect(results.map(\.history.id) == [latestID, differentID])
        #expect(repository.fetchContent(id: latestID)?.stringValue == prefix + "A")
        #expect(repository.fetchContent(id: differentID)?.stringValue == prefix + "B")
    }

    @Test
    func canonicallyEquivalentUnicodeWithDifferentBytesRemainsDistinct() throws {
        let composedID = try insertLegacyHistory("composed", text: "caf\u{00E9}", updateAt: 10)
        let decomposedID = try insertLegacyHistory("decomposed", text: "cafe\u{0301}", updateAt: 20)

        let results = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "caf"), includesThumbnailAsset: false, limit: 10, offset: 0
        )

        #expect(results.map(\.history.id) == [decomposedID, composedID])
    }

    @Test(arguments: [NSPasteboard.PasteboardType.png, .fileURL])
    func imageAndFilePayloadsAreNotGroupedByTheirSharedText(type: NSPasteboard.PasteboardType) throws {
        let textAsset = PasteboardContent.Asset(type: .string, data: Data("shared label".utf8))
        let plainID = try insertLegacyHistory("plain", assets: [textAsset], updateAt: 10)
        let firstID = try insertLegacyHistory(
            "first-media", assets: [textAsset, .init(type: type, data: Data("payload-one".utf8))], updateAt: 20
        )
        let secondID = try insertLegacyHistory(
            "second-media", assets: [textAsset, .init(type: type, data: Data("payload-two".utf8))], updateAt: 30
        )

        let results = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "shared"), includesThumbnailAsset: false, limit: 10, offset: 0
        )

        #expect(results.map(\.history.id) == [secondID, firstID, plainID])
    }

    @Test
    func allowingDuplicateDisplayKeepsEveryFormatVariantAndPaginatesRawRows() throws {
        let richID = try insertLegacyHistory("rich", assets: [
            .init(type: .string, data: Data("same text".utf8)),
            .init(type: .rtf, data: Data("{\\rtf1 same text}".utf8))
        ], updateAt: 10)
        let plainID = try insertLegacyHistory("plain", text: "same text", updateAt: 20)
        let query = HistorySearchQuery(text: "", groupsEquivalentText: false)

        let firstPage = try repository.searchHistoryDetails(
            query: query, includesThumbnailAsset: false, limit: 1, offset: 0
        )
        let secondPage = try repository.searchHistoryDetails(
            query: query, includesThumbnailAsset: false, limit: 1, offset: 1
        )

        #expect(firstPage.map(\.history.id) == [plainID])
        #expect(secondPage.map(\.history.id) == [richID])
    }

    @Test(arguments: [NSPasteboard.PasteboardType.rtf, .html])
    func multipleRichTextItemsRemainVisibleAndSurviveDeletingThePlainTextGroup(type: NSPasteboard.PasteboardType) throws {
        let multiAssets = [
            PasteboardContent.Asset(type: .string, data: Data("same text".utf8)),
            .init(type: type, data: Data("first rich item".utf8)),
            .init(type: type, data: Data("second rich item".utf8))
        ]
        let multiID = try insertLegacyHistory("multiple-rich-items", assets: multiAssets, updateAt: 10)
        let plainID = try insertLegacyHistory("plain", text: "same text", updateAt: 20)
        let query = HistorySearchQuery(text: "same")

        let results = try repository.searchHistoryDetails(
            query: query, includesThumbnailAsset: false, limit: 10, offset: 0
        )

        #expect(results.map(\.history.id) == [plainID, multiID])
        try repository.deleteDisplayedHistory(id: plainID, query: query)
        #expect(repository.fetchHistory(id: plainID) == nil)
        #expect(repository.fetchContent(id: multiID)?.assets == multiAssets)
    }

    @Test
    func deletingDisplayedGroupRemovesItsVariantsAndSuppressesEverySyncIdentity() throws {
        let richID = try insertLegacyHistory("rich", assets: [
            .init(type: .string, data: Data("same text".utf8)),
            .init(type: .rtf, data: Data("{\\rtf1 same text}".utf8))
        ], updateAt: 10)
        let plainID = try insertLegacyHistory("plain", text: "same text", updateAt: 20)
        let unrelatedID = try insertLegacyHistory("unrelated", text: "different text", updateAt: 30)

        try repository.deleteDisplayedHistory(id: plainID, query: HistorySearchQuery(text: ""))

        #expect(repository.fetchHistory(id: richID) == nil)
        #expect(repository.fetchHistory(id: plainID) == nil)
        #expect(repository.fetchContent(id: richID) == nil)
        #expect(repository.fetchContent(id: plainID) == nil)
        #expect(repository.fetchHistory(id: unrelatedID) != nil)
        @Dependency(\.defaultDatabase) var database
        let suppressions = try database.read { try SyncSuppression.all.fetchAll($0) }
        #expect(Set(suppressions.map(\.recordID)) == Set(["rich", "plain"]))
        for id in [richID, plainID] {
            #expect(try !repository.upsertSyncPayload(.init(
                id: id.rawValue, text: "same text", updateAt: 100,
                deviceID: "remote-device", sourceKind: .plainText
            )))
            #expect(repository.fetchHistory(id: id) == nil)
        }
    }

    @Test
    func deletingFilteredDisplayGroupPreservesTheExcludedFormatVariant() throws {
        let richAssets = [
            PasteboardContent.Asset(type: .string, data: Data("same text".utf8)),
            PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 same text}".utf8))
        ]
        let olderRichID = try insertLegacyHistory("older-rich", assets: richAssets, updateAt: 10)
        let richID = try insertLegacyHistory("rich", assets: richAssets, updateAt: 20)
        let plainID = try insertLegacyHistory("plain", text: "same text", updateAt: 30)

        try repository.deleteDisplayedHistory(
            id: richID, query: HistorySearchQuery(text: "same", types: [.rtf])
        )

        #expect(repository.fetchHistory(id: olderRichID) == nil)
        #expect(repository.fetchHistory(id: richID) == nil)
        #expect(repository.fetchHistory(id: plainID) != nil)
        @Dependency(\.defaultDatabase) var database
        let suppressions = try database.read { try SyncSuppression.all.fetchAll($0) }
        #expect(Set(suppressions.map(\.recordID)) == Set(["older-rich", "rich"]))
    }

    @Test
    func deletingWhenDuplicateDisplayIsAllowedRemovesOnlyTheSelectedRow() throws {
        let firstID = try insertLegacyHistory("first", text: "same text", updateAt: 10)
        let secondID = try insertLegacyHistory("second", text: "same text", updateAt: 20)

        try repository.deleteDisplayedHistory(
            id: secondID, query: HistorySearchQuery(text: "", groupsEquivalentText: false)
        )

        #expect(repository.fetchHistory(id: firstID) != nil)
        #expect(repository.fetchHistory(id: secondID) == nil)
        @Dependency(\.defaultDatabase) var database
        let suppressions = try database.read { try SyncSuppression.all.fetchAll($0) }
        #expect(suppressions.map(\.recordID) == ["second"])
    }

    private func insertLegacyHistory(_ id: String, text: String, updateAt: Int) throws -> PasteboardHistory.ID {
        try insertLegacyHistory(id, assets: [.init(type: .string, data: Data(text.utf8))], updateAt: updateAt)
    }

    private func insertLegacyHistory(
        _ rawID: String, assets: [PasteboardContent.Asset], updateAt: Int
    ) throws -> PasteboardHistory.ID {
        let id = PasteboardHistory.ID(rawValue: rawID)
        let content = PasteboardContent(assets: assets)
        let history = PasteboardHistory(
            id: id, title: String(content.historyTitle.prefix(10_001)), pasteboardTypes: content.types,
            updateAt: updateAt, deviceID: "legacy-fixture"
        )
        @Dependency(\.defaultDatabase) var database
        try database.write { db in
            try PasteboardHistory.upsert { history }.execute(db)
            let drafts = assets.map {
                PasteboardHistoryAsset.Draft(pasteboardHistoryID: id, pasteboardType: $0.type, data: $0.data)
            }
            try PasteboardHistoryAsset.insert { drafts }.execute(db)
        }
        return id
    }
}
