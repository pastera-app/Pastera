//
//  PasteboardHistoryRepository.swift
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
import Combine
import Dependencies
import GRDB
import SQLiteData

// swiftlint:disable type_body_length file_length

enum HistorySearchError: Error, Equatable {
    case invalidRegularExpression(String)
}

struct HistoryRetentionSettings: Equatable {
    static let defaultStoredHistoryLimit = 2000
    static let defaultMaxSyncedHistoryTextBytes = 256 * 1024
    static let defaultMaxHistorySnapshotTextBudgetBytes = 8 * 1024 * 1024
    static let defaultMediaHistoryLimit = 15
    static let minimumMediaHistoryLimit = 1
    static let maximumMediaHistoryLimit = 50

    let menuDisplayLimit: Int
    let storedHistoryLimit: Int
    let maxSyncedHistoryTextBytes: Int
    let maxHistorySnapshotTextBudgetBytes: Int
    let maxImageHistorySize: Int
    let maxFileHistorySize: Int

    static func current(defaults: UserDefaults = AppEnvironment.current.defaults) -> HistoryRetentionSettings {
        let menuDisplayLimit = defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        let storedHistoryLimit = defaults.integer(forKey: Constants.UserDefaults.storedHistoryLimit)
        let maxSyncedHistoryTextBytes = defaults.integer(forKey: Constants.UserDefaults.maxSyncedHistoryTextBytes)
        let maxHistorySnapshotTextBudgetBytes = defaults.integer(
            forKey: Constants.UserDefaults.maxHistorySnapshotTextBudgetBytes
        )

        return HistoryRetentionSettings(
            menuDisplayLimit: max(0, menuDisplayLimit),
            storedHistoryLimit: storedHistoryLimit > 0 ? storedHistoryLimit : defaultStoredHistoryLimit,
            maxSyncedHistoryTextBytes: maxSyncedHistoryTextBytes > 0
                ? maxSyncedHistoryTextBytes
                : defaultMaxSyncedHistoryTextBytes,
            maxHistorySnapshotTextBudgetBytes: maxHistorySnapshotTextBudgetBytes > 0
                ? maxHistorySnapshotTextBudgetBytes
                : defaultMaxHistorySnapshotTextBudgetBytes,
            maxImageHistorySize: mediaHistoryLimit(
                forKey: Constants.UserDefaults.maxImageHistorySize,
                defaults: defaults
            ),
            maxFileHistorySize: mediaHistoryLimit(
                forKey: Constants.UserDefaults.maxFileHistorySize,
                defaults: defaults
            )
        )
    }

    static func mediaHistoryLimit(forKey key: String, defaults: UserDefaults = AppEnvironment.current.defaults) -> Int {
        guard let value = defaults.object(forKey: key) as? NSNumber else {
            return defaultMediaHistoryLimit
        }
        return clampedMediaHistoryLimit(value.intValue)
    }

    static func clampedMediaHistoryLimit(_ value: Int) -> Int {
        min(max(value, minimumMediaHistoryLimit), maximumMediaHistoryLimit)
    }
}

enum HistoryTextSourceKind: String, Codable {
    case plainText
    case url
}

struct PasteboardHistorySyncPayload: Equatable {
    let id: String
    let text: String
    let updateAt: Int
    let deviceID: String?
    let sourceKind: HistoryTextSourceKind

    var textByteCount: Int {
        text.lengthOfBytes(using: .utf8)
    }
}

struct HistorySearchQuery: Equatable {
    enum Mode: Equatable {
        case plain
        case regex
    }

    enum SortOrder: Equatable {
        case newestFirst
        case oldestFirst
    }

    let text: String
    let mode: Mode
    let caseSensitive: Bool
    let types: Set<NSPasteboard.PasteboardType>
    let fileCategories: Set<PasteraFinderFileCategory>
    let sortOrder: SortOrder
    let groupsEquivalentText: Bool

    init(
        text: String,
        mode: Mode = .plain,
        caseSensitive: Bool = false,
        types: Set<NSPasteboard.PasteboardType> = [],
        fileCategories: Set<PasteraFinderFileCategory> = [],
        sortOrder: SortOrder = .newestFirst,
        groupsEquivalentText: Bool = true
    ) {
        self.text = text
        self.mode = mode
        self.caseSensitive = caseSensitive
        self.types = types
        self.fileCategories = fileCategories
        self.sortOrder = sortOrder
        self.groupsEquivalentText = groupsEquivalentText
    }
}

struct PasteboardHistorySearchCandidate: Equatable {
    let id: PasteboardHistory.ID
    let title: String
    let pasteboardTypes: [NSPasteboard.PasteboardType]
    let updateAt: Int
    let ocrText: String?

    init(history: PasteboardHistory, ocrText: String? = nil) {
        self.id = history.id
        self.title = history.title
        self.pasteboardTypes = history.pasteboardTypes
        self.updateAt = history.updateAt
        self.ocrText = ocrText
    }

    var searchableText: String {
        guard let ocrText, !ocrText.isEmpty else { return title }
        return "\(title)\n\(ocrText)"
    }
}

@Selection
struct PasteboardHistoryChangeToken: Equatable {
    let id: PasteboardHistory.ID
    let updateAt: Int
}

@Selection
struct PasteboardHistoryOCRChangeToken: Equatable {
    let pasteboardHistoryID: PasteboardHistory.ID
    let updatedAt: Int
}

protocol PasteboardHistoryRepositoryProtocol {
    func observeHistoryChanges() -> AnyPublisher<Void, Never>
    func observeTextSyncCandidateChanges(currentDeviceID: String?) -> AnyPublisher<Void, Never>
    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never>
    func hasHistories() -> Bool
    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail]
    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail]
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory?
    func fetchHistory(matching content: PasteboardContent) -> PasteboardHistory?
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent?

    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int)
    func saveCapturedHistory(
        preferredID: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int
    ) -> PasteboardHistory.ID?
    @discardableResult
    func createDerivedTextHistory(text: String, updateAt: Int) -> PasteboardHistory.ID?
    @discardableResult
    func updateTextHistory(id: PasteboardHistory.ID, text: String, updateAt: Int) -> Bool
    @discardableResult
    func upsertOCRText(
        historyID: PasteboardHistory.ID,
        sourceHash: String,
        recognizedText: String,
        updatedAt: Int
    ) -> Bool
    func deleteOCRText(historyID: PasteboardHistory.ID)
    func fetchOCRText(historyID: PasteboardHistory.ID) -> PasteboardHistoryOCRText?
    func fetchOCRText(sourceHash: String) -> PasteboardHistoryOCRText?
    func fetchOCRIndexingCandidateIDs(limit: Int) -> [PasteboardHistory.ID]
    func enqueueOCRJob(historyID: PasteboardHistory.ID, priority: Int, enqueuedAt: Int)
    func fetchNextOCRJobID() -> PasteboardHistory.ID?
    func deleteOCRJob(historyID: PasteboardHistory.ID)
    func countOCRJobs() -> Int
    func deleteHistory(id: PasteboardHistory.ID)
    func deleteDisplayedHistory(id: PasteboardHistory.ID, query: HistorySearchQuery) throws
    func deleteAll()
    func deleteOverflowingHistories(maxHistorySize: Int)
    func pruneHistories(settings: HistoryRetentionSettings)
    func compactOversizedThumbnailAssets(maxBytes: Int) -> Int
    func fetchSyncPayloads(
        currentDeviceID: String?,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) -> [PasteboardHistorySyncPayload]
    func fetchFileSyncSnapshot(
        currentDeviceID: String?,
        limit: Int,
        maxFileBytes: Int,
        includedFileTypes: Set<PasteboardAvailableType>
    ) -> FileSyncExportSnapshot
    @discardableResult
    func upsertSyncPayload(_ payload: PasteboardHistorySyncPayload) throws -> Bool
    func shouldImportFileSyncHistory(historyID: String, updatedAt: Int) -> Bool
    @discardableResult
    func upsertFileSyncHistory(_ payload: FileSyncHistoryPayload) -> Bool
    func suppressSyncedHistory(id: PasteboardHistory.ID)
}

extension PasteboardHistoryRepositoryProtocol {
    func saveCapturedHistory(
        preferredID: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int
    ) -> PasteboardHistory.ID? {
        save(id: preferredID, content: content, updateAt: updateAt)
        return preferredID
    }

    func deleteDisplayedHistory(id: PasteboardHistory.ID, query: HistorySearchQuery) throws {
        deleteHistory(id: id)
    }

    func fetchHistory(matching content: PasteboardContent) -> PasteboardHistory? {
        let id = PasteboardHistory.ID(rawValue: content.hash)
        guard fetchContent(id: id) == content else { return nil }
        return fetchHistory(id: id)
    }

    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        observeHistories()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func observeTextSyncCandidateChanges(currentDeviceID _: String?) -> AnyPublisher<Void, Never> {
        observeHistoryChanges()
    }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int
    ) -> [PasteboardHistoryDetail] {
        fetchHistoryDetails(
            ascending: ascending,
            includesThumbnailAsset: includesThumbnailAsset,
            limit: limit,
            offset: 0
        )
    }

    func fetchSyncPayloads(
        currentDeviceID: String?,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) -> [PasteboardHistorySyncPayload] {
        []
    }

    func fetchFileSyncSnapshot(
        currentDeviceID: String?,
        limit: Int,
        maxFileBytes: Int
    ) -> FileSyncExportSnapshot {
        fetchFileSyncSnapshot(
            currentDeviceID: currentDeviceID,
            limit: limit,
            maxFileBytes: maxFileBytes,
            includedFileTypes: Set(PasteboardAvailableType.syncFileTypes)
        )
    }

    func fetchFileSyncSnapshot(
        currentDeviceID: String?,
        limit: Int,
        maxFileBytes: Int,
        includedFileTypes: Set<PasteboardAvailableType>
    ) -> FileSyncExportSnapshot {
        FileSyncExportSnapshot(histories: [], skippedAssetCount: 0)
    }

    func upsertSyncPayload(_ payload: PasteboardHistorySyncPayload) -> Bool { false }

    func updateTextHistory(id _: PasteboardHistory.ID, text _: String, updateAt _: Int) -> Bool { false }

    func createDerivedTextHistory(text _: String, updateAt _: Int) -> PasteboardHistory.ID? { nil }

    func upsertOCRText(
        historyID _: PasteboardHistory.ID,
        sourceHash _: String,
        recognizedText _: String,
        updatedAt _: Int
    ) -> Bool { false }

    func deleteOCRText(historyID _: PasteboardHistory.ID) {}

    func fetchOCRText(historyID _: PasteboardHistory.ID) -> PasteboardHistoryOCRText? { nil }

    func fetchOCRText(sourceHash _: String) -> PasteboardHistoryOCRText? { nil }

    func fetchOCRIndexingCandidateIDs(limit _: Int) -> [PasteboardHistory.ID] { [] }

    func enqueueOCRJob(historyID _: PasteboardHistory.ID, priority _: Int, enqueuedAt _: Int) {}

    func fetchNextOCRJobID() -> PasteboardHistory.ID? { nil }

    func deleteOCRJob(historyID _: PasteboardHistory.ID) {}

    func countOCRJobs() -> Int { 0 }

    func shouldImportFileSyncHistory(historyID: String, updatedAt: Int) -> Bool { true }

    func upsertFileSyncHistory(_ payload: FileSyncHistoryPayload) -> Bool { false }

    func suppressSyncedHistory(id: PasteboardHistory.ID) {}

    func compactOversizedThumbnailAssets(maxBytes: Int) -> Int { 0 }
}

final class PasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
    private var database: any DatabaseWriter {
        @Dependency(\.defaultDatabase) var database
        return database
    }

    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        @FetchAll(
            PasteboardHistory
                .all
                .order { $0.updateAt.desc() }
                .select {
                    PasteboardHistoryChangeToken.Columns(
                        id: $0.id,
                        updateAt: $0.updateAt
                    )
                }
        )
        var historyChangeTokens

        @FetchAll(
            PasteboardHistoryOCRText
                .all
                .order { $0.updatedAt.desc() }
                .select {
                    PasteboardHistoryOCRChangeToken.Columns(
                        pasteboardHistoryID: $0.pasteboardHistoryID,
                        updatedAt: $0.updatedAt
                    )
                }
        )
        var ocrChangeTokens

        return Publishers.CombineLatest($historyChangeTokens.publisher, $ocrChangeTokens.publisher)
            .map { _ in () }
            .prepend(())
            .eraseToAnyPublisher()
    }

    func observeTextSyncCandidateChanges(currentDeviceID: String?) -> AnyPublisher<Void, Never> {
        guard let currentDeviceID else {
            return Just(()).eraseToAnyPublisher()
        }
        @FetchAll(
            PasteboardHistory
                .all
                .where { $0.deviceID.eq(currentDeviceID) }
                .where { $0.isTextSyncCandidate }
                .order { $0.updateAt.desc() }
                .select {
                    PasteboardHistoryChangeToken.Columns(id: $0.id, updateAt: $0.updateAt)
                }
        )
        var tokens

        return $tokens.publisher
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        @FetchAll(PasteboardHistory.all.order { $0.updateAt.desc() })
        var histories

        return $histories.publisher.eraseToAnyPublisher()
    }

    func hasHistories() -> Bool {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistory
                    .select { $0.id }
                    .limit(1)
                    .fetchOne(database) != nil
            }
        } ?? false
    }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int = 0
    ) -> [PasteboardHistoryDetail] {
        guard limit > 0 else { return [] }
        return withErrorReporting {
            try database.read { database in
                let histories = PasteboardHistory
                    .all
                    .order { columns in
                        if ascending {
                            columns.updateAt
                        } else {
                            columns.updateAt.desc()
                        }
                    }
                    .limit(limit, offset: max(0, offset))

                guard includesThumbnailAsset else {
                    return try histories
                        .fetchAll(database)
                        .map { PasteboardHistoryDetail(history: $0, thumbnailAsset: nil) }
                }

                return try histories
                    .leftJoin(PasteboardHistoryThumbnailAsset.all) { $0.id.eq($1.pasteboardHistoryID) }
                    .select { PasteboardHistoryDetail.Columns(history: $0, thumbnailAsset: $1) }
                    .fetchAll(database)
            }
        } ?? []
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        guard limit > 0 else { return [] }
        if !query.groupsEquivalentText && query.text.isEmpty && query.types.isEmpty && query.fileCategories.isEmpty {
            return fetchHistoryDetails(
                ascending: query.sortOrder == .oldestFirst,
                includesThumbnailAsset: includesThumbnailAsset,
                limit: limit,
                offset: offset
            )
        }

        let ids = try matchingHistoryIDs(query: query, limit: limit, offset: offset)
        return fetchHistoryDetails(ids: ids, includesThumbnailAsset: includesThumbnailAsset)
    }

    func matchingHistoryIDs(
        query: HistorySearchQuery,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistory.ID] {
        guard limit > 0 else { return [] }

        let matcher = try makeMatcher(for: query)
        return try database.read { database in
            let groups = try displayHistoryGroups(query: query, matcher: matcher, database: database)
            return groups.dropFirst(max(0, offset)).prefix(limit).compactMap { $0.first?.id }
        }
    }

    func fetchHistoryDetails(
        ids: [PasteboardHistory.ID],
        includesThumbnailAsset: Bool
    ) -> [PasteboardHistoryDetail] {
        guard !ids.isEmpty else { return [] }
        var indexByID = [PasteboardHistory.ID: Int]()
        ids.enumerated().forEach { offset, id in
            if indexByID[id] == nil {
                indexByID[id] = offset
            }
        }
        return (withErrorReporting {
            try database.read { database in
                let histories = PasteboardHistory
                    .where { $0.id.in(ids) }

                let details: [PasteboardHistoryDetail]
                if includesThumbnailAsset {
                    details = try histories
                        .leftJoin(PasteboardHistoryThumbnailAsset.all) { $0.id.eq($1.pasteboardHistoryID) }
                        .select { PasteboardHistoryDetail.Columns(history: $0, thumbnailAsset: $1) }
                        .fetchAll(database)
                } else {
                    details = try histories
                        .fetchAll(database)
                        .map { PasteboardHistoryDetail(history: $0, thumbnailAsset: nil) }
                }

                return details.sorted {
                    indexByID[$0.history.id, default: Int.max] < indexByID[$1.history.id, default: Int.max]
                }
            }
        } ?? [])
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistory.find(id).fetchOne(database)
            }
        }
    }

    func fetchHistory(matching content: PasteboardContent) -> PasteboardHistory? {
        withErrorReporting {
            try database.read { database in
                let hashID = PasteboardHistory.ID(rawValue: content.hash)
                if let history = try PasteboardHistory.find(hashID).fetchOne(database),
                   history.pasteboardTypes == content.types {
                    let assets = try PasteboardHistoryAsset
                        .where { $0.pasteboardHistoryID.eq(hashID) }
                        .fetchAll(database)
                    if assets.map({ PasteboardContent.Asset(type: $0.pasteboardType, data: $0.data) }) == content.assets {
                        return history
                    }
                }

                // Imported and edited plain text can retain an ID unrelated to its current hash.
                // Other formats must not scan histories that share an empty or generic title.
                guard Self.isEditablePlainTextHistoryTypes(content.types) else { return nil }
                let title = content.historyTitle[0...10000]
                let candidates = try PasteboardHistory
                    .where { $0.title.eq(title) }
                    .order { $0.updateAt.desc() }
                    .fetchAll(database)
                    .filter { $0.pasteboardTypes == content.types }
                guard !candidates.isEmpty else { return nil }

                let assets = try PasteboardHistoryAsset
                    .where { $0.pasteboardHistoryID.in(candidates.map(\.id)) }
                    .fetchAll(database)
                let assetsByHistoryID = Dictionary(grouping: assets, by: \.pasteboardHistoryID)
                return candidates.first { history in
                    let storedAssets = assetsByHistoryID[history.id, default: []].map {
                        PasteboardContent.Asset(type: $0.pasteboardType, data: $0.data)
                    }
                    return storedAssets == content.assets
                }
            }
        }
    }

    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? {
        withErrorReporting {
            try database.read { database in
                guard try PasteboardHistory.find(id).fetchOne(database) != nil else {
                    return nil
                }
                let assets = try PasteboardHistoryAsset
                    .where { $0.pasteboardHistoryID.eq(id) }
                    .fetchAll(database)
                return PasteboardContent(
                    assets: assets.map {
                        PasteboardContent.Asset(type: $0.pasteboardType, data: $0.data)
                    }
                )
            }
        }
    }

    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {
        withErrorReporting {
            try database.write { database in
                let exists = try PasteboardHistory.find(id).fetchOne(database) != nil
                try saveHistory(
                    id: id, content: content, updateAt: updateAt, insertingAssets: !exists, database: database
                )
            }
        }
    }

    func saveCapturedHistory(
        preferredID: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int
    ) -> PasteboardHistory.ID? {
        withErrorReporting {
            try database.write { database in
                let existingHistory = try PasteboardHistory.find(preferredID).fetchOne(database)
                var savedID = preferredID
                if let existingHistory {
                    let assets = try PasteboardHistoryAsset
                        .where { $0.pasteboardHistoryID.eq(preferredID) }
                        .fetchAll(database)
                        .map { PasteboardContent.Asset(type: $0.pasteboardType, data: $0.data) }
                    // A remote import or edit may have changed the match after capture looked it up.
                    if existingHistory.pasteboardTypes != content.types || assets != content.assets {
                        savedID = PasteboardHistory.ID(rawValue: UUID().uuidString)
                    }
                }
                try saveHistory(
                    id: savedID, content: content, updateAt: updateAt,
                    insertingAssets: existingHistory == nil || savedID != preferredID, database: database
                )
                return savedID
            }
        }
    }

    private func saveHistory(
        id: PasteboardHistory.ID,
        content: PasteboardContent,
        updateAt: Int,
        insertingAssets: Bool,
        database: Database
    ) throws {
        let facets = Self.contentFacets(pasteboardTypes: content.types)
        let history = PasteboardHistory(
            id: id,
            title: content.historyTitle[0...10000],
            pasteboardTypes: content.types,
            updateAt: updateAt,
            deviceID: CPYUtilities.deviceID,
            containsImage: facets.containsImage,
            containsFile: facets.containsFile,
            isTextSyncCandidate: facets.isTextSyncCandidate
        )
        try PasteboardHistory.upsert { history }.execute(database)
        if insertingAssets {
            let assets = content.assets.map {
                PasteboardHistoryAsset.Draft(pasteboardHistoryID: id, pasteboardType: $0.type, data: $0.data)
            }
            try PasteboardHistoryAsset.insert { assets }.execute(database)
            if let thumbnailAsset = thumbnailAsset(from: content, id: id) {
                try PasteboardHistoryThumbnailAsset.insert { thumbnailAsset }.execute(database)
            }
        }
    }

    @discardableResult
    func createDerivedTextHistory(text: String, updateAt: Int) -> PasteboardHistory.ID? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let content = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .string, data: Data(text.utf8))]
        )
        let id = PasteboardHistory.ID(rawValue: UUID().uuidString)
        save(id: id, content: content, updateAt: updateAt)
        return fetchHistory(id: id) == nil ? nil : id
    }

    @discardableResult
    func updateTextHistory(id: PasteboardHistory.ID, text: String, updateAt: Int) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data(text.utf8))
            ]
        )
        let history = PasteboardHistory(
            id: id,
            title: content.historyTitle[0...10000],
            pasteboardTypes: content.types,
            updateAt: updateAt,
            deviceID: CPYUtilities.deviceID,
            containsImage: false,
            containsFile: false,
            isTextSyncCandidate: true
        )

        return withErrorReporting {
            try database.write { database in
                guard let existingHistory = try PasteboardHistory.find(id).fetchOne(database),
                      Self.isEditablePlainTextHistoryTypes(existingHistory.pasteboardTypes) else {
                    return false
                }

                try PasteboardHistory.upsert { history }.execute(database)
                try PasteboardHistoryAsset
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(id) }
                    .execute(database)
                try PasteboardHistoryThumbnailAsset
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(id) }
                    .execute(database)
                try PasteboardHistoryOCRText
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(id) }
                    .execute(database)

                let assets = content.assets.map {
                    PasteboardHistoryAsset.Draft(pasteboardHistoryID: id, pasteboardType: $0.type, data: $0.data)
                }
                try PasteboardHistoryAsset.insert { assets }.execute(database)
                if let thumbnailAsset = thumbnailAsset(from: content, id: id) {
                    try PasteboardHistoryThumbnailAsset.insert { thumbnailAsset }.execute(database)
                }
                return true
            }
        } ?? false
    }

    @discardableResult
    func upsertOCRText(
        historyID: PasteboardHistory.ID,
        sourceHash: String,
        recognizedText: String,
        updatedAt: Int
    ) -> Bool {
        let normalizedText = PasteboardHistoryOCRTextLimits.normalized(recognizedText)
        return withErrorReporting {
            try database.write { database in
                guard try PasteboardHistory.find(historyID).fetchOne(database) != nil else {
                    return false
                }
                try PasteboardHistoryOCRText.upsert {
                    PasteboardHistoryOCRText(
                        pasteboardHistoryID: historyID,
                        sourceHash: sourceHash,
                        recognizedText: normalizedText,
                        updatedAt: updatedAt
                    )
                }
                .execute(database)
                return true
            }
        } ?? false
    }

    func deleteOCRText(historyID: PasteboardHistory.ID) {
        withErrorReporting {
            try database.write { database in
                try PasteboardHistoryOCRText
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(historyID) }
                    .execute(database)
            }
        }
    }

    func fetchOCRText(historyID: PasteboardHistory.ID) -> PasteboardHistoryOCRText? {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistoryOCRText.find(historyID).fetchOne(database)
            }
        }
    }

    func fetchOCRText(sourceHash: String) -> PasteboardHistoryOCRText? {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistoryOCRText
                    .where { $0.sourceHash.eq(sourceHash) }
                    .order { $0.updatedAt.desc() }
                    .limit(1)
                    .fetchOne(database)
            }
        }
    }

    func fetchOCRIndexingCandidateIDs(limit: Int) -> [PasteboardHistory.ID] {
        guard limit > 0 else { return [] }
        return withErrorReporting {
            try database.read { database in
                var candidateIDs = [PasteboardHistory.ID]()
                var offset = 0
                let batchSize = max(limit * 4, 50)

                while candidateIDs.count < limit {
                    let rawHistories = try PasteboardHistory
                        .all
                        .where { $0.containsImage || $0.containsFile }
                        .order { $0.updateAt.desc() }
                        .limit(batchSize, offset: offset)
                        .fetchAll(database)
                    guard !rawHistories.isEmpty else { break }
                    let histories = rawHistories
                    if !histories.isEmpty {
                        let historyIDs = histories.map(\.id)
                        let indexedIDs = try PasteboardHistoryOCRText
                            .where { $0.pasteboardHistoryID.in(historyIDs) }
                            .select { $0.pasteboardHistoryID }
                            .fetchAll(database)
                        let indexedIDSet = Set(indexedIDs)

                        for history in histories where candidateIDs.count < limit && !indexedIDSet.contains(history.id) {
                            candidateIDs.append(history.id)
                        }
                    }

                    offset += batchSize
                }
                return candidateIDs
            }
        } ?? []
    }

    func enqueueOCRJob(historyID: PasteboardHistory.ID, priority: Int, enqueuedAt: Int) {
        withErrorReporting {
            try database.write { database in
                guard try PasteboardHistory.find(historyID).fetchOne(database) != nil else { return }
                try PasteboardHistoryOCRJob.upsert {
                    PasteboardHistoryOCRJob(
                        pasteboardHistoryID: historyID,
                        priority: priority,
                        enqueuedAt: enqueuedAt
                    )
                }
                .execute(database)
            }
        }
    }

    func fetchNextOCRJobID() -> PasteboardHistory.ID? {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistoryOCRJob
                    .all
                    .order { ($0.priority.desc(), $0.enqueuedAt.desc()) }
                    .select { $0.pasteboardHistoryID }
                    .limit(1)
                    .fetchOne(database)
            }
        } ?? nil
    }

    func deleteOCRJob(historyID: PasteboardHistory.ID) {
        withErrorReporting {
            try database.write { database in
                try PasteboardHistoryOCRJob
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(historyID) }
                    .execute(database)
            }
        }
    }

    func countOCRJobs() -> Int {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistoryOCRJob.all.fetchCount(database)
            }
        } ?? 0
    }

    func deleteHistory(id: PasteboardHistory.ID) {
        suppressSyncedHistory(id: id)
        withErrorReporting {
            try database.write { database in
                try PasteboardHistory
                    .delete()
                    .where { $0.id.eq(id) }
                    .execute(database)
            }
        }
    }

    func deleteDisplayedHistory(id: PasteboardHistory.ID, query: HistorySearchQuery) throws {
        let matcher = try makeMatcher(for: query)
        try database.write { database in
            let groups = try displayHistoryGroups(query: query, matcher: matcher, database: database)
            guard let group = groups.first(where: { $0.contains(where: { $0.id == id }) }) else { return }
            let ids = group.map(\.id)
            let suppressedAt = Int(Date().timeIntervalSince1970)
            let suppressions = ids.map { id in
                SyncSuppression(
                    syncIdentity: syncIdentity(kind: .history, id: id.rawValue),
                    kind: .history,
                    recordID: id.rawValue,
                    suppressedAt: suppressedAt
                )
            }
            try SyncSuppression.upsert { suppressions }.execute(database)
            try PasteboardHistory.delete().where { $0.id.in(ids) }.execute(database)
        }
    }

    func deleteAll() {
        withErrorReporting {
            try database.write { database in
                try deleteAll(database: database)
            }
        }
    }

    func deleteOverflowingHistories(maxHistorySize: Int) {
        withErrorReporting {
            try database.write { database in
                try deleteOverflowingHistories(maxHistorySize: maxHistorySize, database: database)
            }
        }
    }

    func pruneHistories(settings: HistoryRetentionSettings) {
        withErrorReporting {
            try database.write { database in
                try deleteOverflowingHistories(maxHistorySize: settings.storedHistoryLimit, database: database)
                try deleteOverflowingMediaHistories(settings: settings, database: database)
            }
        }
    }

    private func deleteOverflowingHistories(maxHistorySize: Int, database: Database) throws {
        guard maxHistorySize > 0 else {
            try deleteAll(database: database)
            return
        }
        let deletingIDs = try PasteboardHistory
            .order { $0.updateAt.desc() }
            .limit(-1, offset: maxHistorySize)
            .select { $0.id }
            .fetchAll(database)
        guard !deletingIDs.isEmpty else { return }
        try PasteboardHistory
            .delete()
            .where { $0.id.in(deletingIDs) }
            .execute(database)
    }

    private func deleteOverflowingMediaHistories(settings: HistoryRetentionSettings, database: Database) throws {
        let imageIDs = try PasteboardHistory
            .where { $0.containsImage }
            .order { $0.updateAt.desc() }
            .limit(-1, offset: settings.maxImageHistorySize)
            .select { $0.id }
            .fetchAll(database)
        let fileIDs = try PasteboardHistory
            .where { $0.containsFile }
            .order { $0.updateAt.desc() }
            .limit(-1, offset: settings.maxFileHistorySize)
            .select { $0.id }
            .fetchAll(database)
        let deletingIDs = Array(Set(imageIDs).union(fileIDs))

        guard !deletingIDs.isEmpty else { return }
        try PasteboardHistory
            .delete()
            .where { $0.id.in(Array(Set(deletingIDs))) }
            .execute(database)
    }

    private func deleteAll(database: Database) throws {
        let ids = try PasteboardHistory
            .select { $0.id }
            .fetchAll(database)
        try ids.forEach { id in
            try SyncSuppression.upsert {
                SyncSuppression(
                    syncIdentity: syncIdentity(kind: .history, id: id.rawValue),
                    kind: .history,
                    recordID: id.rawValue,
                    suppressedAt: Int(Date().timeIntervalSince1970)
                )
            }
            .execute(database)
        }
        try PasteboardHistory.delete().execute(database)
    }

    func compactOversizedThumbnailAssets(maxBytes: Int) -> Int {
        let boundedMaxBytes = max(0, maxBytes)
        guard boundedMaxBytes > 0 else { return 0 }
        return withErrorReporting {
            let writer = database
            let compactedCount = try writer.write { database in
                var imageThumbnailCursor = try #sql(
                    """
                    SELECT "pasteboardHistoryID", "kind", "data"
                    FROM "pasteboardHistoryThumbnailAssets"
                    WHERE "kind" = 'image'
                    """,
                    as: PasteboardHistoryThumbnailAsset.self
                )
                .fetchCursor(database)
                var compactedCount = 0
                while let thumbnail = try imageThumbnailCursor.next() {
                    let didCompact = try autoreleasepool { () throws -> Bool in
                        let storedAssets = try PasteboardHistoryAsset
                            .where { $0.pasteboardHistoryID.eq(thumbnail.pasteboardHistoryID) }
                            .fetchAll(database)
                        let content = PasteboardContent(
                            assets: storedAssets.map {
                                PasteboardContent.Asset(type: $0.pasteboardType, data: $0.data)
                            }
                        )
                        let thumbnailMaxBytes = imageThumbnailMaxBytes(for: content, maxBytes: boundedMaxBytes)
                        guard shouldRebuildImageThumbnail(thumbnail, maxBytes: thumbnailMaxBytes),
                              let compactThumbnail = thumbnailAsset(
                                from: content,
                                id: thumbnail.pasteboardHistoryID,
                                maxBytes: boundedMaxBytes
                              ),
                              shouldReplaceImageThumbnail(
                                thumbnail,
                                with: compactThumbnail,
                                maxBytes: thumbnailMaxBytes
                              ) else {
                            return false
                        }
                        try PasteboardHistoryThumbnailAsset
                            .upsert { compactThumbnail }
                            .execute(database)
                        return true
                    }
                    if didCompact {
                        compactedCount += 1
                    }
                }
                return compactedCount
            }
            if compactedCount > 0 {
                try writer.vacuum()
            }
            return compactedCount
        } ?? 0
    }

    private func shouldRebuildImageThumbnail(
        _ thumbnail: PasteboardHistoryThumbnailAsset,
        maxBytes: Int
    ) -> Bool {
        if thumbnail.data.count > maxBytes {
            return true
        }
        guard let pixelSize = imagePixelSize(thumbnail.data) else {
            return true
        }
        let expectedSize = expectedHoverPreviewPixelSize(for: pixelSize)
        return pixelSize.width < expectedSize.width || pixelSize.height < expectedSize.height
    }

    private func shouldReplaceImageThumbnail(
        _ currentThumbnail: PasteboardHistoryThumbnailAsset,
        with replacementThumbnail: PasteboardHistoryThumbnailAsset,
        maxBytes: Int
    ) -> Bool {
        guard replacementThumbnail.kind == .image else { return false }
        guard replacementThumbnail.data.count <= maxBytes else { return false }
        if replacementThumbnail.data.count < currentThumbnail.data.count {
            return true
        }
        return imagePixelArea(replacementThumbnail.data) > imagePixelArea(currentThumbnail.data)
    }

    private func imagePixelArea(_ data: Data) -> Int {
        guard let pixelSize = imagePixelSize(data) else { return 0 }
        return pixelSize.width * pixelSize.height
    }

    private func imagePixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return (bitmap.pixelsWide, bitmap.pixelsHigh)
    }

    private func expectedHoverPreviewPixelSize(
        for currentSize: (width: Int, height: Int)
    ) -> (width: Int, height: Int) {
        let width = CGFloat(currentSize.width)
        let height = CGFloat(currentSize.height)
        guard width > 0, height > 0 else {
            return (Constants.Thumbnail.hoverPreviewPixelWidth, Constants.Thumbnail.hoverPreviewPixelHeight)
        }

        let aspect = width / height
        let targetWidth = CGFloat(Constants.Thumbnail.hoverPreviewPixelWidth)
        let targetHeight = CGFloat(Constants.Thumbnail.hoverPreviewPixelHeight)
        let fittedWidth: CGFloat
        let fittedHeight: CGFloat
        if aspect >= targetWidth / targetHeight {
            fittedWidth = targetWidth
            fittedHeight = targetWidth / aspect
        } else {
            fittedHeight = targetHeight
            fittedWidth = targetHeight * aspect
        }
        return (Int(fittedWidth.rounded(.down)), Int(fittedHeight.rounded(.down)))
    }

    func fetchSyncPayloads(
        currentDeviceID: String?,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) -> [PasteboardHistorySyncPayload] {
        guard let currentDeviceID, limit > 0 else { return [] }
        return withErrorReporting {
            try database.read { database in
                let boundedLimit = max(0, limit)
                let batchSize = max(50, min(500, boundedLimit * 2))
                var remainingTextBudget = max(0, snapshotTextBudgetBytes)
                var payloads = [PasteboardHistorySyncPayload]()
                var offset = 0
                var shouldStop = false

                while payloads.count < boundedLimit, !shouldStop {
                    let histories = try PasteboardHistory
                        .all
                        .where { $0.deviceID.eq(currentDeviceID) }
                        .order { $0.updateAt.desc() }
                        .limit(batchSize, offset: offset)
                        .fetchAll(database)
                    guard !histories.isEmpty else { break }
                    offset += histories.count

                    let candidateHistories = histories.filter { Self.isTextSyncPasteboardTypes($0.pasteboardTypes) }
                    let candidateIDs = candidateHistories.map(\.id)
                    let assetsByHistoryID: [PasteboardHistory.ID: [PasteboardHistoryAsset]]
                    if candidateIDs.isEmpty {
                        assetsByHistoryID = [:]
                    } else {
                        let assets = try PasteboardHistoryAsset
                            .where { $0.pasteboardHistoryID.in(candidateIDs) }
                            .fetchAll(database)
                        assetsByHistoryID = Dictionary(grouping: assets, by: \.pasteboardHistoryID)
                    }

                    for history in candidateHistories {
                        let assets = assetsByHistoryID[history.id] ?? []
                        guard let textPayload = Self.textSyncPayload(from: assets) else { continue }
                        let textByteCount = textPayload.text.lengthOfBytes(using: .utf8)
                        guard textByteCount <= maxTextBytes else { continue }
                        guard textByteCount <= remainingTextBudget else {
                            shouldStop = true
                            break
                        }
                        remainingTextBudget -= textByteCount
                        payloads.append(PasteboardHistorySyncPayload(
                            id: history.id.rawValue,
                            text: textPayload.text,
                            updateAt: history.updateAt,
                            deviceID: history.deviceID,
                            sourceKind: textPayload.sourceKind
                        ))
                        if payloads.count >= boundedLimit {
                            shouldStop = true
                            break
                        }
                    }

                    if histories.count < batchSize {
                        break
                    }
                }
                return payloads
            }
        } ?? []
    }

    func fetchFileSyncSnapshot(
        currentDeviceID: String?,
        limit: Int,
        maxFileBytes: Int
    ) -> FileSyncExportSnapshot {
        fetchFileSyncSnapshot(
            currentDeviceID: currentDeviceID,
            limit: limit,
            maxFileBytes: maxFileBytes,
            includedFileTypes: Set(PasteboardAvailableType.syncFileTypes)
        )
    }

    func fetchFileSyncSnapshot(
        currentDeviceID: String?,
        limit: Int,
        maxFileBytes: Int,
        includedFileTypes: Set<PasteboardAvailableType>
    ) -> FileSyncExportSnapshot {
        guard let currentDeviceID, limit > 0 else {
            return FileSyncExportSnapshot(histories: [], skippedAssetCount: 0)
        }
        let boundedLimit = min(max(0, limit), 10)
        let boundedMaxFileBytes = min(max(0, maxFileBytes), 25 * 1024 * 1024)
        return withErrorReporting {
            try database.read { database in
                var remainingFileSlots = boundedLimit
                var payloads = [FileSyncHistoryPayload]()
                var skippedAssetCount = 0
                var offset = 0
                let batchSize = max(20, boundedLimit * 4)

                while remainingFileSlots > 0 {
                    let histories = try PasteboardHistory
                        .all
                        .where { $0.deviceID.eq(currentDeviceID) }
                        .order { $0.updateAt.desc() }
                        .limit(batchSize, offset: offset)
                        .fetchAll(database)
                    guard !histories.isEmpty else { break }
                    offset += histories.count

                    for history in histories where remainingFileSlots > 0 {
                        guard history.pasteboardTypes.contains(where: Self.isFileSyncPasteboardType) else { continue }
                        let storedAssets = try PasteboardHistoryAsset
                            .where { $0.pasteboardHistoryID.eq(history.id) }
                            .fetchAll(database)
                        let extraction = Self.fileSyncAssets(
                            from: storedAssets,
                            maxFileBytes: boundedMaxFileBytes,
                            includedFileTypes: includedFileTypes
                        )
                        guard extraction.isFileSyncHistory else { continue }
                        if extraction.skippedAssetCount > 0 {
                            skippedAssetCount += extraction.skippedAssetCount
                            continue
                        }
                        guard !extraction.assets.isEmpty else { continue }
                        guard extraction.assets.count <= remainingFileSlots else {
                            skippedAssetCount += extraction.assets.count
                            continue
                        }
                        payloads.append(FileSyncHistoryPayload(
                            deviceID: history.deviceID,
                            historyID: history.id.rawValue,
                            updatedAt: history.updateAt,
                            assets: extraction.assets
                        ))
                        remainingFileSlots -= extraction.assets.count
                    }

                    if histories.count < batchSize {
                        break
                    }
                }

                return FileSyncExportSnapshot(histories: payloads, skippedAssetCount: skippedAssetCount)
            }
        } ?? FileSyncExportSnapshot(histories: [], skippedAssetCount: 0)
    }

    @discardableResult
    func upsertSyncPayload(_ payload: PasteboardHistorySyncPayload) throws -> Bool {
        try database.write { database in
            guard try SyncSuppression
                .find(syncIdentity(kind: .history, id: payload.id))
                .fetchOne(database) == nil else {
                return false
            }
            let historyID = PasteboardHistory.ID(rawValue: payload.id)
            if let existingHistory = try PasteboardHistory.find(historyID).fetchOne(database),
               payload.updateAt <= existingHistory.updateAt {
                return false
            }
            try PasteboardHistory
                .upsert {
                        PasteboardHistory(
                            id: historyID,
                            title: payload.text[0...10000],
                            pasteboardTypes: [.string],
                            updateAt: payload.updateAt,
                            deviceID: payload.deviceID,
                            containsImage: false,
                            containsFile: false,
                            isTextSyncCandidate: true
                        )
                }
                .execute(database)
            try PasteboardHistoryAsset
                .delete()
                .where { $0.pasteboardHistoryID.eq(historyID) }
                .execute(database)
            try PasteboardHistoryThumbnailAsset
                .delete()
                .where { $0.pasteboardHistoryID.eq(historyID) }
                .execute(database)
            try PasteboardHistoryOCRText
                .delete()
                .where { $0.pasteboardHistoryID.eq(historyID) }
                .execute(database)
            let assets = [
                PasteboardHistoryAsset.Draft(
                    pasteboardHistoryID: historyID,
                    pasteboardType: .string,
                    data: Data(payload.text.utf8)
                )
            ]
            try PasteboardHistoryAsset.insert { assets }.execute(database)
            return true
        }
    }

    @discardableResult
    func upsertFileSyncHistory(_ payload: FileSyncHistoryPayload) -> Bool {
        withErrorReporting {
            let historyID = PasteboardHistory.ID(rawValue: payload.historyID)
            return try database.write { database in
                guard try SyncSuppression
                    .find(syncIdentity(kind: .history, id: payload.historyID))
                    .fetchOne(database) == nil else {
                    return false
                }
                if let existingHistory = try PasteboardHistory.find(historyID).fetchOne(database),
                   payload.updatedAt <= existingHistory.updateAt {
                    return false
                }
                let assets = try Self.assets(from: payload)
                guard !assets.isEmpty else { return false }
                let content = PasteboardContent(assets: assets)
                let facets = Self.contentFacets(pasteboardTypes: content.types)
                try PasteboardHistory
                    .upsert {
                        PasteboardHistory(
                            id: historyID,
                            title: content.historyTitle[0...10000],
                            pasteboardTypes: content.types,
                            updateAt: payload.updatedAt,
                            deviceID: payload.deviceID,
                            containsImage: facets.containsImage,
                            containsFile: facets.containsFile,
                            isTextSyncCandidate: facets.isTextSyncCandidate
                        )
                    }
                    .execute(database)
                try PasteboardHistoryAsset
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(historyID) }
                    .execute(database)
                try PasteboardHistoryThumbnailAsset
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(historyID) }
                    .execute(database)
                try PasteboardHistoryOCRText
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(historyID) }
                    .execute(database)
                let drafts = content.assets.map {
                    PasteboardHistoryAsset.Draft(pasteboardHistoryID: historyID, pasteboardType: $0.type, data: $0.data)
                }
                try PasteboardHistoryAsset.insert { drafts }.execute(database)
                if let thumbnailAsset = thumbnailAsset(from: content, id: historyID) {
                    try PasteboardHistoryThumbnailAsset.insert { thumbnailAsset }.execute(database)
                }
                return true
            }
        } ?? false
    }

    func shouldImportFileSyncHistory(historyID: String, updatedAt: Int) -> Bool {
        withErrorReporting {
            let recordID = PasteboardHistory.ID(rawValue: historyID)
            return try database.read { database in
                guard try SyncSuppression
                    .find(syncIdentity(kind: .history, id: recordID.rawValue))
                    .fetchOne(database) == nil else {
                    return false
                }
                if let existingHistory = try PasteboardHistory.find(recordID).fetchOne(database),
                   updatedAt <= existingHistory.updateAt {
                    return false
                }
                return true
            }
        } ?? false
    }

    private static func textSyncPayload(
        from assets: [PasteboardHistoryAsset]
    ) -> (text: String, sourceKind: HistoryTextSourceKind)? {
        let types = Set(assets.map(\.pasteboardType))
        let plainTextTypes: Set<NSPasteboard.PasteboardType> = [.string, .deprecatedString]
        if types.isSubset(of: plainTextTypes),
           let text = assets.compactMap({ plainText(from: $0) }).first {
            return (text, .plainText)
        }

        let urlTypes: Set<NSPasteboard.PasteboardType> = [.URL, .deprecatedURL]
        if types.isSubset(of: urlTypes),
           let urlText = assets.compactMap({ nonFileURLText(from: $0) }).first {
            return (urlText, .url)
        }
        return nil
    }

    private static func isTextSyncPasteboardTypes(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        guard !types.isEmpty else { return false }
        let typeSet = Set(types)
        let plainTextTypes: Set<NSPasteboard.PasteboardType> = [.string, .deprecatedString]
        let urlTypes: Set<NSPasteboard.PasteboardType> = [.URL, .deprecatedURL]
        return typeSet.isSubset(of: plainTextTypes) || typeSet.isSubset(of: urlTypes)
    }

    private static func contentFacets(
        pasteboardTypes: [NSPasteboard.PasteboardType]
    ) -> (containsImage: Bool, containsFile: Bool, isTextSyncCandidate: Bool) {
        (
            pasteboardTypes.contains(where: \.isClipyImageType),
            pasteboardTypes.contains(.fileURL),
            isTextSyncPasteboardTypes(pasteboardTypes)
        )
    }

    private static func isEditablePlainTextHistoryTypes(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        guard !types.isEmpty else { return false }
        let plainTextTypes: Set<NSPasteboard.PasteboardType> = [.string, .deprecatedString]
        return Set(types).isSubset(of: plainTextTypes)
    }

    private static func canHaveOCRImageSource(pasteboardTypes: [NSPasteboard.PasteboardType]) -> Bool {
        pasteboardTypes.contains(where: { $0.isClipyImageType }) || pasteboardTypes.contains(.fileURL)
    }

    private static func canHaveOCRImageSource(content: PasteboardContent) -> Bool {
        if content.assets.contains(where: { $0.type.isClipyImageType }) {
            return true
        }
        return content.assets
            .filter { $0.type == .fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
            .contains { PasteraFileTypeClassifier.kind(for: $0) == .image }
    }

    private func matchesSearchMetadata(
        _ candidate: PasteboardHistorySearchCandidate,
        query: HistorySearchQuery
    ) -> Bool {
        if !query.types.isEmpty && Set(candidate.pasteboardTypes).isDisjoint(with: query.types) {
            return false
        }
        if !query.fileCategories.isEmpty {
            guard candidate.pasteboardTypes.contains(.fileURL) else { return false }
            let fileCategory = PasteraFinderFileCategory.category(forHistoryTitle: candidate.title)
            guard query.fileCategories.contains(fileCategory) else { return false }
        }
        return true
    }

    private func matchesSearchText(
        _ candidate: PasteboardHistorySearchCandidate,
        query: HistorySearchQuery,
        matcher: (String) -> Bool,
        database: Database
    ) throws -> Bool {
        if matcher(candidate.title) {
            return true
        }
        guard !query.text.isEmpty,
              Self.canHaveOCRImageSource(pasteboardTypes: candidate.pasteboardTypes),
              let ocrText = try PasteboardHistoryOCRText.find(candidate.id).fetchOne(database),
              !ocrText.recognizedText.isEmpty else {
            return false
        }
        return matcher("\(candidate.title)\n\(ocrText.recognizedText)")
    }

    private static func plainText(from asset: PasteboardHistoryAsset) -> String? {
        guard asset.pasteboardType == .string || asset.pasteboardType == .deprecatedString else {
            return nil
        }
        return String(data: asset.data, encoding: .utf8)
    }

    private static func nonFileURLText(from asset: PasteboardHistoryAsset) -> String? {
        guard asset.pasteboardType == .URL || asset.pasteboardType == .deprecatedURL else {
            return nil
        }
        if let url = URL(dataRepresentation: asset.data, relativeTo: nil), !url.isFileURL {
            return url.absoluteString
        }
        guard let text = String(data: asset.data, encoding: .utf8),
              let url = URL(string: text),
              !url.isFileURL else {
            return nil
        }
        return url.absoluteString
    }

    func suppressSyncedHistory(id: PasteboardHistory.ID) {
        withErrorReporting {
            try database.write { database in
                try SyncSuppression.upsert {
                    SyncSuppression(
                        syncIdentity: syncIdentity(kind: .history, id: id.rawValue),
                        kind: .history,
                        recordID: id.rawValue,
                        suppressedAt: Int(Date().timeIntervalSince1970)
                    )
                }
                .execute(database)
            }
        }
    }
}

private struct FileSyncAssetExtraction {
    let isFileSyncHistory: Bool
    let assets: [FileSyncAssetPayload]
    let skippedAssetCount: Int
}

private extension PasteboardHistoryRepository {
    static func fileSyncAssets(
        from assets: [PasteboardHistoryAsset],
        maxFileBytes: Int,
        includedFileTypes: Set<PasteboardAvailableType>
    ) -> FileSyncAssetExtraction {
        var fileAssets = [FileSyncAssetPayload]()
        let candidateAssets = assets.enumerated().filter { isFileSyncPasteboardType($0.element.pasteboardType) }
        let candidateCount = candidateAssets.count
        let boundedMaxFileBytes = max(0, maxFileBytes)

        guard candidateCount > 0 else {
            return FileSyncAssetExtraction(isFileSyncHistory: false, assets: [], skippedAssetCount: 0)
        }
        guard !includedFileTypes.isEmpty,
              candidateAssets.allSatisfy({
                  guard let fileType = PasteboardAvailableType.syncFileType(for: $0.element.pasteboardType) else {
                      return false
                  }
                  return includedFileTypes.contains(fileType)
              }) else {
            return FileSyncAssetExtraction(isFileSyncHistory: false, assets: [], skippedAssetCount: 0)
        }

        for (index, asset) in candidateAssets {
            guard let payload = fileSyncAsset(
                from: asset,
                assetIndex: index,
                maxFileBytes: boundedMaxFileBytes
            ) else {
                return FileSyncAssetExtraction(
                    isFileSyncHistory: true,
                    assets: [],
                    skippedAssetCount: candidateCount
                )
            }
            fileAssets.append(payload)
        }

        return FileSyncAssetExtraction(isFileSyncHistory: true, assets: fileAssets, skippedAssetCount: 0)
    }

    static func assets(from payload: FileSyncHistoryPayload) throws -> [PasteboardContent.Asset] {
        guard payload.assets.allSatisfy({ $0.pasteboardType != .fileURL }) else {
            return []
        }
        return payload.assets.sorted { $0.assetIndex < $1.assetIndex }.map { asset in
            PasteboardContent.Asset(type: asset.pasteboardType, data: asset.data)
        }
    }

    static func fileSyncAsset(
        from asset: PasteboardHistoryAsset,
        assetIndex: Int,
        maxFileBytes: Int
    ) -> FileSyncAssetPayload? {
        guard asset.pasteboardType != .fileURL else { return nil }
        guard asset.data.count <= maxFileBytes else { return nil }
        return FileSyncAssetPayload(
            assetIndex: assetIndex,
            pasteboardType: asset.pasteboardType,
            data: asset.data,
            originalFilename: nil
        )
    }

    static func isFileSyncPasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
        PasteboardAvailableType.syncFileType(for: type) != nil
    }

    func fetchSearchCandidates(database: Database) throws -> [PasteboardHistorySearchCandidate] {
        try PasteboardHistory.all
            .order { ($0.updateAt.desc(), $0.id) }
            .fetchAll(database)
            .map { PasteboardHistorySearchCandidate(history: $0) }
    }

    func displayHistoryGroups(
        query: HistorySearchQuery,
        matcher: (String) -> Bool,
        database: Database
    ) throws -> [[PasteboardHistorySearchCandidate]] {
        let candidates = try fetchSearchCandidates(database: database).filter {
            guard matchesSearchMetadata($0, query: query) else { return false }
            return try matchesSearchText($0, query: query, matcher: matcher, database: database)
        }
        let textByID = query.groupsEquivalentText
            ? try groupingTextForCollisions(candidates: candidates, database: database)
            : [:]
        var groups = [[PasteboardHistorySearchCandidate]]()
        var groupIndexByText = [Data: Int]()
        for candidate in candidates {
            if let text = textByID[candidate.id] {
                if let index = groupIndexByText[text] {
                    groups[index].append(candidate)
                    continue
                }
                groupIndexByText[text] = groups.count
            }
            groups.append([candidate])
        }
        // Candidates are newest first, so a group's first record retains its latest content and timestamp.
        return query.sortOrder == .oldestFirst ? Array(groups.reversed()) : groups
    }

    func groupingTextForCollisions(
        candidates: [PasteboardHistorySearchCandidate],
        database: Database
    ) throws -> [PasteboardHistory.ID: Data] {
        let textTypes: Set<NSPasteboard.PasteboardType> = [.string, .deprecatedString, .rtf, .html]
        let textCandidates = candidates.filter { candidate in
            let types = Set(candidate.pasteboardTypes)
            // Repeated rich-text formats also represent multiple pasteboard items.
            return types.count == candidate.pasteboardTypes.count
                && types.isSubset(of: textTypes)
                && (types.contains(.string) || types.contains(.deprecatedString))
        }
        // Titles identify possible collisions only; equality is established from complete asset bytes below.
        let titleGroups = Dictionary(grouping: textCandidates, by: \.title)
        let collisionIDs = titleGroups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) }
        var textByID = [PasteboardHistory.ID: Data]()
        let plainTextTypes: [NSPasteboard.PasteboardType] = [.string, .deprecatedString]
        let batchSize = 100
        for start in stride(from: 0, to: collisionIDs.count, by: batchSize) {
            let ids = Array(collisionIDs[start..<min(start + batchSize, collisionIDs.count)])
            let assets = try PasteboardHistoryAsset
                .where { $0.pasteboardHistoryID.in(ids) }
                .where { $0.pasteboardType.in(plainTextTypes) }
                .fetchAll(database)
            for (id, textAssets) in Dictionary(grouping: assets, by: \.pasteboardHistoryID) {
                let current = textAssets.filter { $0.pasteboardType == .string }
                let legacy = textAssets.filter { $0.pasteboardType == .deprecatedString }
                // Multiple items and contradictory text representations must retain their separate paste semantics.
                guard current.count <= 1, legacy.count <= 1,
                      let text = (current.first ?? legacy.first)?.data,
                      !text.isEmpty,
                      legacy.first.map({ $0.data == text }) ?? true else { continue }
                textByID[id] = text
            }
        }
        return textByID
    }

    func makeMatcher(for query: HistorySearchQuery) throws -> (String) -> Bool {
        guard !query.text.isEmpty else { return { _ in true } }

        switch query.mode {
        case .plain:
            return { value in
                if query.caseSensitive {
                    return value.contains(query.text)
                }
                return value.range(of: query.text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        case .regex:
            let options: NSRegularExpression.Options = query.caseSensitive ? [] : [.caseInsensitive]
            let regularExpression: NSRegularExpression
            do {
                regularExpression = try NSRegularExpression(pattern: query.text, options: options)
            } catch {
                throw HistorySearchError.invalidRegularExpression(query.text)
            }
            return { value in
                let range = NSRange(value.startIndex..., in: value)
                return regularExpression.firstMatch(in: value, options: [], range: range) != nil
            }
        }
    }

    func thumbnailAsset(
        from content: PasteboardContent,
        id: PasteboardHistory.ID,
        maxBytes: Int = Constants.Thumbnail.maxEncodedBytes
    ) -> PasteboardHistoryThumbnailAsset? {
        var asset: PasteboardHistoryThumbnailAsset?
        if let thumbnailImage = content.thumbnailImage,
           let thumbnailData = imageThumbnailData(
            from: thumbnailImage,
            maxBytes: imageThumbnailMaxBytes(for: content, maxBytes: maxBytes)
           ) {
            asset = PasteboardHistoryThumbnailAsset(
                pasteboardHistoryID: id,
                kind: .image,
                data: thumbnailData
            )
        }
        if let colorCodeImage = content.colorCodeImage,
           let colorCodeData = PasteraImageEncoding.pngData(from: colorCodeImage) ?? colorCodeImage.tiffRepresentation {
            asset = PasteboardHistoryThumbnailAsset(
                pasteboardHistoryID: id,
                kind: .colorCode,
                data: colorCodeData
            )
        }
        return asset
    }

    func imageThumbnailData(from image: NSImage, maxBytes: Int) -> Data? {
        guard maxBytes > 0,
              let thumbnailData = PasteraImageEncoding.pngData(from: image, maxBytes: maxBytes) ?? image.tiffRepresentation,
              thumbnailData.count <= maxBytes else {
            return nil
        }
        return thumbnailData
    }

    func imageThumbnailMaxBytes(for content: PasteboardContent, maxBytes: Int) -> Int {
        let boundedMaxBytes = max(0, maxBytes)
        guard let sourceImageBytes = content.assets
            .first(where: { $0.type.isClipyImageType })?
            .data
            .count else {
            return boundedMaxBytes
        }
        return min(boundedMaxBytes, sourceImageBytes)
    }

    func syncIdentity(kind: SyncEntityKind, id: String) -> String {
        "\(kind.rawValue):\(id)"
    }
}

private enum PasteboardHistoryRepositoryKey: DependencyKey {
    static var liveValue: any PasteboardHistoryRepositoryProtocol { PasteboardHistoryRepository() }
}

extension DependencyValues {
    var pasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
        get { self[PasteboardHistoryRepositoryKey.self] }
        set { self[PasteboardHistoryRepositoryKey.self] = newValue }
    }
}
