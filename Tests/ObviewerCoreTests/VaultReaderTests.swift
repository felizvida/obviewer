import Foundation
import Testing
@testable import ObviewerCore

struct VaultReaderTests {
    @Test
    func loadVaultIndexesNotesAndAttachmentsFromDisk() throws {
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

        #expect(snapshot.notes.count == 2)
        #expect(snapshot.resolveNoteID(for: "Projects/Plan") == "Projects/Plan.md")
        #expect(snapshot.attachment(for: "cover.png", from: "Journal/Today.md")?.kind == .image)
        #expect(snapshot.attachment(for: "manual.pdf")?.kind == .pdf)
        #expect(snapshot.attachment(for: "notes.txt")?.kind == .other)
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
