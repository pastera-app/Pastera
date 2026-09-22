//
//  ReleasePackagingConfigurationTests.swift
//
//  Pastera
//
//  Created by Codex on 2026/06/15.
//

import Foundation
import Testing

struct ReleasePackagingConfigurationTests {
    @Test
    func productionPackagesDoNotReferenceClipyOrganization() throws {
        let project = try projectText("pastera.xcodeproj/project.pbxproj")
        let resolved = try projectText(
            "pastera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )

        #expect(!project.localizedCaseInsensitiveContains("github.com/Clipy/"))
        #expect(!resolved.localizedCaseInsensitiveContains("github.com/Clipy/"))
    }

    @Test
    func productionProjectDoesNotContainRealmRuntime() throws {
        let project = try projectText("pastera.xcodeproj/project.pbxproj")
        let resolved = try projectText(
            "pastera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )

        #expect(!project.localizedCaseInsensitiveContains("realm-swift"))
        #expect(!project.contains("RealmSwift"))
        #expect(!resolved.localizedCaseInsensitiveContains("realm-swift"))
        #expect(!resolved.localizedCaseInsensitiveContains("realm-core"))
    }

    @Test
    func adHocSigningConfigurationDoesNotOverrideRelease() throws {
        let adHoc = try projectText("Configurations/CodeSigning-AdHoc.xcconfig")

        #expect(!adHoc.contains("CODE_SIGN_IDENTITY[config=Release] = -"))
        #expect(!adHoc.contains("PROVISIONING_PROFILE_SPECIFIER[config=Release] ="))
        #expect(!adHoc.contains("\nDEVELOPMENT_TEAM =\n"))
    }

    @Test
    func releaseSigningConfigurationEnablesDistributionRequirements() throws {
        let signing = try projectText("Configurations/CodeSigning.xcconfig")

        #expect(signing.contains("CODE_SIGN_IDENTITY[config=Release] = Developer ID Application"))
        #expect(signing.contains("ENABLE_HARDENED_RUNTIME[config=Release] = YES"))
        #expect(signing.contains("OTHER_CODE_SIGN_FLAGS[config=Release] = --timestamp"))
    }

    @Test
    func releaseProjectEmbedsExactlyThreeSignedAgentHelpersAndSkill() throws {
        let project = try projectText("pastera.xcodeproj/project.pbxproj")
        let localInstall = try projectText("script/install_local.sh")
        let releaseDMG = try projectText("script/package_release_dmg.sh")
        let helperNames = ["PasteraClaudeMCP", "PasteraCodexMCP", "pastera"]

        let appTargetStart = try #require(project.range(
            of: "FAC43DC51B35D8B100C06102 /* pastera */ = {\n\t\t\tisa = PBXNativeTarget;"
        ))
        let appTargetEnd = try #require(project.range(
            of: "\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t};",
            range: appTargetStart.lowerBound..<project.endIndex
        ))
        let appTarget = String(project[appTargetStart.lowerBound..<appTargetEnd.upperBound])

        #expect(project.contains("/* Embed Agent Helpers */ = {"))
        #expect(project.contains("dstPath = Contents/Helpers;"))
        #expect(project.contains("dstSubfolderSpec = 1;"))
        for name in helperNames {
            #expect(project.components(separatedBy: "/* \(name) in Embed Agent Helpers */").count - 1 == 2)
            #expect(project.contains(
                "/* \(name) in Embed Agent Helpers */ = {isa = PBXBuildFile; " +
                    "fileRef ="
            ))
        }
        #expect(project.components(
            separatedBy: "settings = {ATTRIBUTES = (CodeSignOnCopy, ); };"
        ).count - 1 == 3)
        #expect(appTarget.contains("/* PasteraCodexMCP */"))
        #expect(appTarget.contains("/* PasteraClaudeMCP */"))
        #expect(appTarget.contains("/* PasteraCLI */"))
        #expect(project.components(separatedBy: "/* pastera-vault in Resources */").count - 1 == 2)
        #expect(project.components(separatedBy: "path = integrations/pastera-vault;").count - 1 == 1)
        #expect(project.components(
            separatedBy: "OTHER_CODE_SIGN_FLAGS = \"--identifier $(PRODUCT_BUNDLE_IDENTIFIER)\";"
        ).count - 1 == 6)
        #expect(project.components(
            separatedBy: "PRODUCT_BUNDLE_IDENTIFIER = \"com.pastera-app.PasteraCodexMCP\";"
        ).count - 1 == 2)
        #expect(project.components(
            separatedBy: "PRODUCT_BUNDLE_IDENTIFIER = \"com.pastera-app.PasteraClaudeMCP\";"
        ).count - 1 == 2)
        #expect(project.components(
            separatedBy: "PRODUCT_BUNDLE_IDENTIFIER = \"com.pastera-app.pastera\";"
        ).count - 1 == 2)
        #expect(localInstall.contains("--identifier com.pastera-app.PasteraCodexMCP"))
        #expect(localInstall.contains("--identifier com.pastera-app.PasteraClaudeMCP"))
        #expect(localInstall.contains("--identifier com.pastera-app.pastera"))
        #expect(localInstall.contains("codesign --verify --deep --strict"))
        #expect(releaseDMG.contains(
            "OTHER_CODE_SIGN_FLAGS=\"--timestamp --identifier \\$(PRODUCT_BUNDLE_IDENTIFIER)\""
        ))
        #expect(!releaseDMG.contains("\n        OTHER_CODE_SIGN_FLAGS=--timestamp\n"))
        #expect(releaseDMG.contains("--identifier com.pastera-app.PasteraCodexMCP"))
        #expect(releaseDMG.contains("--identifier com.pastera-app.PasteraClaudeMCP"))
        #expect(releaseDMG.contains("--identifier com.pastera-app.pastera"))
        #expect(releaseDMG.contains("sign_ad_hoc_app"))
    }

    @Test
    func releaseUsesAnAppScopedDataProtectionKeychainGroup() throws {
        let signing = try projectText("Configurations/CodeSigning.xcconfig")
        let entitlements = try projectText("pastera/Pastera.entitlements")

        #expect(signing.contains(
            "CODE_SIGN_ENTITLEMENTS[config=Release] = pastera/Pastera.entitlements"
        ))
        #expect(!signing.contains("CODE_SIGN_ENTITLEMENTS[config=Debug]"))
        #expect(entitlements.contains("<key>keychain-access-groups</key>"))
        #expect(entitlements.contains("<string>BBCHAJ584H.com.pastera-app.Pastera</string>"))
    }

    @Test
    func releasePackagingScriptCreatesSignedNotarizedDmg() throws {
        let script = try projectText("script/package_release_dmg.sh")

        #expect(script.contains("hdiutil create"))
        #expect(script.contains("notarytool submit"))
        #expect(script.contains("stapler staple"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("spctl -a -vv"))
        #expect(script.contains("ln -s /Applications"))
        #expect(script.contains("-target \"${APP_TARGET}\""))
        #expect(script.contains("CFBundleShortVersionString"))
        #expect(script.contains("CFBundleVersion"))
        #expect(script.contains("EXPECTED_MARKETING_VERSION=\"${VERSION%%-*}\""))
        #expect(script.contains("BUNDLE_SHORT_VERSION"))
        #expect(script.contains("BUNDLE_BUILD_VERSION"))
    }

    @Test
    func releasePackagingScriptIncludesInstallGuide() throws {
        let script = try projectText("script/package_release_dmg.sh")

        #expect(script.contains("prepare_install_guide_assets"))
        #expect(script.contains("configure_dmg_window"))
        #expect(script.contains("render_dmg_install_guide.swift"))
        #expect(script.contains(".background"))
        #expect(script.contains("pastera-dmg-guide.png"))
        #expect(script.contains("bounds of container window of volumeRoot to {120, 120, 980, 660}"))
        #expect(script.contains("icon size of icon view options of container window of volumeRoot to 96"))
        #expect(script.contains("position of item \"Pastera.app\" of volumeRoot to {210, 285}"))
        #expect(script.contains("position of item \"Applications\" of volumeRoot to {650, 285}"))
        #expect(script.contains("position of item \"Open Privacy & Security.webloc\" of volumeRoot to {430, 430}"))
        #expect(script.contains("Pastera 安装说明.txt"))
        #expect(script.contains("Open Privacy & Security.webloc"))
        #expect(script.contains("Open Anyway"))
        #expect(script.contains("Control-click"))
        #expect(script.contains("Privacy & Security"))
        #expect(script.contains("Accessibility"))
    }

    @Test
    func releasePackagingScriptCreatesSignedNotarizedPkg() throws {
        let script = try projectText("script/package_release_pkg.sh")

        #expect(script.contains("DEVELOPER_ID_APPLICATION"))
        #expect(script.contains("DEVELOPER_ID_INSTALLER"))
        #expect(script.contains("NOTARY_KEYCHAIN_PROFILE"))
        #expect(script.contains("pkgbuild"))
        #expect(script.contains("productbuild"))
        #expect(script.contains("productsign"))
        #expect(script.contains("notarytool submit"))
        #expect(script.contains("stapler validate"))
        #expect(script.contains("spctl -a -vv -t install"))
        #expect(script.contains("--skip-notarization"))
        #expect(script.contains("postinstall"))
        #expect(script.contains("installer-resources"))
        #expect(script.contains("Pastera-${VERSION}-macOS.pkg"))
        #expect(script.contains("--pastera-open-setup-guide"))
    }

    @Test
    func installerQuitsRunningPasteraBeforeReplacingApp() throws {
        let packageScript = try projectText("script/package_release_pkg.sh")
        let preinstall = try projectText("script/installer-resources/pkg/scripts/preinstall")
        let processHelper = try projectText("script/pastera_process.sh")
        let localInstall = try projectText("script/install_local.sh")

        #expect(packageScript.contains("${RESOURCES_DIR}/scripts/preinstall"))
        #expect(packageScript.contains("pastera_process.sh"))
        #expect(preinstall.contains("quit_running_pastera"))
        #expect(processHelper.contains("osascript"))
        #expect(processHelper.contains("pkill -TERM -x"))
        #expect(processHelper.contains("pkill -KILL -x"))
        #expect(processHelper.contains("launchctl asuser"))
        #expect(localInstall.contains("script/pastera_process.sh"))
        #expect(localInstall.contains("quit_running_pastera"))
    }

    @Test
    func releasePackagingScriptSupportsLocalAdHocDryRun() throws {
        let script = try projectText("script/package_release_dmg.sh")

        #expect(script.contains("DEVELOPER_ID_APPLICATION is required unless --skip-notarization is passed."))
        #expect(script.contains("CODE_SIGNING_ALLOWED=NO"))
        #expect(script.contains("sign_ad_hoc_app"))
    }

    @Test
    func releasePackageEntryPointRunsDmgPackagingAndOptionalAppcastUpdate() throws {
        let script = try projectText("script/package_release.sh")

        #expect(script.contains("script/package_release_dmg.sh"))
        #expect(script.contains("script/update_appcast_for_dmg.sh"))
        #expect(script.contains("--update-appcast"))
        #expect(script.contains("--skip-notarization"))
        #expect(script.contains("--update-appcast requires a signed and notarized DMG"))
        #expect(script.contains("do not combine it with --skip-notarization"))
    }

    @Test
    func appcastUpdateScriptGeneratesAndVerifiesArtifactDrivenFeed() throws {
        let script = try projectText("script/update_appcast_for_dmg.sh")
        let verifier = try projectText("script/verify_sparkle_ed_signature.swift")

        #expect(script.contains("generate_appcast"))
        #expect(script.contains("--ed-key-file -"))
        #expect(script.contains("--download-url-prefix"))
        #expect(script.contains("--link"))
        #expect(script.contains("--versions"))
        #expect(script.contains("--maximum-versions"))
        #expect(script.contains("hdiutil attach"))
        #expect(script.contains("SUPublicEDKey"))
        #expect(script.contains("verify_sparkle_ed_signature.swift"))
        #expect(script.contains("sparkle:edSignature"))
        #expect(script.contains("application/x-apple-diskimage"))
        #expect(!script.contains("sign_update"))
        #expect(!script.contains("perl -0pi"))
        #expect(verifier.contains("Curve25519.Signing.PublicKey"))
        #expect(verifier.contains("isValidSignature"))
    }

    @Test
    func releaseEntrypointsKeepLabelSeparateFromArtifactVersions() throws {
        let package = try projectText("script/package_release.sh")
        let workflow = try projectText(".github/workflows/release-dmg.yml")

        #expect(!package.contains("--version \"${VERSION}\" \\\n        --tag \"${TAG}\""))
        #expect(workflow.contains("SPARKLE_PRIVATE_KEY is required"))
        #expect(!workflow.contains("--version \"${{ inputs.version }}\" \\\n            --tag \"${{ inputs.tag }}\""))
    }

    @Test
    func homebrewCaskInstallsReleaseDmg() throws {
        let cask = try projectText("Casks/pastera.rb")

        #expect(cask.contains("cask \"pastera\" do"))
        #expect(cask.contains("version \"3.0.5-beta\""))
        #expect(cask.contains("sha256 \"5ffae9018d629c7f345154dc23fb5c0fcd8b9da2925f61c93e5de93636ccbe9f\""))
        #expect(cask.contains("https://github.com/pastera-app/Pastera/releases/download/v#{version}/Pastera-#{version}-macOS.dmg"))
        #expect(cask.contains("app \"Pastera.app\""))
        #expect(cask.contains("uninstall quit: \"com.pastera-app.Pastera\""))
        #expect(cask.contains("zap trash:"))
        #expect(cask.contains("Automatic Paste"))
        #expect(!cask.contains("pkg \""))
        #expect(!cask.contains(".pkg"))
    }

    @Test
    func homebrewCaskUpdateScriptRefreshesDmgMetadata() throws {
        let script = try projectText("script/update_homebrew_cask.sh")

        #expect(script.contains("Casks/pastera.rb"))
        #expect(script.contains("shasum -a 256"))
        #expect(script.contains("Pastera-${VERSION}-macOS.dmg"))
        #expect(script.contains("https://github.com/pastera-app/Pastera/releases/download/${TAG}/Pastera-${VERSION}-macOS.dmg"))
        #expect(script.contains("PASTERA_CASK_VERSION=\"${VERSION}\""))
        #expect(script.contains("PASTERA_CASK_SHA256=\"${SHA256}\""))
        #expect(script.contains("s/version \"[^\"]+\"/version \"$version\"/"))
        #expect(script.contains("s/sha256 \"[^\"]+\"/sha256 \"$sha256\"/"))
        #expect(script.contains("--check-url"))
    }

    @Test
    func releaseWorkflowPublishesDmgAsset() throws {
        let workflow = try projectText(".github/workflows/release-dmg.yml")

        #expect(workflow.contains("script/package_release_dmg.sh"))
        #expect(workflow.contains("script/update_appcast_for_dmg.sh"))
        #expect(workflow.contains("gh release upload"))
        #expect(workflow.contains("Pastera-${{ inputs.version }}-macOS.dmg"))
        #expect(workflow.contains("Build signed notarized DMG"))
        #expect(workflow.contains("Publish appcast to feed branch"))
        #expect(workflow.contains("SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}"))
        #expect(!workflow.contains("- name: Update appcast for DMG"))

        let buildRange = try #require(workflow.range(of: "Build signed notarized DMG"))
        let uploadRange = try #require(workflow.range(of: "gh release upload"))
        let appcastRange = try #require(workflow.range(of: "script/update_appcast_for_dmg.sh"))
        #expect(buildRange.lowerBound < uploadRange.lowerBound)
        #expect(uploadRange.lowerBound < appcastRange.lowerBound)
    }

    @Test
    func releaseWorkflowPublishesPkgAssetWithoutRemovingDmgWorkflow() throws {
        let workflow = try projectText(".github/workflows/release-pkg.yml")

        #expect(workflow.contains("Build signed notarized PKG"))
        #expect(workflow.contains("script/package_release_pkg.sh"))
        #expect(workflow.contains("DEVELOPER_ID_APPLICATION"))
        #expect(workflow.contains("DEVELOPER_ID_INSTALLER"))
        #expect(workflow.contains("NOTARY_KEYCHAIN_PROFILE"))
        #expect(workflow.contains("gh release upload"))
        #expect(workflow.contains("Pastera-${{ inputs.version }}-macOS.pkg"))
        #expect(!workflow.contains("script/update_appcast_for_dmg.sh"))

        _ = try projectText(".github/workflows/release-dmg.yml")
    }

    private func projectText(_ path: String) throws -> String {
        let url = projectRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
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
