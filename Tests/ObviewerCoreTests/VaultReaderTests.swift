import Foundation
import XCTest
@testable import ObviewerCore

final class VaultReaderTests: XCTestCase {
    func testLoadVaultIndexesNotesAndAttachmentsFromDisk() throws {
        let sandbox = try TemporaryVault()
        defer { sandbox.cleanup() }

        try sandbox.write(
            "Journal/Today.md",
            contents: """
            # Today

            See [[Projects/Plan]] and #research.

            ![[cover.png]]
            """
        )
        try sandbox.write(
            "Projects/Plan.md",
            contents: """
            # Plan

            [Manual](manual.pdf)
            """
        )
        try sandbox.writeData("Journal/cover.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        try sandbox.writeData("manual.pdf", data: Data([0x25, 0x50, 0x44, 0x46]))
        try sandbox.write("notes.txt", contents: "plain attachment")

        let snapshot = try VaultReader().loadVault(at: sandbox.rootURL)

        XCTAssertEqual(snapshot.notes.count, 2)
        XCTAssertEqual(snapshot.resolveNoteID(for: "Projects/Plan"), "Projects/Plan.md")
        XCTAssertEqual(snapshot.attachment(for: "cover.png", from: "Journal/Today.md")?.kind, .image)
        XCTAssertEqual(snapshot.attachment(for: "manual.pdf")?.kind, .pdf)
        XCTAssertEqual(snapshot.attachment(for: "notes.txt")?.kind, .other)
    }

    func testLoadVaultReportsProgress() throws {
        let sandbox = try TemporaryVault()
        defer { sandbox.cleanup() }

        try sandbox.write("One.md", contents: "# One")
        try sandbox.write("Two.md", contents: "# Two")
        try sandbox.writeData("cover.png", data: Data([0x89, 0x50, 0x4E, 0x47]))

        var events = [VaultLoadingProgress]()
        _ = try VaultReader().loadVault(at: sandbox.rootURL) { progress in
            events.append(progress)
        }

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.last?.processedFileCount, 3)
        XCTAssertEqual(events.last?.noteCount, 2)
        XCTAssertEqual(events.last?.attachmentCount, 1)
    }
}

private struct TemporaryVault {
    let rootURL: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
        rootURL = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func write(_ relativePath: String, contents: String) throws {
        let fileURL = rootURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        guard let data = contents.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: fileURL)
    }

    func writeData(_ relativePath: String, data: Data) throws {
        let fileURL = rootURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
