//
//  PasteboardContentTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/28.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import CryptoKit
import SQLite3
import Testing
@testable import Pastera

// swiftlint:disable type_body_length file_length

@MainActor
@Suite
struct PasteboardContentTests {
    @Test
    func typesAreDerivedFromAssetsInOrder() {
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8)),
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .pdf, data: Data("pdf".utf8))
            ]
        )
        #expect(content.types == [.rtf, .string, .pdf])
    }

    @Test
    func imageInitializerStoresTiffAsset() throws {
        let image = NSImage.create(with: .red, size: NSSize(width: 10, height: 10))
        let content = try #require(PasteboardContent(image: image))

        #expect(content.types == [.tiff])
        #expect(content.assets.count == 1)
        #expect(content.assets.first?.type == .tiff)
        #expect(content.assets.first?.data.isEmpty == false)
    }

    @Test
    func stringPropertiesUseModernAndDeprecatedStringData() {
        let modernContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8))
            ]
        )
        let deprecatedContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .deprecatedString, data: Data("Legacy".utf8))
            ]
        )
        let mixedContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )

        #expect(modernContent.isOnlyStringType)
        #expect(modernContent.stringValue == "Hello")
        #expect(deprecatedContent.isOnlyStringType)
        #expect(deprecatedContent.stringValue == "Legacy")
        #expect(!mixedContent.isOnlyStringType)
        #expect(mixedContent.stringValue == "Hello")
    }

    @Test
    func colorCodeImageIsCreatedFromHexString() {
        let colorContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("#ff0000".utf8))
            ]
        )
        let invalidContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("not a color".utf8))
            ]
        )

        #expect(colorContent.colorCodeImage?.size == NSSize(width: 20, height: 20))
        #expect(invalidContent.colorCodeImage == nil)
    }

    @Test
    func thumbnailImageIsCreatedFromStoredTiffData() throws {
        let defaults = UserDefaults.standard
        let previousWidth = defaults.object(forKey: Constants.UserDefaults.thumbnailWidth)
        let previousHeight = defaults.object(forKey: Constants.UserDefaults.thumbnailHeight)
        defer {
            if let previousWidth {
                defaults.set(previousWidth, forKey: Constants.UserDefaults.thumbnailWidth)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailWidth)
            }
            if let previousHeight {
                defaults.set(previousHeight, forKey: Constants.UserDefaults.thumbnailHeight)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailHeight)
            }
        }
        defaults.set(8, forKey: Constants.UserDefaults.thumbnailWidth)
        defaults.set(6, forKey: Constants.UserDefaults.thumbnailHeight)

        let image = NSImage.create(with: .blue, size: NSSize(width: 20, height: 10))
        let sourceBitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let content = PasteboardContent(image: image)
        let expectedSize = NSSize(width: sourceBitmap.pixelsWide, height: sourceBitmap.pixelsHigh)

        #expect(content?.thumbnailImage?.size == expectedSize)
    }

    @Test
    func thumbnailImageIsCreatedFromStoredPNGData() throws {
        let defaults = UserDefaults.standard
        let previousWidth = defaults.object(forKey: Constants.UserDefaults.thumbnailWidth)
        let previousHeight = defaults.object(forKey: Constants.UserDefaults.thumbnailHeight)
        defer {
            if let previousWidth {
                defaults.set(previousWidth, forKey: Constants.UserDefaults.thumbnailWidth)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailWidth)
            }
            if let previousHeight {
                defaults.set(previousHeight, forKey: Constants.UserDefaults.thumbnailHeight)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailHeight)
            }
        }
        defaults.set(8, forKey: Constants.UserDefaults.thumbnailWidth)
        defaults.set(6, forKey: Constants.UserDefaults.thumbnailHeight)

        let image = NSImage.create(with: .blue, size: NSSize(width: 20, height: 10))
        let tiffData = try #require(image.tiffRepresentation)
        let pngData = try #require(NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]))
        let sourceBitmap = try #require(NSBitmapImageRep(data: pngData))
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .png, data: pngData)
            ]
        )
        let expectedSize = NSSize(width: sourceBitmap.pixelsWide, height: sourceBitmap.pixelsHigh)

        #expect(content.thumbnailImage?.size == expectedSize)
    }

    @Test
    func thumbnailEncodingUsesResampledBitmapInsteadOfOriginalRepresentation() throws {
        let defaults = UserDefaults.standard
        let previousWidth = defaults.object(forKey: Constants.UserDefaults.thumbnailWidth)
        let previousHeight = defaults.object(forKey: Constants.UserDefaults.thumbnailHeight)
        defer {
            if let previousWidth {
                defaults.set(previousWidth, forKey: Constants.UserDefaults.thumbnailWidth)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailWidth)
            }
            if let previousHeight {
                defaults.set(previousHeight, forKey: Constants.UserDefaults.thumbnailHeight)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailHeight)
            }
        }
        defaults.set(100, forKey: Constants.UserDefaults.thumbnailWidth)
        defaults.set(32, forKey: Constants.UserDefaults.thumbnailHeight)

        let image = try makeNoisyImage(width: 1200, height: 800)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .tiff, data: try #require(image.tiffRepresentation))
            ]
        )

        let thumbnail = try #require(content.thumbnailImage)
        let pngData = try #require(PasteraImageEncoding.pngData(
            from: thumbnail,
            maxBytes: Constants.Thumbnail.maxEncodedBytes
        ))
        let encodedBitmap = try #require(NSBitmapImageRep(data: pngData))

        #expect(encodedBitmap.pixelsWide <= Constants.Thumbnail.hoverPreviewPixelWidth)
        #expect(encodedBitmap.pixelsHigh <= Constants.Thumbnail.hoverPreviewPixelHeight)
        #expect(encodedBitmap.pixelsWide > 100)
        #expect(encodedBitmap.pixelsHigh > 32)
        #expect(pngData.count < Constants.Thumbnail.maxEncodedBytes)
    }

    @Test
    func screenshotThumbnailKeepsEnoughPixelsForHoverPreview() throws {
        let defaults = UserDefaults.standard
        let previousWidth = defaults.object(forKey: Constants.UserDefaults.thumbnailWidth)
        let previousHeight = defaults.object(forKey: Constants.UserDefaults.thumbnailHeight)
        defer {
            if let previousWidth {
                defaults.set(previousWidth, forKey: Constants.UserDefaults.thumbnailWidth)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailWidth)
            }
            if let previousHeight {
                defaults.set(previousHeight, forKey: Constants.UserDefaults.thumbnailHeight)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailHeight)
            }
        }
        defaults.set(100, forKey: Constants.UserDefaults.thumbnailWidth)
        defaults.set(32, forKey: Constants.UserDefaults.thumbnailHeight)

        let image = try makeScreenshotLikeImage(width: 1200, height: 800)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .tiff, data: try #require(image.tiffRepresentation))
            ]
        )

        let thumbnail = try #require(content.thumbnailImage)
        let pngData = try #require(PasteraImageEncoding.pngData(
            from: thumbnail,
            maxBytes: Constants.Thumbnail.maxEncodedBytes
        ))
        let encodedBitmap = try #require(NSBitmapImageRep(data: pngData))

        #expect(encodedBitmap.pixelsWide >= 800)
        #expect(encodedBitmap.pixelsHigh >= 530)
        #expect(pngData.count < Constants.Thumbnail.maxEncodedBytes)
    }

    @Test
    func filePreviewClassifierRecognizesImageFilesWithoutFixedExtensionList() throws {
        let image = NSImage.create(with: .purple, size: NSSize(width: 18, height: 12))
        let pngData = try makeImageData(image, type: .png)
        let url = try writeTemporaryImage(data: pngData, extension: "customimage")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(PasteraFileTypeClassifier.kind(for: url) == .image)
        #expect(PasteraFileTypeClassifier.canCreateImageThumbnail(from: url))
    }

    @Test
    func filePreviewClassifierReadsBoundedTextPreviewAndRejectsBinaryFiles() throws {
        let textURL = try writeTemporaryFile(
            name: "notes.md",
            data: Data(("First line\n" + String(repeating: "Second line\n", count: 200)).utf8)
        )
        let binaryURL = try writeTemporaryFile(
            name: "archive.zip",
            data: Data([0x00, 0x01, 0x02, 0x03, 0x04])
        )
        defer {
            try? FileManager.default.removeItem(at: textURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: binaryURL.deletingLastPathComponent())
        }

        let preview = try #require(PasteraFileTypeClassifier.textPreview(from: textURL, maxBytes: 16))

        #expect(preview == "First line\nSecon")
        #expect(PasteraFileTypeClassifier.kind(for: textURL) == .document)
        #expect(PasteraFileTypeClassifier.kind(for: binaryURL) == .archive)
        #expect(PasteraFileTypeClassifier.textPreview(from: binaryURL) == nil)
    }

    @Test
    func finderFileCategoryClassifiesDocumentArchiveCodeOtherAndRejectsDirectories() throws {
        let documentURL = try writeTemporaryFile(name: "report.docx", data: Data("doc".utf8))
        let archiveURL = try writeTemporaryFile(name: "backup.zip", data: Data([0x50, 0x4B]))
        let codeURL = try writeTemporaryFile(name: "main.swift", data: Data("let value = 1".utf8))
        let unknownURL = try writeTemporaryFile(name: "payload.unknown", data: Data("payload".utf8))
        let extensionlessURL = try writeTemporaryFile(name: "README", data: Data("readme".utf8))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            [documentURL, archiveURL, codeURL, unknownURL, extensionlessURL].forEach {
                try? FileManager.default.removeItem(at: $0.deletingLastPathComponent())
            }
            try? FileManager.default.removeItem(at: directoryURL)
        }

        #expect(PasteraFinderFileCategory.category(for: documentURL) == .document)
        #expect(PasteraFinderFileCategory.category(for: archiveURL) == .archive)
        #expect(PasteraFinderFileCategory.category(for: codeURL) == .code)
        #expect(PasteraFinderFileCategory.category(for: unknownURL) == .other)
        #expect(PasteraFinderFileCategory.category(for: extensionlessURL) == .other)
        #expect(PasteraFinderFileCategory.category(for: directoryURL) == nil)
    }

    @Test
    func fileURLContentKeepsOriginalAssetAndCreatesDisplayTitleForDocumentFiles() throws {
        let textURL = try writeTemporaryFile(name: "notes.md", data: Data("Hello from file".utf8))
        defer { try? FileManager.default.removeItem(at: textURL.deletingLastPathComponent()) }
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .fileURL, data: textURL.dataRepresentation)
            ]
        )

        #expect(content.assets == [PasteboardContent.Asset(type: .fileURL, data: textURL.dataRepresentation)])
        #expect(content.historyTitle == "notes.md\nHello from file")
    }

    @Test
    func fileURLContentKeepsFileNameForArchiveCodeDocumentAndOtherFiles() throws {
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

            #expect(content.historyTitle.components(separatedBy: .newlines).first == cases[index].name)
        }
    }

    @Test
    func contentHashIsStableAndContentBased() {
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )
        let equivalentContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )
        let changedDataContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello!".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )
        let changedOrderContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8)),
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8))
            ]
        )

        #expect(content.hash == "4c6a4ba3cd6a6aad6a2c6620542b11c94edf2af3297611aeba21a86e79dbeb20")
        #expect(content.hash == equivalentContent.hash)
        #expect(content.hash != changedDataContent.hash)
        #expect(content.hash != changedOrderContent.hash)
    }

    @Test
    func contentHashMatchesLegacyLengthPrefixedConcatenation() {
        let assets = [
            PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
            PasteboardContent.Asset(type: .rtf, data: Data(repeating: 0x2A, count: 64)),
            PasteboardContent.Asset(type: .pdf, data: Data("pdf-data".utf8))
        ]

        let content = PasteboardContent(assets: assets)

        #expect(content.hash == legacyLengthPrefixedHash(for: assets))
    }

    @Test
    func imageFileInitializerPreservesPNGBytes() throws {
        let image = NSImage.create(with: .red, size: NSSize(width: 18, height: 12))
        let pngData = try makeImageData(image, type: .png)
        let url = try writeTemporaryImage(data: pngData, extension: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try #require(PasteboardContent(imageFileURL: url))

        #expect(content.types == [.png])
        #expect(content.assets.count == 1)
        #expect(content.assets.first?.type == .png)
        #expect(content.assets.first?.data == pngData)
    }

    @Test
    func imageFileInitializerReencodesNonPNGImagesAsPNG() throws {
        let image = NSImage.create(with: .green, size: NSSize(width: 18, height: 12))
        let jpegData = try makeImageData(image, type: .jpeg)
        let url = try writeTemporaryImage(data: jpegData, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try #require(PasteboardContent(imageFileURL: url))

        #expect(content.types == [.png])
        #expect(content.assets.count == 1)
        let asset = try #require(content.assets.first)
        #expect(asset.type == .png)
        #expect(asset.data != jpegData)
        #expect(asset.data.starts(with: pngSignature))
        #expect(NSImage(data: asset.data) != nil)
    }

    @Test
    func imageFileInitializerRejectsInvalidImageFiles() throws {
        let url = try writeTemporaryImage(data: Data("not an image".utf8), extension: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(PasteboardContent(imageFileURL: url) == nil)
    }

    @Test
    func pasteboardInitializerPreservesMultipleImageItems() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardContentTests.images"))
        pasteboard.clearContents()
        let firstImage = try #require(NSImage.create(with: .red, size: NSSize(width: 10, height: 10)).tiffRepresentation)
        let secondImage = try #require(NSImage.create(with: .blue, size: NSSize(width: 20, height: 20)).tiffRepresentation)
        let firstItem = NSPasteboardItem()
        firstItem.setData(firstImage, forType: .tiff)
        let secondItem = NSPasteboardItem()
        secondItem.setData(secondImage, forType: .tiff)
        pasteboard.writeObjects([firstItem, secondItem])

        let content = try #require(PasteboardContent(pasteboard: pasteboard, types: [.tiff]))

        #expect(content.assets.map(\.type) == [.tiff, .tiff])
        #expect(content.assets.map(\.data) == [firstImage, secondImage])
    }

    @Test
    func pasteServiceWritesSnipasteImageWithStandardPNGType() throws {
        let image = NSImage.create(with: .red, size: NSSize(width: 18, height: 12))
        let pngData = try makeImageData(image, type: .png)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .clipySnipastePNG, data: pngData)
            ]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardContentTests.snipastePNG"))
        defer { pasteboard.clearContents() }

        PasteService().copyContentToPasteboard(content, to: pasteboard)

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.types.contains(.clipySnipastePNG))
        #expect(item.types.contains(.png))
        #expect(item.data(forType: .clipySnipastePNG) == pngData)
        #expect(item.data(forType: .png) == pngData)
    }

    @Test
    func pasteServiceWritesDeprecatedTIFFAsStandardTIFFType() throws {
        let image = NSImage.create(with: .blue, size: NSSize(width: 18, height: 12))
        let tiffData = try #require(image.tiffRepresentation)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .deprecatedTIFF, data: tiffData)
            ]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardContentTests.deprecatedTIFF"))
        defer { pasteboard.clearContents() }

        PasteService().copyContentToPasteboard(content, to: pasteboard)

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.types.contains(.tiff))
        #expect(item.data(forType: .tiff) == tiffData)
    }

    @Test
    func pasteServiceKeepsMultipleImageItemsSeparateWhenAddingCompatibleTypes() throws {
        let firstImage = NSImage.create(with: .red, size: NSSize(width: 12, height: 12))
        let secondImage = NSImage.create(with: .green, size: NSSize(width: 16, height: 16))
        let firstData = try makeImageData(firstImage, type: .png)
        let secondData = try makeImageData(secondImage, type: .png)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .clipySnipastePNG, data: firstData),
                PasteboardContent.Asset(type: .clipyApplePNG, data: secondData)
            ]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardContentTests.multiImage"))
        defer { pasteboard.clearContents() }

        PasteService().copyContentToPasteboard(content, to: pasteboard)

        let items = try #require(pasteboard.pasteboardItems)
        #expect(items.count == 2)
        #expect(items[0].types.contains(.clipySnipastePNG))
        #expect(items[0].types.contains(.png))
        #expect(items[0].data(forType: .png) == firstData)
        #expect(items[1].types.contains(.png))
        #expect(items[1].data(forType: .png) == secondData)
    }

    @Test
    func pasteServiceDoesNotDuplicateStandardPNGType() throws {
        let image = NSImage.create(with: .orange, size: NSSize(width: 18, height: 12))
        let pngData = try makeImageData(image, type: .png)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .png, data: pngData)
            ]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardContentTests.standardPNG"))
        defer { pasteboard.clearContents() }

        PasteService().copyContentToPasteboard(content, to: pasteboard)

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.types.filter { $0 == .png }.count == 1)
        #expect(item.data(forType: .png) == pngData)
    }

    @Test
    func oneDriveFolderSyncProviderWritesBoundedHistorySQLiteSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let payloads = (0..<2005).map { index in
            PasteboardHistorySyncPayload(
                id: "history-\(index)",
                text: "History \(index)",
                updateAt: index,
                deviceID: "device-a",
                sourceKind: .plainText
            )
        }

        try provider.saveHistorySnapshot(
            payloads,
            deviceID: "device-a",
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 8 * 1024 * 1024
        )

        let snapshot = try #require(provider.loadHistorySnapshots(excludingDeviceID: "device-b").first)
        let sqliteURL = rootURL.appendingPathComponent("history/devices/device-a.sqlite")
        let protocolURL = rootURL.appendingPathComponent("history/protocol.json")
        let sqliteData = try Data(contentsOf: sqliteURL)
        let protocolData = try Data(contentsOf: protocolURL)
        #expect(snapshot.deviceID == "device-a")
        #expect(snapshot.payloads.count == 2000)
        #expect(snapshot.payloads.first?.id == "history-2004")
        #expect(snapshot.payloads.last?.id == "history-5")
        #expect(protocolData.range(of: Data("\"schemaVersion\"".utf8)) != nil)
        #expect(protocolData.range(of: Data("4".utf8)) != nil)
        #expect(sqliteData.starts(with: Data("SQLite format 3".utf8)))
        #expect(sqliteData.range(of: Data("schemaVersion".utf8)) != nil)
        #expect(sqliteData.range(of: Data("windowSignature".utf8)) != nil)
        #expect(sqliteData.range(of: Data("History 2004".utf8)) != nil)
        #expect(sqliteData.range(of: Data("plainText".utf8)) != nil)
        #expect(sqliteData.range(of: Data("history_assets".utf8)) == nil)
        #expect(sqliteData.range(of: Data("history_thumbnails".utf8)) == nil)
        #expect(sqliteData.range(of: Data("pasteboardType".utf8)) == nil)
        #expect(sqliteData.range(of: Data("public.utf8-plain-text".utf8)) == nil)
        #expect(snapshot.payloads.first?.text == "History 2004")
        #expect(snapshot.payloads.first?.sourceKind == .plainText)
        #expect(!FileManager.default.fileExists(atPath: sqliteURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: sqliteURL.path + "-shm"))
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("manifest.json").path))
    }

    @Test
    func oneDriveFolderSyncProviderUpgradesOldHistoryProtocolWithoutRemovingRemoteSnapshots() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let oldHistoryDirectory = rootURL.appendingPathComponent("history/devices", isDirectory: true)
        let filesDirectory = rootURL.appendingPathComponent("files/devices/device-a", isDirectory: true)
        try FileManager.default.createDirectory(at: oldHistoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        try Data("{\"schemaVersion\":3,\"generatedAt\":1}".utf8)
            .write(to: rootURL.appendingPathComponent("history/protocol.json"))
        try Data("old sqlite".utf8)
            .write(to: oldHistoryDirectory.appendingPathComponent("old-device.sqlite"))
        try Data("{\"manifestVersion\":1}".utf8)
            .write(to: filesDirectory.appendingPathComponent("manifest.json"))
        let payload = PasteboardHistorySyncPayload(
            id: "history-1",
            text: "History",
            updateAt: 1,
            deviceID: "device-a",
            sourceKind: .plainText
        )

        try provider.saveHistorySnapshot(
            [payload],
            deviceID: "device-a",
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 8 * 1024 * 1024
        )

        let protocolData = try Data(contentsOf: rootURL.appendingPathComponent("history/protocol.json"))
        #expect(protocolData.range(of: Data("\"schemaVersion\"".utf8)) != nil)
        #expect(protocolData.range(of: Data("4".utf8)) != nil)
        #expect(try Data(contentsOf: oldHistoryDirectory.appendingPathComponent("old-device.sqlite"))
            == Data("old sqlite".utf8))
        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "device-a").isEmpty)
        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "another-device")
            .flatMap(\.payloads).map(\.id) == ["history-1"])
        #expect(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("history/devices/device-a.sqlite").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: filesDirectory.appendingPathComponent("manifest.json").path
        ))
    }

    @Test(arguments: ["missing", "empty", "malformed"], ["states", "snapshots", "save"])
    func historySnapshotsSurviveIncompleteSharedProtocol(protocolState: String, entryPoint: String) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let remotePayload = PasteboardHistorySyncPayload(
            id: "arrived-before-protocol", text: "Remote text", updateAt: 10,
            deviceID: "remote-device", sourceKind: .plainText
        )
        try provider.saveHistorySnapshot(
            [remotePayload], deviceID: "remote-device", limit: 10,
            maxTextBytes: 1024, snapshotTextBudgetBytes: 4096
        )
        let remoteURL = rootURL.appendingPathComponent("history/devices/remote-device.sqlite")
        let remoteData = try Data(contentsOf: remoteURL)
        let remoteModifiedAt = try FileManager.default.attributesOfItem(atPath: remoteURL.path)[.modificationDate] as? Date
        let protocolURL = rootURL.appendingPathComponent("history/protocol.json")
        let incompleteProtocol: Data?
        switch protocolState {
        case "missing":
            incompleteProtocol = nil
            try FileManager.default.removeItem(at: protocolURL)
        case "empty":
            incompleteProtocol = Data()
            try Data().write(to: protocolURL)
        default:
            incompleteProtocol = Data("{\"schemaVersion\":".utf8)
            try incompleteProtocol?.write(to: protocolURL)
        }

        if entryPoint == "states" {
            #expect(try provider.historySnapshotFileStates(excludingDeviceID: "local-device")
                .map(\.url.lastPathComponent) == ["remote-device.sqlite"])
        } else if entryPoint == "snapshots" {
            #expect(try provider.loadHistorySnapshots(excludingDeviceID: "local-device")
                .flatMap(\.payloads) == [remotePayload])
        }
        if entryPoint != "save" {
            #expect((try? Data(contentsOf: protocolURL)) == incompleteProtocol)
            #expect((try? Data(contentsOf: remoteURL)) == remoteData)
        }

        try provider.saveHistorySnapshot(
            [PasteboardHistorySyncPayload(
                id: "local-history", text: "Local text", updateAt: 20,
                deviceID: "local-device", sourceKind: .plainText
            )], deviceID: "local-device", limit: 10,
            maxTextBytes: 1024, snapshotTextBudgetBytes: 4096
        )

        #expect((try? Data(contentsOf: remoteURL)) == remoteData)
        #expect(try FileManager.default.attributesOfItem(atPath: remoteURL.path)[.modificationDate] as? Date == remoteModifiedAt)
        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "local-device")
            .flatMap(\.payloads) == [remotePayload])
    }

    @Test
    func oneDriveFolderSyncProviderReadsHistoryWithoutProtocolPermissionAndPreservesItOnSaveFailure() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let protocolURL = rootURL.appendingPathComponent("history/protocol.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: protocolURL.path)
            try? FileManager.default.removeItem(at: rootURL)
        }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        try provider.saveHistorySnapshot([
            PasteboardHistorySyncPayload(
                id: "remote-history", text: "Remote history", updateAt: 10,
                deviceID: "remote-device", sourceKind: .plainText
            )
        ], deviceID: "remote-device", limit: 2000, maxTextBytes: 256 * 1024,
           snapshotTextBudgetBytes: 8 * 1024 * 1024)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: protocolURL.path)

        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "local-device")
            .first?.payloads.first?.id == "remote-history")
        #expect(throws: (any Error).self) {
            try provider.saveHistorySnapshot(
                [], deviceID: "local-device", limit: 10,
                maxTextBytes: 1024, snapshotTextBudgetBytes: 4096
            )
        }
        #expect(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("history/devices/remote-device.sqlite").path
        ))

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: protocolURL.path)
        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "local-device")
            .first?.payloads.first?.id == "remote-history")
    }

    @Test
    func oneDriveFolderSyncProviderRejectsFutureProtocolWithoutOverwritingSharedHistory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        try provider.saveHistorySnapshot(
            [PasteboardHistorySyncPayload(
                id: "remote-history", text: "Remote text", updateAt: 10,
                deviceID: "remote-device", sourceKind: .plainText
            )], deviceID: "remote-device", limit: 10,
            maxTextBytes: 1024, snapshotTextBudgetBytes: 4096
        )
        let protocolURL = rootURL.appendingPathComponent("history/protocol.json")
        let futureProtocol = Data("{\"schemaVersion\":99,\"generatedAt\":1}".utf8)
        try futureProtocol.write(to: protocolURL)
        let remoteURL = rootURL.appendingPathComponent("history/devices/remote-device.sqlite")
        let remoteData = try Data(contentsOf: remoteURL)

        #expect(throws: (any Error).self) {
            try provider.saveHistorySnapshot(
                [], deviceID: "local-device", limit: 10,
                maxTextBytes: 1024, snapshotTextBudgetBytes: 4096
            )
        }

        #expect((try? Data(contentsOf: protocolURL)) == futureProtocol)
        #expect((try? Data(contentsOf: remoteURL)) == remoteData)
        #expect(!FileManager.default.fileExists(atPath:
            rootURL.appendingPathComponent("history/devices/local-device.sqlite").path))
    }

    @Test
    func oneDriveFolderSyncProviderReportsHistorySnapshotFileStates() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let payload = PasteboardHistorySyncPayload(
            id: "remote-history",
            text: "Remote",
            updateAt: 1,
            deviceID: "remote-device",
            sourceKind: .plainText
        )
        try provider.saveHistorySnapshot(
            [payload],
            deviceID: "remote-device",
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 8 * 1024 * 1024
        )

        let states = try provider.historySnapshotFileStates(excludingDeviceID: "local-device")

        let state = try #require(states.first)
        #expect(states.count == 1)
        #expect(state.deviceID == "remote-device")
        #expect(state.byteCount > 0)
        #expect(state.modifiedAtNanoseconds > 0)
    }

    @Test(arguments: ["2", "3"])
    func oneDriveFolderSyncProviderSkipsOldHistorySnapshotsWithoutRemovingThem(schemaVersion: String) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let historyDirectory = rootURL.appendingPathComponent("history/devices", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let sqliteURL = historyDirectory.appendingPathComponent("remote.sqlite")
        var handle: OpaquePointer?
        sqlite3_open_v2(sqliteURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer {
            if let handle {
                sqlite3_close(handle)
            }
        }
        sqlite3_exec(handle, """
            CREATE TABLE metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
            INSERT INTO metadata(key, value) VALUES ('schemaVersion', '\(schemaVersion)'), ('deviceID', 'remote-device');
            CREATE TABLE histories (id TEXT PRIMARY KEY NOT NULL, updatedAt INTEGER NOT NULL, title TEXT NOT NULL);
            """, nil, nil, nil)
        sqlite3_close(handle)
        handle = nil
        let oldSnapshotData = try Data(contentsOf: sqliteURL)

        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "device-a").isEmpty)
        #expect((try? Data(contentsOf: sqliteURL)) == oldSnapshotData)
    }

    @Test
    func oneDriveFolderSyncProviderWritesFullSnippetSQLiteSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = SnippetSyncSnapshot(
            folders: [
                SnippetFolderSyncPayload(
                    id: UUID().uuidString,
                    title: "Folder",
                    index: 1,
                    isEnabled: true,
                    updatedAt: 10,
                    deviceID: "device-a"
                )
            ],
            snippets: [
                SnippetSyncPayload(
                    id: UUID().uuidString,
                    folderID: UUID().uuidString,
                    title: "Snippet",
                    content: "content",
                    index: 2,
                    isEnabled: false,
                    updatedAt: 20,
                    deviceID: "device-a"
                )
            ]
        )

        try provider.saveSnippetSnapshot(snapshot, deviceID: "device-a")

        let loaded = try #require(provider.loadSnippetSnapshots(excludingDeviceID: "device-b").first)
        let sqliteURL = rootURL.appendingPathComponent("snippets/devices/device-a.sqlite")
        let sqliteData = try Data(contentsOf: sqliteURL)
        #expect(loaded.deviceID == "device-a")
        #expect(loaded.snapshot == snapshot)
        #expect(sqliteData.starts(with: Data("SQLite format 3".utf8)))
        #expect(!FileManager.default.fileExists(atPath: sqliteURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("snippets/items").path))
    }

    @Test
    func oneDriveFolderSyncProviderRoundTripsSnippetDeletionTombstones() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let folderID = UUID().uuidString
        let snippetID = UUID().uuidString
        let snapshot = SnippetSyncSnapshot(
            folders: [],
            snippets: [],
            deletedFolders: [
                SnippetFolderDeletionSyncPayload(
                    id: folderID,
                    title: "AI Prompt",
                    deletedAt: 30,
                    deviceID: "device-a"
                )
            ],
            deletedSnippets: [
                SnippetDeletionSyncPayload(
                    id: snippetID,
                    folderID: folderID,
                    folderTitle: "AI Prompt",
                    content: "removed content",
                    deletedAt: 40,
                    deviceID: "device-a"
                )
            ]
        )

        try provider.saveSnippetSnapshot(snapshot, deviceID: "device-a")

        let loaded = try #require(provider.loadSnippetSnapshots(excludingDeviceID: "device-b").first)
        #expect(loaded.snapshot == snapshot)
    }

    @Test
    func oneDriveFolderSyncProviderSkipsUnchangedSnippetSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = stableSnippetSnapshot()
        let sqliteURL = rootURL.appendingPathComponent("snippets/devices/device-a.sqlite")
        try provider.saveSnippetSnapshot(snapshot, deviceID: "device-a")
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: sqliteURL.path)
        let firstData = try Data(contentsOf: sqliteURL)

        try provider.saveSnippetSnapshot(snapshot, deviceID: "device-a")

        #expect(try FileManager.default.attributesOfItem(atPath: sqliteURL.path)[.modificationDate] as? Date == oldDate)
        #expect(try Data(contentsOf: sqliteURL) == firstData)
    }

    @Test
    func oneDriveFolderSyncProviderWritesChangedSnippetSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let sqliteURL = rootURL.appendingPathComponent("snippets/devices/device-a.sqlite")
        try provider.saveSnippetSnapshot(stableSnippetSnapshot(), deviceID: "device-a")
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: sqliteURL.path)

        try provider.saveSnippetSnapshot(stableSnippetSnapshot(content: "changed"), deviceID: "device-a")

        let loaded = try #require(provider.loadSnippetSnapshots(excludingDeviceID: "device-b").first)
        #expect(loaded.snapshot.snippets.first?.content == "changed")
        #expect(try FileManager.default.attributesOfItem(atPath: sqliteURL.path)[.modificationDate] as? Date != oldDate)
    }

    @Test
    func oneDriveFolderSyncProviderRecreatesDeletedSnippetSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = stableSnippetSnapshot()
        let sqliteURL = rootURL.appendingPathComponent("snippets/devices/device-a.sqlite")
        try provider.saveSnippetSnapshot(snapshot, deviceID: "device-a")
        try FileManager.default.removeItem(at: sqliteURL)

        try provider.saveSnippetSnapshot(snapshot, deviceID: "device-a")

        let loaded = try #require(provider.loadSnippetSnapshots(excludingDeviceID: "device-b").first)
        #expect(loaded.snapshot.snippets.first?.content == "stable")
        #expect(loaded.snapshot.folders.count == 2)
        #expect(loaded.snapshot.deletedFolders.count == 2)
        #expect(loaded.snapshot.deletedSnippets.count == 2)
    }

    @Test
    func oneDriveFolderSyncProviderWritesFileManifestAndDirectAssetFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-1",
                    updatedAt: 10,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .pdf,
                            data: Data("%PDF".utf8),
                            originalFilename: "document.pdf"
                        ),
                        FileSyncAssetPayload(
                            assetIndex: 1,
                            pasteboardType: .png,
                            data: Data([0x89, 0x50, 0x4E, 0x47]),
                            originalFilename: nil
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")

        let loaded = try #require(provider.loadFileSnapshots(excludingDeviceID: "device-b").first)
        let manifestURL = rootURL.appendingPathComponent("files/devices/device-a/manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let objectURLs = try #require(FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/device-a/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL })

        #expect(loaded.deviceID == "device-a")
        #expect(loaded.histories == snapshot.histories)
        let assetFiles = objectURLs.filter { ["pdf", "png"].contains($0.pathExtension) }
        #expect(assetFiles.count == 2)
        #expect(Set(assetFiles.map(\.pathExtension)) == ["pdf", "png"])
        #expect(manifestData.range(of: Data("manifestVersion".utf8)) != nil)
        #expect(manifestData.range(of: Data("document.pdf".utf8)) != nil)
        #expect(manifestData.range(of: Data("sha256".utf8)) == nil)
        #expect(manifestData.range(of: Data("%PDF".utf8)) == nil)
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("files/devices/device-a.sqlite").path))
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("files/objects").path))

        try provider.saveFileSnapshot(FileSyncExportSnapshot(histories: [], skippedAssetCount: 0), deviceID: "device-a")

        let remainingObjects = try FileManager.default.contentsOfDirectory(
            at: rootURL.appendingPathComponent("files/devices/device-a/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        #expect(remainingObjects.isEmpty)
    }

    @Test
    func oneDriveFolderSyncProviderSkipsUnsupportedFinderFileAssets() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-file",
                    updatedAt: 10,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .fileURL,
                            data: URL(fileURLWithPath: "/tmp/report.txt").dataRepresentation,
                            originalFilename: "report.txt"
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")

        let loaded = try #require(provider.loadFileSnapshots(excludingDeviceID: "device-b").first)
        let assetURLs = FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/device-a/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []
        #expect(loaded.histories.isEmpty)
        #expect(assetURLs.isEmpty)
    }

    @Test
    func oneDriveFolderSyncProviderReusesUnchangedDirectAssetFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-1",
                    updatedAt: 10,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .pdf,
                            data: Data("%PDF stable".utf8),
                            originalFilename: "document.pdf"
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")
        let objectURL = try #require(FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/device-a/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.first { $0.pathExtension == "pdf" })
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: objectURL.path)

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")

        let attributes = try FileManager.default.attributesOfItem(atPath: objectURL.path)
        #expect(attributes[.modificationDate] as? Date == oldDate)
        #expect(try Data(contentsOf: objectURL) == Data("%PDF stable".utf8))
    }

    @Test
    func oneDriveFolderSyncProviderSkipsUnchangedFileManifest() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = stableFileSnapshot()
        let manifestURL = rootURL.appendingPathComponent("files/devices/device-a/manifest.json")
        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")
        var existingManifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        existingManifest["generatedAt"] = 1_000
        try JSONSerialization.data(withJSONObject: existingManifest).write(to: manifestURL)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: manifestURL.path)
        let firstData = try Data(contentsOf: manifestURL)

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")

        #expect(try FileManager.default.attributesOfItem(atPath: manifestURL.path)[.modificationDate] as? Date == oldDate)
        #expect(try Data(contentsOf: manifestURL) == firstData)
    }

    @Test
    func oneDriveFolderSyncProviderMaintainsAssetsWithUnchangedManifest() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = stableFileSnapshot()
        let deviceURL = rootURL.appendingPathComponent("files/devices/device-a")
        let manifestURL = deviceURL.appendingPathComponent("manifest.json")
        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")
        let assetURL = try #require(FileManager.default.enumerator(
            at: deviceURL.appendingPathComponent("assets"), includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.first { $0.pathExtension == "pdf" })
        let orphanURL = assetURL.deletingLastPathComponent().appendingPathComponent("orphan.pdf")
        try Data("orphan".utf8).write(to: orphanURL)
        try FileManager.default.removeItem(at: assetURL)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: manifestURL.path)

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")

        #expect(try Data(contentsOf: assetURL) == Data("%PDF stable".utf8))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(try FileManager.default.attributesOfItem(atPath: manifestURL.path)[.modificationDate] as? Date == oldDate)
    }

    @Test
    func oneDriveFolderSyncProviderRecreatesDeletedFileManifest() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = stableFileSnapshot()
        let manifestURL = rootURL.appendingPathComponent("files/devices/device-a/manifest.json")
        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")
        try FileManager.default.removeItem(at: manifestURL)

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")

        let loaded = try #require(provider.loadFileSnapshots(excludingDeviceID: "device-b").first)
        #expect(loaded.histories == snapshot.histories)
    }

    @Test
    func oneDriveFolderSyncProviderWritesChangedFileManifest() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let manifestURL = rootURL.appendingPathComponent("files/devices/device-a/manifest.json")
        try provider.saveFileSnapshot(stableFileSnapshot(), deviceID: "device-a")
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: manifestURL.path)
        let changedSnapshot = stableFileSnapshot(updatedAt: 20)

        try provider.saveFileSnapshot(changedSnapshot, deviceID: "device-a")

        let loaded = try #require(provider.loadFileSnapshots(excludingDeviceID: "device-b").first)
        #expect(loaded.histories.first?.updatedAt == 20)
        #expect(try FileManager.default.attributesOfItem(atPath: manifestURL.path)[.modificationDate] as? Date != oldDate)
    }

    @Test
    func oneDriveFolderSyncProviderCapsDirectAssetFileNames() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let longName = String(repeating: "a", count: 320) + ".pdf"
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-1",
                    updatedAt: 10,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .pdf,
                            data: Data("%PDF long name".utf8),
                            originalFilename: longName
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )

        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")

        let objectURL = try #require(FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/device-a/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.first { $0.pathExtension == "pdf" })
        #expect(objectURL.lastPathComponent.lengthOfBytes(using: .utf8) <= 255)
        #expect(objectURL.lastPathComponent.hasSuffix(".pdf"))
        let loaded = try #require(provider.loadFileSnapshots(excludingDeviceID: "device-b").first)
        #expect(loaded.histories == snapshot.histories)
    }

    @Test
    func oneDriveFolderSyncProviderSkipsFileGroupsWhenFileValidationFails() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-1",
                    updatedAt: 10,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .pdf,
                            data: Data("%PDF".utf8),
                            originalFilename: nil
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )
        try provider.saveFileSnapshot(snapshot, deviceID: "device-a")
        let objectURL = try #require(FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/device-a/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.first { $0.pathExtension == "pdf" })
        try Data("tampered".utf8).write(to: objectURL)

        let loaded = try #require(provider.loadFileSnapshots(excludingDeviceID: "device-b").first)
        #expect(loaded.histories.isEmpty)
        #expect(loaded.skippedAssetCount == 1)
    }

    @Test
    func oneDriveFolderSyncProviderPreservesPreviousManifestWhenReplacementFails() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let originalSnapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-original",
                    updatedAt: 10,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .pdf,
                            data: Data("original".utf8),
                            originalFilename: nil
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )
        let replacementSnapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-replacement",
                    updatedAt: 20,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .pdf,
                            data: Data("replacement".utf8),
                            originalFilename: nil
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )
        try OneDriveFolderSyncProvider(rootURL: rootURL).saveFileSnapshot(originalSnapshot, deviceID: "device-a")
        let failingProvider = OneDriveFolderSyncProvider(
            rootURL: rootURL,
            fileManager: MoveFailingFileManager(failingDestinationExtension: "json")
        )

        #expect(throws: Error.self) {
            try failingProvider.saveFileSnapshot(replacementSnapshot, deviceID: "device-a")
        }

        let loaded = try #require(OneDriveFolderSyncProvider(rootURL: rootURL)
            .loadFileSnapshots(excludingDeviceID: "device-b")
            .first)
        #expect(loaded.histories == originalSnapshot.histories)
        let assetURLs = FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/device-a/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []
        #expect(!assetURLs.contains { $0.path.contains("history-replacement") })
    }

    @Test
    func oneDriveFolderSyncProviderPreservesPreviousFileWhenReplacementFails() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "device-a",
                    historyID: "history-1",
                    updatedAt: 10,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .pdf,
                            data: Data("stable".utf8),
                            originalFilename: nil
                        )
                    ]
                )
            ],
            skippedAssetCount: 0
        )
        try OneDriveFolderSyncProvider(rootURL: rootURL).saveFileSnapshot(snapshot, deviceID: "device-a")
        let failingProvider = OneDriveFolderSyncProvider(
            rootURL: rootURL,
            fileManager: MoveFailingFileManager(failingDestinationExtension: "pdf")
        )

        try failingProvider.saveFileSnapshot(snapshot, deviceID: "device-a")

        let loaded = try #require(OneDriveFolderSyncProvider(rootURL: rootURL)
            .loadFileSnapshots(excludingDeviceID: "device-b")
            .first)
        #expect(loaded.histories == snapshot.histories)
        #expect(loaded.skippedAssetCount == 0)
    }

    @Test
    func oneDriveFolderSyncProviderSkipsCorruptSQLiteSnapshots() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let historyDirectory = rootURL.appendingPathComponent("history/devices", isDirectory: true)
        let snippetDirectory = rootURL.appendingPathComponent("snippets/devices", isDirectory: true)
        let fileDirectory = rootURL.appendingPathComponent("files/devices", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snippetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
        try Data("not sqlite".utf8).write(to: historyDirectory.appendingPathComponent("remote.sqlite"))
        try Data("not sqlite".utf8).write(to: snippetDirectory.appendingPathComponent("remote.sqlite"))
        try Data("not sqlite".utf8).write(to: fileDirectory.appendingPathComponent("remote.sqlite"))

        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "device-a").isEmpty)
        #expect(try provider.loadSnippetSnapshots(excludingDeviceID: "device-a").isEmpty)
        #expect(try provider.loadFileSnapshots(excludingDeviceID: "device-a").isEmpty)
    }
}

@MainActor
@Suite
struct OneDriveFolderSyncProviderDirectoryTests {
    @Test
    func usesSelectedFolderAsSyncRoot() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let history = PasteboardHistorySyncPayload(
            id: "history-1",
            text: "History",
            updateAt: 1,
            deviceID: "device-a",
            sourceKind: .plainText
        )

        try provider.saveHistorySnapshot(
            [history],
            deviceID: "device:a/with\\bad*chars?",
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 8 * 1024 * 1024
        )

        #expect(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("history/devices/device-a-with-bad-chars.sqlite").path
        ))
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("manifest.json").path))
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("histories").path))
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("PasteraSync").path))
    }
}

private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

private final class MoveFailingFileManager: FileManager {
    private let failingDestinationExtension: String

    init(failingDestinationExtension: String) {
        self.failingDestinationExtension = failingDestinationExtension
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL.pathExtension == failingDestinationExtension {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

private func stableSnippetSnapshot(content: String = "stable") -> SnippetSyncSnapshot {
    SnippetSyncSnapshot(
        folders: [
            .init(id: "folder-b", title: "B", index: 1, isEnabled: true, updatedAt: 10, deviceID: "device-a"),
            .init(id: "folder-a", title: "A", index: 0, isEnabled: true, updatedAt: 10, deviceID: "device-a")
        ],
        snippets: [
            .init(id: "snippet-a", folderID: "folder-a", title: "Snippet", content: content,
                  index: 0, isEnabled: true, updatedAt: 10, deviceID: "device-a")
        ],
        deletedFolders: [
            .init(id: "deleted-folder-b", title: "B", deletedAt: 30, deviceID: "device-a"),
            .init(id: "deleted-folder-a", title: "A", deletedAt: 20, deviceID: "device-a")
        ],
        deletedSnippets: [
            .init(id: "deleted-snippet-b", folderID: "folder-b", folderTitle: "B", content: "old B",
                  deletedAt: 30, deviceID: "device-a"),
            .init(id: "deleted-snippet-a", folderID: "folder-a", folderTitle: "A", content: "old A",
                  deletedAt: 20, deviceID: "device-a")
        ]
    )
}

private func stableFileSnapshot(updatedAt: Int = 10) -> FileSyncExportSnapshot {
    FileSyncExportSnapshot(
        histories: [
            .init(deviceID: "device-a", historyID: "history-1", updatedAt: updatedAt, assets: [
                .init(assetIndex: 0, pasteboardType: .pdf, data: Data("%PDF stable".utf8),
                      originalFilename: "document.pdf")
            ])
        ],
        skippedAssetCount: 0
    )
}

private func legacyLengthPrefixedHash(for assets: [PasteboardContent.Asset]) -> String {
    var data = Data()
    assets.forEach { asset in
        data.append(lengthPrefixed: Data(asset.type.rawValue.utf8))
        data.append(lengthPrefixed: asset.data)
    }
    return SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func makeImageData(_ image: NSImage, type: NSBitmapImageRep.FileType) throws -> Data {
    let tiffData = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiffData))
    return try #require(bitmap.representation(using: type, properties: [:]))
}

private func makeNoisyImage(width: Int, height: Int) throws -> NSImage {
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

private func makeScreenshotLikeImage(width: Int, height: Int) throws -> NSImage {
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

private func writeTemporaryImage(data: Data, extension pathExtension: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("image").appendingPathExtension(pathExtension)
    try data.write(to: url)
    return url
}

private func writeTemporaryFile(name: String, data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

private extension Data {
    mutating func append(lengthPrefixed value: Data) {
        var length = UInt64(value.count).bigEndian
        Swift.withUnsafeBytes(of: &length) {
            append(contentsOf: $0)
        }
        append(value)
    }
}
