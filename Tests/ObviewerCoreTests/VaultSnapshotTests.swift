import Foundation
import XCTest
@testable import ObviewerCore

final class VaultSnapshotTests: XCTestCase {
    func testResolveNoteIDSupportsExactRelativePathAndTitleAliases() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Projects/Plan.md", title: "Launch Plan"),
                .fixture(relativePath: "Archive/Plan.md", title: "Archive Plan"),
            ],
            attachments: []
        )

        XCTAssertEqual(snapshot.resolveNoteID(for: "Projects/Plan"), "Projects/Plan.md")
        XCTAssertEqual(snapshot.resolveNoteID(for: "Launch Plan"), "Projects/Plan.md")
    }

    func testResolveNoteIDFallsBackToSourceRelativePathsForMarkdownLinks() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Projects/Area/Current.md", title: "Current"),
                .fixture(relativePath: "Projects/Shared/Guide.md", title: "Guide"),
            ],
            attachments: []
        )

        let resolved = snapshot.resolveNoteID(
            for: "../Shared/Guide.md",
            from: "Projects/Area/Current.md"
        )

        XCTAssertEqual(resolved, "Projects/Shared/Guide.md")
    }

    func testResolveNoteIDPrefersCurrentFolderForDuplicateBasenames() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Journal/Today.md", title: "Today"),
                .fixture(relativePath: "Journal/Daily.md", title: "Daily"),
                .fixture(relativePath: "Projects/Daily.md", title: "Daily"),
            ],
            attachments: []
        )

        let resolved = snapshot.resolveNoteID(
            for: "Daily",
            from: "Journal/Today.md"
        )

        XCTAssertEqual(resolved, "Journal/Daily.md")
    }

    func testAttachmentLookupPrefersCurrentFolderForDuplicateBasenames() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Projects/Overview.md", title: "Overview"),
            ],
            attachments: [
                .fixture(relativePath: "Journal/cover.png"),
                .fixture(relativePath: "Projects/cover.png"),
            ]
        )

        let resolved = snapshot.attachment(
            for: "cover.png",
            from: "Projects/Overview.md"
        )

        XCTAssertEqual(resolved?.relativePath, "Projects/cover.png")
    }

    func testAttachmentLookupSupportsExactRelativePathsWithoutSourceNote() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Root.md", title: "Root"),
            ],
            attachments: [
                .fixture(relativePath: "Assets/Images/cover.png"),
                .fixture(relativePath: "Projects/cover.png"),
            ]
        )

        let resolved = snapshot.attachment(for: "Assets/Images/cover.png")

        XCTAssertEqual(resolved?.relativePath, "Assets/Images/cover.png")
    }

    func testAttachmentLookupFallsBackToSourceRelativePathsForMarkdownLinks() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Projects/Area/Current.md", title: "Current"),
            ],
            attachments: [
                .fixture(relativePath: "Projects/Area/images/cover.png"),
            ]
        )

        let resolved = snapshot.attachment(
            for: "images/cover.png",
            from: "Projects/Area/Current.md"
        )

        XCTAssertEqual(resolved?.relativePath, "Projects/Area/images/cover.png")
    }

    func testSnapshotSortsNotesByModifiedDateDescendingThenPath() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(
                    relativePath: "Projects/Beta.md",
                    title: "Beta",
                    modifiedAt: Date(timeIntervalSince1970: 10)
                ),
                .fixture(
                    relativePath: "Projects/Alpha.md",
                    title: "Alpha",
                    modifiedAt: Date(timeIntervalSince1970: 10)
                ),
                .fixture(
                    relativePath: "Projects/Older.md",
                    title: "Older",
                    modifiedAt: Date(timeIntervalSince1970: 5)
                ),
            ],
            attachments: []
        )

        XCTAssertEqual(
            snapshot.notes.map(\.id),
            ["Projects/Alpha.md", "Projects/Beta.md", "Projects/Older.md"]
        )
    }
}

private extension VaultNote {
    static func fixture(
        relativePath: String,
        title: String,
        modifiedAt: Date = .distantPast
    ) -> VaultNote {
        VaultNote(
            id: relativePath,
            title: title,
            relativePath: relativePath,
            folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                ? ""
                : (relativePath as NSString).deletingLastPathComponent,
            previewText: title,
            tags: [],
            outboundLinks: [],
            tableOfContents: [],
            blocks: [],
            wordCount: 0,
            readingTimeMinutes: 1,
            modifiedAt: modifiedAt
        )
    }
}

private extension VaultAttachment {
    static func fixture(relativePath: String, kind: Kind = .image) -> VaultAttachment {
        VaultAttachment(
            relativePath: relativePath,
            url: URL(fileURLWithPath: "/tmp/obviewer-tests/\(relativePath)"),
            kind: kind
        )
    }
}
