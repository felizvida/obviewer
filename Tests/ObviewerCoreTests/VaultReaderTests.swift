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

        let recorder = ProgressRecorder()
        _ = try VaultReader().loadVault(at: sandbox.rootURL) { progress in
            recorder.append(progress)
        }
        let events = recorder.values

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.last?.processedFileCount, 3)
        XCTAssertEqual(events.last?.noteCount, 2)
        XCTAssertEqual(events.last?.attachmentCount, 1)
    }

    func testLoadVaultClassifiesAudioVideoAndSkipsHiddenFiles() throws {
        let sandbox = try TemporaryVault()
        defer { sandbox.cleanup() }

        try sandbox.write("Visible.md", contents: "# Visible")
        try sandbox.write(".Hidden.md", contents: "# Hidden")
        try sandbox.writeData("media/audio.m4a", data: Data("audio".utf8))
        try sandbox.writeData("media/video.mp4", data: Data("video".utf8))
        try sandbox.writeData("media/archive.bin", data: Data("other".utf8))
        try sandbox.writeData(".secret.png", data: Data([0x89, 0x50, 0x4E, 0x47]))

        let snapshot = try VaultReader().loadVault(at: sandbox.rootURL)

        XCTAssertEqual(snapshot.notes.map(\.id), ["Visible.md"])
        XCTAssertEqual(snapshot.attachments.count, 3)
        XCTAssertEqual(snapshot.attachment(for: "media/audio.m4a")?.kind, .audio)
        XCTAssertEqual(snapshot.attachment(for: "media/video.mp4")?.kind, .video)
        XCTAssertEqual(snapshot.attachment(for: "media/archive.bin")?.kind, .other)
        XCTAssertNil(snapshot.attachment(for: ".secret.png"))
    }

    func testReloadVaultReusesUnchangedNotesFromPreviousSnapshot() throws {
        let sandbox = try TemporaryVault()
        defer { sandbox.cleanup() }

        try sandbox.write(
            "Projects/Plan.md",
            contents: """
            # Plan

            Original disk content.
            """
        )

        let fileURL = sandbox.rootURL.appending(path: "Projects/Plan.md")
        let modifiedAt = try XCTUnwrap(
            fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )

        let previousSnapshot = VaultSnapshot(
            rootURL: sandbox.rootURL,
            notes: [
                VaultNote(
                    id: "Projects/Plan.md",
                    title: "Reused Snapshot Title",
                    relativePath: "Projects/Plan.md",
                    folderPath: "Projects",
                    previewText: "Reused snapshot preview",
                    frontmatter: NoteFrontmatter(
                        entries: [
                            FrontmatterEntry(key: "status", value: .string("cached")),
                        ]
                    ),
                    tags: ["cached"],
                    outboundLinks: [],
                    tableOfContents: [],
                    blocks: [.paragraph(text: .plain("Reused snapshot body"))],
                    wordCount: 3,
                    readingTimeMinutes: 1,
                    modifiedAt: modifiedAt
                ),
            ],
            attachments: []
        )

        let snapshot = try VaultReader().reloadVault(
            at: sandbox.rootURL,
            previousSnapshot: previousSnapshot
        )

        let note = try XCTUnwrap(snapshot.note(withID: "Projects/Plan.md"))
        XCTAssertEqual(note.title, "Reused Snapshot Title")
        XCTAssertEqual(note.previewText, "Reused snapshot preview")
        XCTAssertEqual(note.tags, ["cached"])
        XCTAssertEqual(note.frontmatter.value(for: "status"), .string("cached"))
    }

    func testReloadVaultReusesUnchangedAttachmentsFromPreviousSnapshot() throws {
        let sandbox = try TemporaryVault()
        defer { sandbox.cleanup() }

        try sandbox.writeData("Assets/cover.png", data: Data([0x89, 0x50, 0x4E, 0x47]))

        let fileURL = sandbox.rootURL.appending(path: "Assets/cover.png")
        let modifiedAt = try XCTUnwrap(
            fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )

        let previousAttachment = VaultAttachment(
            relativePath: "Assets/cover.png",
            url: URL(fileURLWithPath: "/tmp/obviewer-tests/reused-cover.png"),
            kind: .image,
            modifiedAt: modifiedAt
        )
        let previousSnapshot = VaultSnapshot(
            rootURL: sandbox.rootURL,
            notes: [],
            attachments: [previousAttachment]
        )

        let snapshot = try VaultReader().reloadVault(
            at: sandbox.rootURL,
            previousSnapshot: previousSnapshot
        )

        XCTAssertEqual(snapshot.attachments, [previousAttachment])
    }

    func testReloadVaultAppliesSelectiveCreatedModifiedAndRemovedPaths() throws {
        let sandbox = try TemporaryVault()
        defer { sandbox.cleanup() }

        try sandbox.write(
            "Projects/Plan.md",
            contents: """
            # Plan

            Original plan body.
            """
        )
        try sandbox.write(
            "Journal/Today.md",
            contents: """
            # Today

            Unchanged journal note.
            """
        )
        try sandbox.writeData("Projects/manual.pdf", data: Data([0x25, 0x50, 0x44, 0x46]))

        let initialSnapshot = try VaultReader().loadVault(at: sandbox.rootURL)
        let unchangedJournal = try XCTUnwrap(initialSnapshot.note(withID: "Journal/Today.md"))

        try sandbox.write(
            "Projects/Plan.md",
            contents: """
            # Plan

            Updated selective reload body.
            """
        )
        try sandbox.write(
            "Projects/Backlog.md",
            contents: """
            # Backlog

            Added during selective reload.
            """
        )
        try sandbox.writeData("Projects/cover.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        try sandbox.delete("Projects/manual.pdf")

        let snapshot = try VaultReader().reloadVault(
            at: sandbox.rootURL,
            previousSnapshot: initialSnapshot,
            changes: VaultReloadChanges(
                modifiedPaths: ["Projects/Plan.md"],
                createdPaths: ["Projects/Backlog.md", "Projects/cover.png"],
                removedPaths: ["Projects/manual.pdf"]
            )
        )

        XCTAssertEqual(snapshot.notes.count, 3)
        XCTAssertEqual(snapshot.attachments.count, 1)
        XCTAssertEqual(
            snapshot.note(withID: "Projects/Plan.md")?.previewText,
            "Plan"
        )
        XCTAssertNotNil(snapshot.note(withID: "Projects/Backlog.md"))
        XCTAssertEqual(
            snapshot.attachment(for: "Projects/cover.png")?.kind,
            .image
        )
        XCTAssertNil(snapshot.attachment(for: "Projects/manual.pdf"))
        XCTAssertEqual(snapshot.note(withID: "Journal/Today.md"), unchangedJournal)
    }

    func testLoadLargeGeneratedVaultExercisesRealObsidianFeatures() throws {
        let fixture = try TemporaryDemoVault(profile: .integration)
        defer { fixture.cleanup() }

        let recorder = ProgressRecorder()
        let snapshot = try VaultReader().loadVault(at: fixture.rootURL) { progress in
            recorder.append(progress)
        }
        let events = recorder.values

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
        XCTAssertTrue(alphaOverview.blocks.contains(where: containsInlineImage(path: "cover.png")))
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

    func testLoadLargeGeneratedVaultBuildsSearchableSnapshot() throws {
        let fixture = try TemporaryDemoVault(profile: .integration)
        defer { fixture.cleanup() }

        let snapshot = try VaultReader().loadVault(at: fixture.rootURL)
        let manifest = fixture.manifest

        let readerTaggedIDs = Set(snapshot.searchNotes(matching: "#reader").map(\.id))
        XCTAssertTrue(readerTaggedIDs.contains(manifest.homeNoteID))
        XCTAssertTrue(readerTaggedIDs.contains("Reader Playground.md"))

        let duplicateDailyIDs = Set(snapshot.searchNotes(matching: "Daily").map(\.id))
        XCTAssertTrue(duplicateDailyIDs.contains(manifest.alphaDailyNoteID))
        XCTAssertTrue(duplicateDailyIDs.contains(manifest.betaDailyNoteID))

        let architectureIDs = Set(snapshot.searchNotes(matching: "Knowledge/Architecture").map(\.id))
        XCTAssertTrue(architectureIDs.contains(manifest.architectureIndexNoteID))
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events = [VaultLoadingProgress]()

    func append(_ progress: VaultLoadingProgress) {
        lock.lock()
        events.append(progress)
        lock.unlock()
    }

    var values: [VaultLoadingProgress] {
        lock.lock()
        defer { lock.unlock() }
        return events
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

    func delete(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: rootURL.appending(path: relativePath))
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

private func containsInlineImage(
    path expectedPath: String,
    alt expectedAlt: String? = nil,
    sizeHint expectedSizeHint: ImageSizeHint? = nil
) -> (RenderBlock) -> Bool {
    { block in
        richTexts(in: block).contains { richText in
            richText.runs.contains { run in
                if case .image(let path, let alt, let sizeHint) = run {
                    guard path == expectedPath else {
                        return false
                    }

                    if let expectedAlt, alt != expectedAlt {
                        return false
                    }

                    if let expectedSizeHint, sizeHint != expectedSizeHint {
                        return false
                    }

                    return true
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
    case .list(let items):
        return listRichTexts(in: items)
    case .quote(let text):
        return [text]
    case .callout(_, let title, let body):
        return [title, body]
    case .table(let headers, let rows):
        return headers + rows.flatMap { $0 }
    case .footnotes(let items):
        return items.map(\.text)
    case .code, .image, .unsupported, .divider:
        return []
    }
}

private func listRichTexts(in items: [RenderListItem]) -> [RichText] {
    items.flatMap { item in
        [item.text] + listRichTexts(in: item.children)
    }
}
