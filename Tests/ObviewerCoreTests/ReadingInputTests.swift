import Foundation
import XCTest
@testable import ObviewerCore

final class ReadingInputTests: XCTestCase {
    func testMarkdownFileDefaultsToFocusedMarkdownProfileInput() throws {
        let sandbox = try TemporaryReadingInputDirectory()
        defer { sandbox.cleanup() }
        let noteURL = try sandbox.write("Draft.md", contents: "# Draft")

        let input = DefaultReadingInputAdapter().makeInputSource(for: noteURL)

        XCTAssertEqual(input.url, noteURL.standardizedFileURL)
        XCTAssertEqual(input.kind, .markdownFile)
        XCTAssertEqual(input.profile, .markdown)
        XCTAssertEqual(input.rootURL, sandbox.rootURL.standardizedFileURL)
        XCTAssertNil(input.watchURL)
        XCTAssertEqual(input.focusRelativePath, "Draft.md")
    }

    func testObsidianFolderDefaultsToObsidianProfile() throws {
        let sandbox = try TemporaryReadingInputDirectory()
        defer { sandbox.cleanup() }
        try sandbox.createDirectory(".obsidian")

        let input = DefaultReadingInputAdapter().makeInputSource(for: sandbox.rootURL)

        XCTAssertEqual(input.kind, .folder)
        XCTAssertEqual(input.profile, .obsidian)
        XCTAssertEqual(input.rootURL, sandbox.rootURL.standardizedFileURL)
        XCTAssertEqual(input.watchURL, sandbox.rootURL.standardizedFileURL)
        XCTAssertNil(input.focusRelativePath)
    }

    func testPlainFolderDefaultsToMarkdownProfile() throws {
        let sandbox = try TemporaryReadingInputDirectory()
        defer { sandbox.cleanup() }

        let input = DefaultReadingInputAdapter().makeInputSource(for: sandbox.rootURL)

        XCTAssertEqual(input.kind, .folder)
        XCTAssertEqual(input.profile, .markdown)
    }

    func testPreferredProfileOverridesDetectedFolderProfile() throws {
        let sandbox = try TemporaryReadingInputDirectory()
        defer { sandbox.cleanup() }
        try sandbox.createDirectory(".obsidian")

        let input = DefaultReadingInputAdapter().makeInputSource(
            for: sandbox.rootURL,
            preferredProfile: .markdown
        )

        XCTAssertEqual(input.kind, .folder)
        XCTAssertEqual(input.profile, .markdown)
    }
}

private struct TemporaryReadingInputDirectory {
    let rootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func write(_ relativePath: String, contents: String) throws -> URL {
        let url = rootURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    func createDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: rootURL.appending(path: relativePath, directoryHint: .isDirectory),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
