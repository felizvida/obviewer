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

    func testResolveNoteIDSupportsFrontmatterAliases() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(
                    relativePath: "Projects/Plan.md",
                    title: "Launch Plan",
                    frontmatter: NoteFrontmatter(
                        entries: [
                            FrontmatterEntry(
                                key: "aliases",
                                value: .array([.string("Control Center"), .string("Release Home")])
                            ),
                        ]
                    )
                ),
            ],
            attachments: []
        )

        XCTAssertEqual(snapshot.resolveNoteID(for: "Control Center"), "Projects/Plan.md")
        XCTAssertEqual(snapshot.resolveNoteID(for: "Release Home"), "Projects/Plan.md")
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

    func testSearchNotesMatchesTitlePathPreviewTagsAndFrontmatter() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(
                    relativePath: "Projects/Plan.md",
                    title: "Launch Plan",
                    previewText: "Ship the control center rollout",
                    tags: ["roadmap"],
                    frontmatter: NoteFrontmatter(
                        entries: [
                            FrontmatterEntry(
                                key: "aliases",
                                value: .array([.string("Control Center")])
                            ),
                            FrontmatterEntry(
                                key: "owner",
                                value: .string("Platform Experience")
                            ),
                        ]
                    )
                ),
                .fixture(
                    relativePath: "Journal/Today.md",
                    title: "Today",
                    previewText: "Research sync notes",
                    tags: ["research"]
                ),
            ],
            attachments: []
        )

        XCTAssertEqual(snapshot.searchNotes(matching: "launch").map(\.id), ["Projects/Plan.md"])
        XCTAssertEqual(snapshot.searchNotes(matching: "projects/plan").map(\.id), ["Projects/Plan.md"])
        XCTAssertEqual(snapshot.searchNotes(matching: "control center").map(\.id), ["Projects/Plan.md"])
        XCTAssertEqual(snapshot.searchNotes(matching: "platform experience").map(\.id), ["Projects/Plan.md"])
        XCTAssertEqual(snapshot.searchNotes(matching: "#research").map(\.id), ["Journal/Today.md"])
        XCTAssertEqual(Set(snapshot.searchNotes(matching: "research").map(\.id)), ["Journal/Today.md"])
    }

    func testSearchNotesReturnsAllNotesForBlankQuery() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "One.md", title: "One"),
                .fixture(relativePath: "Two.md", title: "Two"),
            ],
            attachments: []
        )

        XCTAssertEqual(snapshot.searchNotes(matching: "").map(\.id), ["One.md", "Two.md"])
        XCTAssertEqual(snapshot.searchNotes(matching: "   ").map(\.id), ["One.md", "Two.md"])
    }

    func testIndexDiagnosticsSummarizesVaultShape() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(
                    relativePath: "Projects/Plan.md",
                    title: "Launch Plan",
                    tags: ["roadmap", "alpha"],
                    outboundLinks: ["Projects/Today"],
                    wordCount: 120
                ),
                .fixture(
                    relativePath: "Projects/Today.md",
                    title: "Today",
                    tags: ["alpha"],
                    wordCount: 80
                ),
                .fixture(
                    relativePath: "Journal/Today.md",
                    title: "Journal Today",
                    tags: ["journal"],
                    wordCount: 40
                ),
                .fixture(
                    relativePath: "Root.md",
                    title: "Root",
                    wordCount: 10
                ),
            ],
            attachments: [
                .fixture(relativePath: "Projects/cover.png", kind: .image),
                .fixture(relativePath: "Assets/manual.pdf", kind: .pdf),
            ]
        )

        let diagnostics = snapshot.indexDiagnostics(topFolderCount: 3)

        XCTAssertEqual(diagnostics.totalFileCount, 6)
        XCTAssertEqual(diagnostics.noteCount, 4)
        XCTAssertEqual(diagnostics.attachmentCount, 2)
        XCTAssertEqual(diagnostics.folderCount, 3)
        XCTAssertEqual(diagnostics.uniqueTagCount, 3)
        XCTAssertEqual(diagnostics.graphNodeCount, 4)
        XCTAssertEqual(diagnostics.graphEdgeCount, 1)
        XCTAssertEqual(diagnostics.totalWordCount, 250)
        XCTAssertEqual(diagnostics.averageWordsPerNote, 62.5, accuracy: 0.001)
        XCTAssertEqual(diagnostics.averageOutboundLinksPerNote, 0.25, accuracy: 0.001)
        XCTAssertEqual(
            diagnostics.attachmentKindCounts,
            [
                VaultAttachmentKindSummary(kind: .image, count: 1),
                VaultAttachmentKindSummary(kind: .pdf, count: 1),
            ]
        )
        XCTAssertEqual(diagnostics.largestFolders.first?.folderPath, "Projects")
        XCTAssertEqual(diagnostics.largestFolders.first?.totalFileCount, 3)
        XCTAssertEqual(diagnostics.largestFolders.first?.noteCount, 2)
        XCTAssertEqual(diagnostics.largestFolders.first?.attachmentCount, 1)
    }

    func testIndexManifestCapturesNotesAndAttachments() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(
                    relativePath: "Projects/Plan.md",
                    title: "Launch Plan",
                    modifiedAt: Date(timeIntervalSince1970: 10)
                ),
                .fixture(
                    relativePath: "Root.md",
                    title: "Root",
                    modifiedAt: Date(timeIntervalSince1970: 20)
                ),
            ],
            attachments: [
                VaultAttachment(
                    relativePath: "Assets/cover.png",
                    url: URL(fileURLWithPath: "/tmp/obviewer-tests/Assets/cover.png"),
                    kind: .image,
                    modifiedAt: Date(timeIntervalSince1970: 30)
                ),
            ]
        )

        XCTAssertEqual(
            snapshot.indexManifest.files,
            [
                VaultIndexedFile(
                    relativePath: "Assets/cover.png",
                    kind: .image,
                    modifiedAt: Date(timeIntervalSince1970: 30)
                ),
                VaultIndexedFile(
                    relativePath: "Projects/Plan.md",
                    kind: .note,
                    modifiedAt: Date(timeIntervalSince1970: 10)
                ),
                VaultIndexedFile(
                    relativePath: "Root.md",
                    kind: .note,
                    modifiedAt: Date(timeIntervalSince1970: 20)
                ),
            ]
        )
    }

    func testPersistentIndexReconstructsLookupAndGraphState() {
        let original = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(
                    relativePath: "Alpha/Daily.md",
                    title: "Daily",
                    outboundLinks: ["Shared/Hub"],
                    modifiedAt: Date(timeIntervalSince1970: 10)
                ),
                .fixture(
                    relativePath: "Beta/Daily.md",
                    title: "Daily",
                    outboundLinks: ["Shared/Hub"],
                    modifiedAt: Date(timeIntervalSince1970: 20)
                ),
                .fixture(
                    relativePath: "Shared/Hub.md",
                    title: "Hub",
                    modifiedAt: Date(timeIntervalSince1970: 30)
                ),
            ],
            attachments: [
                VaultAttachment(
                    relativePath: "Alpha/cover.png",
                    url: URL(fileURLWithPath: "/tmp/obviewer-tests/Alpha/cover.png"),
                    kind: .image,
                    modifiedAt: Date(timeIntervalSince1970: 40)
                ),
                VaultAttachment(
                    relativePath: "Beta/cover.png",
                    url: URL(fileURLWithPath: "/tmp/obviewer-tests/Beta/cover.png"),
                    kind: .image,
                    modifiedAt: Date(timeIntervalSince1970: 50)
                ),
            ]
        )

        let restored = VaultSnapshot(
            rootURL: original.rootURL,
            notes: original.notes,
            attachments: original.attachments,
            indexManifest: original.indexManifest,
            persistentIndex: original.persistentIndex
        )

        XCTAssertEqual(restored.resolveNoteID(for: "Daily", from: "Alpha/Daily.md"), "Alpha/Daily.md")
        XCTAssertEqual(restored.attachment(for: "cover.png", from: "Beta/Daily.md")?.relativePath, "Beta/cover.png")
        XCTAssertEqual(restored.noteGraph.edges, original.noteGraph.edges)
    }
}

private extension VaultNote {
    static func fixture(
        relativePath: String,
        title: String,
        previewText: String? = nil,
        tags: [String] = [],
        frontmatter: NoteFrontmatter = NoteFrontmatter(),
        outboundLinks: [String] = [],
        wordCount: Int = 0,
        modifiedAt: Date = .distantPast
    ) -> VaultNote {
        VaultNote(
            id: relativePath,
            title: title,
            relativePath: relativePath,
            folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                ? ""
                : (relativePath as NSString).deletingLastPathComponent,
            previewText: previewText ?? title,
            frontmatter: frontmatter,
            tags: tags,
            outboundLinks: outboundLinks,
            tableOfContents: [],
            blocks: [],
            wordCount: wordCount,
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
