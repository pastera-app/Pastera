//
//  SyncCoordinatorTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/16.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import Combine
import DependenciesTestSupport
import Foundation
import Testing
@testable import Pastera

// swiftlint:disable file_length

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
// swiftlint:disable:next type_body_length
struct SyncCoordinatorTests {
    private let historyRepository = PasteboardHistoryRepository()
    private let snippetRepository = SnippetRepository()

    @Test
    func coordinatorErrorsUseChineseStatusText() {
        #expect(SyncCoordinatorError.noEnabledWork.localizedDescription == "请先开启至少一个同步开关。")
        #expect(SyncCoordinatorError.missingOneDrive.localizedDescription == "请先安装并登录 OneDrive。")
        #expect(SyncCoordinatorError.folderUnavailable.localizedDescription == "所选 OneDrive 文件夹不可用。")
    }

    @Test
    func settingsStoreCapsHistorySyncLimitAtTwoThousand() throws {
        let suiteName = "Pastera.SyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5000, forKey: Constants.UserDefaults.storedHistoryLimit)

        let settings = UserDefaultsSyncSettingsStore(defaults: defaults).settings()

        #expect(settings.historyLimit == 2000)
    }

    @Test
    func settingsStoreCapsFileSyncLimitsAtSupportedMaximums() throws {
        let suiteName = "Pastera.SyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(250 * 1024 * 1024, forKey: Constants.UserDefaults.maxSyncedFileBytes)
        defaults.set(99, forKey: Constants.UserDefaults.syncedFileLimitPerDevice)

        let settings = UserDefaultsSyncSettingsStore(defaults: defaults).settings()

        #expect(settings.maxSyncedFileBytes == 25 * 1024 * 1024)
        #expect(settings.syncedFileLimitPerDevice == 10)
    }

    @Test
    func defaultFolderResolverCreatesRecommendedCloudStorageOneDriveFolder() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let oneDriveRootURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive")
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        let expectedURL = oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .found(let candidate) = resolution else {
            #expect(Bool(false), "Expected a single recommended OneDrive sync location, got \(resolution)")
            return
        }
        #expect(candidate.displayName == "OneDrive")
        #expect(candidate.oneDriveRootURL == oneDriveRootURL.resolvingSymlinksInPath().standardizedFileURL)
        #expect(candidate.syncRootURL == expectedURL.resolvingSymlinksInPath().standardizedFileURL)
        #expect(candidate.isOneDriveBacked)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: expectedURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test
    func defaultFolderResolverChoosesPersonalOneDriveWhenMultipleAccountsExist() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let personalURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive")
        let workURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive - Work")
        try FileManager.default.createDirectory(at: personalURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .found(let candidate) = resolution else {
            #expect(Bool(false), "Expected the personal OneDrive candidate, got \(resolution)")
            return
        }
        #expect(candidate.displayName == "OneDrive")
        #expect(FileManager.default.fileExists(atPath: syncRootURL(oneDriveRootURL: personalURL).path))
        #expect(!FileManager.default.fileExists(atPath: syncRootURL(oneDriveRootURL: workURL).path))
    }

    @Test
    func defaultFolderResolverRequiresSelectionForSingleNamedAccount() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let workURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive-公司名称")
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .multiple(let candidates) = resolution else {
            #expect(Bool(false), "Expected explicit selection for a named OneDrive account, got \(resolution)")
            return
        }
        #expect(candidates.map(\.displayName) == ["OneDrive-公司名称"])
        #expect(!FileManager.default.fileExists(atPath: syncRootURL(oneDriveRootURL: workURL).path))
    }

    @Test
    func defaultFolderResolverRequiresSelectionForMultipleNamedAccounts() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let firstURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive-公司甲")
        let secondURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive-公司乙")
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .multiple(let candidates) = resolution else {
            #expect(Bool(false), "Expected explicit selection for multiple OneDrive accounts, got \(resolution)")
            return
        }
        #expect(Set(candidates.map(\.displayName)) == ["OneDrive-公司甲", "OneDrive-公司乙"])
        #expect(!FileManager.default.fileExists(atPath: syncRootURL(oneDriveRootURL: firstURL).path))
        #expect(!FileManager.default.fileExists(atPath: syncRootURL(oneDriveRootURL: secondURL).path))
    }

    @Test
    func defaultFolderResolverDoesNotFallbackToDocumentsFolder() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let documentsOneDriveURL = homeURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("oneDrive", isDirectory: true)
        try FileManager.default.createDirectory(at: documentsOneDriveURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        #expect(resolution == .notFound)
        #expect(!FileManager.default.fileExists(
            atPath: syncRootURL(oneDriveRootURL: documentsOneDriveURL).path
        ))
    }

    @Test
    func defaultFolderResolverDeduplicatesCanonicalOneDriveRoots() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let oneDriveURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive")
        let aliasURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive - Alias")
        try FileManager.default.createDirectory(at: oneDriveURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: oneDriveURL)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .found(let candidate) = resolution else {
            #expect(Bool(false), "Expected duplicate canonical OneDrive roots to collapse to one candidate")
            return
        }
        #expect(candidate.oneDriveRootURL == oneDriveURL.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test
    func defaultFolderResolverIgnoresEnglishSharedLibraryWithoutFileProviderIdentity() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let sharedLibraryURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive - Shared Libraries - Work")
        try FileManager.default.createDirectory(at: sharedLibraryURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        #expect(resolution == .notFound)
    }

    @Test
    func defaultFolderResolverRejectsCloudTempEvenWhenFileProviderBacked() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let cloudTempURL = oneDriveRootURL(homeURL: homeURL, name: "OneDriveCloudTemp")
        try FileManager.default.createDirectory(at: cloudTempURL, withIntermediateDirectories: true)
        let resolver = SyncDefaultFolderResolver(
            fileManager: .default,
            fileProviderIdentityChecker: { _ in true }
        )

        #expect(resolver.resolve(homeDirectory: homeURL) == .notFound)
    }

    @Test
    func defaultFolderResolverIgnoresLocalizedSharedLibraryWithoutFileProviderIdentity() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let sharedLibraryURL = oneDriveRootURL(
            homeURL: homeURL,
            name: "OneDrive-共享的库-oneDrive"
        )
        try FileManager.default.createDirectory(at: sharedLibraryURL, withIntermediateDirectories: true)

        let resolver = SyncDefaultFolderResolver(fileManager: .default)

        #expect(resolver.resolve(homeDirectory: homeURL) == .notFound)
        #expect(resolver.oneDriveCandidates(homeDirectory: homeURL).isEmpty)
    }

    @Test
    func defaultFolderResolverIncludesLocalizedFileProviderSharedLibrary() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let sharedLibraryURL = oneDriveRootURL(
            homeURL: homeURL,
            name: "OneDrive-共享的库-oneDrive"
        )
        try FileManager.default.createDirectory(at: sharedLibraryURL, withIntermediateDirectories: true)
        let expectedRootURL = sharedLibraryURL.standardizedFileURL
        let resolver = SyncDefaultFolderResolver(
            fileManager: .default,
            fileProviderIdentityChecker: { $0.standardizedFileURL == expectedRootURL }
        )

        let candidates = resolver.oneDriveCandidates(homeDirectory: homeURL)

        #expect(candidates.map(\.oneDriveRootURL) == [expectedRootURL])
        #expect(candidates.map(\.displayName) == ["OneDrive-共享的库-oneDrive"])
    }

    @Test
    func passwordVaultRootValidationRejectsLocalizedSharedLibraryWithoutFileProviderIdentity() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let rootURL = syncRootURL(oneDriveRootURL: oneDriveRootURL(
            homeURL: homeURL,
            name: "OneDrive-共享的库-oneDrive"
        ))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        #expect(Environment.validatePasswordVaultSyncRoot(rootURL) == .folderUnavailable)
    }

    @Test
    func passwordVaultRootValidationAllowsLocalizedFileProviderSharedLibrary() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let sharedLibraryURL = oneDriveRootURL(
            homeURL: homeURL,
            name: "OneDrive-共享的库-oneDrive"
        )
        let rootURL = syncRootURL(oneDriveRootURL: sharedLibraryURL)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let expectedRootURL = sharedLibraryURL.standardizedFileURL

        let failure = Environment.validatePasswordVaultSyncRoot(
            rootURL,
            fileProviderIdentityChecker: { $0.standardizedFileURL == expectedRootURL }
        )

        #expect(failure == nil)
    }

    @Test
    func passwordVaultRootValidationAllowsExplicitlySelectedWorkAccount() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let rootURL = syncRootURL(oneDriveRootURL: oneDriveRootURL(
            homeURL: homeURL,
            name: "OneDrive-公司名称"
        ))
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        #expect(Environment.validatePasswordVaultSyncRoot(rootURL) == nil)
    }

    @Test
    func coordinatorHonorsIndependentUploadSwitches() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Synced history".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 10)
        let folder = try #require(snippetRepository.insertFolder())
        _ = try #require(snippetRepository.insertSnippet(to: folder.id))

        var settings = makeSettings(rootURL: rootURL, historyUpload: true, snippetUpload: false)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.count == 1)
        #expect(try provider.loadSnippetSnapshots(excludingDeviceID: "remote-device").isEmpty)

        settings = makeSettings(rootURL: rootURL, historyUpload: false, snippetUpload: true)
        coordinator.syncNow(reason: .manual, wait: true)

        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.count == 1)
        #expect(try provider.loadSnippetSnapshots(excludingDeviceID: "remote-device").first?.snapshot.snippets.count == 1)
        #expect(try provider.loadSnippetSnapshots(excludingDeviceID: "remote-device").first?.snapshot.folders.count == 1)
    }

    @Test
    func coordinatorSkipsUnchangedHistoryWindowUpload() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Stable history".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 10)
        let settings = makeSettings(rootURL: rootURL, historyUpload: true)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)
        let sqliteURL = rootURL.appendingPathComponent("history/devices/\(currentDeviceID).sqlite")
        let firstModificationDate = try #require(FileManager.default
            .attributesOfItem(atPath: sqliteURL.path)[.modificationDate] as? Date)
        Thread.sleep(forTimeInterval: 1.1)

        coordinator.syncNow(reason: .manual, wait: true)

        let secondModificationDate = try #require(FileManager.default
            .attributesOfItem(atPath: sqliteURL.path)[.modificationDate] as? Date)
        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.uploadedCount == 0)
        #expect(secondModificationDate == firstModificationDate)
    }

    @Test
    func coordinatorDoesNotPostStatusChangeForAutomaticHistoryNoOp() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Quiet no-op".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 10)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyUpload: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )
        var notificationCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: SyncCoordinator.statusDidChangeNotification,
            object: coordinator,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        coordinator.syncNow(reason: .manual, wait: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        notificationCount = 0

        coordinator.syncNow(reason: .timer, wait: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(notificationCount == 0)
        #expect(coordinator.status.uploadedCount == 1)
    }

    @Test
    func coordinatorClearsFailedStatusAfterSuccessfulAutomaticNoOp() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        try provider.saveHistorySnapshot(
            [], deviceID: "remote-device", limit: 2000,
            maxTextBytes: 256 * 1024, snapshotTextBudgetBytes: 8 * 1024 * 1024
        )
        let devicesURL = rootURL.appendingPathComponent("history/devices", isDirectory: true)
        try FileManager.default.removeItem(at: devicesURL)
        try Data("Blocked history directory".utf8).write(to: devicesURL)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .failed)
        #expect(coordinator.status.errorDescription != nil)
        try FileManager.default.removeItem(at: devicesURL)
        try FileManager.default.createDirectory(at: devicesURL, withIntermediateDirectories: true)

        coordinator.syncNow(reason: .timer, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.errorDescription == nil)
        #expect(coordinator.status.importedCount == 0)
        #expect(coordinator.status.uploadedCount == 0)
    }

    @Test
    func coordinatorClearsSkippedStatusAfterSuccessfulAutomaticNoOp() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.removeItem(at: rootURL)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyImport: true) },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .skipped)
        #expect(coordinator.status.errorDescription != nil)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        coordinator.syncNow(reason: .timer, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.errorDescription == nil)
        #expect(coordinator.status.importedCount == 0)
        #expect(coordinator.status.uploadedCount == 0)
    }

    @Test
    func coordinatorClearsWarningAfterSuccessfulAutomaticNoOp() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let remoteDirectoryURL = rootURL.appendingPathComponent("files/devices/remote-device", isDirectory: true)
        try FileManager.default.createDirectory(at: remoteDirectoryURL, withIntermediateDirectories: true)
        try Data("Incomplete manifest".utf8).write(to: remoteDirectoryURL.appendingPathComponent("manifest.json"))
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, fileImport: true) },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.warningDescription != nil)
        try FileManager.default.removeItem(at: remoteDirectoryURL)

        coordinator.syncNow(reason: .timer, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.warningDescription == nil)
        #expect(coordinator.status.importedCount == 0)
        #expect(coordinator.status.uploadedCount == 0)
    }

    @Test
    func coordinatorSkipsUnchangedRemoteHistorySnapshotBeforeUpsert() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        try provider.saveHistorySnapshot([
            PasteboardHistorySyncPayload(
                id: "remote-history",
                text: "Remote",
                updateAt: 10,
                deviceID: "remote-device",
                sourceKind: .plainText
            )
        ], deviceID: "remote-device", limit: 2000, maxTextBytes: 256 * 1024, snapshotTextBudgetBytes: 8 * 1024 * 1024)
        let countingRepository = CountingHistoryRepository()
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyImport: true) },
            providerFactory: { _ in provider },
            historyRepository: countingRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)
        #expect(countingRepository.upsertedHistoryIDs == ["remote-history"])
        countingRepository.upsertedHistoryIDs.removeAll()

        coordinator.syncNow(reason: .timer, wait: true)

        #expect(countingRepository.upsertedHistoryIDs.isEmpty)
    }

    @Test
    func coordinatorPreservesRemoteHistoryWarningAfterUploadOnlyNoOp() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyUpload: true, historyImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )
        coordinator.syncNow(reason: .manual, wait: true)

        let remoteID = PasteboardHistory.ID(rawValue: "pending-remote-history")
        try provider.saveHistorySnapshot([
            PasteboardHistorySyncPayload(
                id: remoteID.rawValue, text: "Pending remote history", updateAt: 10,
                deviceID: "remote-device", sourceKind: .plainText
            )
        ], deviceID: "remote-device", limit: 2000, maxTextBytes: 256 * 1024,
           snapshotTextBudgetBytes: 8 * 1024 * 1024)
        let snapshotURL = rootURL.appendingPathComponent("history/devices/remote-device.sqlite")
        let validBytes = try Data(contentsOf: snapshotURL)
        try Data(repeating: 0xFF, count: validBytes.count).write(to: snapshotURL)

        coordinator.syncNow(reason: .timer, wait: true)

        let warning = try #require(coordinator.status.warningDescription)
        #expect(historyRepository.fetchHistory(id: remoteID) == nil)

        coordinator.syncNow(reason: .localChange, wait: true)

        #expect(coordinator.status.warningDescription == warning)
        #expect(coordinator.status.uploadedCount == 0)
        #expect(historyRepository.fetchHistory(id: remoteID) == nil)

        try validBytes.write(to: snapshotURL)
        coordinator.syncNow(reason: .timer, wait: true)

        #expect(historyRepository.fetchHistory(id: remoteID)?.title == "Pending remote history")
        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.warningDescription == nil)
    }

    @Test
    func coordinatorRetriesRecoveredHistorySnapshotWithUnchangedFileState() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let remoteID = PasteboardHistory.ID(rawValue: "recovered-remote-history")
        try provider.saveHistorySnapshot([
            PasteboardHistorySyncPayload(
                id: remoteID.rawValue,
                text: "Recovered remote history",
                updateAt: 10,
                deviceID: "remote-device",
                sourceKind: .plainText
            )
        ], deviceID: "remote-device", limit: 2000, maxTextBytes: 256 * 1024, snapshotTextBudgetBytes: 8 * 1024 * 1024)
        let snapshotURL = rootURL.appendingPathComponent("history/devices/remote-device.sqlite")
        let validBytes = try Data(contentsOf: snapshotURL)
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        try Data(repeating: 0xFF, count: validBytes.count).write(to: snapshotURL)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: snapshotURL.path)
        let failedFileStates = try provider.historySnapshotFileStates(excludingDeviceID: currentDeviceID)
        #expect(failedFileStates.count == 1)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(historyRepository.fetchHistory(id: remoteID) == nil)
        #expect(coordinator.status.warningDescription != nil)
        try validBytes.write(to: snapshotURL)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: snapshotURL.path)
        let recoveredFileStates = try provider.historySnapshotFileStates(excludingDeviceID: currentDeviceID)
        #expect(recoveredFileStates == failedFileStates)

        coordinator.syncNow(reason: .timer, wait: true)

        #expect(historyRepository.fetchHistory(id: remoteID)?.title == "Recovered remote history")
        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 1)
        #expect(coordinator.status.warningDescription == nil)
    }

    @Test
    func coordinatorHonorsIndependentFileSwitches() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let text = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .string, data: Data("Text history".utf8))]
        )
        let pdf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data("%PDF".utf8))]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 20)
        historyRepository.save(id: PasteboardHistory.ID(rawValue: pdf.hash), content: pdf, updateAt: 10)

        var settings = makeSettings(rootURL: rootURL, historyUpload: true, fileUpload: false)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.count == 1)
        #expect(try provider.loadFileSnapshots(excludingDeviceID: "remote-device").isEmpty)

        settings = makeSettings(rootURL: rootURL, historyUpload: false, fileUpload: true)
        coordinator.syncNow(reason: .manual, wait: true)

        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.count == 1)
        let fileSnapshot = try #require(provider.loadFileSnapshots(excludingDeviceID: "remote-device").first)
        #expect(fileSnapshot.histories.map(\.historyID) == [pdf.hash])
        #expect(fileSnapshot.histories.first?.assets.first?.pasteboardType == .pdf)
        #expect(coordinator.status.uploadedCount == 1)
    }

    @Test
    func coordinatorCleansDuplicateSnippetsBeforeExport() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snippetRepository = SyncSnippetRepository(
            snapshot: makeSnippetSnapshot(title: "AI Prompt", content: "Prompt")
        )
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, snippetUpload: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(snippetRepository.removeDuplicateCallCount == 1)
        #expect(try provider.loadSnippetSnapshots(excludingDeviceID: "remote-device").first?.snapshot.folders.count == 1)
        #expect(try provider.loadSnippetSnapshots(excludingDeviceID: "remote-device").first?.snapshot.snippets.count == 1)
    }

    @Test
    func coordinatorCleansDuplicateSnippetsBeforeImport() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let remoteSnapshot = makeSnippetSnapshot(title: "AI Prompt", content: "Prompt")
        try provider.saveSnippetSnapshot(remoteSnapshot, deviceID: "remote-device")
        let snippetRepository = SyncSnippetRepository(upsertResult: 1)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, snippetImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(snippetRepository.removeDuplicateCallCount == 1)
        #expect(snippetRepository.upsertedSnapshots == [remoteSnapshot])
        #expect(coordinator.status.importedCount == 1)
    }

    @Test
    func coordinatorReportsSkippedFileWarningWithoutBlockingTextHistoryUpload() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let text = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .string, data: Data("Text still syncs".utf8))]
        )
        let tooLarge = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data(repeating: 1, count: 6))]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 20)
        historyRepository.save(id: PasteboardHistory.ID(rawValue: tooLarge.hash), content: tooLarge, updateAt: 10)
        let settings = makeSettings(
            rootURL: rootURL,
            historyUpload: true,
            fileUpload: true,
            maxSyncedFileBytes: 5
        )
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.count == 1)
        #expect(try provider.loadFileSnapshots(excludingDeviceID: "remote-device").first?.histories.isEmpty == true)
        #expect(coordinator.status.statusText.contains("已跳过 1 个文件"))
    }

    @Test
    func coordinatorReportsImportFileValidationWarningWithoutFailingSync() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "remote-device",
                    historyID: "remote-file",
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
        try provider.saveFileSnapshot(snapshot, deviceID: "remote-device")
        let objectURL = try #require(FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/remote-device/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.first { $0.pathExtension == "pdf" })
        try Data("tampered".utf8).write(to: objectURL)
        let settings = makeSettings(rootURL: rootURL, fileImport: true)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 0)
        #expect(coordinator.status.statusText.contains("已跳过 1 个文件（缺失、超限或校验失败）"))
    }

    @Test
    func coordinatorCapsImportedFilesPerRemoteDeviceBeforeReadingEverything() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let histories = (0..<11).map { index in
            FileSyncHistoryPayload(
                deviceID: "remote-device",
                historyID: "remote-file-\(index)",
                updatedAt: 100 - index,
                assets: [
                    FileSyncAssetPayload(
                        assetIndex: 0,
                        pasteboardType: .pdf,
                        data: Data("PDF-\(index)".utf8),
                        originalFilename: "remote-\(index).pdf"
                    )
                ]
            )
        }
        try provider.saveFileSnapshot(FileSyncExportSnapshot(histories: histories, skippedAssetCount: 0), deviceID: "remote-device")
        let settings = makeSettings(rootURL: rootURL, fileImport: true, syncedFileLimitPerDevice: 10)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 10)
        #expect(historyRepository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-file-0")) != nil)
        #expect(historyRepository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-file-9")) != nil)
        #expect(historyRepository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-file-10")) == nil)
        #expect(coordinator.status.statusText.contains("已跳过 1 个文件"))
    }

    @Test
    func coordinatorDoesNotReadOrWarnAboutUnselectedFileTypesDuringImport() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let snapshot = FileSyncExportSnapshot(
            histories: [
                FileSyncHistoryPayload(
                    deviceID: "remote-device",
                    historyID: "remote-image",
                    updatedAt: 20,
                    assets: [
                        FileSyncAssetPayload(
                            assetIndex: 0,
                            pasteboardType: .png,
                            data: Data([0x89, 0x50, 0x4E, 0x47]),
                            originalFilename: nil
                        )
                    ]
                ),
                FileSyncHistoryPayload(
                    deviceID: "remote-device",
                    historyID: "remote-pdf",
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
        try provider.saveFileSnapshot(snapshot, deviceID: "remote-device")
        let imageObjectURL = try #require(FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/remote-device/assets/remote-image", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.first { $0.pathExtension == "png" })
        try Data("tampered image".utf8).write(to: imageObjectURL)
        let settings = makeSettings(
            rootURL: rootURL,
            fileImport: true,
            fileAssetTypes: [.pdf]
        )
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 1)
        #expect(!coordinator.status.statusText.contains("已跳过"))
        #expect(historyRepository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-image")) == nil)
        #expect(historyRepository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-pdf"))?.assets.first?.type == .pdf)
    }

    @Test
    func coordinatorTimerUsesGranularUploadAndImportScopes() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Local upload".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 10)
        let remoteID = PasteboardHistory.ID(rawValue: "remote-history")
        try provider.saveHistorySnapshot([
            PasteboardHistorySyncPayload(
                id: remoteID.rawValue,
                text: "Remote history",
                updateAt: 20,
                deviceID: "remote-device",
                sourceKind: .plainText
            )
        ], deviceID: "remote-device", limit: 2000, maxTextBytes: 256 * 1024, snapshotTextBudgetBytes: 8 * 1024 * 1024)
        var settings = makeSettings(
            rootURL: rootURL,
            historyUpload: true,
            historyImport: false
        )
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .timer, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(historyRepository.fetchHistory(id: remoteID) == nil)
        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.count == 1)

        settings = makeSettings(
            rootURL: rootURL,
            historyUpload: false,
            historyImport: true
        )
        coordinator.syncNow(reason: .timer, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.uploadedCount == 0)
        #expect(historyRepository.fetchHistory(id: remoteID)?.title == "Remote history")
    }

    @Test
    func coordinatorLocalChangeUploadsWhenUploadScopeIsOn() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Background gated".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 10)
        let settings = makeSettings(rootURL: rootURL, historyUpload: true)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .localChange, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(try provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.count == 1)
    }

    @Test
    func coordinatorLocalChangeDoesNotImportWhenOnlyImportScopeIsOn() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let remoteID = PasteboardHistory.ID(rawValue: "remote-import-only")
        try provider.saveHistorySnapshot([
            PasteboardHistorySyncPayload(
                id: remoteID.rawValue,
                text: "Remote import only",
                updateAt: 20,
                deviceID: "remote-device",
                sourceKind: .plainText
            )
        ], deviceID: "remote-device", limit: 2000, maxTextBytes: 256 * 1024, snapshotTextBudgetBytes: 8 * 1024 * 1024)
        let settings = makeSettings(rootURL: rootURL, historyImport: true)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .localChange, wait: true)

        #expect(coordinator.status.phase == .idle)
        #expect(historyRepository.fetchHistory(id: remoteID) == nil)
    }

    @Test
    func coordinatorCountsOnlyActualImportsWhenRemoteRecordIsSkippedByLWW() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let localContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Local newer".utf8))
            ]
        )
        let sharedID = PasteboardHistory.ID(rawValue: "shared-history")
        historyRepository.save(id: sharedID, content: localContent, updateAt: 30)
        let remotePayload = PasteboardHistorySyncPayload(
            id: sharedID.rawValue,
            text: "Remote older",
            updateAt: 20,
            deviceID: "remote-device",
            sourceKind: .plainText
        )
        try provider.saveHistorySnapshot(
            [remotePayload],
            deviceID: "remote-device",
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 8 * 1024 * 1024
        )
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 0)
        #expect(coordinator.status.statusText == "没有新数据。OneDrive 云端上传状态请查看 OneDrive。")
        #expect(historyRepository.fetchHistory(id: sharedID)?.title == "Local newer")
    }

    @Test
    func coordinatorDoesNotReadOlderRemoteFileAssets() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let sharedID = PasteboardHistory.ID(rawValue: "shared-file-history")
        let localContent = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data("local newer pdf".utf8))]
        )
        historyRepository.save(id: sharedID, content: localContent, updateAt: 30)
        let remotePayload = FileSyncHistoryPayload(
            deviceID: "remote-device",
            historyID: sharedID.rawValue,
            updatedAt: 20,
            assets: [
                FileSyncAssetPayload(
                    assetIndex: 0,
                    pasteboardType: .pdf,
                    data: Data("remote older pdf".utf8),
                    originalFilename: "remote.pdf"
                )
            ]
        )
        try provider.saveFileSnapshot(
            FileSyncExportSnapshot(histories: [remotePayload], skippedAssetCount: 0),
            deviceID: "remote-device"
        )
        let objectURL = try #require(FileManager.default.enumerator(
            at: rootURL.appendingPathComponent("files/devices/remote-device/assets", isDirectory: true),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.first { $0.pathExtension == "pdf" })
        try Data("tampered remote bytes".utf8).write(to: objectURL)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, fileImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 0)
        #expect(!coordinator.status.statusText.contains("已跳过"))
        #expect(historyRepository.fetchContent(id: sharedID) == localContent)
    }

    @Test
    func coordinatorUploadsBusinessTimestampWithoutFallback() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Zero timestamp".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 0)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyUpload: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        let payload = try #require(provider.loadHistorySnapshots(excludingDeviceID: "remote-device").first?.payloads.first)
        #expect(payload.updateAt == 0)
        #expect(payload.text == "Zero timestamp")
        #expect(payload.sourceKind == .plainText)
        #expect(coordinator.status.statusText == "已写入 1 条到本地同步文件夹，等待 OneDrive 客户端上传；Pastera 不知道云端是否已完成。")
    }

    @Test
    func coordinatorSynchronizesOneDriveVaultWhileLockedWithoutGenericRoot() throws {
        let missingRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vaultSync = CoordinatorPasswordVaultSyncController(
            snapshot: makeVaultSnapshot(mode: .oneDrive, localVaultAvailable: false)
        )
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: missingRootURL) },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository,
            passwordVaultSyncServiceProvider: { vaultSync }
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(vaultSync.synchronizeReasons == [.manual])
        #expect(vaultSync.snapshot.mode == .oneDrive)
        #expect(coordinator.status.phase == .idle)
    }

    @Test
    func coordinatorDebouncesPendingVaultChanges() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let vaultSync = CoordinatorPasswordVaultSyncController(
            snapshot: makeVaultSnapshot(mode: .oneDrive, pendingChangeCount: 0)
        )
        let processStatus = CoordinatorOneDriveProcessStatusService()
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL) },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository,
            passwordVaultSyncServiceProvider: { vaultSync },
            oneDriveProcessStatusServiceProvider: { processStatus },
            vaultChangeDebounceInterval: 0.02
        )
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.syncNow(reason: .timer, wait: true)
        vaultSync.removeSynchronizeReasons()

        vaultSync.publish(makeVaultSnapshot(mode: .oneDrive, pendingChangeCount: 1))
        vaultSync.publish(makeVaultSnapshot(mode: .oneDrive, pendingChangeCount: 2))
        Thread.sleep(forTimeInterval: 0.08)
        coordinator.syncNow(reason: .timer, wait: true)

        #expect(vaultSync.synchronizeReasons.filter { $0 == .localChange }.count == 1)
    }

    @Test
    func coordinatorRetriesWhenVaultModeChangesToOneDrive() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let vaultSync = CoordinatorPasswordVaultSyncController(
            snapshot: makeVaultSnapshot(mode: .localOnly)
        )
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL) },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository,
            passwordVaultSyncServiceProvider: { vaultSync }
        )
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.syncNow(reason: .timer, wait: true)
        vaultSync.removeSynchronizeReasons()

        vaultSync.publish(makeVaultSnapshot(mode: .oneDrive))
        coordinator.syncNow(reason: .timer, wait: true)

        #expect(vaultSync.synchronizeReasons.filter { $0 == .startup }.count == 1)
    }

    @Test
    func coordinatorRebindsDynamicVaultServiceWhenOneDriveLifecycleChanges() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let localOnlySync = CoordinatorPasswordVaultSyncController(
            snapshot: makeVaultSnapshot(mode: .localOnly)
        )
        let oneDriveSync = CoordinatorPasswordVaultSyncController(
            snapshot: makeVaultSnapshot(mode: .oneDrive)
        )
        var currentSync = localOnlySync
        let processStatus = CoordinatorOneDriveProcessStatusService()
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL) },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository,
            passwordVaultSyncServiceProvider: { currentSync },
            oneDriveProcessStatusServiceProvider: { processStatus },
            vaultChangeDebounceInterval: 0.02
        )
        coordinator.start()
        coordinator.syncNow(reason: .timer, wait: true)
        localOnlySync.removeSynchronizeReasons()

        currentSync = oneDriveSync
        processStatus.sendLifecycleChange()
        processStatus.sendLifecycleChange()
        Thread.sleep(forTimeInterval: 0.04)
        coordinator.syncNow(reason: .timer, wait: true)

        #expect(localOnlySync.synchronizeReasons.isEmpty)
        #expect(oneDriveSync.synchronizeReasons.filter { $0 == .startup }.count == 2)

        oneDriveSync.removeSynchronizeReasons()
        oneDriveSync.publish(makeVaultSnapshot(mode: .oneDrive, pendingChangeCount: 1))
        Thread.sleep(forTimeInterval: 0.08)
        coordinator.syncNow(reason: .timer, wait: true)
        #expect(oneDriveSync.synchronizeReasons.filter { $0 == .localChange }.count == 1)

        coordinator.stop()
        oneDriveSync.removeSynchronizeReasons()
        processStatus.sendLifecycleChange()
        oneDriveSync.publish(makeVaultSnapshot(mode: .oneDrive, pendingChangeCount: 2))
        Thread.sleep(forTimeInterval: 0.08)

        #expect(oneDriveSync.synchronizeReasons.isEmpty)
    }

    @Test
    func coordinatorRetriesVaultImmediatelyWhenOneDriveLifecycleChangesWhileGenericQueueIsBusy() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let vaultSync = CoordinatorPasswordVaultSyncController(
            snapshot: makeVaultSnapshot(mode: .oneDrive)
        )
        let processStatus = CoordinatorOneDriveProcessStatusService()
        let coordinatorQueue = DispatchQueue(label: "Pastera.SyncCoordinatorTests.blocked")
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL) },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository,
            passwordVaultSyncServiceProvider: { vaultSync },
            oneDriveProcessStatusServiceProvider: { processStatus },
            queue: coordinatorQueue
        )
        coordinator.start()
        coordinator.syncNow(reason: .timer, wait: true)
        vaultSync.removeSynchronizeReasons()

        let enteredQueue = DispatchSemaphore(value: 0)
        let releaseQueue = DispatchSemaphore(value: 0)
        coordinatorQueue.async {
            enteredQueue.signal()
            _ = releaseQueue.wait(timeout: .now() + 5)
        }
        #expect(enteredQueue.wait(timeout: .now() + 1) == .success)

        processStatus.sendLifecycleChange()

        #expect(vaultSync.synchronizeReasons == [.startup])

        releaseQueue.signal()
        coordinator.syncNow(reason: .timer, wait: true)
        coordinator.stop()
    }

    private func makeRootURL() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func oneDriveRootURL(homeURL: URL, name: String) -> URL {
        homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private func syncRootURL(oneDriveRootURL: URL) -> URL {
        oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    private func makeSettings(
        rootURL: URL,
        historyUpload: Bool = false,
        historyImport: Bool = false,
        snippetUpload: Bool = false,
        snippetImport: Bool = false,
        fileUpload: Bool = false,
        fileImport: Bool = false,
        fileAssetTypes: Set<PasteboardAvailableType> = Set(PasteboardAvailableType.syncFileTypes),
        maxSyncedFileBytes: Int = 25 * 1024 * 1024,
        syncedFileLimitPerDevice: Int = 10
    ) -> SyncSettings {
        SyncSettings(
            rootURL: rootURL,
            historyUploadEnabled: historyUpload,
            historyImportEnabled: historyImport,
            snippetUploadEnabled: snippetUpload,
            snippetImportEnabled: snippetImport,
            fileUploadEnabled: fileUpload,
            fileImportEnabled: fileImport,
            fileAssetTypes: fileAssetTypes,
            pollInterval: 300,
            maxSyncedHistoryTextBytes: 256 * 1024,
            maxHistorySnapshotTextBudgetBytes: 8 * 1024 * 1024,
            historyLimit: 2000,
            maxSyncedFileBytes: maxSyncedFileBytes,
            syncedFileLimitPerDevice: syncedFileLimitPerDevice
        )
    }

    private func makeSnippetSnapshot(title: String, content: String) -> SnippetSyncSnapshot {
        let folderID = UUID().uuidString
        return SnippetSyncSnapshot(
            folders: [
                SnippetFolderSyncPayload(
                    id: folderID,
                    title: title,
                    index: 0,
                    isEnabled: true,
                    updatedAt: 10,
                    deviceID: "test-device"
                )
            ],
            snippets: [
                SnippetSyncPayload(
                    id: UUID().uuidString,
                    folderID: folderID,
                    title: "Snippet",
                    content: content,
                    index: 0,
                    isEnabled: true,
                    updatedAt: 10,
                    deviceID: "test-device"
                )
            ]
        )
    }

    private var currentDeviceID: String {
        CPYUtilities.deviceID ?? ProcessInfo.processInfo.hostName
    }

    private func makeVaultSnapshot(
        mode: PasswordVaultSyncMode,
        localVaultAvailable: Bool = true,
        pendingChangeCount: Int = 0
    ) -> PasswordVaultSyncSnapshot {
        PasswordVaultSyncSnapshot(
            mode: mode,
            phase: mode == .oneDrive ? .synced : .disabled,
            localVaultAvailable: localVaultAvailable,
            remoteVaultAvailable: mode == .oneDrive,
            pendingChangeCount: pendingChangeCount,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
    }
}

private final class CoordinatorPasswordVaultSyncController: PasswordVaultSyncControlling {
    private let lock = NSLock()
    private var currentSnapshot: PasswordVaultSyncSnapshot
    private var observers = [UUID: (PasswordVaultSyncSnapshot) -> Void]()
    private var reasons = [SyncCoordinator.Reason]()

    init(snapshot: PasswordVaultSyncSnapshot) {
        currentSnapshot = snapshot
    }

    var snapshot: PasswordVaultSyncSnapshot {
        lock.withLock { currentSnapshot }
    }

    var synchronizeReasons: [SyncCoordinator.Reason] {
        lock.withLock { reasons }
    }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        let initialSnapshot = lock.withLock {
            observers[identifier] = observer
            return currentSnapshot
        }
        observer(initialSnapshot)
        return identifier
    }

    func removeObserver(_ identifier: UUID) {
        _ = lock.withLock { observers.removeValue(forKey: identifier) }
    }

    func record(_: PasswordVaultCommit) {}

    func synchronize(reason: SyncCoordinator.Reason) {
        lock.withLock { reasons.append(reason) }
    }

    func enableOneDrive(
        rootURL _: URL,
        remoteMasterPassword _: String?, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        completion(.success(()))
    }

    func publish(_ snapshot: PasswordVaultSyncSnapshot) {
        let callbacks = lock.withLock {
            currentSnapshot = snapshot
            return Array(observers.values)
        }
        callbacks.forEach { $0(snapshot) }
    }

    func removeSynchronizeReasons() {
        lock.withLock { reasons.removeAll() }
    }
}

private final class CoordinatorOneDriveProcessStatusService: OneDriveProcessStatusServicing {
    private let lock = NSLock()
    private var onChange: (() -> Void)?

    func currentStatus() -> OneDriveProcessStatus {
        .running(appURL: URL(fileURLWithPath: "/Applications/OneDrive.app"))
    }

    func isMainApplicationRunning() -> Bool { true }

    func openOneDrive() -> Bool { true }

    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation {
        lock.withLock { self.onChange = onChange }
        return OneDriveProcessStatusObservation { [weak self] in
            self?.lock.withLock { self?.onChange = nil }
        }
    }

    func sendLifecycleChange() {
        lock.withLock { onChange }?()
    }
}

private final class SyncSnippetRepository: SnippetRepositoryProtocol {
    private let snapshot: SnippetSyncSnapshot
    private let upsertResult: Int
    private(set) var removeDuplicateCallCount = 0
    private(set) var upsertedSnapshots = [SnippetSyncSnapshot]()

    init(
        snapshot: SnippetSyncSnapshot = SnippetSyncSnapshot(folders: [], snippets: []),
        upsertResult: Int = 0
    ) {
        self.snapshot = snapshot
        self.upsertResult = upsertResult
    }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { [] }
    func fetchFolderDetail(id _: SnippetFolder.ID) -> SnippetFolderDetail? { nil }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { snapshot }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int {
        upsertedSnapshots.append(snapshot)
        return upsertResult
    }
    func removeDuplicateFoldersAndSnippets() -> Int {
        removeDuplicateCallCount += 1
        return 0
    }
    func updateFolderTitle(_: SnippetFolder.ID, title _: String) -> Bool { true }
    func updateFolderIsEnabled(_: SnippetFolder.ID, isEnabled _: Bool) {}
    func updateFolderIndexes(_: [SnippetFolder.ID]) {}
    func deleteFolder(_: SnippetFolder.ID) {}
    func fetchSnippet(id _: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to _: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_: Snippet.ID, title _: String) {}
    func updateSnippetContent(_: Snippet.ID, content _: String) -> Bool { true }
    func updateSnippetIsEnabled(_: Snippet.ID, isEnabled _: Bool) {}
    func updateSnippetIndexes(_: [Snippet.ID]) {}
    func moveSnippet(_: Snippet.ID, to _: SnippetFolder.ID, snippetIDs _: [Snippet.ID]) {}
    func deleteSnippet(_: Snippet.ID) {}
}

private final class CountingHistoryRepository: PasteboardHistoryRepositoryProtocol {
    var upsertedHistoryIDs = [String]()

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { false }

    func fetchHistoryDetails(
        ascending _: Bool,
        includesThumbnailAsset _: Bool,
        limit _: Int,
        offset _: Int
    ) -> [PasteboardHistoryDetail] {
        []
    }

    func searchHistoryDetails(
        query _: HistorySearchQuery,
        includesThumbnailAsset _: Bool,
        limit _: Int,
        offset _: Int
    ) throws -> [PasteboardHistoryDetail] {
        []
    }

    func fetchHistory(id _: PasteboardHistory.ID) -> PasteboardHistory? { nil }

    func fetchContent(id _: PasteboardHistory.ID) -> PasteboardContent? { nil }

    func save(id _: PasteboardHistory.ID, content _: PasteboardContent, updateAt _: Int) {}

    func deleteHistory(id _: PasteboardHistory.ID) {}

    func deleteAll() {}

    func deleteOverflowingHistories(maxHistorySize _: Int) {}

    func pruneHistories(settings _: HistoryRetentionSettings) {}

    @discardableResult
    func upsertSyncPayload(_ payload: PasteboardHistorySyncPayload) -> Bool {
        upsertedHistoryIDs.append(payload.id)
        return true
    }

    func suppressSyncedHistory(id _: PasteboardHistory.ID) {}
}

// swiftlint:enable file_length
