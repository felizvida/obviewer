import Foundation
import XCTest
@testable import ObviewerCore
@testable import ObviewerMacApp

final class LaunchReadingInputTests: XCTestCase {
    func testParsesMarkdownSwitchWithRelativePath() throws {
        let currentDirectoryURL = URL(fileURLWithPath: "/tmp/obviewer-cwd", isDirectory: true)

        let request = try XCTUnwrap(
            LaunchReadingInputParser.parse(
                ["--markdown", "Notes/Readme.md"],
                currentDirectoryURL: currentDirectoryURL
            )
        )

        XCTAssertEqual(request.preferredProfile, .markdown)
        XCTAssertEqual(request.url.path, "/tmp/obviewer-cwd/Notes/Readme.md")
    }

    func testParsesProfileAndOpenFlags() throws {
        let request = try XCTUnwrap(
            LaunchReadingInputParser.parse(["--profile", "obsidian", "--open", "/tmp/Vault"])
        )

        XCTAssertEqual(request.preferredProfile, .obsidian)
        XCTAssertEqual(request.url.path, "/tmp/Vault")
    }

    func testParsesProfileEqualsSyntaxAndIgnoresMacProcessSerialArgument() throws {
        let request = try XCTUnwrap(
            LaunchReadingInputParser.parse(["-psn_0_12345", "--profile=markdown", "/tmp/Note.md"])
        )

        XCTAssertEqual(request.preferredProfile, .markdown)
        XCTAssertEqual(request.url.path, "/tmp/Note.md")
    }

    func testReturnsNilWhenNoInputPathIsProvided() {
        XCTAssertNil(LaunchReadingInputParser.parse(["--markdown", "-psn_0_12345"]))
    }
}
