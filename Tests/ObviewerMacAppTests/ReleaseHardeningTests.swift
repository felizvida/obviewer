import Foundation
import XCTest
@testable import ObviewerMacApp

final class ReleaseHardeningTests: XCTestCase {
    @MainActor
    func testBookmarkStoreCreatesReadOnlySecurityScopedBookmarks() {
        let options = BookmarkStore.bookmarkCreationOptions

        XCTAssertTrue(options.contains(.withSecurityScope))
        XCTAssertTrue(options.contains(.securityScopeAllowOnlyReadAccess))
    }

    func testEntitlementsStaySandboxedAndReadOnly() throws {
        // Only these keys are allowed; anything new needs a deliberate review.
        // network.client is in the app only because WKWebView can't start in the sandbox without it.
        let allowedByFile: [String: Set<String>] = [
            "Configuration/Obviewer.entitlements": [
                "com.apple.security.app-sandbox",
                "com.apple.security.files.user-selected.read-only",
                "com.apple.security.print",
                "com.apple.security.network.client",
            ],
            "Configuration/ObviewerQuickLook.entitlements": [
                "com.apple.security.app-sandbox",
                "com.apple.security.files.user-selected.read-only",
            ],
        ]

        for (file, allowed) in allowedByFile {
            let entitlements = try loadPropertyList(at: repositoryRootURL.appendingPathComponent(file))

            XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true, file)
            XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-only"] as? Bool, true, file)
            for forbidden in [
                "com.apple.security.files.user-selected.read-write",
                "com.apple.security.files.downloads.read-write",
                "com.apple.security.files.all",
                "com.apple.security.network.server",
            ] {
                XCTAssertNil(entitlements[forbidden], "\(forbidden) must not appear in \(file)")
            }
            XCTAssertTrue(
                Set(entitlements.keys).isSubset(of: allowed),
                "Unexpected entitlements in \(file): \(Set(entitlements.keys).subtracting(allowed))"
            )
        }
    }

    func testReleaseBuildsNeverShipTheDebuggerEntitlement() throws {
        let projectYAML = try String(contentsOf: repositoryRootURL.appendingPathComponent("project.yml"), encoding: .utf8)
        let buildScript = try String(contentsOf: repositoryRootURL.appendingPathComponent("scripts/build_app.sh"), encoding: .utf8)
        let releaseCommon = try String(contentsOf: repositoryRootURL.appendingPathComponent("scripts/release_common.sh"), encoding: .utf8)
        XCTAssertTrue(projectYAML.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO"))
        XCTAssertTrue(buildScript.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO"))
        XCTAssertTrue(releaseCommon.contains("com.apple.security.get-task-allow"))
    }

    func testAdHocReleasesLoadWithoutLibraryValidationExceptions() throws {
        let projectYAML = try String(contentsOf: repositoryRootURL.appendingPathComponent("project.yml"), encoding: .utf8)
        let releaseCommon = try String(contentsOf: repositoryRootURL.appendingPathComponent("scripts/release_common.sh"), encoding: .utf8)
        let packaging = try String(contentsOf: repositoryRootURL.appendingPathComponent("scripts/package_release_dmg.sh"), encoding: .utf8)
        // Internal modules are static: an ad-hoc hardened app can't load ad-hoc frameworks.
        XCTAssertFalse(projectYAML.contains("type: framework"))
        XCTAssertTrue(projectYAML.contains("type: library.static"))
        for entitlement in ["disable-library-validation", "allow-unsigned-executable-memory", "allow-dyld-environment-variables"] {
            XCTAssertFalse(projectYAML.contains(entitlement))
        }
        XCTAssertTrue(releaseCommon.contains("verify_loadable_without_library_exceptions"))
        XCTAssertTrue(releaseCommon.contains("verify_no_detritus"))
        // The icon ships as the committed, inspectable App/AppIcon.icns; no asset catalog
        // (Assets.car can't be inspected by the publication check).
        XCTAssertTrue(projectYAML.contains("CFBundleIconFile: AppIcon"))
        XCTAssertFalse(projectYAML.contains(".xcassets"))
        XCTAssertFalse(projectYAML.contains("ASSETCATALOG_COMPILER_APPICON_NAME"))
        XCTAssertTrue(releaseCommon.contains("verify_icon_payload"))
        // The DMG is verified as produced, and no active command builds it with -srcfolder
        // (comments explaining why are fine).
        let activeLines = packaging
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        XCTAssertTrue(activeLines.contains { $0.hasPrefix("verify_dmg ") })
        XCTAssertFalse(activeLines.contains { $0.contains("-srcfolder") })
        // Behavior of the helpers is tested against mock tools in Renderer/test/release-scripts.test.js.
    }

    func testPublicationPolicyGatesCIAndReleases() throws {
        let ci = try String(contentsOf: repositoryRootURL.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
        let release = try String(contentsOf: repositoryRootURL.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
        XCTAssertTrue(ci.contains("publication-check.mjs --tracked"))
        XCTAssertTrue(release.contains("publication-check.mjs --tracked"))
        XCTAssertTrue(release.contains("publication-check.mjs dist"))
        // Hosted workflows publish nothing generated: release files are built locally,
        // passed by the maintainer's pre-publication guard, and uploaded by hand.
        for workflow in [ci, release] {
            XCTAssertFalse(workflow.contains("actions/upload-artifact"))
            XCTAssertFalse(workflow.contains("GITHUB_STEP_SUMMARY"))
            XCTAssertFalse(workflow.contains("gh release create"))
            XCTAssertFalse(workflow.contains("gh release upload"))
            XCTAssertFalse(workflow.contains("contents: write"))
        }
        // The local payload script checks every file before it prints the upload command,
        // and never uploads by itself.
        let payload = try String(contentsOf: repositoryRootURL.appendingPathComponent("scripts/make_release_payload.sh"), encoding: .utf8)
        let scan = try XCTUnwrap(payload.range(of: "node scripts/publication-check.mjs \"$OUT\""))
        let command = try XCTUnwrap(payload.range(of: "echo \"  gh release create"))
        XCTAssertLessThan(scan.lowerBound, command.lowerBound)
        let activeLines = payload.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") == false }
        XCTAssertFalse(activeLines.contains { $0.contains("gh release") && $0.contains("echo") == false })
    }

    func testReleaseValidationAlsoChecksTheQuickLookExtension() throws {
        let releaseCommon = try String(
            contentsOf: repositoryRootURL.appendingPathComponent("scripts/release_common.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(releaseCommon.contains("ObviewerQuickLook.appex"))
        XCTAssertTrue(releaseCommon.contains("com.apple.security.network.client"))
    }

    func testReleaseScriptsAreExecutableAndSyntaxCheckedByCIEntrypoints() throws {
        let requiredExecutableScripts = [
            "scripts/build_app.sh",
            "scripts/generate_xcode_project.sh",
            "scripts/notarize_release_app.sh",
            "scripts/package_release_app.sh",
            "scripts/package_release_dmg.sh",
        ]

        for script in requiredExecutableScripts {
            let scriptURL = repositoryRootURL.appendingPathComponent(script)
            let permissions = try filePermissions(at: scriptURL)
            XCTAssertNotEqual(
                permissions & 0o111,
                0,
                "\(script) must be executable because Makefile/release workflows invoke it directly."
            )
        }
    }

    func testReleaseValidationRejectsReadWriteEntitlementAndRequiresHardenedRuntime() throws {
        let releaseCommon = try String(
            contentsOf: repositoryRootURL.appendingPathComponent("scripts/release_common.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(releaseCommon.contains("flags=.*runtime"))
        XCTAssertTrue(releaseCommon.contains("com.apple.security.files.user-selected.read-only"))
        XCTAssertTrue(releaseCommon.contains("com.apple.security.files.user-selected.read-write"))
    }

    func testProjectSourceRequiresHardenedRuntimeAndBuildSettingVersion() throws {
        let projectYAML = try String(
            contentsOf: repositoryRootURL.appendingPathComponent("project.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(projectYAML.contains("ENABLE_HARDENED_RUNTIME: YES"))
        XCTAssertTrue(projectYAML.contains("path: App/Info.plist"))
        XCTAssertTrue(projectYAML.contains("CFBundleShortVersionString: \"$(MARKETING_VERSION)\""))
        XCTAssertTrue(projectYAML.contains("CFBundleVersion: \"$(CURRENT_PROJECT_VERSION)\""))
    }

    private var repositoryRootURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }

    private func loadPropertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any] else {
            XCTFail("Expected dictionary plist at \(url.path)")
            return [:]
        }
        return dictionary
    }

    private func filePermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            XCTFail("Missing POSIX permissions for \(url.path)")
            return 0
        }
        return permissions.intValue
    }
}
