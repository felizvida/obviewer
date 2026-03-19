import Foundation
import XCTest
@testable import ObviewerCore

final class VaultSnapshotTests: XCTestCase {
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
}

private extension VaultNote {
    static func fixture(relativePath: String, title: String) -> VaultNote {
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
            modifiedAt: .distantPast
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
