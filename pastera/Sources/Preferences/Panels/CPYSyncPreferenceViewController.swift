//
//  CPYSyncPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/16.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

// swiftlint:disable file_length

final class PasteraSyncSwitch: NSButton {
    static let onTrackColor = NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 46, height: 24)
    }

    override func setNextState() {
        super.setNextState()
        needsDisplay = true
    }

    override func performClick(_ sender: Any?) {
        super.performClick(sender)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 1, dy: 1)
        let radius = trackRect.height / 2
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.48
        let isOn = state == .on
        let trackColor = isOn ? Self.onTrackColor : offTrackColor
        trackColor.withAlphaComponent(trackColor.alphaComponent * enabledAlpha).setFill()
        trackPath.fill()

        let thumbDiameter = max(1, trackRect.height - 4)
        let thumbX = isOn
            ? trackRect.maxX - thumbDiameter - 2
            : trackRect.minX + 2
        let thumbRect = NSRect(
            x: thumbX,
            y: trackRect.midY - thumbDiameter / 2,
            width: thumbDiameter,
            height: thumbDiameter
        )
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        thumbColor.withAlphaComponent(enabledAlpha).setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func configure() {
        title = ""
        setButtonType(.switch)
        isBordered = false
        imagePosition = .noImage
        focusRingType = .none
    }

    private var offTrackColor: NSColor {
        isDarkAppearance
            ? NSColor(calibratedWhite: 1.0, alpha: 0.14)
            : NSColor(calibratedWhite: 0.0, alpha: 0.16)
    }

    private var thumbColor: NSColor {
        isDarkAppearance
            ? NSColor(calibratedWhite: 0.92, alpha: 1.0)
            : NSColor(calibratedWhite: 0.98, alpha: 1.0)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private final class PasteraVaultSyncSummaryView: NSStackView {
    private let symbolView = NSImageView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        for label in [summaryLabel, detailLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textStack.addArrangedSubview(label)
        }
        addArrangedSubview(symbolView)
        addArrangedSubview(textStack)
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16),
            widthAnchor.constraint(lessThanOrEqualToConstant: 250)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(text: String, detail: String?, symbolName: String, tintColor: NSColor) {
        symbolView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        symbolView.contentTintColor = tintColor
        summaryLabel.stringValue = text
        summaryLabel.textColor = tintColor
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil
        let accessibilityText = detail.map { "\(text), \($0)" } ?? text
        toolTip = accessibilityText
        setAccessibilityLabel(accessibilityText)
    }
}

private struct PasteraVaultSyncPresentation {
    let text: String
    let detail: String?
    let symbolName: String
    let tintColor: NSColor
}

final class CPYSyncPreferenceViewController: PasteraPreferencePageViewController {
    private enum Text {
        static let uploadHistory = pasteraPreferenceString("Upload History")
        static let importHistory = pasteraPreferenceString("Import History")
        static let uploadSnippets = pasteraPreferenceString("Upload Snippets")
        static let importSnippets = pasteraPreferenceString("Import Snippets")
        static let fileTypes = pasteraPreferenceString("File Types")
        static let syncInfo = "i"
        static let syncInfoLabel = pasteraPreferenceString("Sync Information")
        static let syncInfoText = pasteraPreferenceString("OneDrive Sync Description")
        static let switchOn = pasteraPreferenceString("On")
        static let switchOff = pasteraPreferenceString("Off")
        static let changeFolder = pasteraPreferenceString("Change")
        static let showInFinder = pasteraPreferenceString("Show in Finder")
        static let syncNow = pasteraPreferenceString("Sync Now")
        static let oneDriveFolder = pasteraPreferenceString("Sync Location")
        static let manualSync = pasteraPreferenceString("Manual Sync")
        static let notDetected = pasteraPreferenceString("OneDrive Not Detected")
        static let enableVaultSync = pasteraPreferenceString("Enable OneDrive Sync")
    }

    private struct FileTypeOption {
        let identifier: String
        let types: Set<PasteboardAvailableType>
        let title: String
        let accessibilityLabel: String
        let symbolName: String
    }

    private let settingsStore = UserDefaultsSyncSettingsStore()
    private let passwordVaultSyncService = AppEnvironment.current.passwordVaultSyncService
    private var passwordVaultSyncObserver: UUID?
    private var syncActivityObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var oneDriveProcessStatusObservation: OneDriveProcessStatusObservation?
    private var switchRows = [(stateLabel: NSTextField, control: PasteraSyncSwitch)]()
    private weak var folderRow: PasteraPreferenceSettingRowView?

    private let syncInfoButton = NSButton(title: Text.syncInfo, target: nil, action: nil)
    private let historyUploadSwitch = PasteraSyncSwitch()
    private let historyImportSwitch = PasteraSyncSwitch()
    private let snippetUploadSwitch = PasteraSyncSwitch()
    private let snippetImportSwitch = PasteraSyncSwitch()
    private var fileTypeButtons = [NSButton]()
    private let oneDriveStatusBadge = PasteraOneDriveStatusBadge()
    private let changeFolderButton = NSButton(title: Text.changeFolder, target: nil, action: nil)
    private let showFolderButton = NSButton(title: Text.showInFinder, target: nil, action: nil)
    private let syncNowButton = NSButton(title: Text.syncNow, target: nil, action: nil)
    private let vaultSyncSummaryView = PasteraVaultSyncSummaryView()
    private let enableVaultSyncButton = NSButton(title: Text.enableVaultSync, target: nil, action: nil)
    private let defaultFolderResolutionProvider: () -> SyncDefaultFolderResolution
    private let defaultFolderResolver: SyncDefaultFolderResolver
    private let revealInFinder: (URL) -> Void
    private let chooseSyncRoot: (NSWindow?, URL?) -> URL?
    private let injectedSyncRootProbe: ((URL) -> Bool)?
    private let passwordVaultSyncSnapshotProvider: () -> PasswordVaultSyncSnapshot
    private let oneDriveProcessStatusService: OneDriveProcessStatusServicing
    private let enablePasswordVaultSync: (
        URL,
        @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) -> Void
    private var requiresOneDriveSelection = false
    private var infoPopover: NSPopover?
    private let fileTypeOptions: [FileTypeOption] = [
        FileTypeOption(
            identifier: "sync-image",
            types: [.tiff],
            title: "",
            accessibilityLabel: pasteraPreferenceString("Images"),
            symbolName: "photo"
        ),
        FileTypeOption(
            identifier: "sync-document-assets",
            types: [.pdf, .rtf, .rtfd],
            title: "",
            accessibilityLabel: pasteraPreferenceString("Common Document Types"),
            symbolName: "doc.text"
        )
    ]

    init(
        defaultFolderResolver: SyncDefaultFolderResolver = SyncDefaultFolderResolver(),
        defaultFolderResolutionProvider: (() -> SyncDefaultFolderResolution)? = nil,
        revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        chooseSyncRoot: @escaping (NSWindow?, URL?) -> URL? = { _, currentRootURL in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = Text.changeFolder
            panel.message = pasteraPreferenceString("Choose a OneDrive folder for Pastera sync.")
            panel.directoryURL = currentRootURL
            return panel.runModal() == .OK ? panel.url : nil
        },
        syncRootProbe: ((URL) -> Bool)? = nil,
        oneDriveProcessStatusService: OneDriveProcessStatusServicing = AppEnvironment.current.oneDriveProcessStatusService,
        passwordVaultSyncSnapshotProvider: @escaping () -> PasswordVaultSyncSnapshot = {
            AppEnvironment.current.passwordVaultSyncService.snapshot
        },
        enablePasswordVaultSync: @escaping (
            URL,
            @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
        ) -> Void = { rootURL, completion in
            AppEnvironment.current.passwordVaultSyncService.enableOneDrive(
                rootURL: rootURL,
                remoteMasterPassword: nil,
                completion: completion
            )
        }
    ) {
        self.defaultFolderResolver = defaultFolderResolver
        self.defaultFolderResolutionProvider = defaultFolderResolutionProvider ?? { defaultFolderResolver.resolve() }
        self.revealInFinder = revealInFinder
        self.chooseSyncRoot = chooseSyncRoot
        self.injectedSyncRootProbe = syncRootProbe
        self.oneDriveProcessStatusService = oneDriveProcessStatusService
        self.passwordVaultSyncSnapshotProvider = passwordVaultSyncSnapshotProvider
        self.enablePasswordVaultSync = enablePasswordVaultSync
        super.init(paneID: .sync, title: pasteraPreferenceString("Sync"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        removeObservers()
        resetContent()
        switchRows.removeAll()
        fileTypeButtons.removeAll()
        super.loadView()
        buildPage()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindActions()
        refreshDefaultFolderAvailability()
        removeObservers()
        syncActivityObserver = NotificationCenter.default.addObserver(
            forName: SyncCoordinator.statusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateSyncActivityState()
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self, self.isViewLoaded, self.view.window?.isVisible == true else { return }
            self.refreshSavedFolderStatus()
        }
        oneDriveProcessStatusObservation = oneDriveProcessStatusService.startMonitoring { [weak self] in
            guard let self, self.isViewLoaded, self.view.window?.isVisible == true else { return }
            self.refreshDefaultFolderAvailability()
        }
        passwordVaultSyncObserver = passwordVaultSyncService.addObserver { [weak self] _ in
            let refresh: () -> Void = { [weak self] in
                guard let self, self.isViewLoaded else { return }
                self.updatePasswordVaultSyncSummary()
            }
            if Thread.isMainThread {
                refresh()
            } else {
                DispatchQueue.main.async(execute: refresh)
            }
        }
    }

    deinit {
        removeObservers()
    }

    private func buildPage() {
        syncInfoButton.bezelStyle = .circular
        syncInfoButton.font = .systemFont(ofSize: 11, weight: .semibold)
        syncInfoButton.setAccessibilityLabel(Text.syncInfoLabel)
        syncInfoButton.toolTip = Text.syncInfoText

        let statusControl = NSStackView(views: [oneDriveStatusBadge, syncInfoButton])
        statusControl.orientation = .horizontal
        statusControl.alignment = .centerY
        statusControl.spacing = 6
        let statusRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("OneDrive Status"),
            subtitle: pasteraPreferenceString("Sync uses a local OneDrive folder without connecting an account."),
            control: statusControl
        )

        let folderControls = NSStackView(views: [changeFolderButton, showFolderButton])
        folderControls.orientation = .horizontal
        folderControls.alignment = .centerY
        folderControls.spacing = 8
        let folderRow = PasteraPreferenceSettingRowView(
            title: Text.oneDriveFolder,
            subtitle: pasteraPreferenceString("Choose a writable Pastera folder inside OneDrive."),
            control: folderControls
        )
        self.folderRow = folderRow

        let accountGroup = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("OneDrive"),
            symbolName: "cloud",
            accentColor: .systemBlue
        )
        accountGroup.addRow(statusRow)
        accountGroup.addRow(folderRow)
        addGroup(accountGroup)
        registerAnchor("sync.oneDriveStatus", view: statusRow)
        registerAnchor("sync.rootFolder", view: folderRow)

        enableVaultSyncButton.bezelStyle = .rounded
        enableVaultSyncButton.controlSize = .small
        enableVaultSyncButton.setAccessibilityLabel(Text.enableVaultSync)
        let vaultStatusRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Password Vault Sync"),
            subtitle: pasteraPreferenceString("Password vault sync is independent from history and snippet sync."),
            control: vaultSyncSummaryView
        )
        let vaultManagementRow = PasteraPreferenceSettingRowView(
            title: pasteraPreferenceString("Enable Password Vault Sync"),
            subtitle: pasteraPreferenceString("Create an encrypted OneDrive replica using the selected folder."),
            control: enableVaultSyncButton
        )
        let vaultGroup = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Password Vault"),
            symbolName: "lock.shield",
            accentColor: .systemIndigo
        )
        vaultGroup.addRow(vaultStatusRow)
        vaultGroup.addRow(vaultManagementRow)
        addGroup(vaultGroup)
        registerAnchor("sync.passwordVault", view: vaultStatusRow)

        fileTypeButtons = fileTypeOptions.map(makeFileTypeCheckbox)
        let fileTypeControls = NSStackView(views: fileTypeButtons)
        fileTypeControls.orientation = .horizontal
        fileTypeControls.alignment = .centerY
        fileTypeControls.spacing = 8
        let fileTypeRow = PasteraPreferenceSettingRowView(
            title: Text.fileTypes,
            subtitle: pasteraPreferenceString("Choose which history file types are uploaded and imported."),
            control: fileTypeControls
        )

        let scopeGroup = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Sync Scope"),
            symbolName: "arrow.triangle.2.circlepath",
            accentColor: .systemTeal
        )
        scopeGroup.addRow(fileTypeRow)
        scopeGroup.addRow(makeSwitchRow(title: Text.uploadHistory, control: historyUploadSwitch))
        scopeGroup.addRow(makeSwitchRow(title: Text.importHistory, control: historyImportSwitch))
        scopeGroup.addRow(makeSwitchRow(title: Text.uploadSnippets, control: snippetUploadSwitch))
        scopeGroup.addRow(makeSwitchRow(title: Text.importSnippets, control: snippetImportSwitch))
        addGroup(scopeGroup)
        registerAnchor("sync.fileTypes", view: fileTypeRow)

        let actionRow = PasteraPreferenceSettingRowView(
            title: Text.manualSync,
            subtitle: pasteraPreferenceString("Run all enabled upload and import tasks now."),
            control: syncNowButton
        )
        let actionsGroup = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Actions"),
            symbolName: "bolt",
            accentColor: .systemOrange
        )
        actionsGroup.addRow(actionRow)
        addGroup(actionsGroup)
        registerAnchor("sync.actions", view: actionRow)
    }

    private func makeSwitchRow(title: String, control: PasteraSyncSwitch) -> PasteraPreferenceSettingRowView {
        let stateLabel = NSTextField(labelWithString: Text.switchOff)
        stateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stateLabel.alignment = .right
        stateLabel.textColor = .secondaryLabelColor
        control.setAccessibilityLabel(title)
        let controls = NSStackView(views: [control, stateLabel])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        switchRows.append((stateLabel, control))
        return PasteraPreferenceSettingRowView(title: title, control: controls)
    }

    private func makeFileTypeCheckbox(_ option: FileTypeOption) -> NSButton {
        let button = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(toggleFileTypeCheckbox(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(option.identifier)
        button.setAccessibilityLabel(option.accessibilityLabel)
        button.toolTip = option.accessibilityLabel
        button.image = NSImage(systemSymbolName: option.symbolName, accessibilityDescription: option.accessibilityLabel)
        button.imagePosition = .imageOnly
        button.alignment = .center
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.lineBreakMode = .byTruncatingTail
        return button
    }

    private func resetContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        contentStack.removeFromSuperview()
    }

    private func removeObservers() {
        if let passwordVaultSyncObserver {
            passwordVaultSyncService.removeObserver(passwordVaultSyncObserver)
            self.passwordVaultSyncObserver = nil
        }
        oneDriveProcessStatusObservation?.cancel()
        oneDriveProcessStatusObservation = nil
        if let syncActivityObserver {
            NotificationCenter.default.removeObserver(syncActivityObserver)
            self.syncActivityObserver = nil
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}

extension CPYSyncPreferenceViewController {
    func refreshDefaultFolderAvailability() {
        applyDefaultFolder()
        updateControls()
        updateSyncActivityState()
    }

    func refreshSavedFolderStatus() {
        _ = updateControls()
        updateSyncActivityState()
    }
}

private extension CPYSyncPreferenceViewController {
    func bindActions() {
        historyUploadSwitch.target = self
        historyUploadSwitch.action = #selector(toggleHistoryUpload(_:))
        historyImportSwitch.target = self
        historyImportSwitch.action = #selector(toggleHistoryImport(_:))
        snippetUploadSwitch.target = self
        snippetUploadSwitch.action = #selector(toggleSnippetUpload(_:))
        snippetImportSwitch.target = self
        snippetImportSwitch.action = #selector(toggleSnippetImport(_:))
        syncInfoButton.target = self
        syncInfoButton.action = #selector(showSyncInfo(_:))
        oneDriveStatusBadge.setRedetectTarget(self, action: #selector(redetectOneDrive))
        changeFolderButton.target = self
        changeFolderButton.action = #selector(changeFolder)
        showFolderButton.target = self
        showFolderButton.action = #selector(showFolderInFinder)
        syncNowButton.target = self
        syncNowButton.action = #selector(syncNow)
        enableVaultSyncButton.target = self
        enableVaultSyncButton.action = #selector(enableVaultSync)
    }

    @objc func showSyncInfo(_ sender: NSButton) {
        if infoPopover?.isShown == true {
            infoPopover?.close()
            return
        }

        let label = NSTextField(wrappingLabelWithString: Text.syncInfoText)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.frame = NSRect(x: 12, y: 12, width: 280, height: 78)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 102))
        contentView.addSubview(label)

        let controller = NSViewController()
        controller.view = contentView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        infoPopover = popover
    }

    @objc func redetectOneDrive() {
        oneDriveStatusBadge.setRedetecting(true)
        refreshDefaultFolderAvailability()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.oneDriveStatusBadge.setRedetecting(false)
        }
    }

    @objc func showFolderInFinder() {
        guard ensureDefaultFolderAvailable(), let rootURL = settingsStore.settings().rootURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        revealInFinder(rootURL)
    }

    @objc func changeFolder() {
        let currentRootURL = settingsStore.settings().rootURL
        guard let selectedURL = chooseSyncRoot(view.window, currentRootURL) else {
            return
        }
        applyCustomSyncRoot(selectedURL)
    }

    @objc func syncNow() {
        guard prepareManualSync() else { return }
        syncNowButton.isEnabled = false
        SyncCoordinator.shared.syncNow(reason: .manual)
    }

    @objc func enableVaultSync() {
        guard passwordVaultSyncSnapshotProvider().mode == .localOnly,
              ensureDefaultFolderAvailable(),
              let rootURL = settingsStore.settings().rootURL else {
            return
        }
        enableVaultSyncButton.isEnabled = false
        enablePasswordVaultSync(rootURL) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateControls()
            }
        }
    }

    @objc func toggleHistoryUpload(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setHistoryUploadEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleHistoryImport(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setHistoryImportEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleSnippetUpload(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setSnippetUploadEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleSnippetImport(_ sender: PasteraSyncSwitch) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        settingsStore.setSnippetImportEnabled(sender.state == .on)
        updateControls()
    }

    @objc func toggleFileTypeCheckbox(_ sender: NSButton) {
        guard ensureDefaultFolderAvailable() else {
            sender.state = .off
            updateControls()
            return
        }
        guard let identifier = sender.identifier?.rawValue,
              let option = fileTypeOptions.first(where: { $0.identifier == identifier }) else {
            return
        }
        option.types.forEach {
            settingsStore.setFileTypeEnabled($0, enabled: sender.state == .on)
        }
        updateControls()
    }

    @discardableResult
    func updateControls() -> Bool {
        let settings = settingsStore.settings()
        let rootIsAvailable = updateOneDriveStatus(rootURL: settings.rootURL)
        showFolderButton.isEnabled = rootIsAvailable
        updateSwitch(historyUploadSwitch, isOn: settings.historyUploadEnabled)
        updateSwitch(historyImportSwitch, isOn: settings.historyImportEnabled)
        updateSwitch(snippetUploadSwitch, isOn: settings.snippetUploadEnabled)
        updateSwitch(snippetImportSwitch, isOn: settings.snippetImportEnabled)
        updateFileTypeCheckboxes(settings: settings)
        updatePasswordVaultSyncSummary()
        return rootIsAvailable
    }

    func updatePasswordVaultSyncSummary() {
        let snapshot = passwordVaultSyncSnapshotProvider()
        enableVaultSyncButton.isHidden = snapshot.mode == .oneDrive
        enableVaultSyncButton.isEnabled = snapshot.mode == .localOnly
            && (settingsStore.settings().rootURL.map(isSyncRootAvailable) ?? false)
        let presentation = passwordVaultSyncPresentation(for: snapshot)
        vaultSyncSummaryView.update(
            text: presentation.text,
            detail: presentation.detail,
            symbolName: presentation.symbolName,
            tintColor: presentation.tintColor
        )
    }

    func passwordVaultSyncPresentation(
        for snapshot: PasswordVaultSyncSnapshot
    ) -> PasteraVaultSyncPresentation {
        guard snapshot.mode == .oneDrive else {
            return PasteraVaultSyncPresentation(
                text: pasteraPreferenceString("OneDrive sync is off"),
                detail: nil,
                symbolName: "cloud",
                tintColor: .secondaryLabelColor
            )
        }
        let pendingDetail = snapshot.pendingChangeCount > 0
            ? String(
                format: pasteraPreferenceString("%lld changes waiting"),
                Int64(snapshot.pendingChangeCount)
            )
            : nil
        switch snapshot.phase {
        case .synced:
            let detail = snapshot.lastSyncAt.map {
                String(
                    format: pasteraPreferenceString("Last synced: %@"),
                    DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short)
                )
            }
            return PasteraVaultSyncPresentation(
                text: pasteraPreferenceString("OneDrive is connected"),
                detail: detail,
                symbolName: "checkmark.circle.fill",
                tintColor: .systemBlue
            )
        case .syncing:
            return PasteraVaultSyncPresentation(
                text: pasteraPreferenceString("Syncing with OneDrive"),
                detail: pendingDetail,
                symbolName: "arrow.triangle.2.circlepath",
                tintColor: .systemBlue
            )
        case .disconnected:
            let text = snapshot.pendingChangeCount > 0
                ? String(
                    format: pasteraPreferenceString("OneDrive is disconnected; %lld changes are waiting"),
                    Int64(snapshot.pendingChangeCount)
                )
                : pasteraPreferenceString("OneDrive is disconnected")
            return PasteraVaultSyncPresentation(
                text: text,
                detail: nil,
                symbolName: "bolt.slash.fill",
                tintColor: .systemRed
            )
        case .waitingForUnlock:
            return PasteraVaultSyncPresentation(
                text: pasteraPreferenceString("Sync is waiting for unlock"),
                detail: pendingDetail,
                symbolName: "lock.fill",
                tintColor: .systemOrange
            )
        case .conflicts(let count):
            let conflictCount = max(count, snapshot.conflictCopyCount)
            let text = String(
                format: pasteraPreferenceString("OneDrive has %lld conflict copies"),
                Int64(conflictCount)
            )
            return PasteraVaultSyncPresentation(
                text: text,
                detail: pendingDetail,
                symbolName: "exclamationmark.triangle.fill",
                tintColor: .systemOrange
            )
        case .failed(let failure):
            return PasteraVaultSyncPresentation(
                text: passwordVaultSyncFailureMessage(failure),
                detail: pendingDetail,
                symbolName: "xmark.octagon.fill",
                tintColor: .systemRed
            )
        case .disabled:
            return PasteraVaultSyncPresentation(
                text: pasteraPreferenceString("OneDrive sync needs attention"),
                detail: pendingDetail,
                symbolName: "xmark.octagon.fill",
                tintColor: .systemRed
            )
        }
    }

    func updateSwitch(_ control: PasteraSyncSwitch, isOn: Bool) {
        control.state = isOn ? .on : .off
        control.setAccessibilityValue(isOn ? Text.switchOn : Text.switchOff)
        control.needsDisplay = true
        guard let switchRow = switchRows.first(where: { $0.control === control }) else {
            return
        }
        switchRow.stateLabel.stringValue = isOn ? Text.switchOn : Text.switchOff
        switchRow.stateLabel.textColor = isOn ? PasteraSyncSwitch.onTrackColor : .secondaryLabelColor
    }

    func updateFileTypeCheckboxes(settings: SyncSettings) {
        for button in fileTypeButtons {
            guard let identifier = button.identifier?.rawValue,
                  let option = fileTypeOptions.first(where: { $0.identifier == identifier }) else {
                continue
            }
            button.state = !settings.fileAssetTypes.isDisjoint(with: option.types) ? .on : .off
        }
    }

    @discardableResult
    func updateOneDriveStatus(rootURL: URL?) -> Bool {
        guard let rootURL else {
            oneDriveStatusBadge.state = requiresOneDriveSelection ? .selectionRequired : .notDetected
            folderRow?.toolTip = nil
            changeFolderButton.toolTip = nil
            showFolderButton.toolTip = nil
            return false
        }
        var isDirectory: ObjCBool = false
        let isAvailable = FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && isOneDriveBacked(rootURL)
            && FileManager.default.isWritableFile(atPath: rootURL.path)
        if isAvailable {
            oneDriveStatusBadge.state = .available
        } else if oneDriveProcessStatusService.currentStatus().isRunning {
            oneDriveStatusBadge.state = .runningFolderUnavailable
        } else {
            oneDriveStatusBadge.state = .unavailable
        }
        let displayName = displayName(for: rootURL)
        folderRow?.toolTip = displayName
        changeFolderButton.toolTip = displayName
        showFolderButton.toolTip = displayName
        return isAvailable
    }

    func updateSyncActivityState() {
        let status = SyncCoordinator.shared.status
        syncNowButton.isEnabled = status.phase != .syncing
    }

    func prepareManualSync() -> Bool {
        guard ensureDefaultFolderAvailable() else {
            return false
        }
        let settings = settingsStore.settings()
        guard settings.hasEnabledWork else {
            return false
        }
        return true
    }

    func ensureDefaultFolderAvailable() -> Bool {
        applyDefaultFolder()
        guard let rootURL = settingsStore.settings().rootURL else {
            return false
        }
        return isSyncRootAvailable(rootURL)
    }

    func applyDefaultFolder() {
        if let rootURL = settingsStore.settings().rootURL {
            requiresOneDriveSelection = false
            if !isSyncRootAvailable(rootURL) {
                updateControls()
            }
            return
        }
        switch defaultFolderResolutionProvider() {
        case .found(let candidate):
            requiresOneDriveSelection = false
            useDefaultFolder(candidate)
        case .notFound:
            requiresOneDriveSelection = false
            settingsStore.setRootURL(nil)
        case .multiple(let candidates):
            guard let candidate = defaultFolderResolver.preferredCandidate(from: candidates) else {
                requiresOneDriveSelection = true
                settingsStore.setRootURL(nil)
                return
            }
            requiresOneDriveSelection = false
            useDefaultFolder(candidate)
        }
    }

    func useDefaultFolder(_ candidate: SyncDefaultFolderCandidate) {
        guard let preparedCandidate = defaultFolderResolver.prepare(candidate),
              canWriteSyncProbe(at: preparedCandidate.syncRootURL) else {
            settingsStore.setRootURL(nil)
            return
        }
        settingsStore.setRootURL(preparedCandidate.syncRootURL)
    }

    func applyCustomSyncRoot(_ selectedURL: URL) {
        let rootURL = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        guard isSyncRootAvailable(rootURL), canWriteSyncProbe(at: rootURL) else {
            updateControls()
            return
        }
        settingsStore.setRootURL(rootURL)
        updateControls()
    }

    func isSyncRootAvailable(_ rootURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && isOneDriveBacked(rootURL)
            && FileManager.default.isWritableFile(atPath: rootURL.path)
    }

    func isOneDriveBacked(_ rootURL: URL) -> Bool {
        if rootURL.standardizedFileURL.pathComponents.contains("CloudStorage") {
            return SyncDefaultFolderResolver.isUsableOneDriveBackedURL(rootURL)
        }
        return defaultFolderResolver.oneDriveCandidate(containing: rootURL) != nil
    }

    func canWriteSyncProbe(at rootURL: URL) -> Bool {
        if let injectedSyncRootProbe {
            return injectedSyncRootProbe(rootURL)
        }
        let probeURL = rootURL.appendingPathComponent(".pastera-sync-check", isDirectory: false)
        let payload = UUID().uuidString
        do {
            try payload.write(to: probeURL, atomically: true, encoding: .utf8)
            let checkedPayload = try String(contentsOf: probeURL, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeURL)
            return checkedPayload == payload
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            return false
        }
    }

    func displayName(for rootURL: URL) -> String {
        oneDriveDisplayName(for: rootURL) ?? Text.notDetected
    }

    func oneDriveDisplayName(for rootURL: URL) -> String? {
        let components = rootURL.standardizedFileURL.pathComponents
        guard let cloudStorageIndex = components.firstIndex(of: "CloudStorage"),
              components.indices.contains(cloudStorageIndex + 1) else {
            return defaultFolderResolver.oneDriveCandidate(containing: rootURL).map { candidate in
                relativeDisplayName(rootURL: rootURL, oneDriveRootURL: candidate.oneDriveRootURL)
            }
        }
        let oneDriveName = components[cloudStorageIndex + 1]
        guard oneDriveName.range(of: "OneDrive", options: [.anchored, .caseInsensitive]) != nil else {
            return nil
        }
        let remainingComponents = components.dropFirst(cloudStorageIndex + 2)
        return ([oneDriveName] + Array(remainingComponents)).joined(separator: " > ")
    }

    func relativeDisplayName(rootURL: URL, oneDriveRootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let oneDrivePath = oneDriveRootURL.standardizedFileURL.path
        guard rootPath.hasPrefix(oneDrivePath) else {
            return oneDriveRootURL.lastPathComponent
        }
        let suffix = rootPath.dropFirst(oneDrivePath.count).split(separator: "/").map(String.init)
        return ([oneDriveRootURL.lastPathComponent] + suffix).joined(separator: " > ")
    }
}
