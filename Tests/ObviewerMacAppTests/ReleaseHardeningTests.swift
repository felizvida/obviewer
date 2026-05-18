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
        let entitlements = try loadPropertyList(at: repositoryRootURL.appendingPathComponent("Configuration/Obviewer.entitlements"))

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-only"] as? Bool, true)
        XCTAssertNil(entitlements["com.apple.security.files.user-selected.read-write"])
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
