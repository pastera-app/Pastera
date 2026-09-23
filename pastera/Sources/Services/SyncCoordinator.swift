//
//  SyncCoordinator.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/16.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Combine
import CoreServices
import FileProvider
import Foundation

// swiftlint:disable file_length

struct SyncSettings: Equatable {
    let rootURL: URL?
    let historyUploadEnabled: Bool
    let historyImportEnabled: Bool
    let snippetUploadEnabled: Bool
    let snippetImportEnabled: Bool
    let fileUploadEnabled: Bool
    let fileImportEnabled: Bool
    let fileAssetTypes: Set<PasteboardAvailableType>
    let pollInterval: TimeInterval
    let maxSyncedHistoryTextBytes: Int
    let maxHistorySnapshotTextBudgetBytes: Int
    let historyLimit: Int
    let maxSyncedFileBytes: Int
    let syncedFileLimitPerDevice: Int

    var hasEnabledWork: Bool {
        hasEnabledUploadWork || hasEnabledImportWork
    }

    var hasEnabledUploadWork: Bool {
        historyUploadEnabled
            || snippetUploadEnabled
            || fileUploadEnabled
    }

    var hasEnabledImportWork: Bool {
        historyImportEnabled
            || snippetImportEnabled
            || fileImportEnabled
    }
}

struct SyncStatus: Equatable {
    enum Phase: Equatable {
        case idle
        case skipped
        case syncing
        case succeeded
        case failed
    }

    let phase: Phase
    let lastSyncAt: Date?
    let uploadedCount: Int
    let importedCount: Int
    let errorDescription: String?
    let warningDescription: String?

    var statusText: String {
        if let errorDescription {
            return errorDescription
        }
        let warningSuffix = warningDescription.map { " \($0)。" } ?? ""
        switch phase {
        case .idle:
            return "未同步"
        case .skipped:
            return "已跳过"
        case .syncing:
            return "同步中..."
        case .succeeded:
            let uploadStatusText = "，等待 OneDrive 客户端上传；" +
                "Pastera 不知道云端是否已完成。"
            if importedCount > 0, uploadedCount > 0 {
                return "已导入 \(importedCount) 条，已写入 \(uploadedCount) 条到本地同步文件夹" +
                    uploadStatusText + warningSuffix
            }
            if importedCount > 0 {
                return "已导入 \(importedCount) 条。OneDrive 云端上传状态请查看 OneDrive。" + warningSuffix
            }
            if uploadedCount > 0 {
                return "已写入 \(uploadedCount) 条到本地同步文件夹" + uploadStatusText + warningSuffix
            }
            return "没有新数据。OneDrive 云端上传状态请查看 OneDrive。" + warningSuffix
        case .failed:
            return "同步失败"
        }
    }

    static let idle = SyncStatus(
        phase: .idle,
        lastSyncAt: nil,
        uploadedCount: 0,
        importedCount: 0,
        errorDescription: nil,
        warningDescription: nil
    )
}

enum SyncCoordinatorError: LocalizedError {
    case noEnabledWork
    case missingOneDrive
    case folderUnavailable

    var errorDescription: String? {
        switch self {
        case .noEnabledWork:
            return "请先开启至少一个同步开关。"
        case .missingOneDrive:
            return "请先安装并登录 OneDrive。"
        case .folderUnavailable:
            return "所选 OneDrive 文件夹不可用。"
        }
    }
}

final class UserDefaultsSyncSettingsStore {
    static let didChangeNotification = Notification.Name("PasteraSyncSettingsDidChange")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func settings() -> SyncSettings {
        let rootPath = defaults.string(forKey: Constants.UserDefaults.syncRootPath)
        let pollInterval = defaults.double(forKey: Constants.UserDefaults.syncPollInterval)
        let retentionSettings = HistoryRetentionSettings.current(defaults: defaults)
        let fileAssetTypes = fileAssetTypes()
        return SyncSettings(
            rootURL: rootPath.map { URL(fileURLWithPath: $0, isDirectory: true) },
            historyUploadEnabled: defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled),
            historyImportEnabled: defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled),
            snippetUploadEnabled: defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled),
            snippetImportEnabled: defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled),
            fileUploadEnabled: !fileAssetTypes.isEmpty && defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled),
            fileImportEnabled: !fileAssetTypes.isEmpty && defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled),
            fileAssetTypes: fileAssetTypes,
            pollInterval: pollInterval > 0 ? pollInterval : 300,
            maxSyncedHistoryTextBytes: retentionSettings.maxSyncedHistoryTextBytes,
            maxHistorySnapshotTextBudgetBytes: retentionSettings.maxHistorySnapshotTextBudgetBytes,
            historyLimit: min(retentionSettings.storedHistoryLimit, HistoryRetentionSettings.defaultStoredHistoryLimit),
            maxSyncedFileBytes: maxSyncedFileBytes(),
            syncedFileLimitPerDevice: syncedFileLimitPerDevice()
        )
    }

    func setRootURL(_ url: URL?) {
        if let url {
            defaults.set(url.standardizedFileURL.path, forKey: Constants.UserDefaults.syncRootPath)
        } else {
            defaults.removeObject(forKey: Constants.UserDefaults.syncRootPath)
        }
        notifyChange()
    }

    func setHistoryUploadEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncHistoryUploadEnabled)
        updateDerivedFileScopes()
        notifyChange()
    }

    func setSnippetUploadEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncSnippetUploadEnabled)
        notifyChange()
    }

    func setFileUploadEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncFileUploadEnabled)
        notifyChange()
    }

    func setHistoryImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncHistoryImportEnabled)
        updateDerivedFileScopes()
        notifyChange()
    }

    func setSnippetImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncSnippetImportEnabled)
        notifyChange()
    }

    func setFileImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncFileImportEnabled)
        notifyChange()
    }

    func setFileTypeEnabled(_ type: PasteboardAvailableType, enabled: Bool) {
        var states = fileTypeStates()
        states[type.rawValue] = NSNumber(value: enabled)
        defaults.set(states, forKey: Constants.UserDefaults.syncFileTypes)
        updateDerivedFileScopes()
        notifyChange()
    }

    private func maxSyncedFileBytes() -> Int {
        let value = defaults.integer(forKey: Constants.UserDefaults.maxSyncedFileBytes)
        let maximum = 25 * 1024 * 1024
        return value > 0 ? min(value, maximum) : maximum
    }

    private func syncedFileLimitPerDevice() -> Int {
        let value = defaults.integer(forKey: Constants.UserDefaults.syncedFileLimitPerDevice)
        return value > 0 ? min(value, 10) : 10
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }

    private func fileAssetTypes() -> Set<PasteboardAvailableType> {
        Set(fileTypeStates().compactMap { key, value in
            guard value.boolValue else { return nil }
            return PasteboardAvailableType(rawValue: key)
        })
    }

    private func fileTypeStates() -> [String: NSNumber] {
        let values = defaults.object(forKey: Constants.UserDefaults.syncFileTypes) as? [String: Any] ?? [:]
        return PasteboardAvailableType.syncFileTypes.reduce(into: [String: NSNumber]()) { result, type in
            if let number = values[type.rawValue] as? NSNumber {
                result[type.rawValue] = number
            } else if let bool = values[type.rawValue] as? Bool {
                result[type.rawValue] = NSNumber(value: bool)
            } else {
                result[type.rawValue] = NSNumber(value: false)
            }
        }
    }

    private func updateDerivedFileScopes() {
        let hasFileTypes = !fileAssetTypes().isEmpty
        defaults.set(
            hasFileTypes && defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled),
            forKey: Constants.UserDefaults.syncFileUploadEnabled
        )
        defaults.set(
            hasFileTypes && defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled),
            forKey: Constants.UserDefaults.syncFileImportEnabled
        )
        defaults.synchronize()
    }
}

struct SyncDefaultFolderCandidate: Equatable {
    let oneDriveRootURL: URL
    let syncRootURL: URL
    let displayName: String
    let isOneDriveBacked: Bool
}

enum SyncDefaultFolderResolution: Equatable {
    case found(SyncDefaultFolderCandidate)
    case notFound
    case multiple([SyncDefaultFolderCandidate])
}

struct SyncDefaultFolderResolver {
    typealias FileProviderIdentityChecker = (URL) -> Bool

    let fileManager: FileManager
    private let fileProviderIdentityChecker: FileProviderIdentityChecker

    init(
        fileManager: FileManager = .default,
        fileProviderIdentityChecker: @escaping FileProviderIdentityChecker = {
            SyncDefaultFolderResolver.isFileProviderBacked($0)
        }
    ) {
        self.fileManager = fileManager
        self.fileProviderIdentityChecker = fileProviderIdentityChecker
    }

    func resolve(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> SyncDefaultFolderResolution {
        let candidates = oneDriveCandidates(homeDirectory: homeDirectory)
        guard !candidates.isEmpty else {
            return .notFound
        }
        guard let candidate = preferredCandidate(from: candidates) else {
            return .multiple(candidates)
        }
        guard let preparedCandidate = prepare(candidate) else {
            return .notFound
        }
        return .found(preparedCandidate)
    }

    func preferredCandidate(from candidates: [SyncDefaultFolderCandidate]) -> SyncDefaultFolderCandidate? {
        let sortedCandidates = candidates.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        return sortedCandidates.first {
            $0.displayName.compare("OneDrive", options: [.caseInsensitive]) == .orderedSame
        }
    }

    func prepare(_ candidate: SyncDefaultFolderCandidate) -> SyncDefaultFolderCandidate? {
        do {
            try fileManager.createDirectory(at: candidate.syncRootURL, withIntermediateDirectories: true)
            return SyncDefaultFolderCandidate(
                oneDriveRootURL: canonicalURL(candidate.oneDriveRootURL),
                syncRootURL: canonicalURL(candidate.syncRootURL),
                displayName: candidate.displayName,
                isOneDriveBacked: candidate.isOneDriveBacked
            )
        } catch {
            return nil
        }
    }

    func oneDriveCandidates(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SyncDefaultFolderCandidate] {
        let cloudStorageURL = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cloudStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter(isUsableOneDriveRoot)
            .reduce(into: [String: SyncDefaultFolderCandidate]()) { uniqueCandidates, url in
                let oneDriveRootURL = canonicalURL(url)
                uniqueCandidates[oneDriveRootURL.path] = SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: Self.defaultFolderURL(oneDriveRootURL: oneDriveRootURL),
                    displayName: url.lastPathComponent,
                    isOneDriveBacked: true
                )
            }
            .values
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func oneDriveCandidate(
        containing url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> SyncDefaultFolderCandidate? {
        let targetURL = canonicalURL(url)
        return oneDriveCandidates(homeDirectory: homeDirectory)
            .first { candidate in
                targetURL.path == candidate.oneDriveRootURL.path
                    || targetURL.path.hasPrefix(candidate.oneDriveRootURL.path + "/")
            }
    }

    static func defaultFolderURL(oneDriveRootURL: URL) -> URL {
        oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    static func defaultFolderURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .appendingPathComponent("OneDrive", isDirectory: true)
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    static func isUsableOneDriveBackedURL(_ url: URL) -> Bool {
        isUsableOneDriveBackedURL(url, fileProviderIdentityChecker: isFileProviderBacked)
    }

    static func isUsableOneDriveBackedURL(
        _ url: URL,
        fileProviderIdentityChecker: FileProviderIdentityChecker
    ) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard let cloudStorageIndex = components.firstIndex(of: "CloudStorage"),
              components.indices.contains(cloudStorageIndex + 1) else {
            return false
        }
        let rootName = components[cloudStorageIndex + 1]
        guard isUsableOneDriveRootName(rootName) else {
            return false
        }
        guard isSharedLibraryRootName(rootName) else {
            return true
        }
        let rootPath = NSString.path(withComponents: Array(components.prefix(cloudStorageIndex + 2)))
        return fileProviderIdentityChecker(URL(fileURLWithPath: rootPath, isDirectory: true))
    }

    static func isUsableOneDriveRootName(_ name: String) -> Bool {
        guard name.range(of: "OneDrive", options: [.anchored, .caseInsensitive]) != nil else {
            return false
        }
        return name.range(of: "CloudTemp", options: [.caseInsensitive]) == nil
    }

    static func isFileProviderBacked(_ url: URL) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        let success = DispatchSemaphore(value: 0)
        NSFileProviderManager.getIdentifierForUserVisibleFile(at: url) { itemIdentifier, domainIdentifier, error in
            if itemIdentifier != nil, domainIdentifier != nil, error == nil {
                success.signal()
            }
            completion.signal()
        }
        guard completion.wait(timeout: .now() + 1) == .success else {
            return false
        }
        return success.wait(timeout: .now()) == .success
    }

    private static func isSharedLibraryRootName(_ name: String) -> Bool {
        name.range(of: "Shared Libraries", options: [.caseInsensitive]) != nil
            || name.range(of: "共享的库", options: [.caseInsensitive]) != nil
            || name.range(of: "共享库", options: [.caseInsensitive]) != nil
    }

    private func isUsableOneDriveRoot(_ url: URL) -> Bool {
        guard Self.isUsableOneDriveBackedURL(
            url,
            fileProviderIdentityChecker: fileProviderIdentityChecker
        ) else {
            return false
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}

// swiftlint:disable:next type_body_length
final class SyncCoordinator {
    private struct ActivationSignature: Equatable {
        let rootPath: String?
        let rootAvailable: Bool
        let pollInterval: TimeInterval
        let historyObservationEnabled: Bool
        let snippetObservationEnabled: Bool
        let remoteObservationEnabled: Bool
        let hasEnabledWork: Bool
        let vaultSyncEnabled: Bool
    }
    enum Reason: Equatable {
        case startup
        case timer
        case localChange
        case remoteChange
        case manual
    }

    static let shared = SyncCoordinator()
    static let statusDidChangeNotification = Notification.Name("PasteraSyncStatusDidChange")

    @Published private(set) var status = SyncStatus.idle

    private let settingsProvider: () -> SyncSettings
    private let providerFactory: (URL) -> OneDriveFolderSyncProvider
    private let historyRepository: PasteboardHistoryRepositoryProtocol
    private let snippetRepository: SnippetRepositoryProtocol
    private let passwordVaultSyncServiceProvider: () -> PasswordVaultSyncControlling
    private let oneDriveProcessStatusServiceProvider: () -> OneDriveProcessStatusServicing
    private let vaultChangeDebounceInterval: TimeInterval
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var timer: DispatchSourceTimer?
    private var remoteFolderObservation: SyncRemoteFolderObservation?
    private var remoteObservationID: UUID?
    private var pendingRemoteImport: DispatchWorkItem?
    private var historyObservation: AnyCancellable?
    private var historyObservationID: UUID?
    private var snippetObservation: AnyCancellable?
    private var configurationObservation: AnyCancellable?
    private var observedPasswordVaultSyncService: PasswordVaultSyncControlling?
    private var passwordVaultSyncObserverIdentifier: UUID?
    private var observedOneDriveProcessStatusService: OneDriveProcessStatusServicing?
    private var oneDriveProcessStatusObservation: OneDriveProcessStatusObservation?
    private var lastOneDriveIsRunning: Bool?
    private var pendingVaultSyncWorkItem: DispatchWorkItem?
    private var lastPasswordVaultSyncSnapshot: PasswordVaultSyncSnapshot?
    private var isStarted = false
    private var activationSignature: ActivationSignature?
    private var lastHistoryExportSignature: HistoryWindowSignature?
    private var importedHistorySnapshotStates = [String: HistoryRemoteSnapshotState]()

    private struct DirectionPlan {
        let upload: Bool
        let importRemote: Bool
    }

    private struct SyncRunResult {
        var uploaded = 0
        var imported = 0
        var warnings = [String]()

        var isNoOp: Bool {
            uploaded == 0 && imported == 0 && warnings.isEmpty
        }

        var warningDescription: String? {
            warnings.isEmpty ? nil : warnings.joined(separator: "；")
        }
    }

    init(
        settingsProvider: @escaping () -> SyncSettings = { UserDefaultsSyncSettingsStore().settings() },
        providerFactory: @escaping (URL) -> OneDriveFolderSyncProvider = { OneDriveFolderSyncProvider(rootURL: $0) },
        historyRepository: PasteboardHistoryRepositoryProtocol = PasteboardHistoryRepository(),
        snippetRepository: SnippetRepositoryProtocol = SnippetRepository(),
        passwordVaultSyncServiceProvider: @escaping () -> PasswordVaultSyncControlling = {
            AppEnvironment.current.passwordVaultSyncService
        },
        oneDriveProcessStatusServiceProvider: @escaping () -> OneDriveProcessStatusServicing = {
            AppEnvironment.current.oneDriveProcessStatusService
        },
        vaultChangeDebounceInterval: TimeInterval = 2,
        queue: DispatchQueue = DispatchQueue(label: "com.pastera.sync.coordinator", qos: .utility)
    ) {
        self.settingsProvider = settingsProvider
        self.providerFactory = providerFactory
        self.historyRepository = historyRepository
        self.snippetRepository = snippetRepository
        self.passwordVaultSyncServiceProvider = passwordVaultSyncServiceProvider
        self.oneDriveProcessStatusServiceProvider = oneDriveProcessStatusServiceProvider
        self.vaultChangeDebounceInterval = vaultChangeDebounceInterval
        self.queue = queue
        queue.setSpecific(key: queueKey, value: ())
    }

    func start() {
        stop()
        performOnQueueAndWait {
            isStarted = true
            configurationObservation = NotificationCenter.default.publisher(
                for: UserDefaultsSyncSettingsStore.didChangeNotification
            )
            .sink { [weak self] _ in self?.reloadConfiguration() }
            bindPasswordVaultSyncObservation()
            bindOneDriveProcessStatusObservation()
            applyConfiguration()
        }
        syncNow(reason: .startup)
    }

    func stop() {
        performOnQueueAndWait { stopOnQueue() }
    }

    private func stopOnQueue() {
        stopRemoteFolderObservation()
        timer?.cancel()
        timer = nil
        historyObservation = nil
        historyObservationID = nil
        snippetObservation = nil
        configurationObservation = nil
        pendingVaultSyncWorkItem?.cancel()
        pendingVaultSyncWorkItem = nil
        if let identifier = passwordVaultSyncObserverIdentifier {
            observedPasswordVaultSyncService?.removeObserver(identifier)
        }
        passwordVaultSyncObserverIdentifier = nil
        observedPasswordVaultSyncService = nil
        lastPasswordVaultSyncSnapshot = nil
        oneDriveProcessStatusObservation?.cancel()
        oneDriveProcessStatusObservation = nil
        observedOneDriveProcessStatusService = nil
        lastOneDriveIsRunning = nil
        activationSignature = nil
        isStarted = false
    }

    func reloadConfiguration() {
        queue.async { [weak self] in
            guard let self, self.isStarted else { return }
            self.bindPasswordVaultSyncObservation()
            self.bindOneDriveProcessStatusObservation()
            self.applyConfiguration()
        }
    }

    private func applyConfiguration() {
        let settings = settingsProvider()
        let rootAvailable = settings.rootURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let vaultSyncEnabled = passwordVaultSyncServiceProvider().snapshot.mode == .oneDrive
        // Keep observing configured folders while OneDrive is still making them available.
        let genericSyncEnabled = settings.rootURL != nil && settings.hasEnabledWork
        let signature = ActivationSignature(
            rootPath: settings.rootURL?.standardizedFileURL.path,
            rootAvailable: rootAvailable,
            pollInterval: settings.pollInterval,
            historyObservationEnabled: genericSyncEnabled
                && (settings.historyUploadEnabled || settings.fileUploadEnabled),
            snippetObservationEnabled: genericSyncEnabled && settings.snippetUploadEnabled,
            remoteObservationEnabled: genericSyncEnabled,
            hasEnabledWork: genericSyncEnabled,
            vaultSyncEnabled: vaultSyncEnabled
        )
        guard signature != activationSignature else { return }
        activationSignature = signature
        stopRemoteFolderObservation()
        if signature.remoteObservationEnabled, let rootURL = settings.rootURL {
            observeRemoteFolder(rootURL: rootURL)
        }
        guard genericSyncEnabled || vaultSyncEnabled else {
            timer?.cancel()
            timer = nil
            historyObservation = nil
            historyObservationID = nil
            snippetObservation = nil
            return
        }
        installTimer()
        observeLocalChanges(settings: settings, enabled: genericSyncEnabled)
    }

    func syncNow(reason: Reason, wait: Bool = false) {
        let work = { [weak self] in
            guard let self else { return }
            self.performSync(reason: reason)
        }
        if wait {
            performOnQueueAndWait(work)
        } else {
            queue.async {
                work()
            }
        }
    }

    private func performOnQueueAndWait(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            operation()
        } else {
            queue.sync(execute: operation)
        }
    }

    private func installTimer() {
        timer?.cancel()
        let interval = max(30, settingsProvider().pollInterval)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.performSync(reason: .timer)
        }
        timer.resume()
        self.timer = timer
    }

    private func stopRemoteFolderObservation() {
        remoteObservationID = nil
        pendingRemoteImport?.cancel()
        pendingRemoteImport = nil
        remoteFolderObservation = nil
    }

    private func observeRemoteFolder(rootURL: URL) {
        let observationID = UUID()
        remoteObservationID = observationID
        remoteFolderObservation = SyncRemoteFolderObservation(
            rootURL: rootURL,
            deviceID: currentDeviceID,
            queue: queue
        ) { [weak self] in
            guard let self, self.isStarted, self.remoteObservationID == observationID,
                  self.pendingRemoteImport == nil else { return }
            // Bound the delay even while a cloud download keeps producing events.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isStarted, self.remoteObservationID == observationID else { return }
                self.pendingRemoteImport = nil
                let rootWasAvailable = self.activationSignature?.rootAvailable == true
                self.applyConfiguration()
                let rootRecovered = !rootWasAvailable && self.activationSignature?.rootAvailable == true
                self.performSync(reason: rootRecovered ? .startup : .remoteChange)
            }
            self.pendingRemoteImport = work
            self.queue.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func observeLocalChanges(settings: SyncSettings, enabled: Bool) {
        historyObservation = nil
        historyObservationID = nil
        if enabled, settings.historyUploadEnabled || settings.fileUploadEnabled {
            let observationID = UUID()
            historyObservationID = observationID
            let publisher = settings.fileUploadEnabled
                ? historyRepository.observeHistoryChanges()
                : historyRepository.observeTextSyncCandidateChanges(currentDeviceID: currentDeviceID)
            historyObservation = publisher
                .dropFirst()
                // Continuous copying must not postpone exports until the clipboard becomes quiet.
                .throttle(for: .milliseconds(250), scheduler: queue, latest: true)
                .sink { [weak self] _ in
                    guard let self, self.isStarted, self.historyObservationID == observationID else { return }
                    self.performSync(reason: .localChange)
                }
        }

        snippetObservation = nil
        if enabled, settings.snippetUploadEnabled {
            snippetObservation = snippetRepository.observeFolderDetails()
                .dropFirst()
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncNow(reason: .localChange) }
        }
    }

    private func performSync(reason: Reason) {
        if reason == .remoteChange {
            performGenericSync(reason: reason, vaultSyncEnabled: false)
            return
        }
        let vaultSyncEnabled = synchronizePasswordVaultIfEnabled(reason: reason)
        performGenericSync(reason: reason, vaultSyncEnabled: vaultSyncEnabled)
    }

    @discardableResult
    private func synchronizePasswordVaultIfEnabled(reason: Reason) -> Bool {
        let passwordVaultSyncService = passwordVaultSyncServiceProvider()
        guard passwordVaultSyncService.snapshot.mode == .oneDrive else { return false }
        passwordVaultSyncService.synchronize(reason: reason)
        return true
    }

    private func performGenericSync(reason: Reason, vaultSyncEnabled: Bool) {
        let settings = settingsProvider()
        guard settings.hasEnabledWork else {
            if !vaultSyncEnabled {
                setSkipped(error: SyncCoordinatorError.noEnabledWork)
            }
            return
        }
        guard let rootURL = settings.rootURL else {
            setSkipped(error: SyncCoordinatorError.missingOneDrive)
            return
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            setSkipped(error: SyncCoordinatorError.folderUnavailable)
            return
        }
        let directionPlan = directionPlan(reason: reason, settings: settings)
        guard directionPlan.upload || directionPlan.importRemote else { return }

        if reason == .manual {
            setStatus(SyncStatus(
                phase: .syncing,
                lastSyncAt: status.lastSyncAt,
                uploadedCount: status.uploadedCount,
                importedCount: status.importedCount,
                errorDescription: nil,
                warningDescription: nil
            ))
        }

        do {
            let provider = providerFactory(rootURL)
            let result = try sync(settings: settings, provider: provider, directionPlan: directionPlan)
            if reason != .manual, result.isNoOp {
                guard reason != .localChange,
                      status.phase != .succeeded || status.warningDescription != nil else { return }
            }
            setStatus(SyncStatus(
                phase: .succeeded,
                lastSyncAt: Date(),
                uploadedCount: result.uploaded,
                importedCount: result.imported,
                errorDescription: nil,
                warningDescription: result.warningDescription
            ))
        } catch {
            setStatus(SyncStatus(
                phase: .failed,
                lastSyncAt: status.lastSyncAt,
                uploadedCount: status.uploadedCount,
                importedCount: status.importedCount,
                errorDescription: error.localizedDescription,
                warningDescription: nil
            ))
        }
    }

    private func bindPasswordVaultSyncObservation() {
        let service = passwordVaultSyncServiceProvider()
        guard observedPasswordVaultSyncService !== service else { return }
        if let identifier = passwordVaultSyncObserverIdentifier {
            observedPasswordVaultSyncService?.removeObserver(identifier)
        }
        pendingVaultSyncWorkItem?.cancel()
        pendingVaultSyncWorkItem = nil
        lastPasswordVaultSyncSnapshot = nil
        observedPasswordVaultSyncService = service
        passwordVaultSyncObserverIdentifier = service.addObserver { [weak self, weak service] snapshot in
            guard let self, let service else { return }
            self.queue.async { [weak self, weak service] in
                guard let self,
                      let service,
                      self.isStarted,
                      self.observedPasswordVaultSyncService === service else { return }
                self.handlePasswordVaultSyncSnapshot(snapshot)
            }
        }
    }

    private func bindOneDriveProcessStatusObservation() {
        let service = oneDriveProcessStatusServiceProvider()
        guard observedOneDriveProcessStatusService !== service else { return }
        oneDriveProcessStatusObservation?.cancel()
        observedOneDriveProcessStatusService = service
        lastOneDriveIsRunning = service.currentStatus().isRunning
        oneDriveProcessStatusObservation = service.startMonitoring { [weak self, weak service] in
            guard let self, let service else { return }
            let isRunning = service.currentStatus().isRunning
            _ = self.synchronizePasswordVaultIfEnabled(reason: .startup)
            self.queue.async { [weak self, weak service] in
                guard let self,
                      let service,
                      self.isStarted,
                      self.observedOneDriveProcessStatusService === service else { return }
                let didReconnect = self.lastOneDriveIsRunning == false && isRunning
                self.lastOneDriveIsRunning = isRunning
                self.bindPasswordVaultSyncObservation()
                self.applyConfiguration()
                // FileProvider process changes can occur while OneDrive stays running.
                guard didReconnect else { return }
                let vaultSyncEnabled = self.passwordVaultSyncServiceProvider().snapshot.mode == .oneDrive
                self.performGenericSync(reason: .startup, vaultSyncEnabled: vaultSyncEnabled)
            }
        }
    }

    private func handlePasswordVaultSyncSnapshot(_ snapshot: PasswordVaultSyncSnapshot) {
        let previousSnapshot = lastPasswordVaultSyncSnapshot
        lastPasswordVaultSyncSnapshot = snapshot
        if let previousSnapshot, previousSnapshot.mode != snapshot.mode {
            if snapshot.mode == .localOnly {
                pendingVaultSyncWorkItem?.cancel()
                pendingVaultSyncWorkItem = nil
            }
            applyConfiguration()
            if snapshot.mode == .oneDrive {
                performSync(reason: .startup)
            }
        }
        guard snapshot.mode == .oneDrive,
              let previousSnapshot,
              snapshot.pendingChangeCount > previousSnapshot.pendingChangeCount else { return }
        pendingVaultSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted else { return }
            self.performSync(reason: .localChange)
        }
        pendingVaultSyncWorkItem = workItem
        queue.asyncAfter(
            deadline: .now() + max(0, vaultChangeDebounceInterval),
            execute: workItem
        )
    }

    private func sync(
        settings: SyncSettings,
        provider: OneDriveFolderSyncProvider,
        directionPlan: DirectionPlan
    ) throws -> SyncRunResult {
        var result = SyncRunResult()

        if directionPlan.importRemote, settings.historyImportEnabled {
            let historyResult = try importHistories(provider: provider)
            result.imported += historyResult.imported
            if historyResult.unreadableCount > 0 {
                result.warnings.append("有 \(historyResult.unreadableCount) 个历史快照暂未读取，将在下次同步重试")
            }
        }
        if directionPlan.importRemote, settings.snippetImportEnabled {
            result.imported += try importSnippets(provider: provider)
        }
        if directionPlan.importRemote, settings.fileImportEnabled {
            do {
                let fileResult = try importFiles(settings: settings, provider: provider)
                result.imported += fileResult.imported
                if let warning = fileResult.warning {
                    result.warnings.append(warning)
                }
            } catch {
                result.warnings.append("文件同步失败：\(error.localizedDescription)")
            }
        }
        if directionPlan.upload, settings.historyUploadEnabled {
            result.uploaded += try exportHistories(settings: settings, provider: provider)
        }
        if directionPlan.upload, settings.snippetUploadEnabled {
            result.uploaded += try exportSnippets(provider: provider)
        }
        if directionPlan.upload, settings.fileUploadEnabled {
            do {
                let fileResult = try exportFiles(settings: settings, provider: provider)
                result.uploaded += fileResult.uploaded
                if let warning = fileResult.warning {
                    result.warnings.append(warning)
                }
            } catch {
                result.warnings.append("文件同步失败：\(error.localizedDescription)")
            }
        }
        return result
    }

    private func importHistories(provider: OneDriveFolderSyncProvider) throws -> (imported: Int, unreadableCount: Int) {
        let states = try provider.historySnapshotFileStates(excludingDeviceID: currentDeviceID)
        let changedStates = states.filter {
            importedHistorySnapshotStates[$0.cacheKey] != $0
        }
        var imported = 0
        var unreadableCount = 0
        for state in changedStates {
            guard let snapshot = try? provider.loadHistorySnapshot(at: state.url) else {
                unreadableCount += 1
                continue
            }
            if snapshot.deviceID != currentDeviceID {
                for payload in snapshot.payloads {
                    imported += try historyRepository.upsertSyncPayload(payload) ? 1 : 0
                }
            }
            // A cloud placeholder may become readable without changing its size or modification time.
            importedHistorySnapshotStates[state.cacheKey] = state
        }
        return (imported, unreadableCount)
    }

    private func importSnippets(provider: OneDriveFolderSyncProvider) throws -> Int {
        _ = snippetRepository.removeDuplicateFoldersAndSnippets()
        return try provider.loadSnippetSnapshots(excludingDeviceID: currentDeviceID).reduce(0) { importedCount, snapshot in
            importedCount + snippetRepository.upsertSyncSnapshot(snapshot.snapshot)
        }
    }

    private func importFiles(
        settings: SyncSettings,
        provider: OneDriveFolderSyncProvider
    ) throws -> (imported: Int, warning: String?) {
        let loadResult = try provider.loadFileSnapshotResult(
            excludingDeviceID: currentDeviceID,
            includedFileTypes: settings.fileAssetTypes,
            maxFileBytes: settings.maxSyncedFileBytes,
            maxAssetsPerDevice: settings.syncedFileLimitPerDevice,
            shouldImportHistory: { [historyRepository] historyID, updatedAt in
                historyRepository.shouldImportFileSyncHistory(historyID: historyID, updatedAt: updatedAt)
            }
        )
        let imported = loadResult.snapshots.reduce(0) { importedCount, snapshot in
            importedCount + snapshot.histories.reduce(0) { historyImportedCount, payload in
                guard payload.assets.allSatisfy({
                    guard let fileType = PasteboardAvailableType.syncFileType(for: $0.pasteboardType) else {
                        return false
                    }
                    return settings.fileAssetTypes.contains(fileType)
                }) else {
                    return historyImportedCount
                }
                return historyImportedCount + (historyRepository.upsertFileSyncHistory(payload) ? 1 : 0)
            }
        }
        var warnings = [String]()
        if loadResult.skippedAssetCount > 0 {
            warnings.append("已跳过 \(loadResult.skippedAssetCount) 个文件（缺失、超限或校验失败）")
        }
        if loadResult.skippedManifestCount > 0 {
            warnings.append("已跳过 \(loadResult.skippedManifestCount) 个文件同步清单（无法读取）")
        }
        return (imported, warnings.isEmpty ? nil : warnings.joined(separator: "。"))
    }

    private func exportHistories(settings: SyncSettings, provider: OneDriveFolderSyncProvider) throws -> Int {
        let historyLimit = max(0, min(settings.historyLimit, HistoryRetentionSettings.defaultStoredHistoryLimit))
        let payloads = historyRepository.fetchSyncPayloads(
            currentDeviceID: currentDeviceID,
            limit: historyLimit,
            maxTextBytes: settings.maxSyncedHistoryTextBytes,
            snapshotTextBudgetBytes: settings.maxHistorySnapshotTextBudgetBytes
        )
        let signature = HistoryWindowSignature.make(
            payloads: payloads,
            limit: historyLimit,
            maxTextBytes: settings.maxSyncedHistoryTextBytes,
            snapshotTextBudgetBytes: settings.maxHistorySnapshotTextBudgetBytes
        )
        if lastHistoryExportSignature == signature,
           provider.historySnapshotExists(deviceID: currentDeviceID) {
            return 0
        }
        try provider.saveHistorySnapshot(
            payloads,
            deviceID: currentDeviceID,
            limit: historyLimit,
            maxTextBytes: settings.maxSyncedHistoryTextBytes,
            snapshotTextBudgetBytes: settings.maxHistorySnapshotTextBudgetBytes
        )
        lastHistoryExportSignature = signature
        return payloads.count
    }

    private func exportSnippets(provider: OneDriveFolderSyncProvider) throws -> Int {
        _ = snippetRepository.removeDuplicateFoldersAndSnippets()
        let snapshot = snippetRepository.fetchSyncSnapshot()
        try provider.saveSnippetSnapshot(snapshot, deviceID: currentDeviceID)
        return snapshot.folders.count + snapshot.snippets.count
    }

    private func exportFiles(
        settings: SyncSettings,
        provider: OneDriveFolderSyncProvider
    ) throws -> (uploaded: Int, warning: String?) {
        let snapshot = historyRepository.fetchFileSyncSnapshot(
            currentDeviceID: currentDeviceID,
            limit: settings.syncedFileLimitPerDevice,
            maxFileBytes: settings.maxSyncedFileBytes,
            includedFileTypes: settings.fileAssetTypes
        )
        try provider.saveFileSnapshot(snapshot, deviceID: currentDeviceID)
        let warning = snapshot.skippedAssetCount > 0
            ? "已跳过 \(snapshot.skippedAssetCount) 个文件（超过大小限制或无法同步）"
            : nil
        return (snapshot.assetCount, warning)
    }

    private func setSkipped(error: Error? = nil) {
        setStatus(SyncStatus(
            phase: .skipped,
            lastSyncAt: status.lastSyncAt,
            uploadedCount: status.uploadedCount,
            importedCount: status.importedCount,
            errorDescription: error?.localizedDescription,
            warningDescription: status.warningDescription
        ))
    }

    private func setStatus(_ status: SyncStatus) {
        self.status = status
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: self)
        }
    }

    private var currentDeviceID: String {
        CPYUtilities.deviceID ?? ProcessInfo.processInfo.hostName
    }

    private func directionPlan(reason: Reason, settings: SyncSettings) -> DirectionPlan {
        DirectionPlan(
            upload: reason != .remoteChange && settings.hasEnabledUploadWork,
            importRemote: reason == .localChange ? false : settings.hasEnabledImportWork
        )
    }
}

private final class SyncRemoteFolderObservation {
    private let stream: FSEventStreamRef

    init?(rootURL: URL, deviceID: String, queue: DispatchQueue, onChange: @escaping () -> Void) {
        let rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let callback = Callback(rootPath: rootURL.path, deviceID: deviceID, onChange: onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Callback>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Callback>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        // OneDrive may create several missing ancestors after Pastera has already started.
        var watchURL = rootURL.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: watchURL.path), watchURL.path != "/" {
            watchURL.deleteLastPathComponent()
        }
        let paths = [watchURL.path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
        )
        let createdStream = withExtendedLifetime(callback) {
            FSEventStreamCreate(nil, { _, info, count, eventPaths, eventFlags, _ in
                guard let info else { return }
                let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                for index in 0..<min(count, paths.count) {
                    if callback.shouldImport(path: paths[index], flags: eventFlags[index]) {
                        callback.onChange()
                        return
                    }
                }
            }, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags)
        }
        guard let createdStream else { return nil }
        FSEventStreamSetDispatchQueue(createdStream, queue)
        guard FSEventStreamStart(createdStream) else {
            FSEventStreamInvalidate(createdStream)
            FSEventStreamRelease(createdStream)
            return nil
        }
        stream = createdStream
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private final class Callback {
        let rootPath: String
        let deviceComponent: String
        let onChange: () -> Void

        init(rootPath: String, deviceID: String, onChange: @escaping () -> Void) {
            self.rootPath = rootPath
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
            deviceComponent = String(deviceID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
                .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            self.onChange = onChange
        }

        func shouldImport(path: String, flags: FSEventStreamEventFlags) -> Bool {
            let path = URL(fileURLWithPath: path).standardizedFileURL.path
            let ancestorChangeFlags = FSEventStreamEventFlags(
                kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagItemCreated
                    | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
                    | kFSEventStreamEventFlagRootChanged
            )
            // Moving a prepared OneDrive tree may report only the ancestor's rename.
            if path == rootPath
                || (rootPath.hasPrefix(path + "/") && flags & ancestorChangeFlags != 0) { return true }
            guard path.hasPrefix(rootPath + "/") else { return false }
            let components = path.dropFirst(rootPath.count + 1).split(separator: "/").map(String.init)
            guard let domain = components.first, ["history", "snippets", "files"].contains(domain),
                  !components.contains(where: { $0.hasPrefix(".") }) else { return false }
            if components.count == 1 { return true }
            guard components[1] == "devices" else { return false }
            if components.count == 2 { return true }
            if domain == "files" {
                guard components[2] != deviceComponent else { return false }
                return components.count == 3
                    || (components.count == 4 && components[3] == "manifest.json")
                    || (components.count >= 4 && components[3] == "assets")
            }
            return components.count == 3 && components[2].hasSuffix(".sqlite")
                && components[2] != deviceComponent + ".sqlite"
        }
    }
}

// swiftlint:enable file_length
