import AppKit
import ApplicationServices
import Foundation
import PasteraAgentProtocol

final class VaultAgentPasteApplication {
    let processIdentifier: pid_t
    var bundleIdentifier: String?
    let executableURL: URL
    var isTerminated: Bool
    let application: NSRunningApplication?

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        executableURL: URL,
        isTerminated: Bool,
        application: NSRunningApplication?
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.executableURL = executableURL
        self.isTerminated = isTerminated
        self.application = application
    }
}

final class VaultAgentPasteTargetTracker: VaultAgentPasteTargetTracking {
    private struct StoredTarget {
        let generation: UUID
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let executableURL: URL
        let snapshot: VaultAgentProcessSnapshot
        let signature: VaultAgentCodeSignature
        let focusedElement: AXUIElement?
    }

    private let notificationCenter: NotificationCenter
    private let notificationName: Notification.Name
    private let currentProcessID: pid_t
    private let currentBundleIdentifier: String?
    private let excludedExecutableURLs: () -> [URL]
    private let applicationFromNotification: (Notification) -> VaultAgentPasteApplication?
    private let runningApplication: (pid_t) -> VaultAgentPasteApplication?
    private let processInspector: VaultAgentProcessInspecting
    private let codeSigningInspector: VaultAgentCodeSigningInspecting
    private let focusedElement: (pid_t) -> AXUIElement?
    private let activationWorker: DispatchQueue
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var target: StoredTarget?
    private var started = false
    private var activationGeneration: UInt64 = 0

    convenience init(hostIdentityProvider: VaultAgentHostIdentityProviding) {
        self.init(
            notificationCenter: NSWorkspace.shared.notificationCenter,
            notificationName: NSWorkspace.didActivateApplicationNotification,
            currentProcessID: ProcessInfo.processInfo.processIdentifier,
            currentBundleIdentifier: Bundle.main.bundleIdentifier,
            excludedExecutableURLs: {
                var urls = Self.defaultExcludedURLs()
                for client in [VaultAgentClientKind.codex, .claude] {
                    if let path = hostIdentityProvider.installedHostIdentity(for: client)?.canonicalPath {
                        urls.append(URL(fileURLWithPath: path))
                    }
                }
                return urls
            },
            applicationFromNotification: Self.application(from:),
            runningApplication: Self.runningApplication(pid:),
            processInspector: VaultAgentSystemProcessInspector(),
            codeSigningInspector: VaultAgentSystemCodeSigningInspector(),
            focusedElement: Self.focusedElement(pid:)
        )
    }

    init(
        notificationCenter: NotificationCenter,
        notificationName: Notification.Name,
        currentProcessID: pid_t,
        currentBundleIdentifier: String?,
        excludedExecutableURLs: @escaping () -> [URL],
        applicationFromNotification: @escaping (Notification) -> VaultAgentPasteApplication?,
        runningApplication: @escaping (pid_t) -> VaultAgentPasteApplication?,
        processInspector: VaultAgentProcessInspecting,
        codeSigningInspector: VaultAgentCodeSigningInspecting,
        focusedElement: @escaping (pid_t) -> AXUIElement?,
        activationWorker: DispatchQueue = DispatchQueue(
            label: "com.pastera-app.Pastera.vault-agent.paste-target",
            qos: .utility
        )
    ) {
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
        self.currentProcessID = currentProcessID
        self.currentBundleIdentifier = currentBundleIdentifier
        self.excludedExecutableURLs = excludedExecutableURLs
        self.applicationFromNotification = applicationFromNotification
        self.runningApplication = runningApplication
        self.processInspector = processInspector
        self.codeSigningInspector = codeSigningInspector
        self.focusedElement = focusedElement
        self.activationWorker = activationWorker
    }

    deinit { stop() }

    func start() {
        lock.lock()
        guard observer == nil else {
            lock.unlock()
            return
        }
        started = true
        activationGeneration &+= 1
        observer = notificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.applicationDidActivate(notification)
        }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let current = observer
        observer = nil
        started = false
        activationGeneration &+= 1
        target = nil
        lock.unlock()
        if let current { notificationCenter.removeObserver(current) }
    }

    func resolve() throws -> PasteTargetContext {
        lock.lock()
        let stored = target
        lock.unlock()
        guard let stored,
              let application = runningApplication(stored.processIdentifier),
              !application.isTerminated,
              application.processIdentifier == stored.processIdentifier,
              application.bundleIdentifier == stored.bundleIdentifier,
              Self.canonicalPath(application.executableURL) == Self.canonicalPath(stored.executableURL) else {
            throw VaultAgentPasteTargetError.unavailable
        }
        let currentSnapshot: VaultAgentProcessSnapshot
        let currentSignature: VaultAgentCodeSignature
        do {
            currentSnapshot = try processInspector.snapshot(pid: application.processIdentifier)
            currentSignature = try codeSigningInspector.inspect(executableURL: currentSnapshot.executableURL)
        } catch {
            throw VaultAgentPasteTargetError.unavailable
        }
        guard currentSnapshot == stored.snapshot,
              currentSignature == stored.signature,
              Self.canonicalPath(currentSnapshot.executableURL) == Self.canonicalPath(application.executableURL) else {
            throw VaultAgentPasteTargetError.unavailable
        }
        guard let resolvedFocus = focusedElement(application.processIdentifier) ?? stored.focusedElement else {
            throw VaultAgentPasteTargetError.unavailable
        }
        lock.lock()
        let isStillLatest = target?.generation == stored.generation
        lock.unlock()
        guard isStillLatest else { throw VaultAgentPasteTargetError.unavailable }
        return PasteTargetContext(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            application: application.application,
            focusedElement: resolvedFocus
        )
    }

    private func applicationDidActivate(_ notification: Notification) {
        guard let application = applicationFromNotification(notification),
              !application.isTerminated,
              application.processIdentifier != currentProcessID,
              application.bundleIdentifier != currentBundleIdentifier else { return }
        let path = Self.canonicalPath(application.executableURL)
        let excludedPaths = Set(excludedExecutableURLs().map(Self.canonicalPath))
        guard !excludedPaths.contains(path) else { return }

        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        activationGeneration &+= 1
        let candidateGeneration = activationGeneration
        target = nil
        lock.unlock()

        activationWorker.async { [weak self] in
            self?.inspectActivatedApplication(application, path: path, generation: candidateGeneration)
        }
    }

    private func inspectActivatedApplication(
        _ application: VaultAgentPasteApplication,
        path: String,
        generation candidateGeneration: UInt64
    ) {
        // Rapid app switches can queue obsolete targets behind a slow signature check.
        guard lock.withLock({ started && activationGeneration == candidateGeneration }) else { return }
        let snapshot: VaultAgentProcessSnapshot
        let signature: VaultAgentCodeSignature
        do {
            snapshot = try processInspector.snapshot(pid: application.processIdentifier)
            guard snapshot.pid == application.processIdentifier,
                  Self.canonicalPath(snapshot.executableURL) == path else { return }
            signature = try codeSigningInspector.inspect(executableURL: snapshot.executableURL)
        } catch {
            return
        }
        let stored = StoredTarget(
            generation: UUID(),
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            executableURL: application.executableURL,
            snapshot: snapshot,
            signature: signature,
            focusedElement: focusedElement(application.processIdentifier)
        )
        lock.lock()
        if started, activationGeneration == candidateGeneration {
            target = stored
        }
        lock.unlock()
    }

    private static func application(from notification: Notification) -> VaultAgentPasteApplication? {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let executableURL = application.executableURL else { return nil }
        return .init(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            executableURL: executableURL,
            isTerminated: application.isTerminated,
            application: application
        )
    }

    private static func runningApplication(pid: pid_t) -> VaultAgentPasteApplication? {
        guard let application = NSRunningApplication(processIdentifier: pid),
              let executableURL = application.executableURL else { return nil }
        return .init(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            executableURL: executableURL,
            isTerminated: application.isTerminated,
            application: application
        )
    }

    private static func focusedElement(pid: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func defaultExcludedURLs() -> [URL] {
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        return ["PasteraCodexMCP", "PasteraClaudeMCP", "pastera"].map {
            helpers.appendingPathComponent($0)
        }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
