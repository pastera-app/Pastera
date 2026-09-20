//
//  PasteboardContent.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/28.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa
import CryptoKit
import ImageIO
import SQLite3
import SwiftHEXColors
import UniformTypeIdentifiers

// swiftlint:disable type_body_length file_length

struct PasteboardContent: Equatable {
    struct Asset: Equatable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    // MARK: - Properties
    let types: [NSPasteboard.PasteboardType]
    let assets: [Asset]
    let hash: String

    var isOnlyStringType: Bool {
        types == [.string] || types == [.deprecatedString]
    }
    var stringValue: String {
        guard let data = data(for: .string) ?? data(for: .deprecatedString) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    var historyTitle: String {
        let text = stringValue
        if !text.isEmpty { return text }
        return fileURLHistoryTitle ?? ""
    }
    var colorCodeImage: NSImage? {
        guard let color = NSColor(hexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
    }
    var thumbnailImage: NSImage? {
        let defaults = UserDefaults.standard
        let width = max(
            defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth),
            Constants.Thumbnail.hoverPreviewPixelWidth
        )
        let height = max(
            defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight),
            Constants.Thumbnail.hoverPreviewPixelHeight
        )

        let imageURL = assets.filter { $0.type == .fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
            .first(where: {
                PasteraFilePreviewKind.isEnabled(.image)
                    && PasteraFileTypeClassifier.kind(for: $0) == .image
            })
        if let imageURL {
            return PasteraImageEncoding.thumbnailImage(
                from: imageURL,
                maxPixelWidth: width,
                maxPixelHeight: height
            )
        } else if let data = assets.first(where: { $0.type.isClipyImageType })?.data {
            return PasteraImageEncoding.thumbnailImage(
                from: data,
                maxPixelWidth: width,
                maxPixelHeight: height
            )
        }
        return nil
    }

    // MARK: - Initialize
    init(assets: [Asset]) {
        self.types = assets.map(\.type)
        self.assets = assets
        var hasher = SHA256()
        assets.forEach { asset in
            hasher.update(lengthPrefixed: Data(asset.type.rawValue.utf8))
            hasher.update(lengthPrefixed: asset.data)
        }
        self.hash = hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    init?(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        let assets = pasteboard.pasteboardItems?.compactMap { item -> [Asset]? in
            item.types.filter { types.contains($0) }
                .compactMap { type -> Asset? in
                    guard let data = item.data(forType: type) else { return nil }
                    return Asset(type: type, data: data)
                }
        }
        .flatMap { $0 }
        guard let assets, !assets.isEmpty else { return nil }
        self.init(assets: assets)
    }

    init?(image: NSImage) {
        guard let data = image.tiffRepresentation else { return nil }
        self.init(assets: [Asset(type: .tiff, data: data)])
    }

    init?(imageFileURL url: URL) {
        guard let sourceData = try? Data(contentsOf: url),
              let image = NSImage(data: sourceData)
        else { return nil }

        if url.pathExtension.lowercased() == "png" {
            self.init(assets: [Asset(type: .png, data: sourceData)])
        } else if let pngData = PasteraImageEncoding.pngData(from: image) {
            self.init(assets: [Asset(type: .png, data: pngData)])
        } else if let tiffData = image.tiffRepresentation {
            self.init(assets: [Asset(type: .tiff, data: tiffData)])
        } else {
            return nil
        }
    }
}

private extension PasteboardContent {
    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        assets.first(where: { $0.type == type })?.data
    }

    var fileURLs: [URL] {
        assets.filter { $0.type == .fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
    }

    var fileURLHistoryTitle: String? {
        guard let url = fileURLs.first else { return nil }
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty else { return nil }

        if PasteraFileTypeClassifier.kind(for: url) == .image {
            return url.lastPathComponent
        }

        guard let category = PasteraFinderFileCategory.category(for: url) else {
            return fileName
        }
        let previewKind = PasteraFilePreviewKind(finderFileCategory: category)
        guard category.supportsTextPreview,
              PasteraFilePreviewKind.isEnabled(previewKind),
              let preview = PasteraFileTypeClassifier.textPreview(from: url) else {
            return fileName
        }
        return "\(fileName)\n\(preview)"
    }
}

enum PasteraFinderFileCategory: String, CaseIterable, Hashable {
    case document
    case archive
    case code
    case other

    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers",
        "key", "txt", "rtf", "rtfd", "md", "csv"
    ]
    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "pkg"
    ]
    private static let codeExtensions: Set<String> = [
        "swift", "js", "ts", "tsx", "java", "kt", "py", "go", "rs", "c", "cpp",
        "h", "hpp", "cs", "rb", "php", "html", "css", "json", "xml", "yml",
        "yaml", "toml", "sql", "sh", "zsh"
    ]

    var title: String {
        switch self {
        case .document:
            return "文档"
        case .archive:
            return "压缩包"
        case .code:
            return "代码"
        case .other:
            return "其他"
        }
    }

    var symbolName: String {
        switch self {
        case .document:
            return "doc.text"
        case .archive:
            return "archivebox"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .other:
            return "doc"
        }
    }

    var supportsTextPreview: Bool {
        self == .document || self == .code
    }

    static func category(for url: URL) -> PasteraFinderFileCategory? {
        guard url.isFileURL, !PasteraFileTypeClassifier.isDirectory(url) else { return nil }
        return category(forFilename: url.lastPathComponent)
    }

    static func category(forFilename filename: String) -> PasteraFinderFileCategory {
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        if documentExtensions.contains(pathExtension) {
            return .document
        }
        if archiveExtensions.contains(pathExtension) {
            return .archive
        }
        if codeExtensions.contains(pathExtension) {
            return .code
        }
        return .other
    }

    static func category(forHistoryTitle title: String) -> PasteraFinderFileCategory {
        let fileName = title
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !fileName.isEmpty else { return .other }
        return category(forFilename: fileName)
    }

    func icon() -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: title)
        image?.isTemplate = true
        return image
    }
}

enum PasteraFilePreviewKind: String, CaseIterable {
    case image
    case document
    case archive
    case code
    case other

    init(finderFileCategory category: PasteraFinderFileCategory) {
        switch category {
        case .document:
            self = .document
        case .archive:
            self = .archive
        case .code:
            self = .code
        case .other:
            self = .other
        }
    }

    static func defaultStates() -> [String: NSNumber] {
        allCases.reduce(into: [String: NSNumber]()) { states, kind in
            states[kind.rawValue] = NSNumber(value: true)
        }
    }

    static func isEnabled(_ kind: PasteraFilePreviewKind, defaults: UserDefaults = AppEnvironment.current.defaults) -> Bool {
        let values = defaults.object(forKey: Constants.UserDefaults.filePreviewTypes) as? [String: Any] ?? [:]
        if let number = values[kind.rawValue] as? NSNumber {
            return number.boolValue
        }
        if let bool = values[kind.rawValue] as? Bool {
            return bool
        }
        return true
    }

    static func states(defaults: UserDefaults = AppEnvironment.current.defaults) -> [String: NSNumber] {
        let values = defaults.object(forKey: Constants.UserDefaults.filePreviewTypes) as? [String: Any] ?? [:]
        return allCases.reduce(into: [String: NSNumber]()) { result, kind in
            if let number = values[kind.rawValue] as? NSNumber {
                result[kind.rawValue] = number
            } else if let bool = values[kind.rawValue] as? Bool {
                result[kind.rawValue] = NSNumber(value: bool)
            } else {
                result[kind.rawValue] = NSNumber(value: true)
            }
        }
    }
}

enum PasteraFileTypeClassifier {
    private static let textPreviewMaxBytes = 256 * 1024

    static func kind(for url: URL) -> PasteraFilePreviewKind? {
        guard url.isFileURL, !isDirectory(url) else { return nil }
        if isImageFile(url) {
            return .image
        }
        if let category = PasteraFinderFileCategory.category(for: url) {
            return PasteraFilePreviewKind(finderFileCategory: category)
        }
        return nil
    }

    static func textPreview(from url: URL, maxBytes: Int = textPreviewMaxBytes) -> String? {
        guard url.isFileURL, maxBytes > 0, !isDirectory(url),
              let data = readPrefix(from: url, maxBytes: maxBytes),
              !data.isEmpty,
              !looksBinary(data),
              let text = decodeText(data) else {
            return nil
        }
        let preview = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? nil : preview
    }

    static func canCreateImageThumbnail(from url: URL) -> Bool {
        PasteraImageEncoding.thumbnailImage(from: url, maxPixelWidth: 64, maxPixelHeight: 64) != nil
    }

    private static func isImageFile(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
            return true
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    fileprivate static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func readPrefix(from url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes)
    }

    private static func looksBinary(_ data: Data) -> Bool {
        if data.contains(0) {
            return true
        }
        let allowedControls: Set<UInt8> = [0x09, 0x0A, 0x0D]
        let controlCount = data.reduce(0) { count, byte in
            byte < 0x20 && !allowedControls.contains(byte) ? count + 1 : count
        }
        return controlCount > max(2, data.count / 20)
    }

    private static func decodeText(_ data: Data) -> String? {
        [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]
            .lazy
            .compactMap { String(data: data, encoding: $0) }
            .first
    }
}

private extension SHA256 {
    mutating func update(lengthPrefixed data: Data) {
        var length = UInt64(data.count).bigEndian
        let lengthData = Swift.withUnsafeBytes(of: &length) { Data($0) }
        update(data: lengthData)
        update(data: data)
    }
}

enum PasteraImageEncoding {
    static func thumbnailImage(from url: URL, maxPixelWidth: Int, maxPixelHeight: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        return thumbnailImage(from: source, maxPixelWidth: maxPixelWidth, maxPixelHeight: maxPixelHeight)
    }

    static func thumbnailImage(from data: Data, maxPixelWidth: Int, maxPixelHeight: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        return thumbnailImage(from: source, maxPixelWidth: maxPixelWidth, maxPixelHeight: maxPixelHeight)
    }

    static func pngData(from image: NSImage) -> Data? {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                return pngData
            }
        }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func pngData(from image: NSImage, maxBytes: Int) -> Data? {
        guard maxBytes > 0 else { return pngData(from: image) }
        var candidate = image
        var candidateData = pngData(from: candidate)
        while let data = candidateData,
              data.count > maxBytes,
              let downsizedImage = downsizedImage(from: candidate) {
            candidate = downsizedImage
            candidateData = pngData(from: candidate)
        }
        return candidateData
    }

    private static func downsizedImage(from image: NSImage) -> NSImage? {
        guard let pixelSize = bitmapPixelSize(of: image),
              pixelSize.width > 32 || pixelSize.height > 32 else {
            return nil
        }

        let nextWidth = max(1, Int((CGFloat(pixelSize.width) * 0.85).rounded(.down)))
        let nextHeight = max(1, Int((CGFloat(pixelSize.height) * 0.85).rounded(.down)))
        guard nextWidth < pixelSize.width || nextHeight < pixelSize.height else { return nil }
        return image.resizeImage(CGFloat(nextWidth), CGFloat(nextHeight))
    }

    private static func bitmapPixelSize(of image: NSImage) -> (width: Int, height: Int)? {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return (bitmap.pixelsWide, bitmap.pixelsHigh)
        }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return (cgImage.width, cgImage.height)
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        return (Int(size.width.rounded()), Int(size.height.rounded()))
    }

    private static func thumbnailImage(
        from source: CGImageSource,
        maxPixelWidth: Int,
        maxPixelHeight: Int
    ) -> NSImage? {
        guard maxPixelWidth > 0,
              maxPixelHeight > 0,
              let sourcePixelSize = imagePixelSize(of: source) else {
            return nil
        }

        let maxPixelLength = fittingMaxPixelLength(
            sourcePixelSize: sourcePixelSize,
            maxPixelWidth: maxPixelWidth,
            maxPixelHeight: maxPixelHeight
        )
        guard maxPixelLength > 0 else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelLength
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        return image.resizeImage(CGFloat(cgImage.width), CGFloat(cgImage.height)) ?? image
    }

    private static func imagePixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0,
              height.intValue > 0 else {
            return nil
        }
        return (width.intValue, height.intValue)
    }

    private static func fittingMaxPixelLength(
        sourcePixelSize: (width: Int, height: Int),
        maxPixelWidth: Int,
        maxPixelHeight: Int
    ) -> Int {
        let sourceAspect = CGFloat(sourcePixelSize.width) / CGFloat(sourcePixelSize.height)
        let targetAspect = CGFloat(maxPixelWidth) / CGFloat(maxPixelHeight)
        return sourceAspect >= targetAspect ? maxPixelWidth : maxPixelHeight
    }
}

enum SyncEntityKind: String, Codable {
    case history
    case snippet
    case snippetFolder
}

struct HistorySyncSnapshot: Equatable {
    let deviceID: String
    let payloads: [PasteboardHistorySyncPayload]
}

struct HistoryWindowSignature: Equatable, Codable {
    let rawValue: String

    static func make(
        payloads: [PasteboardHistorySyncPayload],
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) -> HistoryWindowSignature {
        var hasher = SHA256()
        [
            "v4",
            "\(limit)",
            "\(maxTextBytes)",
            "\(snapshotTextBudgetBytes)",
            "\(payloads.count)"
        ].forEach { hasher.update(lengthPrefixed: Data($0.utf8)) }
        for payload in payloads {
            [
                payload.id,
                "\(payload.updateAt)",
                payload.sourceKind.rawValue,
                "\(payload.textByteCount)"
            ].forEach { hasher.update(lengthPrefixed: Data($0.utf8)) }
        }
        return HistoryWindowSignature(
            rawValue: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }
}

struct HistoryRemoteSnapshotState: Equatable {
    let deviceID: String
    let url: URL
    let byteCount: Int
    let modifiedAtNanoseconds: Int64

    var cacheKey: String {
        url.standardizedFileURL.path
    }
}

struct SnippetDeviceSyncSnapshot: Equatable {
    let deviceID: String
    let snapshot: SnippetSyncSnapshot
}

struct FileSyncAssetPayload: Equatable {
    let assetIndex: Int
    let pasteboardType: NSPasteboard.PasteboardType
    let data: Data
    let originalFilename: String?
    let byteCountOverride: Int?
    let modifiedAtNanoseconds: Int64?

    init(
        assetIndex: Int,
        pasteboardType: NSPasteboard.PasteboardType,
        data: Data,
        originalFilename: String?,
        byteCount: Int? = nil,
        modifiedAtNanoseconds: Int64? = nil
    ) {
        self.assetIndex = assetIndex
        self.pasteboardType = pasteboardType
        self.data = data
        self.originalFilename = originalFilename
        self.byteCountOverride = byteCount
        self.modifiedAtNanoseconds = modifiedAtNanoseconds
    }

    var byteCount: Int {
        byteCountOverride ?? data.count
    }

    static func == (lhs: FileSyncAssetPayload, rhs: FileSyncAssetPayload) -> Bool {
        lhs.assetIndex == rhs.assetIndex
            && lhs.pasteboardType == rhs.pasteboardType
            && lhs.data == rhs.data
            && lhs.originalFilename == rhs.originalFilename
            && lhs.byteCount == rhs.byteCount
            && lhs.modifiedAtNanoseconds == rhs.modifiedAtNanoseconds
    }
}

struct FileSyncHistoryPayload: Equatable {
    let deviceID: String?
    let historyID: String
    let updatedAt: Int
    let assets: [FileSyncAssetPayload]

    var assetCount: Int {
        assets.count
    }
}

struct FileSyncExportSnapshot: Equatable {
    let histories: [FileSyncHistoryPayload]
    let skippedAssetCount: Int

    var assetCount: Int {
        histories.reduce(0) { $0 + $1.assetCount }
    }
}

struct FileDeviceSyncSnapshot: Equatable {
    let deviceID: String
    let histories: [FileSyncHistoryPayload]
    let skippedAssetCount: Int
}

struct FileDeviceSyncLoadResult: Equatable {
    let snapshots: [FileDeviceSyncSnapshot]
    let skippedManifestCount: Int
    var skippedAssetCount: Int { snapshots.reduce(0) { $0 + $1.skippedAssetCount } }
}

enum SyncSQLiteError: LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case missingMetadata(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "无法打开同步数据库：\(message)"
        case .executeFailed(let message):
            return "无法写入同步数据库：\(message)"
        case .prepareFailed(let message):
            return "无法准备同步数据库查询：\(message)"
        case .stepFailed(let message):
            return "无法读取同步数据库：\(message)"
        case .missingMetadata(let key):
            return "同步数据库缺少元数据：\(key)"
        }
    }
}

final class OneDriveFolderSyncProvider {
    private static let historyProtocolVersion = 4

    private let rootURL: URL
    private let fileManager: FileManager

    private struct HistoryProtocolManifest: Codable {
        let schemaVersion: Int
        let generatedAt: Int
    }

    private struct FileDirectoryManifest: Codable {
        let manifestVersion: Int
        let schemaVersion: Int
        let deviceID: String
        let generatedAt: Int
        let assetCount: Int
        let histories: [FileDirectoryHistory]
    }

    private struct FileDirectoryHistory: Codable {
        let historyID: String
        let updatedAt: Int
        let assets: [FileDirectoryAsset]
    }

    private struct FileDirectoryAsset: Codable {
        let assetIndex: Int
        let pasteboardType: String
        let byteCount: Int
        let modifiedAtNanoseconds: Int64?
        let relativePath: String
        let originalFilename: String?
    }

    private struct FileSnapshotLoadOptions {
        let excludedDeviceID: String?
        let includedFileTypes: Set<PasteboardAvailableType>
        let maxFileBytes: Int
        let maxAssetsPerDevice: Int
        let shouldImportHistory: ((String, Int) -> Bool)?
    }

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func saveHistorySnapshot(
        _ payloads: [PasteboardHistorySyncPayload],
        deviceID: String,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) throws {
        try removeLegacyV1Paths()
        try ensureHistoryProtocol()
        let destinationURL = historyDevicesURL.appendingPathComponent(fileName(for: deviceID))
        let sortedPayloads = Array(payloads
            .sorted {
                if $0.updateAt == $1.updateAt {
                    return $0.id < $1.id
                }
                return $0.updateAt > $1.updateAt
            }
            .prefix(max(0, limit)))
        let windowSignature = HistoryWindowSignature.make(
            payloads: sortedPayloads,
            limit: limit,
            maxTextBytes: maxTextBytes,
            snapshotTextBudgetBytes: snapshotTextBudgetBytes
        )
        try writeSQLiteSnapshot(to: destinationURL) { database in
            try database.execute("""
                CREATE TABLE metadata (
                  key TEXT PRIMARY KEY NOT NULL,
                  value TEXT NOT NULL
                );
                CREATE TABLE histories (
                  id TEXT PRIMARY KEY NOT NULL,
                  updatedAt INTEGER NOT NULL,
                  sourceKind TEXT NOT NULL,
                  text TEXT NOT NULL
                );
                CREATE INDEX histories_updatedAt_index ON histories(updatedAt DESC);
                """)
            try writeMetadata([
                "schemaVersion": "\(Self.historyProtocolVersion)",
                "deviceID": deviceID,
                "platform": "macOS",
                "generatedAt": "\(Int(Date().timeIntervalSince1970))",
                "historyLimit": "\(limit)",
                "maxTextBytes": "\(maxTextBytes)",
                "snapshotTextBudgetBytes": "\(snapshotTextBudgetBytes)",
                "windowSignature": windowSignature.rawValue
            ], database: database)
            let historyStatement = try database.prepare(
                "INSERT INTO histories(id, updatedAt, sourceKind, text) VALUES (?, ?, ?, ?)"
            )
            for payload in sortedPayloads {
                try historyStatement.reset()
                try historyStatement.bind(payload.id, at: 1)
                try historyStatement.bind(payload.updateAt, at: 2)
                try historyStatement.bind(payload.sourceKind.rawValue, at: 3)
                try historyStatement.bind(payload.text, at: 4)
                try historyStatement.stepToCompletion()
            }
        }
    }

    func loadHistorySnapshots(excludingDeviceID deviceID: String) throws -> [HistorySyncSnapshot] {
        try ensureHistoryProtocol()
        return try loadHistorySnapshots(
            from: historySnapshotFileStates(excludingDeviceID: deviceID),
            excludingDeviceID: deviceID
        )
    }

    func loadHistorySnapshots(
        from states: [HistoryRemoteSnapshotState],
        excludingDeviceID deviceID: String
    ) throws -> [HistorySyncSnapshot] {
        states.compactMap { state in
            let url = state.url
            guard let snapshot = try? loadHistorySnapshot(at: url), snapshot.deviceID != deviceID else {
                return nil
            }
            return snapshot
        }
    }

    func historySnapshotExists(deviceID: String) -> Bool {
        fileManager.fileExists(atPath: historyDevicesURL.appendingPathComponent(fileName(for: deviceID)).path)
    }

    func historySnapshotFileStates(excludingDeviceID deviceID: String) throws -> [HistoryRemoteSnapshotState] {
        try ensureHistoryProtocol()
        let excludedFileName = fileName(for: deviceID)
        return try loadSQLiteFiles(in: historyDevicesURL).compactMap { url in
            guard url.lastPathComponent != excludedFileName,
                  let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                return nil
            }
            let modifiedAt = attributes[.modificationDate] as? Date
            return HistoryRemoteSnapshotState(
                deviceID: url.deletingPathExtension().lastPathComponent,
                url: url,
                byteCount: size.intValue,
                modifiedAtNanoseconds: modifiedAt.map(Self.nanosecondsSince1970) ?? 0
            )
        }
    }

    func saveSnippetSnapshot(_ snapshot: SnippetSyncSnapshot, deviceID: String) throws {
        try removeLegacyV1Paths()
        let destinationURL = snippetDevicesURL.appendingPathComponent(fileName(for: deviceID))
        try writeSQLiteSnapshot(to: destinationURL) { database in
            try database.execute("""
                CREATE TABLE metadata (
                  key TEXT PRIMARY KEY NOT NULL,
                  value TEXT NOT NULL
                );
                CREATE TABLE folders (
                  id TEXT PRIMARY KEY NOT NULL,
                  title TEXT NOT NULL,
                  displayIndex INTEGER NOT NULL,
                  isEnabled INTEGER NOT NULL,
                  updatedAt INTEGER NOT NULL,
                  lastModifiedDeviceID TEXT
                );
                CREATE TABLE snippets (
                  id TEXT PRIMARY KEY NOT NULL,
                  folderID TEXT NOT NULL,
                  title TEXT NOT NULL,
                  content TEXT NOT NULL,
                  displayIndex INTEGER NOT NULL,
                  isEnabled INTEGER NOT NULL,
                  updatedAt INTEGER NOT NULL,
                  lastModifiedDeviceID TEXT
                );
                CREATE TABLE deletedFolders (
                  id TEXT PRIMARY KEY NOT NULL,
                  title TEXT NOT NULL,
                  deletedAt INTEGER NOT NULL,
                  deviceID TEXT
                );
                CREATE TABLE deletedSnippets (
                  id TEXT PRIMARY KEY NOT NULL,
                  folderID TEXT NOT NULL,
                  folderTitle TEXT NOT NULL,
                  content TEXT NOT NULL,
                  deletedAt INTEGER NOT NULL,
                  deviceID TEXT
                );
                """)
            try writeMetadata([
                "schemaVersion": "3",
                "deviceID": deviceID,
                "generatedAt": "\(Int(Date().timeIntervalSince1970))"
            ], database: database)
            let folderStatement = try database.prepare("""
                INSERT INTO folders(id, title, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            let snippetStatement = try database.prepare("""
                INSERT INTO snippets(id, folderID, title, content, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            let deletedFolderStatement = try database.prepare("""
                INSERT INTO deletedFolders(id, title, deletedAt, deviceID)
                VALUES (?, ?, ?, ?)
                """)
            let deletedSnippetStatement = try database.prepare("""
                INSERT INTO deletedSnippets(id, folderID, folderTitle, content, deletedAt, deviceID)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            for folder in snapshot.folders {
                try folderStatement.reset()
                try folderStatement.bind(folder.id, at: 1)
                try folderStatement.bind(folder.title, at: 2)
                try folderStatement.bind(folder.index, at: 3)
                try folderStatement.bind(folder.isEnabled, at: 4)
                try folderStatement.bind(folder.updatedAt, at: 5)
                try folderStatement.bind(folder.deviceID, at: 6)
                try folderStatement.stepToCompletion()
            }
            for snippet in snapshot.snippets {
                try snippetStatement.reset()
                try snippetStatement.bind(snippet.id, at: 1)
                try snippetStatement.bind(snippet.folderID, at: 2)
                try snippetStatement.bind(snippet.title, at: 3)
                try snippetStatement.bind(snippet.content, at: 4)
                try snippetStatement.bind(snippet.index, at: 5)
                try snippetStatement.bind(snippet.isEnabled, at: 6)
                try snippetStatement.bind(snippet.updatedAt, at: 7)
                try snippetStatement.bind(snippet.deviceID, at: 8)
                try snippetStatement.stepToCompletion()
            }
            for folder in snapshot.deletedFolders {
                try deletedFolderStatement.reset()
                try deletedFolderStatement.bind(folder.id, at: 1)
                try deletedFolderStatement.bind(folder.title, at: 2)
                try deletedFolderStatement.bind(folder.deletedAt, at: 3)
                try deletedFolderStatement.bind(folder.deviceID, at: 4)
                try deletedFolderStatement.stepToCompletion()
            }
            for snippet in snapshot.deletedSnippets {
                try deletedSnippetStatement.reset()
                try deletedSnippetStatement.bind(snippet.id, at: 1)
                try deletedSnippetStatement.bind(snippet.folderID, at: 2)
                try deletedSnippetStatement.bind(snippet.folderTitle, at: 3)
                try deletedSnippetStatement.bind(snippet.content, at: 4)
                try deletedSnippetStatement.bind(snippet.deletedAt, at: 5)
                try deletedSnippetStatement.bind(snippet.deviceID, at: 6)
                try deletedSnippetStatement.stepToCompletion()
            }
        }
    }

    func loadSnippetSnapshots(excludingDeviceID deviceID: String) throws -> [SnippetDeviceSyncSnapshot] {
        try loadSQLiteFiles(in: snippetDevicesURL).compactMap { url in
            guard let snapshot = try? loadSnippetSnapshot(at: url), snapshot.deviceID != deviceID else {
                return nil
            }
            return snapshot
        }
    }

    func saveFileSnapshot(_ snapshot: FileSyncExportSnapshot, deviceID: String) throws {
        try removeLegacyV1Paths()
        let deviceDirectoryName = safePathComponent(for: deviceID)
        let deviceDirectoryURL = fileDevicesURL.appendingPathComponent(deviceDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: deviceDirectoryURL, withIntermediateDirectories: true)

        let previousRelativePaths = existingDirectFileRelativePaths(in: deviceDirectoryURL)
        var writtenNewRelativePaths = Set<String>()
        do {
            var manifestHistories = [FileDirectoryHistory]()
            var manifestAssetCount = 0
            var keptRelativePaths = Set<String>()
            for history in snapshot.histories.sorted(by: fileHistorySort) {
                let sortedAssets = history.assets.sorted(by: { $0.assetIndex < $1.assetIndex })
                guard sortedAssets.allSatisfy({ PasteboardAvailableType.syncFileType(for: $0.pasteboardType) != nil }) else {
                    continue
                }
                var manifestAssets = [FileDirectoryAsset]()
                for asset in sortedAssets {
                    let relativePath = fileAssetRelativePath(
                        historyID: history.historyID,
                        updatedAt: history.updatedAt,
                        asset: asset
                    )
                    let objectURL = deviceDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
                    let didWrite = try writeFileAssetIfNeeded(
                        asset,
                        to: objectURL,
                        expectedByteCount: asset.byteCount
                    )
                    if didWrite, !previousRelativePaths.contains(relativePath) {
                        writtenNewRelativePaths.insert(relativePath)
                    }
                    keptRelativePaths.insert(relativePath)
                    manifestAssets.append(FileDirectoryAsset(
                        assetIndex: asset.assetIndex,
                        pasteboardType: asset.pasteboardType.rawValue,
                        byteCount: asset.byteCount,
                        modifiedAtNanoseconds: asset.modifiedAtNanoseconds,
                        relativePath: relativePath,
                        originalFilename: asset.originalFilename
                    ))
                }
                manifestAssetCount += manifestAssets.count
                manifestHistories.append(FileDirectoryHistory(
                    historyID: history.historyID,
                    updatedAt: history.updatedAt,
                    assets: manifestAssets
                ))
            }

            let manifest = FileDirectoryManifest(
                manifestVersion: 1,
                schemaVersion: 1,
                deviceID: deviceID,
                generatedAt: Int(Date().timeIntervalSince1970),
                assetCount: manifestAssetCount,
                histories: manifestHistories
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try writeFileDataAtomically(encoder.encode(manifest), to: fileManifestURL(for: deviceID))
            try pruneDirectFileAssets(in: deviceDirectoryURL, keeping: keptRelativePaths)
            try removeLegacyFileDevicePaths(for: deviceID)
        } catch {
            removeDirectFileAssets(in: deviceDirectoryURL, relativePaths: writtenNewRelativePaths)
            try? pruneDirectFileAssets(in: deviceDirectoryURL, keeping: previousRelativePaths)
            throw error
        }
    }

    func loadFileSnapshots(excludingDeviceID deviceID: String) throws -> [FileDeviceSyncSnapshot] {
        try loadFileSnapshotResult(
            excludingDeviceID: deviceID,
            includedFileTypes: Set(PasteboardAvailableType.syncFileTypes),
            maxFileBytes: 25 * 1024 * 1024,
            maxAssetsPerDevice: 10
        ).snapshots
    }

    func loadFileSnapshotResult(
        excludingDeviceID deviceID: String,
        includedFileTypes: Set<PasteboardAvailableType>,
        maxFileBytes: Int,
        maxAssetsPerDevice: Int = 10,
        shouldImportHistory: ((String, Int) -> Bool)? = nil
    ) throws -> FileDeviceSyncLoadResult {
        var snapshots = [FileDeviceSyncSnapshot]()
        var skippedManifestCount = 0
        for url in try loadFileDeviceDirectories(in: fileDevicesURL) {
            do {
                if let snapshot = try loadFileSnapshot(
                    at: url,
                    options: FileSnapshotLoadOptions(
                        excludedDeviceID: deviceID,
                        includedFileTypes: includedFileTypes,
                        maxFileBytes: maxFileBytes,
                        maxAssetsPerDevice: maxAssetsPerDevice,
                        shouldImportHistory: shouldImportHistory
                    )
                ) {
                    snapshots.append(snapshot)
                }
            } catch {
                skippedManifestCount += 1
            }
        }
        return FileDeviceSyncLoadResult(snapshots: snapshots, skippedManifestCount: skippedManifestCount)
    }

    func loadHistorySnapshot(at url: URL) throws -> HistorySyncSnapshot {
        let database = try SyncSQLiteDatabase(url: url)
        let metadata = try readMetadata(database: database)
        guard metadata["schemaVersion"] == "\(Self.historyProtocolVersion)" else {
            throw SyncSQLiteError.missingMetadata("schemaVersion")
        }
        guard let deviceID = metadata["deviceID"] else { throw SyncSQLiteError.missingMetadata("deviceID") }
        let statement = try database.prepare(
            "SELECT id, updatedAt, sourceKind, text FROM histories ORDER BY updatedAt DESC, id ASC"
        )
        var payloads = [PasteboardHistorySyncPayload]()
        while try statement.step() {
            guard let sourceKind = HistoryTextSourceKind(rawValue: statement.columnString(at: 2)) else {
                continue
            }
            let payload = PasteboardHistorySyncPayload(
                id: statement.columnString(at: 0),
                text: statement.columnString(at: 3),
                updateAt: statement.columnInt(at: 1),
                deviceID: deviceID,
                sourceKind: sourceKind
            )
            payloads.append(payload)
        }
        return HistorySyncSnapshot(deviceID: deviceID, payloads: payloads)
    }

    private func loadSnippetSnapshot(at url: URL) throws -> SnippetDeviceSyncSnapshot {
        let database = try SyncSQLiteDatabase(url: url)
        let metadata = try readMetadata(database: database)
        guard let schemaVersion = metadata["schemaVersion"],
              ["2", "3"].contains(schemaVersion) else {
            throw SyncSQLiteError.missingMetadata("schemaVersion")
        }
        guard let deviceID = metadata["deviceID"] else { throw SyncSQLiteError.missingMetadata("deviceID") }
        let foldersStatement = try database.prepare("""
            SELECT id, title, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID
            FROM folders
            ORDER BY displayIndex ASC, id ASC
            """)
        var folders = [SnippetFolderSyncPayload]()
        while try foldersStatement.step() {
            folders.append(SnippetFolderSyncPayload(
                id: foldersStatement.columnString(at: 0),
                title: foldersStatement.columnString(at: 1),
                index: foldersStatement.columnInt(at: 2),
                isEnabled: foldersStatement.columnBool(at: 3),
                updatedAt: foldersStatement.columnInt(at: 4),
                deviceID: foldersStatement.columnOptionalString(at: 5)
            ))
        }
        let snippetsStatement = try database.prepare("""
            SELECT id, folderID, title, content, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID
            FROM snippets
            ORDER BY displayIndex ASC, id ASC
            """)
        var snippets = [SnippetSyncPayload]()
        while try snippetsStatement.step() {
            snippets.append(SnippetSyncPayload(
                id: snippetsStatement.columnString(at: 0),
                folderID: snippetsStatement.columnString(at: 1),
                title: snippetsStatement.columnString(at: 2),
                content: snippetsStatement.columnString(at: 3),
                index: snippetsStatement.columnInt(at: 4),
                isEnabled: snippetsStatement.columnBool(at: 5),
                updatedAt: snippetsStatement.columnInt(at: 6),
                deviceID: snippetsStatement.columnOptionalString(at: 7)
            ))
        }
        var deletedFolders = [SnippetFolderDeletionSyncPayload]()
        var deletedSnippets = [SnippetDeletionSyncPayload]()
        if schemaVersion == "3" {
            let deletedFoldersStatement = try database.prepare("""
                SELECT id, title, deletedAt, deviceID
                FROM deletedFolders
                ORDER BY deletedAt ASC, id ASC
                """)
            while try deletedFoldersStatement.step() {
                deletedFolders.append(SnippetFolderDeletionSyncPayload(
                    id: deletedFoldersStatement.columnString(at: 0),
                    title: deletedFoldersStatement.columnString(at: 1),
                    deletedAt: deletedFoldersStatement.columnInt(at: 2),
                    deviceID: deletedFoldersStatement.columnOptionalString(at: 3)
                ))
            }
            let deletedSnippetsStatement = try database.prepare("""
                SELECT id, folderID, folderTitle, content, deletedAt, deviceID
                FROM deletedSnippets
                ORDER BY deletedAt ASC, id ASC
                """)
            while try deletedSnippetsStatement.step() {
                deletedSnippets.append(SnippetDeletionSyncPayload(
                    id: deletedSnippetsStatement.columnString(at: 0),
                    folderID: deletedSnippetsStatement.columnString(at: 1),
                    folderTitle: deletedSnippetsStatement.columnString(at: 2),
                    content: deletedSnippetsStatement.columnString(at: 3),
                    deletedAt: deletedSnippetsStatement.columnInt(at: 4),
                    deviceID: deletedSnippetsStatement.columnOptionalString(at: 5)
                ))
            }
        }
        return SnippetDeviceSyncSnapshot(
            deviceID: deviceID,
            snapshot: SnippetSyncSnapshot(
                folders: folders,
                snippets: snippets,
                deletedFolders: deletedFolders,
                deletedSnippets: deletedSnippets
            )
        )
    }

    private func loadFileSnapshot(
        at url: URL,
        options: FileSnapshotLoadOptions
    ) throws -> FileDeviceSyncSnapshot? {
        let manifestData = try Data(contentsOf: fileManifestURL(forDeviceDirectory: url))
        let manifest = try JSONDecoder().decode(FileDirectoryManifest.self, from: manifestData)
        guard manifest.manifestVersion == 1, manifest.schemaVersion == 1 else {
            throw SyncSQLiteError.missingMetadata("manifestVersion")
        }
        let deviceID = manifest.deviceID
        guard deviceID != options.excludedDeviceID else { return nil }
        var skippedAssetCount = 0
        let boundedMaxFileBytes = max(0, options.maxFileBytes)
        var remainingAssetSlots = max(0, options.maxAssetsPerDevice)
        let orderedHistories = manifest.histories.sorted(by: {
            if $0.updatedAt == $1.updatedAt {
                return $0.historyID < $1.historyID
            }
            return $0.updatedAt > $1.updatedAt
        })
        let histories = orderedHistories.compactMap { history -> FileSyncHistoryPayload? in
            guard options.shouldImportHistory?(history.historyID, history.updatedAt) ?? true else {
                return nil
            }
            let rows = history.assets.sorted(by: { $0.assetIndex < $1.assetIndex })
            guard rows.allSatisfy({
                let pasteboardType = NSPasteboard.PasteboardType(rawValue: $0.pasteboardType)
                guard let fileType = PasteboardAvailableType.syncFileType(for: pasteboardType) else {
                    return false
                }
                return options.includedFileTypes.contains(fileType)
            }) else {
                return nil
            }
            guard rows.allSatisfy({ $0.byteCount >= 0 && $0.byteCount <= boundedMaxFileBytes }) else {
                skippedAssetCount += rows.count
                return nil
            }
            guard rows.count <= remainingAssetSlots else {
                skippedAssetCount += rows.count
                return nil
            }
            var assets = [FileSyncAssetPayload]()
            for row in rows {
                guard let asset = loadFileAsset(
                    row,
                    deviceDirectoryURL: url,
                    maxFileBytes: boundedMaxFileBytes
                ) else {
                    skippedAssetCount += rows.count
                    return nil
                }
                assets.append(asset)
            }
            remainingAssetSlots -= rows.count
            return FileSyncHistoryPayload(
                deviceID: deviceID,
                historyID: history.historyID,
                updatedAt: history.updatedAt,
                assets: assets
            )
        }
        return FileDeviceSyncSnapshot(
            deviceID: deviceID,
            histories: histories,
            skippedAssetCount: skippedAssetCount
        )
    }

    private func loadFileAsset(
        _ row: FileDirectoryAsset,
        deviceDirectoryURL: URL,
        maxFileBytes: Int
    ) -> FileSyncAssetPayload? {
        let pasteboardType = NSPasteboard.PasteboardType(rawValue: row.pasteboardType)
        guard let objectURL = directFileURL(for: row.relativePath, deviceDirectoryURL: deviceDirectoryURL),
              fileSizeMatches(at: objectURL, expectedByteCount: row.byteCount, maxFileBytes: maxFileBytes) else {
            return nil
        }
        guard let data = validatedFileData(
            at: objectURL,
            expectedByteCount: row.byteCount,
            maxFileBytes: maxFileBytes
        ) else {
            return nil
        }
        return FileSyncAssetPayload(
            assetIndex: row.assetIndex,
            pasteboardType: pasteboardType,
            data: data,
            originalFilename: row.originalFilename,
            byteCount: row.byteCount,
            modifiedAtNanoseconds: row.modifiedAtNanoseconds
        )
    }

    @discardableResult
    private func writeFileAssetIfNeeded(
        _ asset: FileSyncAssetPayload,
        to destinationURL: URL,
        expectedByteCount: Int
    ) throws -> Bool {
        if fileSizeMatches(
            at: destinationURL,
            expectedByteCount: expectedByteCount,
            maxFileBytes: expectedByteCount
        ) {
            return false
        }
        try writeFileDataAtomically(asset.data, to: destinationURL)
        return true
    }

    private func writeFileDataAtomically(_ data: Data, to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryExtension = destinationURL.pathExtension.isEmpty ? "tmp" : destinationURL.pathExtension
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(temporaryExtension)")
        try? fileManager.removeItem(at: temporaryURL)
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try replaceItem(at: destinationURL, with: temporaryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func fileHistorySort(_ lhs: FileSyncHistoryPayload, _ rhs: FileSyncHistoryPayload) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.historyID < rhs.historyID
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func fileAssetRelativePath(historyID: String, updatedAt: Int, asset: FileSyncAssetPayload) -> String {
        "assets/\(safePathComponent(for: historyID))/\(fileAssetFileName(asset, updatedAt: updatedAt))"
    }

    private func fileAssetFileName(_ asset: FileSyncAssetPayload, updatedAt: Int) -> String {
        let originalName = asset.originalFilename ?? "asset.\(fileExtension(for: asset.pasteboardType))"
        let prefix = String(format: "%03d", asset.assetIndex)
        let version = asset.modifiedAtNanoseconds ?? Int64(updatedAt)
        return "\(prefix)-\(asset.byteCount)-\(version)-\(safeFileName(originalName, maxUTF8Bytes: 180))"
    }

    private func fileExtension(for pasteboardType: NSPasteboard.PasteboardType) -> String {
        switch pasteboardType {
        case .pdf, .deprecatedPDF:
            return "pdf"
        case .rtf, .deprecatedRTF:
            return "rtf"
        case .rtfd, .deprecatedRTFD:
            return "rtfd"
        case .png, .clipyApplePNG, .clipySnipastePNG:
            return "png"
        case .tiff, .deprecatedTIFF:
            return "tiff"
        default:
            return "dat"
        }
    }

    private func pruneDirectFileAssets(in deviceDirectoryURL: URL, keeping relativePaths: Set<String>) throws {
        let assetsURL = deviceDirectoryURL.appendingPathComponent("assets", isDirectory: true)
        guard fileManager.fileExists(atPath: assetsURL.path) else { return }
        guard let enumerator = fileManager.enumerator(
            at: assetsURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        var directories = [URL]()
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                directories.append(url)
                continue
            }
            if !relativePaths.contains(relativePath(of: url, base: deviceDirectoryURL)) {
                try? fileManager.removeItem(at: url)
            }
        }
        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
                  contents.isEmpty else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    private func removeDirectFileAssets(in deviceDirectoryURL: URL, relativePaths: Set<String>) {
        for relativePath in relativePaths {
            guard let url = directFileURL(for: relativePath, deviceDirectoryURL: deviceDirectoryURL) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func existingDirectFileRelativePaths(in deviceDirectoryURL: URL) -> Set<String> {
        guard let manifestData = try? Data(contentsOf: fileManifestURL(forDeviceDirectory: deviceDirectoryURL)),
              let manifest = try? JSONDecoder().decode(FileDirectoryManifest.self, from: manifestData) else {
            return []
        }
        return Set(manifest.histories.flatMap { $0.assets.map(\.relativePath) })
    }

    private func writeMetadata(_ metadata: [String: String], database: SyncSQLiteDatabase) throws {
        let statement = try database.prepare("INSERT INTO metadata(key, value) VALUES (?, ?)")
        for (key, value) in metadata {
            try statement.reset()
            try statement.bind(key, at: 1)
            try statement.bind(value, at: 2)
            try statement.stepToCompletion()
        }
    }

    private func readMetadata(database: SyncSQLiteDatabase) throws -> [String: String] {
        let statement = try database.prepare("SELECT key, value FROM metadata")
        var metadata = [String: String]()
        while try statement.step() {
            metadata[statement.columnString(at: 0)] = statement.columnString(at: 1)
        }
        return metadata
    }

    private func writeSQLiteSnapshot(to destinationURL: URL, write: (SyncSQLiteDatabase) throws -> Void) throws {
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).sqlite")
        try? fileManager.removeItem(at: temporaryURL)
        let database = try SyncSQLiteDatabase(url: temporaryURL)
        do {
            try database.execute("PRAGMA journal_mode=DELETE; PRAGMA synchronous=NORMAL; PRAGMA temp_store=MEMORY;")
            try database.execute("BEGIN IMMEDIATE")
            try write(database)
            try database.execute("COMMIT")
            database.close()
            try replaceItem(at: destinationURL, with: temporaryURL)
        } catch {
            database.close()
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func replaceItem(at destinationURL: URL, with temporaryURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            let replacementURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).\(destinationURL.pathExtension)")
            try fileManager.moveItem(at: temporaryURL, to: replacementURL)
            do {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: replacementURL, backupItemName: nil, options: [])
            } catch {
                try? fileManager.removeItem(at: replacementURL)
                throw error
            }
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func directFileURL(for relativePath: String, deviceDirectoryURL: URL) -> URL? {
        guard relativePath.hasPrefix("assets/"),
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            return nil
        }
        let objectURL = deviceDirectoryURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        let assetsRootURL = deviceDirectoryURL.appendingPathComponent("assets", isDirectory: true).standardizedFileURL
        guard objectURL.path.hasPrefix(assetsRootURL.path + "/") else {
            return nil
        }
        return objectURL
    }

    private func validatedFileData(
        at url: URL,
        expectedByteCount: Int,
        maxFileBytes: Int
    ) -> Data? {
        guard expectedByteCount >= 0,
              expectedByteCount <= maxFileBytes,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(min(expectedByteCount, 1024 * 1024))
        var byteCount = 0

        do {
            while true {
                let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
                guard !chunk.isEmpty else { break }
                byteCount += chunk.count
                guard byteCount <= maxFileBytes else { return nil }
                data.append(chunk)
            }
        } catch {
            return nil
        }

        guard byteCount == expectedByteCount else { return nil }
        return data
    }

    private func fileSizeMatches(
        at url: URL,
        expectedByteCount: Int,
        maxFileBytes: Int
    ) -> Bool {
        guard expectedByteCount >= 0,
              expectedByteCount <= maxFileBytes,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue == expectedByteCount else {
            return false
        }
        return true
    }

    private func loadSQLiteFiles(in directoryURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        return try fileManager
            .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadFileDeviceDirectories(in directoryURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        return try fileManager
            .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true
                    && fileManager.fileExists(atPath: fileManifestURL(forDeviceDirectory: url).path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func removeLegacyV1Paths() throws {
        for url in [
            syncRootURL.appendingPathComponent("manifest.json"),
            syncRootURL.appendingPathComponent("histories", isDirectory: true),
            syncRootURL.appendingPathComponent("snippets/items", isDirectory: true),
            syncRootURL.appendingPathComponent("snippets/folders", isDirectory: true)
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func ensureHistoryProtocol() throws {
        let data: Data?
        do {
            data = try Data(contentsOf: historyProtocolURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            data = nil
        }
        // Read failures are not evidence of an old protocol. Preserve remote snapshots for the next retry.
        if let data,
           let manifest = try? JSONDecoder().decode(HistoryProtocolManifest.self, from: data),
           manifest.schemaVersion == Self.historyProtocolVersion {
            try fileManager.createDirectory(at: historyDevicesURL, withIntermediateDirectories: true)
            return
        }

        if fileManager.fileExists(atPath: historyRootURL.path) {
            try fileManager.removeItem(at: historyRootURL)
        }
        try fileManager.createDirectory(at: historyDevicesURL, withIntermediateDirectories: true)
        let manifest = HistoryProtocolManifest(
            schemaVersion: Self.historyProtocolVersion,
            generatedAt: Int(Date().timeIntervalSince1970)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try writeFileDataAtomically(encoder.encode(manifest), to: historyProtocolURL)
    }

    private func removeLegacyFileDevicePaths(for deviceID: String) throws {
        for url in [
            fileDevicesURL.appendingPathComponent(fileName(for: deviceID)),
            fileObjectsURL.appendingPathComponent(safePathComponent(for: deviceID), isDirectory: true)
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        if let contents = try? fileManager.contentsOfDirectory(at: fileObjectsURL, includingPropertiesForKeys: nil),
           contents.isEmpty {
            try? fileManager.removeItem(at: fileObjectsURL)
        }
    }

    private func relativePath(of url: URL, base baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(basePath.count + 1))
    }

    private var syncRootURL: URL {
        rootURL
    }

    private var historyRootURL: URL {
        syncRootURL.appendingPathComponent("history", isDirectory: true)
    }

    private var historyProtocolURL: URL {
        historyRootURL.appendingPathComponent("protocol.json", isDirectory: false)
    }

    private var historyDevicesURL: URL {
        historyRootURL
            .appendingPathComponent("devices", isDirectory: true)
    }

    private var snippetDevicesURL: URL {
        syncRootURL
            .appendingPathComponent("snippets", isDirectory: true)
            .appendingPathComponent("devices", isDirectory: true)
    }

    private var fileDevicesURL: URL {
        syncRootURL
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent("devices", isDirectory: true)
    }

    private var fileObjectsURL: URL {
        syncRootURL
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)
    }

    private func fileName(for id: String) -> String {
        "\(safePathComponent(for: id)).sqlite"
    }

    private func fileManifestURL(for deviceID: String) -> URL {
        fileDevicesURL
            .appendingPathComponent(safePathComponent(for: deviceID), isDirectory: true)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    private func fileManifestURL(forDeviceDirectory deviceDirectoryURL: URL) -> URL {
        deviceDirectoryURL.appendingPathComponent("manifest.json", isDirectory: false)
    }

    private func safePathComponent(for id: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        let sanitized = String(id.unicodeScalars.map {
            allowedCharacters.contains($0) ? Character($0) : "-"
        })
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return trimmed.isEmpty ? UUID().uuidString : trimmed
    }

    private static func nanosecondsSince1970(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
    }

    private func safeFileName(_ value: String, maxUTF8Bytes: Int = 255) -> String {
        let disallowed = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleanedScalars = value.unicodeScalars.map { scalar in
            disallowed.contains(scalar) ? "-" : Character(scalar)
        }
        let cleaned = String(cleanedScalars).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let fallback = UUID().uuidString
        let name = cleaned.isEmpty ? fallback : cleaned
        guard name.lengthOfBytes(using: .utf8) > maxUTF8Bytes else { return name }

        let nsName = name as NSString
        let pathExtension = nsName.pathExtension
        let rawSuffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        let suffix = rawSuffix.lengthOfBytes(using: .utf8) < maxUTF8Bytes ? rawSuffix : ""
        let suffixBudget = suffix.lengthOfBytes(using: .utf8)
        let baseBudget = max(1, maxUTF8Bytes - suffixBudget)
        let baseName = suffix.isEmpty ? name : nsName.deletingPathExtension
        var truncatedBase = ""
        for character in baseName {
            let candidate = truncatedBase + String(character)
            guard candidate.lengthOfBytes(using: .utf8) <= baseBudget else { break }
            truncatedBase = candidate
        }
        return (truncatedBase.isEmpty ? fallback : truncatedBase) + suffix
    }
}

private final class SyncSQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let database {
                sqlite3_close(database)
            }
            throw SyncSQLiteError.openFailed(message)
        }
        handle = database
    }

    deinit {
        close()
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func execute(_ sql: String) throws {
        guard let handle else { throw SyncSQLiteError.executeFailed("database is closed") }
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw SyncSQLiteError.executeFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func prepare(_ sql: String) throws -> SyncSQLiteStatement {
        guard let handle else { throw SyncSQLiteError.prepareFailed("database is closed") }
        return try SyncSQLiteStatement(database: handle, sql: sql)
    }
}

private final class SyncSQLiteStatement {
    private let database: OpaquePointer
    private var statement: OpaquePointer?

    init(database: OpaquePointer, sql: String) throws {
        self.database = database
        var preparedStatement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &preparedStatement, nil)
        guard result == SQLITE_OK, let preparedStatement else {
            throw SyncSQLiteError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }
        statement = preparedStatement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func reset() throws {
        guard let statement else { return }
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func bind(_ value: String?, at index: Int32) throws {
        guard let statement else { return }
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try checkBind(result)
    }

    func bind(_ value: Int, at index: Int32) throws {
        guard let statement else { return }
        try checkBind(sqlite3_bind_int64(statement, index, sqlite3_int64(value)))
    }

    func bind(_ value: Bool, at index: Int32) throws {
        try bind(value ? 1 : 0, at: index)
    }

    func bind(_ value: Data, at index: Int32) throws {
        guard let statement else { return }
        let result = value.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient)
        }
        try checkBind(result)
    }

    func step() throws -> Bool {
        guard let statement else { return false }
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SyncSQLiteError.stepFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    func stepToCompletion() throws {
        guard try !step() else {
            throw SyncSQLiteError.stepFailed("statement unexpectedly returned a row")
        }
    }

    func columnString(at index: Int32) -> String {
        guard let statement, let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    func columnOptionalString(at index: Int32) -> String? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    func columnInt(at index: Int32) -> Int {
        guard let statement else { return 0 }
        return Int(sqlite3_column_int64(statement, index))
    }

    func columnBool(at index: Int32) -> Bool {
        columnInt(at: index) != 0
    }

    func columnData(at index: Int32) -> Data {
        guard let statement else { return Data() }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard let bytes = sqlite3_column_blob(statement, index), count > 0 else {
            return Data()
        }
        return Data(bytes: bytes, count: count)
    }

    private func checkBind(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw SyncSQLiteError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
