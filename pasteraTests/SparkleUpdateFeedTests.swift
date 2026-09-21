//
//  SparkleUpdateFeedTests.swift
//
//  Clipy
//

import AppKit
import Foundation
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

        #expect(shortVersion == "3.0.3")
        #expect(buildVersion == "303")
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
        #expect(!updaterSource.contains("override func dismissUpdateInstallation"))

        let startDownloadRange = try #require(updaterSource.range(of: "func startDownload()"))
        let openInstallerRange = try #require(
            updaterSource.range(of: "func openInstaller", range: startDownloadRange.upperBound..<updaterSource.endIndex)
        )
        let startDownloadSource = updaterSource[startDownloadRange.lowerBound..<openInstallerRange.lowerBound]
        #expect(!startDownloadSource.contains("completeSparkleReply"))
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
