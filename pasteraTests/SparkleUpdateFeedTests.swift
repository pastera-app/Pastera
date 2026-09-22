//
//  SparkleUpdateFeedTests.swift
//
//  Clipy
//

import AppKit
import Foundation
import Sparkle
import Testing
@testable import Pastera

@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct SparkleUpdateFeedTests {
    @Test
    func infoPlistUsesRawSparkleAppcastFeed() throws {
        let feedURL = try infoPlistValue(forKey: "SUFeedURL")

        #expect(feedURL == "https://raw.githubusercontent.com/pastera-app/Pastera/develop/appcast.xml")
        #expect(!feedURL.hasSuffix("/releases"))
    }

    @Test
    func sourceBundleVersionsUseNumericSparkleComparableValues() throws {
        let shortVersion = try infoPlistValue(forKey: "CFBundleShortVersionString")
        let buildVersion = try infoPlistValue(forKey: "CFBundleVersion")

        #expect(shortVersion == "3.0.6")
        #expect(buildVersion == "306")
        #expect(shortVersion.wholeMatch(of: /[0-9]+(?:\.[0-9]+)*/) != nil)
        #expect(buildVersion.wholeMatch(of: /[0-9]+/) != nil)
    }

    @Test
    func updaterStartsEvenWhenAutomaticChecksAreDisabled() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("pastera/Sources/AppDelegate.swift"),
            encoding: .utf8
        )

        #expect(source.contains("startingUpdater: true"))
        #expect(source.contains("updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates"))
    }

    @Test
    func sourceInfoPlistDeclaresAppIcon() throws {
        #expect(try infoPlistValue(forKey: "CFBundleIconFile") == "AppIcon")
        #expect(try infoPlistValue(forKey: "CFBundleIconName") == "AppIcon")
    }

    @Test
    func legacyClipyLogoAssetIsReplaced() throws {
        let root = projectRoot()
        let legacyLogoPath = root.appendingPathComponent("Resources/clipy_logo.png").path
        let pasteraLogoPath = root.appendingPathComponent("Resources/pastera_logo.png").path

        #expect(!FileManager.default.fileExists(atPath: legacyLogoPath))
        #expect(FileManager.default.fileExists(atPath: pasteraLogoPath))
    }

    @Test
    func appIconAssetsPreserveTransparentEdges() throws {
        let iconURL = projectRoot().appendingPathComponent("pastera/Resources/Assets.xcassets/AppIcon.appiconset/512@2x.png")
        let data = try Data(contentsOf: iconURL)
        let image = try #require(NSBitmapImageRep(data: data))

        #expect(image.pixelsWide == 1024)
        #expect(image.pixelsHigh == 1024)
        #expect(image.hasAlpha)
    }

    @Test
    func appcastLatestItemMatchesCurrentBundleWithoutExecutablePayload() throws {
        let appcastURL = projectRoot().appendingPathComponent("appcast.xml")
        let data = try Data(contentsOf: appcastURL)
        let document = try XMLDocument(data: data)
        let root = try #require(document.rootElement())
        let item = try #require(try document.nodes(forXPath: "/rss/channel/item").first as? XMLElement)
        let shortVersion = try infoPlistValue(forKey: "CFBundleShortVersionString")
        let buildVersion = try infoPlistValue(forKey: "CFBundleVersion")

        #expect(root.name == "rss")
        #expect(root.attribute(forName: "version")?.stringValue == "2.0")
        #expect(item.elements(forName: "title").first?.stringValue == "Pastera \(shortVersion)")
        #expect(item.elements(forName: "sparkle:version").first?.stringValue == buildVersion)
        #expect(item.elements(forName: "sparkle:shortVersionString").first?.stringValue == shortVersion)
        #expect(item.elements(forName: "sparkle:minimumSystemVersion").first?.stringValue == "15.0")
        #expect(item.elements(forName: "sparkle:informationalUpdate").first != nil)
        #expect(item.elements(forName: "enclosure").isEmpty)
        let infoURLString = try #require(
            item.elements(forName: "link").first?.stringValue
        )
        let infoURL = try #require(URL(string: infoURLString))
        #expect(
            infoURL.absoluteString
                == "https://github.com/pastera-app/Pastera/releases/download/v\(shortVersion)-beta/Pastera-\(shortVersion)-beta-macOS.dmg"
        )
        #expect(
            item.elements(forName: "sparkle:releaseNotesLink").first?.stringValue
                == "https://github.com/pastera-app/Pastera/releases/tag/v\(shortVersion)-beta"
        )
        // Legacy clients hand this informational URL to Sparkle's browser action,
        // avoiding the anonymous Release API that their in-app downloader requires.
        #expect(throws: PasteraManualUpdateError.invalidReleaseMetadata) {
            try PasteraManualUpdateAssetResolver.releaseAPIURL(for: infoURL)
        }
    }

    @Test
    func appcastPreservesParseableInstallableHistory() throws {
        let appcastURL = projectRoot().appendingPathComponent("appcast.xml")
        let data = try Data(contentsOf: appcastURL)
        let document = try XMLDocument(data: data)
        let items = try document.nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
        let item = try #require(items.first { !$0.elements(forName: "enclosure").isEmpty })
        let enclosure = try #require(item.elements(forName: "enclosure").first)

        #expect(item.elements(forName: "title").first?.stringValue?.hasPrefix("Pastera ") == true)
        #expect(
            item.elements(forName: "link").first?.stringValue?
                .hasPrefix("https://github.com/pastera-app/Pastera/releases/tag/") == true
        )
        #expect(enclosure.attribute(forName: "url")?.stringValue?.hasPrefix("https://github.com/pastera-app/Pastera/releases/download/") == true)
        #expect(enclosure.attribute(forName: "sparkle:version")?.stringValue?.isEmpty == false)
        #expect(enclosure.attribute(forName: "sparkle:shortVersionString")?.stringValue?.isEmpty == false)
        #expect(enclosure.attribute(forName: "type")?.stringValue?.isEmpty == false)
    }

    @Test
    func manualUpdateResolverSelectsThePublishedDMGForTheRequestedVersion() throws {
        let releaseData = Data(
            """
            {
              "tag_name": "v3.0.2-beta",
              "assets": [
                {
                  "name": "Pastera-3.0.2-beta-macOS.dmg",
                  "content_type": "application/x-apple-diskimage",
                  "state": "uploaded",
                  "size": 34608614,
                  "digest": "sha256:a93cf7b121d24e6c4bd539370e497588fb8cf9c34613cae8ae20133aa42bc396",
                  "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-beta/Pastera-3.0.2-beta-macOS.dmg"
                },
                {
                  "name": "checksums.txt",
                  "content_type": "text/plain",
                  "state": "uploaded",
                  "size": 120,
                  "digest": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                  "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-beta/checksums.txt"
                }
              ]
            }
            """.utf8
        )

        let asset = try PasteraManualUpdateAssetResolver.resolve(
            releaseData: releaseData,
            expectedVersion: "3.0.2",
            expectedTag: "v3.0.2-beta"
        )

        #expect(asset.fileName == "Pastera-3.0.2-beta-macOS.dmg")
        #expect(asset.size == 34_608_614)
        #expect(asset.sha256 == "a93cf7b121d24e6c4bd539370e497588fb8cf9c34613cae8ae20133aa42bc396")
        #expect(
            asset.downloadURL.absoluteString
                == "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-beta/Pastera-3.0.2-beta-macOS.dmg"
        )
    }

    @Test
    func manualUpdateResolverRejectsAnAssetOutsideThePasteraReleasePath() throws {
        let releaseData = Data(
            """
            {
              "tag_name": "v3.0.2-beta",
              "assets": [{
                "name": "Pastera-3.0.2-beta-macOS.dmg",
                "content_type": "application/x-apple-diskimage",
                "state": "uploaded",
                "size": 34608614,
                "digest": "sha256:a93cf7b121d24e6c4bd539370e497588fb8cf9c34613cae8ae20133aa42bc396",
                "browser_download_url": "https://downloads.example.com/Pastera-3.0.2-beta-macOS.dmg"
              }]
            }
            """.utf8
        )

        #expect(throws: PasteraManualUpdateError.untrustedReleaseAsset) {
            try PasteraManualUpdateAssetResolver.resolve(
                releaseData: releaseData,
                expectedVersion: "3.0.2",
                expectedTag: "v3.0.2-beta"
            )
        }
    }

    @Test
    func manualUpdateResolverDoesNotAcceptAnotherVersionWithTheSamePrefix() {
        let releaseData = Data(
            """
            {
              "tag_name": "v3.0.2-beta",
              "assets": [{
                "name": "Pastera-3.0.20-beta-macOS.dmg",
                "content_type": "application/x-apple-diskimage",
                "state": "uploaded",
                "size": 42,
                "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-beta/Pastera-3.0.20-beta-macOS.dmg"
              }]
            }
            """.utf8
        )

        #expect(throws: PasteraManualUpdateError.updateAssetNotFound) {
            try PasteraManualUpdateAssetResolver.resolve(
                releaseData: releaseData,
                expectedVersion: "3.0.2",
                expectedTag: "v3.0.2-beta"
            )
        }
    }

    @Test
    func manualUpdateResolverRejectsAReleaseTagDifferentFromTheTrustedPage() {
        let releaseData = Data(
            """
            {
              "tag_name": "v3.0.2-evil",
              "assets": [{
                "name": "Pastera-3.0.2-evil-macOS.dmg",
                "content_type": "application/x-apple-diskimage",
                "state": "uploaded",
                "size": 42,
                "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-evil/Pastera-3.0.2-evil-macOS.dmg"
              }]
            }
            """.utf8
        )

        #expect(throws: PasteraManualUpdateError.invalidReleaseMetadata) {
            try PasteraManualUpdateAssetResolver.resolve(
                releaseData: releaseData,
                expectedVersion: "3.0.2",
                expectedTag: "v3.0.2-beta"
            )
        }
    }

    @Test
    func manualUpdateResolverRequiresTheExactDMGNameForTheReleaseTag() {
        let releaseData = Data(
            """
            {
              "tag_name": "v3.0.2-beta",
              "assets": [{
                "name": "Pastera-3.0.2-rc-macOS.dmg",
                "content_type": "application/x-apple-diskimage",
                "state": "uploaded",
                "size": 42,
                "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-beta/Pastera-3.0.2-rc-macOS.dmg"
              }]
            }
            """.utf8
        )

        #expect(throws: PasteraManualUpdateError.updateAssetNotFound) {
            try PasteraManualUpdateAssetResolver.resolve(
                releaseData: releaseData,
                expectedVersion: "3.0.2",
                expectedTag: "v3.0.2-beta"
            )
        }
    }

    @Test
    func manualUpdateResolverRejectsAmbiguousExactDMGAssets() {
        let asset = """
        {
          "name": "Pastera-3.0.2-beta-macOS.dmg",
          "content_type": "application/x-apple-diskimage",
          "state": "uploaded",
          "size": 42,
          "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-beta/Pastera-3.0.2-beta-macOS.dmg"
        }
        """
        let releaseData = Data(
            """
            {"tag_name":"v3.0.2-beta","assets":[\(asset),\(asset)]}
            """.utf8
        )

        #expect(throws: PasteraManualUpdateError.updateAssetNotFound) {
            try PasteraManualUpdateAssetResolver.resolve(
                releaseData: releaseData,
                expectedVersion: "3.0.2",
                expectedTag: "v3.0.2-beta"
            )
        }
    }

    @Test
    func manualUpdateVerifierAcceptsTheExpectedSizeAndSHA256() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraManualUpdateVerifier-\(UUID().uuidString).dmg")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try PasteraManualUpdateVerifier.verify(
            fileURL: fileURL,
            expectedSize: 5,
            expectedSHA256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    @Test
    func manualUpdateVerifierRejectsADigestMismatch() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraManualUpdateVerifier-\(UUID().uuidString).dmg")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(throws: PasteraManualUpdateError.digestMismatch) {
            try PasteraManualUpdateVerifier.verify(
                fileURL: fileURL,
                expectedSize: 5,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        }
    }

    @Test
    func manualUpdateVerifierStopsWhenTheOperationIsCanceled() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraManualUpdateVerifier-\(UUID().uuidString).dmg")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let cancellationToken = PasteraManualUpdateCancellationToken()
        cancellationToken.cancel()

        #expect(throws: PasteraManualUpdateError.cancelled) {
            try PasteraManualUpdateVerifier.verify(
                fileURL: fileURL,
                expectedSize: 5,
                expectedSHA256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                cancellationToken: cancellationToken
            )
        }
    }

    @Test
    func canceledManualUpdateCannotMoveTheVerifiedInstallerIntoDownloads() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraManualUpdateFinalize-\(UUID().uuidString)", isDirectory: true)
        let downloadsURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        let temporaryURL = rootURL.appendingPathComponent("download.tmp")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cancellationToken = PasteraManualUpdateCancellationToken()
        cancellationToken.cancel()

        #expect(throws: PasteraManualUpdateError.cancelled) {
            try PasteraManualUpdateFileFinalizer.moveVerifiedFile(
                at: temporaryURL,
                to: downloadsURL,
                fileName: "Pastera-3.0.2-beta-macOS.dmg",
                cancellationToken: cancellationToken
            )
        }
        #expect(FileManager.default.fileExists(atPath: temporaryURL.path))
        #expect(!FileManager.default.fileExists(
            atPath: downloadsURL.appendingPathComponent("Pastera-3.0.2-beta-macOS.dmg").path
        ))
    }

    @Test
    func manualUpdateCancellationDoesNotDiscardACommittedFinalization() {
        let cancellationToken = PasteraManualUpdateCancellationToken()
        let commitStarted = DispatchSemaphore(value: 0)
        let finishCommit = DispatchSemaphore(value: 0)
        let cancelAttempted = DispatchSemaphore(value: 0)
        let commitFinished = DispatchSemaphore(value: 0)
        let cancelFinished = DispatchSemaphore(value: 0)
        let commitSucceeded = PasteraManualUpdateLockedValue(false)
        let cancellationWon = PasteraManualUpdateLockedValue(true)

        let commitThread = Thread {
            defer { commitFinished.signal() }
            do {
                try cancellationToken.performCommitIfActive {
                    commitStarted.signal()
                    finishCommit.wait()
                }
                commitSucceeded.value = true
            } catch {
                commitSucceeded.value = false
            }
        }
        commitThread.qualityOfService = .userInitiated
        commitThread.start()

        #expect(commitStarted.wait(timeout: .now() + 1) == .success)
        let cancelThread = Thread {
            cancelAttempted.signal()
            cancellationWon.value = cancellationToken.cancel()
            cancelFinished.signal()
        }
        cancelThread.qualityOfService = .userInitiated
        cancelThread.start()
        #expect(cancelAttempted.wait(timeout: .now() + 1) == .success)

        finishCommit.signal()
        #expect(commitFinished.wait(timeout: .now() + 1) == .success)
        #expect(cancelFinished.wait(timeout: .now() + 1) == .success)
        #expect(commitSucceeded.value)
        #expect(!cancellationWon.value)
    }

    @Test
    func manualUpdateReleasePageMapsToTheMatchingGitHubAPIEndpoint() throws {
        let releasePageURL = try #require(
            URL(string: "https://github.com/pastera-app/Pastera/releases/tag/v3.0.2-beta")
        )

        let apiURL = try PasteraManualUpdateAssetResolver.releaseAPIURL(for: releasePageURL)

        #expect(
            apiURL.absoluteString
                == "https://api.github.com/repos/pastera-app/Pastera/releases/tags/v3.0.2-beta"
        )
    }

    @Test
    func manualUpdateDownloadChoosesANewNameInsteadOfOverwritingAnExistingInstaller() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraManualUpdateDownloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let existingURL = directoryURL.appendingPathComponent("Pastera-3.0.2-beta-macOS.dmg")
        try Data().write(to: existingURL)

        let destinationURL = PasteraManualUpdateDownloadService.availableDestinationURL(
            directoryURL: directoryURL,
            fileName: "Pastera-3.0.2-beta-macOS.dmg"
        )

        #expect(destinationURL.lastPathComponent == "Pastera-3.0.2-beta-macOS-2.dmg")
    }

    @Test @MainActor
    func manualUpdateDownloadFetchesVerifiesAndSavesThePublishedAsset() async throws {
        let downloadsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteraManualUpdateDownload-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: downloadsURL) }
        let releasePageURL = try #require(
            URL(string: "https://github.com/pastera-app/Pastera/releases/tag/v3.0.2-beta")
        )
        let releaseData = Data(
            """
            {
              "tag_name": "v3.0.2-beta",
              "assets": [{
                "name": "Pastera-3.0.2-beta-macOS.dmg",
                "content_type": "application/x-apple-diskimage",
                "state": "uploaded",
                "size": 5,
                "digest": "sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                "browser_download_url": "https://github.com/pastera-app/Pastera/releases/download/v3.0.2-beta/Pastera-3.0.2-beta-macOS.dmg"
              }]
            }
            """.utf8
        )
        PasteraManualUpdateURLProtocol.handler = { request in
            let url = try #require(request.url)
            let data = url.host == "api.github.com" ? releaseData : Data("hello".utf8)
            let response = try #require(
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, data)
        }
        defer { PasteraManualUpdateURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PasteraManualUpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = PasteraManualUpdateDownloadService(
            session: session,
            downloadsDirectory: downloadsURL
        )

        let downloadedURL = try await withCheckedThrowingContinuation { continuation in
            service.start(
                update: PasteraManualUpdateDescriptor(
                    displayVersion: "3.0.2",
                    currentVersion: "3.0.1",
                    releasePageURL: releasePageURL
                ),
                progress: { _, _ in },
                completion: { continuation.resume(with: $0) }
            )
        }

        #expect(downloadedURL.lastPathComponent == "Pastera-3.0.2-beta-macOS.dmg")
        #expect(try Data(contentsOf: downloadedURL) == Data("hello".utf8))
    }

    @Test
    func appDelegateUsesTheInformationalUpdateDriverForTrustedReleaseDownloads() throws {
        let root = projectRoot()
        let appDelegateSource = try String(
            contentsOf: root.appendingPathComponent("pastera/Sources/AppDelegate.swift"),
            encoding: .utf8
        )
        let updaterSource = try String(
            contentsOf: root.appendingPathComponent("pastera/Sources/Managers/PasteraUpdaterController.swift"),
            encoding: .utf8
        )

        #expect(appDelegateSource.contains("PasteraUpdaterController(startingUpdater: true)"))
        #expect(updaterSource.contains("appcastItem.isInformationOnlyUpdate"))
        #expect(updaterSource.contains("PasteraManualUpdateAssetResolver.releaseAPIURL"))
        #expect(updaterSource.contains("super.showUpdateFound"))
        #expect(updaterSource.contains("super.dismissUpdateInstallation()"))

        let startDownloadRange = try #require(updaterSource.range(of: "func startDownload()"))
        let openInstallerRange = try #require(
            updaterSource.range(of: "func openInstaller", range: startDownloadRange.upperBound..<updaterSource.endIndex)
        )
        let startDownloadSource = updaterSource[startDownloadRange.lowerBound..<openInstallerRange.lowerBound]
        #expect(!startDownloadSource.contains("completeSparkleReply"))
    }

    @Test(arguments: [false, true]) @MainActor
    func scheduledUpdateDoesNotTakeTheCurrentWindowsFocus(informational: Bool) async throws {
        let currentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        currentWindow.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        currentWindow.makeKeyAndOrderFront(nil)
        defer { currentWindow.close() }
        for _ in 0..<50 where NSApp.keyWindow !== currentWindow {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(NSApp.keyWindow === currentWindow)

        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        defer { driver.dismissUpdateInstallation() }
        let item = try makeUpdateAppcastItem(
            informational: informational,
            releasePageURL: URL(string: "https://github.com/pastera-app/Pastera/releases/tag/v99.0.0-beta")
        )
        let state = try makeUserUpdateState(userInitiated: false)
        driver.showUpdateFound(with: item, state: state) { _ in }

        let window = try visiblePasteraUpdateWindow()
        #expect(NSApp.keyWindow === currentWindow)
        #expect(!window.isKeyWindow)

        driver.showUpdateFound(with: item, state: state) { _ in }
        #expect(NSApp.keyWindow === currentWindow)

        driver.showUpdateInFocus()
        #expect(NSApp.keyWindow === window)
    }

    @Test(arguments: [false, true]) @MainActor
    func installableUpdatePreservesAndChangesAutomaticInstallPreference(initiallyEnabled: Bool) throws {
        let hostBundle = try makeUpdaterHostBundle(automaticallyDownloadsUpdates: initiallyEnabled)
        let bundleIdentifier = try #require(hostBundle.bundleIdentifier)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            try? FileManager.default.removeItem(at: hostBundle.bundleURL)
        }
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: hostBundle, coordinator: coordinator)
        let updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: .main, userDriver: driver, delegate: nil)
        driver.updater = updater
        defer { driver.dismissUpdateInstallation() }
        driver.showUpdateFound(with: try makeUpdateAppcastItem(informational: false), state: try makeUserUpdateState()) { _ in }
        let window = try visiblePasteraUpdateWindow()
        let contentView = try #require(window.contentView)
        let checkbox = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.automaticInstall") as? NSButton
        )
        #expect(checkbox.isEnabled)
        #expect(checkbox.state == (initiallyEnabled ? .on : .off))
        #expect(updater.automaticallyDownloadsUpdates == initiallyEnabled)

        checkbox.performClick(nil)
        #expect(updater.automaticallyDownloadsUpdates == !initiallyEnabled)
        #expect(UserDefaults(suiteName: bundleIdentifier)?.bool(forKey: "SUAutomaticallyUpdate") == !initiallyEnabled)

        updater.automaticallyDownloadsUpdates = initiallyEnabled
        #expect(checkbox.state == (initiallyEnabled ? .on : .off))
        updater.automaticallyChecksForUpdates = false
        #expect(!checkbox.isEnabled)
        #expect(!updater.automaticallyDownloadsUpdates)
        #expect(checkbox.state == .off)
        checkbox.performClick(nil)
        #expect(UserDefaults(suiteName: bundleIdentifier)?.bool(forKey: "SUAutomaticallyUpdate") == initiallyEnabled)
        updater.automaticallyChecksForUpdates = true
        #expect(checkbox.isEnabled)
        #expect(updater.automaticallyDownloadsUpdates == initiallyEnabled)
        #expect(checkbox.state == (initiallyEnabled ? .on : .off))
    }

    @Test @MainActor
    func installableUpdateCannotEnableAutomaticInstallationWhenHostDisallowsIt() throws {
        let hostBundle = try makeUpdaterHostBundle(automaticallyDownloadsUpdates: true, allowsAutomaticUpdates: false)
        let bundleIdentifier = try #require(hostBundle.bundleIdentifier)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            try? FileManager.default.removeItem(at: hostBundle.bundleURL)
        }
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: hostBundle, coordinator: coordinator)
        let updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: .main, userDriver: driver, delegate: nil)
        driver.updater = updater
        defer { driver.dismissUpdateInstallation() }
        driver.showUpdateFound(with: try makeUpdateAppcastItem(informational: false), state: try makeUserUpdateState()) { _ in }
        let contentView = try #require(visiblePasteraUpdateWindow().contentView)
        let checkbox = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.automaticInstall") as? NSButton
        )

        #expect(!checkbox.isEnabled)
        #expect(checkbox.state == .off)
        checkbox.performClick(nil)
        #expect(!updater.automaticallyDownloadsUpdates)
        #expect(UserDefaults(suiteName: bundleIdentifier)?.object(forKey: "SUAutomaticallyUpdate") == nil)
    }

    @Test(arguments: [SPUUserUpdateStage.notDownloaded, .downloaded, .installing]) @MainActor
    func installableUpdateRepliesInstallOnceFromUpdateButtonAndRestoresFocus(stage: SPUUserUpdateStage) throws {
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        defer { driver.dismissUpdateInstallation() }
        let item = try makeUpdateAppcastItem(informational: false)
        let state = try makeUserUpdateState(stage: stage)
        var replies: [SPUUserUpdateChoice] = []

        driver.showUpdateFound(with: item, state: state) { replies.append($0) }
        let window = try visiblePasteraUpdateWindow()
        defer { window.close() }
        let contentView = try #require(window.contentView)
        let updateButton = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.download") as? NSButton
        )
        #expect(updateButton.title == Bundle.main.localizedString(forKey: "Update", value: "Update", table: nil))
        window.orderOut(nil)
        driver.showUpdateInFocus()
        #expect(window.isVisible)

        updateButton.performClick(nil)
        updateButton.performClick(nil)
        window.close()

        #expect(replies == [.install])
        #expect(!window.isVisible)
        #expect(!coordinator.isPresentingManualUpdate)
    }

    @Test(arguments: ["manualUpdate.later", "manualUpdate.skip", "close"]) @MainActor
    func installableUpdateDismissalRepliesExactlyOnce(actionIdentifier: String) throws {
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        defer { driver.dismissUpdateInstallation() }
        var replies: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: try makeUpdateAppcastItem(informational: false), state: try makeUserUpdateState()) {
            replies.append($0)
        }
        let window = try visiblePasteraUpdateWindow()
        defer { window.close() }
        if actionIdentifier == "close" {
            window.performClose(nil)
        } else {
            let contentView = try #require(window.contentView)
            let button = try #require(contentView.descendant(withAccessibilityIdentifier: actionIdentifier) as? NSButton)
            button.performClick(nil)
            button.performClick(nil)
        }
        window.close()

        #expect(replies == [actionIdentifier == "manualUpdate.skip" ? .skip : .dismiss])
        #expect(!coordinator.isPresentingManualUpdate)
    }

    @Test(arguments: [SPUUserUpdateStage.notDownloaded, .downloaded, .installing]) @MainActor
    func installableUpdateLaterActionDescribesTheActualSparkleStage(stage: SPUUserUpdateStage) throws {
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        defer { driver.dismissUpdateInstallation() }
        var replies: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(
            with: try makeUpdateAppcastItem(informational: false),
            state: try makeUserUpdateState(stage: stage)
        ) { replies.append($0) }
        let window = try visiblePasteraUpdateWindow()
        defer { window.close() }
        let contentView = try #require(window.contentView)
        let laterButton = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.later") as? NSButton
        )
        let statusLabel = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.status") as? NSTextField
        )
        let expectedTitle = stage == .installing ? "Install on Quit" : "Remind Me Later"
        let expectedStatus: String
        switch stage {
        case .notDownloaded:
            expectedStatus = "Download and install this update, then restart Pastera."
        case .downloaded:
            expectedStatus = "The update has been downloaded and is ready to install."
        case .installing:
            expectedStatus = "The update is ready. Update now to restart Pastera, or install it when Pastera quits."
        @unknown default:
            Issue.record("Unexpected Sparkle update stage")
            return
        }
        #expect(laterButton.title == Bundle.main.localizedString(
            forKey: expectedTitle, value: expectedTitle, table: nil
        ))
        #expect(statusLabel.stringValue == Bundle.main.localizedString(
            forKey: expectedStatus, value: expectedStatus, table: nil
        ))

        laterButton.performClick(nil)
        window.close()

        #expect(replies == [.dismiss])
    }

    @Test @MainActor
    func repeatedInstallableUpdatePresentationKeepsTheOriginalReplyAndWindow() throws {
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        defer { driver.dismissUpdateInstallation() }
        let item = try makeUpdateAppcastItem(informational: false)
        let state = try makeUserUpdateState()
        var firstReplies: [SPUUserUpdateChoice] = []
        var repeatedReplies: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: item, state: state) { firstReplies.append($0) }
        let originalWindow = try visiblePasteraUpdateWindow()
        defer { originalWindow.close() }

        driver.showUpdateFound(with: item, state: state) { repeatedReplies.append($0) }

        #expect(firstReplies.isEmpty)
        #expect(repeatedReplies == [.dismiss])
        #expect(try visiblePasteraUpdateWindow() === originalWindow)
        let contentView = try #require(originalWindow.contentView)
        let button = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.download") as? NSButton
        )
        button.performClick(nil)
        #expect(firstReplies == [.install])
        #expect(repeatedReplies == [.dismiss])
    }

    @Test @MainActor
    func installableUpdateReplyCanReenterPresentationWithoutLosingTheNewWindow() throws {
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        defer { driver.dismissUpdateInstallation() }
        let item = try makeUpdateAppcastItem(informational: false)
        let state = try makeUserUpdateState()
        var firstReplies: [SPUUserUpdateChoice] = []
        var nextReplies: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: item, state: state) { choice in
            firstReplies.append(choice)
            driver.showUpdateFound(with: item, state: state) { nextReplies.append($0) }
        }
        let originalWindow = try visiblePasteraUpdateWindow()
        defer { originalWindow.close() }
        let originalContentView = try #require(originalWindow.contentView)
        let button = try #require(
            originalContentView.descendant(withAccessibilityIdentifier: "manualUpdate.download") as? NSButton
        )

        button.performClick(nil)

        #expect(firstReplies == [.install])
        #expect(nextReplies.isEmpty)
        let nextWindow = try visiblePasteraUpdateWindow()
        #expect(nextWindow !== originalWindow)
        nextWindow.performClose(nil)
        #expect(nextReplies == [.dismiss])
        #expect(firstReplies == [.install])
    }

    @Test @MainActor
    func informationalDirectDownloadKeepsBrowserFallbackAndNeverRepliesInstall() throws {
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        defer { driver.dismissUpdateInstallation() }
        let item = try makeUpdateAppcastItem(informational: true)
        var replies: [SPUUserUpdateChoice] = []

        driver.showUpdateFound(with: item, state: try makeUserUpdateState()) { replies.append($0) }

        #expect(item.isInformationOnlyUpdate)
        #expect(!coordinator.isPresentingManualUpdate)
        #expect(!replies.contains(.install))
    }

    @Test @MainActor
    func sparkleDismissalClosesTheCustomPromptWithoutReplyingAgain() throws {
        let coordinator = PasteraManualUpdateCoordinator()
        let driver = PasteraInformationalUpdateUserDriver(hostBundle: .main, coordinator: coordinator)
        var replies: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: try makeUpdateAppcastItem(informational: false), state: try makeUserUpdateState()) {
            replies.append($0)
        }
        let window = try visiblePasteraUpdateWindow()
        let contentView = try #require(window.contentView)
        let updateButton = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.download") as? NSButton
        )

        driver.dismissUpdateInstallation()
        driver.dismissUpdateInstallation()
        updateButton.performClick(nil)
        window.close()

        #expect(!window.isVisible)
        #expect(!coordinator.isPresentingManualUpdate)
        #expect(replies.isEmpty)
    }

    @Test
    func installableUpdateActionHasExactEnglishAndSimplifiedChineseLabels() throws {
        let catalogURL = projectRoot().appendingPathComponent("pastera/Resources/Localizable.xcstrings")
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let update = try #require(strings["Update"] as? [String: Any])
        let localizations = try #require(update["localizations"] as? [String: [String: [String: String]]])
        #expect(localizations["en"]?["stringUnit"]?["value"] == "Update")
        #expect(localizations["zh-Hans"]?["stringUnit"]?["value"] == "更新")
    }

    @MainActor
    private func visiblePasteraUpdateWindow() throws -> NSWindow {
        try #require(NSApp.windows.first {
            $0.isVisible && $0.contentView?.descendant(withAccessibilityIdentifier: "manualUpdate.download") != nil
        })
    }

    private func makeUpdateAppcastItem(informational: Bool, releasePageURL: URL? = nil) throws -> SUAppcastItem {
        let downloadURL = "https://github.com/pastera-app/Pastera/releases/download/v99.0.0-beta/Pastera-99.0.0-beta-macOS.dmg"
        var properties: [String: Any] = [
            "title": "Pastera 99.0.0",
            "sparkle:version": "9900",
            "sparkle:shortVersionString": "99.0.0",
            "link": releasePageURL?.absoluteString ?? downloadURL
        ]
        if !informational {
            properties["enclosure"] = [
                "url": downloadURL,
                "length": "1024",
                "type": "application/x-apple-diskimage"
            ]
        }
        return try #require(SUAppcastItem(dictionary: properties))
    }

    private func makeUserUpdateState(
        stage: SPUUserUpdateStage = .notDownloaded,
        userInitiated: Bool = true
    ) throws -> SPUUserUpdateState {
        // Exercise Sparkle's public secure-coding initializer without private selectors.
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(stage.rawValue, forKey: "SPUUserUpdateStateStage")
        archiver.encode(userInitiated, forKey: "SPUUserUpdateStateUserInitiated")
        archiver.finishEncoding()
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        defer { unarchiver.finishDecoding() }
        return try #require(SPUUserUpdateState(coder: unarchiver))
    }

    private func makeUpdaterHostBundle(
        automaticallyDownloadsUpdates: Bool,
        allowsAutomaticUpdates: Bool? = nil
    ) throws -> Bundle {
        let identifier = "app.pastera.update-tests.\(UUID().uuidString)"
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(identifier).app")
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": "Pastera Update Tests",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "SUEnableAutomaticChecks": true,
            "SUAutomaticallyUpdate": automaticallyDownloadsUpdates
        ]
        if let allowsAutomaticUpdates {
            info["SUAllowsAutomaticUpdates"] = allowsAutomaticUpdates
        }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contentsURL.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: bundleURL))
    }

    @Test @MainActor
    func informationalUpdateWindowOffersDirectDownloadWithoutAutomaticInstallToggle() throws {
        let releasePageURL = try #require(
            URL(string: "https://github.com/pastera-app/Pastera/releases/tag/v3.0.2-beta")
        )
        var actions: [PasteraManualUpdateAction] = []
        let controller = PasteraManualUpdateWindowController(
            update: PasteraManualUpdateDescriptor(
                displayVersion: "3.0.2",
                currentVersion: "3.0.1",
                releasePageURL: releasePageURL
            ),
            icon: NSImage(size: NSSize(width: 64, height: 64)),
            onAction: { actions.append($0) }
        )
        let contentView = try #require(controller.window?.contentView)
        let downloadButton = try #require(
            contentView.descendant(withAccessibilityIdentifier: "manualUpdate.download") as? NSButton
        )
        let closeButton = try #require(controller.window?.standardWindowButton(.closeButton))

        #expect(contentView.descendant(withAccessibilityIdentifier: "manualUpdate.later") is NSButton)
        #expect(contentView.descendant(withAccessibilityIdentifier: "manualUpdate.skip") is NSButton)
        #expect(contentView.descendant(withAccessibilityIdentifier: "manualUpdate.automaticInstall") == nil)

        downloadButton.performClick(nil)
        #expect(actions == [.download])

        controller.showResolvingDownload()
        #expect(!closeButton.isEnabled)
        controller.showDownloadFailure("Test failure")
        #expect(closeButton.isEnabled)
    }

    @Test
    func manualUpdateCheckUsesSparkleWithoutGitHubDownloadFallback() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent(
                    "pastera/Sources/Preferences/Panels/CPYSoftwareUpdatePreferenceViewController.swift"
                ),
            encoding: .utf8
        )

        #expect(source.contains("updater?.checkForUpdates()"))
        #expect(!source.contains("PasteraGitHubReleaseUpdateChecker"))
        #expect(!source.contains("api.github.com/repos/pastera-app/Pastera/releases"))
        #expect(!source.contains("Open the GitHub release page to download this version."))
    }

    private func infoPlistValue(forKey key: String) throws -> String {
        let plistURL = projectRoot().appendingPathComponent("pastera/Supporting Files/Info.plist")
        let plist = try #require(NSDictionary(contentsOf: plistURL) as? [String: Any])
        return try #require(plist[key] as? String)
    }

    private func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("pastera.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private extension NSView {
    func descendant(withAccessibilityIdentifier identifier: String) -> NSView? {
        if accessibilityIdentifier() == identifier {
            return self
        }
        return subviews.lazy.compactMap { $0.descendant(withAccessibilityIdentifier: identifier) }.first
    }
}

private final class PasteraManualUpdateURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class PasteraManualUpdateLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
// swiftlint:disable:this file_length
