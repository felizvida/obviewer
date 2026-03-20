import Foundation
import XCTest
@testable import ObviewerCore
import ObviewerFixtureSupport

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

    func testLoadLargeGeneratedVaultExercisesRealObsidianFeatures() throws {
        let fixture = try TemporaryDemoVault(profile: .integration)
        defer { fixture.cleanup() }

        var events = [VaultLoadingProgress]()
        let snapshot = try VaultReader().loadVault(at: fixture.rootURL) { progress in
            events.append(progress)
        }

        let manifest = fixture.manifest
        XCTAssertEqual(snapshot.notes.count, manifest.noteCount)
        XCTAssertEqual(snapshot.attachments.count, manifest.attachmentCount)
        XCTAssertNotNil(snapshot.note(withID: manifest.firstJournalNoteID))
        XCTAssertEqual(
            snapshot.resolveNoteID(for: "Daily", from: manifest.alphaOverviewNoteID),
            manifest.alphaDailyNoteID
        )
        XCTAssertEqual(
            snapshot.resolveNoteID(for: "Daily", from: manifest.betaOverviewNoteID),
            manifest.betaDailyNoteID
        )
        XCTAssertEqual(
            snapshot.attachment(for: "cover.png", from: manifest.alphaOverviewNoteID)?.relativePath,
            manifest.alphaCoverAttachmentPath
        )
        XCTAssertEqual(
            snapshot.attachment(for: "cover.png", from: manifest.betaOverviewNoteID)?.relativePath,
            manifest.betaCoverAttachmentPath
        )

        let home = try XCTUnwrap(snapshot.note(withID: manifest.homeNoteID))
        XCTAssertTrue(home.tags.contains("reader"))
        XCTAssertTrue(home.tableOfContents.contains(where: { $0.title == "Reader Checklist" }))
        XCTAssertTrue(home.blocks.contains(where: isTableBlock))
        XCTAssertTrue(home.blocks.contains(where: isImageBlock))
        XCTAssertTrue(
            home.blocks.contains(
                where: containsLink(destination: .attachment(manifest.operationsManualAttachmentPath))
            )
        )

        let alphaOverview = try XCTUnwrap(snapshot.note(withID: manifest.alphaOverviewNoteID))
        XCTAssertTrue(alphaOverview.tags.contains("alpha"))
        XCTAssertTrue(alphaOverview.blocks.contains(where: isTableBlock))
        XCTAssertTrue(alphaOverview.blocks.contains(where: containsLink(destination: .attachment("cover.png"))))
        XCTAssertTrue(
            alphaOverview.blocks.contains(
                where: containsLink(destination: .note(target: "Knowledge/Architecture/Index.md", anchor: "patterns"))
            )
        )

        XCTAssertGreaterThanOrEqual(events.count, 8)
        XCTAssertEqual(events.last?.processedFileCount, manifest.noteCount + manifest.attachmentCount)
        XCTAssertEqual(events.last?.noteCount, manifest.noteCount)
        XCTAssertEqual(events.last?.attachmentCount, manifest.attachmentCount)
        XCTAssertNil(events.last?.currentPath)
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

private func isTableBlock(_ block: RenderBlock) -> Bool {
    if case .table = block {
        return true
    }
    return false
}

private func isImageBlock(_ block: RenderBlock) -> Bool {
    if case .image = block {
        return true
    }
    return false
}

private func containsLink(destination expected: LinkDestination) -> (RenderBlock) -> Bool {
    { block in
        richTexts(in: block).contains { richText in
            richText.runs.contains { run in
                if case .link(_, let destination) = run {
                    return destination == expected
                }
                return false
            }
        }
    }
}

private func richTexts(in block: RenderBlock) -> [RichText] {
    switch block {
    case .heading(_, let text, _):
        return [text]
    case .paragraph(let text):
        return [text]
    case .bulletList(let items):
        return items
    case .quote(let text):
        return [text]
    case .callout(_, let title, let body):
        return [title, body]
    case .table(let headers, let rows):
        return headers + rows.flatMap { $0 }
    case .code, .image, .divider:
        return []
    }
}
