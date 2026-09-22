//
//  OneDriveProcessStatusService.swift
//
//  Pastera
//

import Cocoa

enum OneDriveProcessStatus: Equatable {
    case running(appURL: URL)
    case notRunning(appURL: URL)
    case notInstalled

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    var appURL: URL? {
        switch self {
        case let .running(appURL), let .notRunning(appURL):
            return appURL
        case .notInstalled:
            return nil
        }
    }
}

private struct OneDriveProcessMonitoringSnapshot: Equatable {
    let status: OneDriveProcessStatus
    let runtimeIdentifiers: [String]
}

private final class OneDriveProcessMonitoringState {
    private let lock = NSLock()
    private var snapshot: OneDriveProcessMonitoringSnapshot
    private var revision = 0
    private var isActive = true

    init(snapshot: OneDriveProcessMonitoringSnapshot) {
        self.snapshot = snapshot
    }

    @discardableResult
    func update(_ snapshot: OneDriveProcessMonitoringSnapshot, expectedRevision: Int? = nil) -> Bool {
        lock.withLock {
            guard isActive, expectedRevision == nil || expectedRevision == revision else { return false }
            revision += 1
            guard self.snapshot != snapshot else { return false }
            self.snapshot = snapshot
            return true
        }
    }

    var currentRevision: Int? {
        lock.withLock { isActive ? revision : nil }
    }

    func cancel() {
        lock.withLock { isActive = false }
    }
}

struct OneDriveRunningApplicationSnapshot: Equatable {
    let bundleIdentifier: String?
    let executableURL: URL?
    let localizedName: String?

    init(bundleIdentifier: String?, executableURL: URL?, localizedName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.executableURL = executableURL
        self.localizedName = localizedName
    }

    init(application: NSRunningApplication) {
        self.init(
            bundleIdentifier: application.bundleIdentifier,
            executableURL: application.executableURL,
            localizedName: nil
        )
    }
}

final class OneDriveProcessStatusObservation {
    private let cancellation: () -> Void
    private var isCancelled = false

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    deinit {
        cancel()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellation()
    }
}

protocol OneDriveProcessStatusServicing: AnyObject {
    func currentStatus() -> OneDriveProcessStatus
    func isMainApplicationRunning() -> Bool
    func openOneDrive() -> Bool
    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation
}

final class OneDriveProcessStatusService: OneDriveProcessStatusServicing {
    private static let monitoringQueue = DispatchQueue(label: "com.pastera.onedrive-process-monitor", qos: .utility)
    private static let supportedBundleIdentifiers = [
        "com.microsoft.OneDrive-mac",
        "com.microsoft.OneDrive"
    ]

    private let applicationURLProvider: (String) -> URL?
    private let fallbackApplicationURLs: [URL]
    private let fileExists: (String) -> Bool
    private let runningApplicationsProvider: () -> [OneDriveRunningApplicationSnapshot]
    private let openApplication: (URL) -> Bool
    private let notificationCenter: NotificationCenter
    private let applicationSnapshotFromNotification: (Notification) -> OneDriveRunningApplicationSnapshot?
    private let monitoringPollInterval: TimeInterval

    init(
        applicationURLProvider: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        fallbackApplicationURLs: [URL] = OneDriveProcessStatusService.defaultFallbackApplicationURLs(),
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        runningApplicationsProvider: @escaping () -> [OneDriveRunningApplicationSnapshot] = {
            NSWorkspace.shared.runningApplications.map(OneDriveRunningApplicationSnapshot.init(application:))
        },
        openApplication: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationSnapshotFromNotification: @escaping (Notification) -> OneDriveRunningApplicationSnapshot? = {
            guard let application = $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return nil
            }
            return OneDriveRunningApplicationSnapshot(application: application)
        },
        monitoringPollInterval: TimeInterval = 0.5
    ) {
        self.applicationURLProvider = applicationURLProvider
        self.fallbackApplicationURLs = fallbackApplicationURLs
        self.fileExists = fileExists
        self.runningApplicationsProvider = runningApplicationsProvider
        self.openApplication = openApplication
        self.notificationCenter = notificationCenter
        self.applicationSnapshotFromNotification = applicationSnapshotFromNotification
        self.monitoringPollInterval = monitoringPollInterval
    }

    func currentStatus() -> OneDriveProcessStatus {
        currentStatus(runningApplications: runningApplicationsProvider())
    }

    func isMainApplicationRunning() -> Bool {
        runningApplicationsProvider().contains(where: isOneDriveMainApplication)
    }

    private func currentStatus(
        runningApplications: [OneDriveRunningApplicationSnapshot]
    ) -> OneDriveProcessStatus {
        let runningApplication = runningApplications.first(where: isOneDriveRuntimeApplication)
        guard let appURL = installedApplicationURL() ?? appURL(from: runningApplication) else {
            return .notInstalled
        }

        if runningApplication != nil {
            return .running(appURL: appURL)
        }
        return .notRunning(appURL: appURL)
    }

    func openOneDrive() -> Bool {
        guard let appURL = currentStatus().appURL else { return false }
        return openApplication(appURL)
    }

    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation {
        let monitoringState = OneDriveProcessMonitoringState(snapshot: monitoringSnapshot())
        let launchObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.isOneDriveApplicationNotification(notification) else { return }
            guard monitoringState.update(self.monitoringSnapshot()) else { return }
            onChange()
        }
        let terminateObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.isOneDriveApplicationNotification(notification) else { return }
            guard monitoringState.update(self.monitoringSnapshot()) else { return }
            onChange()
        }

        let timer = DispatchSource.makeTimerSource(queue: Self.monitoringQueue)
        let pollInterval = max(0.001, monitoringPollInterval)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            guard let self,
                  let revision = monitoringState.currentRevision else { return }
            let snapshot = self.monitoringSnapshot()
            DispatchQueue.main.async {
                // A workspace event or cancellation may supersede this background scan.
                guard monitoringState.update(snapshot, expectedRevision: revision) else { return }
                onChange()
            }
        }
        timer.resume()

        return OneDriveProcessStatusObservation { [weak notificationCenter] in
            monitoringState.cancel()
            timer.cancel()
            notificationCenter?.removeObserver(launchObserver)
            notificationCenter?.removeObserver(terminateObserver)
        }
    }

    private func monitoringSnapshot() -> OneDriveProcessMonitoringSnapshot {
        let runningApplications = runningApplicationsProvider()
        let runtimeIdentifiers = Set(
            runningApplications
                .filter(isOneDriveRuntimeApplication)
                .map { application in
                    let bundleIdentifier = application.bundleIdentifier ?? ""
                    let executablePath = application.executableURL?.standardizedFileURL.path ?? ""
                    return "\(bundleIdentifier)\u{0}\(executablePath)"
                }
        ).sorted()
        return OneDriveProcessMonitoringSnapshot(
            status: currentStatus(runningApplications: runningApplications),
            runtimeIdentifiers: runtimeIdentifiers
        )
    }

    private func installedApplicationURL() -> URL? {
        for bundleIdentifier in Self.supportedBundleIdentifiers {
            if let appURL = existingApplicationURL(applicationURLProvider(bundleIdentifier)) {
                return appURL
            }
        }
        return fallbackApplicationURLs
            .compactMap(existingApplicationURL)
            .first
    }

    private func existingApplicationURL(_ url: URL?) -> URL? {
        guard let url = url?.standardizedFileURL,
              fileExists(url.path) else {
            return nil
        }
        return url
    }

    private func isOneDriveRuntimeApplication(_ application: OneDriveRunningApplicationSnapshot) -> Bool {
        if isOneDriveMainApplication(application) {
            return true
        }

        if let bundleIdentifier = application.bundleIdentifier,
           bundleIdentifier == "com.microsoft.OneDrive-mac.FileProvider" {
            return true
        }

        guard let executableURL = application.executableURL?.standardizedFileURL else { return false }
        return executableURL.path.hasSuffix(
            "/OneDrive.app/Contents/PlugIns/OneDrive File Provider.appex/Contents/MacOS/OneDrive File Provider"
        )
    }

    private func isOneDriveMainApplication(_ application: OneDriveRunningApplicationSnapshot) -> Bool {
        if let bundleIdentifier = application.bundleIdentifier,
           Self.supportedBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        guard let executableURL = application.executableURL?.standardizedFileURL else { return false }
        return executableURL.path.hasSuffix("/OneDrive.app/Contents/MacOS/OneDrive")
    }

    private func appURL(from application: OneDriveRunningApplicationSnapshot?) -> URL? {
        guard var candidateURL = application?.executableURL?.standardizedFileURL else { return nil }
        while candidateURL.path != "/" {
            candidateURL.deleteLastPathComponent()
            if candidateURL.lastPathComponent.compare("OneDrive.app", options: [.caseInsensitive]) == .orderedSame {
                return candidateURL
            }
        }
        return nil
    }

    private func isOneDriveApplicationNotification(_ notification: Notification) -> Bool {
        guard let application = applicationSnapshotFromNotification(notification) else { return false }
        return isOneDriveRuntimeApplication(application)
    }

    private static func defaultFallbackApplicationURLs() -> [URL] {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications/OneDrive.app", isDirectory: true),
            homeURL.appendingPathComponent("Applications/OneDrive.app", isDirectory: true)
        ]
    }
}
