//
//  PasteraUpdaterController.swift
//
//  Pastera
//

import AppKit
import Sparkle

@MainActor
final class PasteraUpdaterController {
    let updater: SPUUpdater

    private let userDriver: PasteraInformationalUpdateUserDriver

    init(startingUpdater: Bool) {
        let coordinator = PasteraManualUpdateCoordinator()
        let userDriver = PasteraInformationalUpdateUserDriver(
            hostBundle: .main,
            coordinator: coordinator
        )
        self.userDriver = userDriver
        self.updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
        userDriver.updater = updater

        guard startingUpdater else { return }
        do {
            try updater.start()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

@MainActor
final class PasteraInformationalUpdateUserDriver: SPUStandardUserDriver {
    weak var updater: SPUUpdater?
    private let coordinator: PasteraManualUpdateCoordinator

    init(hostBundle: Bundle, coordinator: PasteraManualUpdateCoordinator) {
        self.coordinator = coordinator
        super.init(hostBundle: hostBundle, delegate: nil)
    }

    override func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        if !appcastItem.isInformationOnlyUpdate,
           let releasePageURL = appcastItem.releaseNotesURL ?? appcastItem.infoURL ?? appcastItem.fileURL {
            super.dismissUpdateInstallation()
            coordinator.present(
                update: PasteraManualUpdateDescriptor(
                    displayVersion: appcastItem.displayVersionString,
                    currentVersion: Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? "—",
                    releasePageURL: releasePageURL
                ),
                mode: .sparkleInstall,
                stage: state.stage,
                userInitiated: state.userInitiated,
                updater: updater,
                reply: reply
            )
            return
        }

        guard appcastItem.isInformationOnlyUpdate,
              let releasePageURL = appcastItem.infoURL,
              (try? PasteraManualUpdateAssetResolver.releaseAPIURL(for: releasePageURL)) != nil else {
            super.showUpdateFound(with: appcastItem, state: state, reply: reply)
            return
        }

        super.dismissUpdateInstallation()
        coordinator.present(
            update: PasteraManualUpdateDescriptor(
                displayVersion: appcastItem.displayVersionString,
                currentVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "—",
                releasePageURL: releasePageURL
            ),
            userInitiated: state.userInitiated,
            reply: reply
        )
    }

    override func showUpdateInFocus() {
        if coordinator.isPresentingManualUpdate {
            coordinator.focusWindow()
        } else {
            super.showUpdateInFocus()
        }
    }

    override func dismissUpdateInstallation() {
        coordinator.dismiss()
        super.dismissUpdateInstallation()
    }
}

@MainActor
final class PasteraManualUpdateCoordinator {
    private let downloadService: PasteraManualUpdateDownloadService
    private let workspace: NSWorkspace
    private var windowController: PasteraManualUpdateWindowController?
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var currentUpdate: PasteraManualUpdateDescriptor?
    private var presentationMode = PasteraUpdatePresentationMode.manualDownload
    private var presentationID: UUID?
    private var downloadedInstallerURL: URL?
    private var isVerifying = false

    init() {
        self.downloadService = PasteraManualUpdateDownloadService()
        self.workspace = .shared
    }

    init(downloadService: PasteraManualUpdateDownloadService, workspace: NSWorkspace) {
        self.downloadService = downloadService
        self.workspace = workspace
    }

    var isPresentingManualUpdate: Bool {
        windowController != nil
    }

    func present(
        update: PasteraManualUpdateDescriptor,
        mode: PasteraUpdatePresentationMode = .manualDownload,
        stage: SPUUserUpdateStage = .notDownloaded,
        userInitiated: Bool = true,
        updater: SPUUpdater? = nil,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        if windowController != nil {
            if userInitiated {
                focusWindow()
            }
            reply(.dismiss)
            return
        }

        currentUpdate = update
        presentationMode = mode
        let presentationID = UUID()
        self.presentationID = presentationID
        pendingReply = reply
        downloadedInstallerURL = nil
        isVerifying = false
        let controller = PasteraManualUpdateWindowController(
            update: update,
            mode: mode,
            stage: stage,
            updater: updater,
            icon: NSApp.applicationIconImage,
            onAction: { [weak self] action in
                guard let self, self.presentationID == presentationID else { return }
                self.handle(action)
            }
        )
        windowController = controller
        if userInitiated {
            focusWindow()
        } else {
            controller.window?.orderFront(nil)
        }
    }

    func focusWindow() {
        NSApp.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        pendingReply = nil
        presentationID = nil
        let controller = windowController
        windowController = nil
        currentUpdate = nil
        downloadedInstallerURL = nil
        isVerifying = false
        downloadService.abandon()
        controller?.dismiss()
    }
}

private extension PasteraManualUpdateCoordinator {
    func handle(_ action: PasteraManualUpdateAction) {
        switch action {
        case .download:
            if presentationMode == .sparkleInstall {
                completeSparkleReply(.install)
            } else if let downloadedInstallerURL {
                openInstaller(downloadedInstallerURL)
            } else {
                startDownload()
            }
        case .cancelDownload:
            if downloadService.cancel() {
                isVerifying = false
                windowController?.showDownloadFailure(localized(
                    "The update download was canceled. You can try again."
                ))
            }
        case .later:
            completeSparkleReply(.dismiss)
        case .skip:
            completeSparkleReply(.skip)
        case .openReleasePage:
            if let releasePageURL = currentUpdate?.releasePageURL {
                workspace.open(releasePageURL)
            }
        }
    }

    func startDownload() {
        guard let update = currentUpdate else { return }
        isVerifying = false
        windowController?.showResolvingDownload()
        downloadService.start(
            update: update,
            progress: { [weak self] completedBytes, totalBytes in
                guard let self else { return }
                if completedBytes >= totalBytes, totalBytes > 0 {
                    guard !self.isVerifying else { return }
                    self.isVerifying = true
                    self.windowController?.showVerifyingDownload()
                } else {
                    self.windowController?.showDownloadProgress(
                        completedBytes: completedBytes,
                        totalBytes: totalBytes
                    )
                }
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isVerifying = false
                switch result {
                case .success(let fileURL):
                    self.downloadedInstallerURL = fileURL
                    self.openInstaller(fileURL)
                case .failure(let error):
                    self.windowController?.showDownloadFailure(self.message(for: error))
                }
            }
        )
    }

    func openInstaller(_ fileURL: URL) {
        if workspace.open(fileURL) {
            windowController?.showInstallerOpened(fileURL: fileURL)
        } else {
            windowController?.showDownloadFailure(localized(
                "The update was downloaded, but the disk image could not be opened. Open it from Downloads or view the release page for help."
            ))
        }
    }

    func completeSparkleReply(_ choice: SPUUserUpdateChoice) {
        guard let reply = pendingReply else { return }
        // Finish the old presentation before Sparkle synchronously starts its next UI stage.
        dismiss()
        reply(choice)
    }

    func message(for error: Error) -> String {
        switch error as? PasteraManualUpdateError {
        case .sizeMismatch, .digestMismatch:
            return localized(
                "The downloaded update failed verification and was not opened. Try again or use the release page."
            )
        case .untrustedReleaseAsset:
            return localized(
                "The update download did not come from the official Pastera release and was blocked."
            )
        case .cannotSaveInstaller, .downloadsDirectoryUnavailable:
            return localized(
                "Pastera could not save the installer in Downloads. Check folder access and try again."
            )
        default:
            return localized(
                "Pastera could not download this update. Check your connection and try again, or view the release page."
            )
        }
    }

    func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
