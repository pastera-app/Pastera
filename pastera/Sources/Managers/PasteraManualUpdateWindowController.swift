//
//  PasteraManualUpdateWindowController.swift
//
//  Pastera
//

import AppKit
import Sparkle

struct PasteraManualUpdateDescriptor: Equatable, Sendable {
    let displayVersion: String
    let currentVersion: String
    let releasePageURL: URL
}

enum PasteraManualUpdateAction: Equatable {
    case download
    case cancelDownload
    case later
    case skip
    case openReleasePage
}

enum PasteraUpdatePresentationMode {
    case manualDownload
    case sparkleInstall
}

@MainActor
final class PasteraManualUpdateWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let windowSize = NSSize(width: 680, height: 380)
        static let margin: CGFloat = 28
        static let iconSize: CGFloat = 72
    }

    private let update: PasteraManualUpdateDescriptor
    private let mode: PasteraUpdatePresentationMode
    private let stage: SPUUserUpdateStage
    private weak var updater: SPUUpdater?
    private let onAction: (PasteraManualUpdateAction) -> Void
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let downloadButton = NSButton(title: "", target: nil, action: nil)
    private let laterButton = NSButton(title: "", target: nil, action: nil)
    private let skipButton = NSButton(title: "", target: nil, action: nil)
    private let automaticInstallButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var automaticUpdateObservations: [NSKeyValueObservation] = []
    private var isDownloading = false
    private var invokesLaterWhenClosing = true
    private var isClosing = false

    init(
        update: PasteraManualUpdateDescriptor,
        mode: PasteraUpdatePresentationMode = .manualDownload,
        stage: SPUUserUpdateStage = .notDownloaded,
        updater: SPUUpdater? = nil,
        icon: NSImage,
        onAction: @escaping (PasteraManualUpdateAction) -> Void
    ) {
        self.update = update
        self.mode = mode
        self.stage = stage
        self.updater = updater
        self.onAction = onAction

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.localized("Software Update")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView(icon: icon)
        if mode == .sparkleInstall, let updater {
            automaticUpdateObservations = [
                updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                    MainActor.assumeIsolated {
                        self?.automaticInstallButton.state = updater.automaticallyDownloadsUpdates ? .on : .off
                    }
                },
                updater.observe(\.allowsAutomaticUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                    MainActor.assumeIsolated {
                        self?.automaticInstallButton.isEnabled = updater.allowsAutomaticUpdates
                    }
                }
            ]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showResolvingDownload() {
        setDownloading(true)
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = Self.localized("Preparing the update download…")
    }

    func showDownloadProgress(completedBytes: Int64, totalBytes: Int64) {
        setDownloading(true)
        progressIndicator.stopAnimation(nil)
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = Double(max(totalBytes, 1))
        progressIndicator.doubleValue = Double(completedBytes)
        let percentage = min(100, max(0, Int((Double(completedBytes) / Double(max(totalBytes, 1))) * 100)))
        statusLabel.stringValue = String(
            format: Self.localized("Downloading update… %d%%"),
            percentage
        )
    }

    func showVerifyingDownload() {
        setDownloading(true)
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = Self.localized("Verifying the downloaded update…")
    }

    func showInstallerOpened(fileURL: URL) {
        setDownloading(false)
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = String(
            format: Self.localized(
                "The disk image is ready. Drag Pastera to Applications to finish installing. If macOS blocks the app, open Privacy & Security settings and choose Open Anyway. Saved to %@."
            ),
            fileURL.path
        )
        downloadButton.title = Self.localized("Open Installer")
        downloadButton.isEnabled = true
        downloadButton.toolTip = fileURL.path
    }

    func showDownloadFailure(_ message: String) {
        setDownloading(false)
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = message
        downloadButton.title = Self.localized("Try Again")
        downloadButton.isEnabled = true
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        isClosing = true
        if invokesLaterWhenClosing {
            onAction(.later)
        }
    }

    func dismiss() {
        invokesLaterWhenClosing = false
        guard !isClosing else { return }
        close()
    }
}

private extension PasteraManualUpdateWindowController {
    func makeContentView(icon: NSImage) -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: Self.localized("A new version of Pastera is available"))
        titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(wrappingLabelWithString: String(
            format: Self.localized("Pastera %@ is available. You currently have version %@."),
            update.displayVersion,
            update.currentVersion
        ))
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        let releaseButton = NSButton(
            title: Self.localized("View Release Notes"),
            target: self,
            action: #selector(openReleasePage)
        )
        releaseButton.bezelStyle = .inline
        releaseButton.setButtonType(.momentaryPushIn)
        releaseButton.setAccessibilityIdentifier("manualUpdate.releasePage")

        let headingStack = NSStackView(views: [titleLabel, subtitleLabel, releaseButton])
        headingStack.orientation = .vertical
        headingStack.alignment = .leading
        headingStack.spacing = 8
        headingStack.translatesAutoresizingMaskIntoConstraints = false

        let statusMessage: String
        if mode == .sparkleInstall {
            switch stage {
            case .notDownloaded:
                statusMessage = "Download and install this update, then restart Pastera."
            case .downloaded:
                statusMessage = "The update has been downloaded and is ready to install."
            case .installing:
                statusMessage = "The update is ready. Update now to restart Pastera, or install it when Pastera quits."
            @unknown default:
                statusMessage = "Download and install this update, then restart Pastera."
            }
        } else {
            statusMessage = "Download the verified disk image here, then finish installation in Finder."
        }
        statusLabel.stringValue = Self.localized(statusMessage)
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 4
        statusLabel.setAccessibilityIdentifier("manualUpdate.status")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.setAccessibilityIdentifier("manualUpdate.progress")

        let statusCard = NSView()
        statusCard.wantsLayer = true
        statusCard.layer?.cornerRadius = 10
        statusCard.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        statusCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        statusCard.layer?.borderWidth = 1
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusLabel)
        statusCard.addSubview(progressIndicator)

        configureButtons()
        let buttonRow = NSStackView(views: [skipButton, NSView(), laterButton, downloadButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        [iconView, headingStack, statusCard, buttonRow].forEach(root.addSubview)
        if mode == .sparkleInstall {
            automaticInstallButton.title = Self.localized("Automatically download and install updates in the future")
            automaticInstallButton.target = self
            automaticInstallButton.action = #selector(automaticInstallChanged)
            automaticInstallButton.isEnabled = false
            automaticInstallButton.setAccessibilityIdentifier("manualUpdate.automaticInstall")
            automaticInstallButton.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(automaticInstallButton)
            NSLayoutConstraint.activate([
                automaticInstallButton.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
                automaticInstallButton.trailingAnchor.constraint(lessThanOrEqualTo: buttonRow.trailingAnchor),
                automaticInstallButton.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -14)
            ])
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Layout.margin),
            iconView.topAnchor.constraint(equalTo: root.topAnchor, constant: Layout.margin),
            iconView.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Layout.iconSize),
            headingStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 20),
            headingStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Layout.margin),
            headingStack.topAnchor.constraint(equalTo: iconView.topAnchor, constant: 2),

            statusCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Layout.margin),
            statusCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Layout.margin),
            statusCard.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 24),
            statusCard.heightAnchor.constraint(equalToConstant: 112),
            statusLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 16),
            progressIndicator.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),

            buttonRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Layout.margin),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Layout.margin),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Layout.margin)
        ])

        return root
    }

    func configureButtons() {
        skipButton.title = Self.localized("Skip This Version")
        skipButton.target = self
        skipButton.action = #selector(skipUpdate)
        skipButton.bezelStyle = .rounded
        skipButton.setAccessibilityIdentifier("manualUpdate.skip")

        laterButton.title = Self.localized(mode == .sparkleInstall && stage == .installing
            ? "Install on Quit"
            : "Remind Me Later")
        laterButton.target = self
        laterButton.action = #selector(remindLater)
        laterButton.bezelStyle = .rounded
        laterButton.setAccessibilityIdentifier("manualUpdate.later")

        downloadButton.title = Self.localized(mode == .sparkleInstall ? "Update" : "Download Update")
        downloadButton.target = self
        downloadButton.action = #selector(downloadUpdate)
        downloadButton.bezelStyle = .rounded
        downloadButton.keyEquivalent = "\r"
        downloadButton.setAccessibilityIdentifier("manualUpdate.download")
    }

    func setDownloading(_ downloading: Bool) {
        isDownloading = downloading
        window?.standardWindowButton(.closeButton)?.isEnabled = !downloading
        progressIndicator.isHidden = false
        downloadButton.title = downloading ? Self.localized("Cancel") : Self.localized("Download Update")
        laterButton.isEnabled = !downloading
        skipButton.isEnabled = !downloading
    }

    @objc func downloadUpdate() {
        onAction(isDownloading ? .cancelDownload : .download)
    }

    @objc func automaticInstallChanged() {
        guard let updater, updater.allowsAutomaticUpdates else { return }
        updater.automaticallyDownloadsUpdates = automaticInstallButton.state == .on
    }

    @objc func remindLater() {
        invokesLaterWhenClosing = false
        onAction(.later)
        dismiss()
    }

    @objc func skipUpdate() {
        invokesLaterWhenClosing = false
        onAction(.skip)
        dismiss()
    }

    @objc func openReleasePage() {
        onAction(.openReleasePage)
    }

    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
