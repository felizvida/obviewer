import Foundation
import XCTest
@testable import ObviewerCore

final class NoteGraphTests: XCTestCase {
    func testNoteGraphSkipsSelfLinksAndDeduplicatesRepeatedEdges() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(
                    relativePath: "Root.md",
                    title: "Root",
                    outboundLinks: ["Root", "Projects/Plan", "Projects/Plan"]
                ),
                .fixture(relativePath: "Projects/Plan.md", title: "Plan"),
            ],
            attachments: []
        )

        XCTAssertEqual(snapshot.noteGraph.outboundNoteIDs(from: "Root.md"), ["Projects/Plan.md"])
        XCTAssertEqual(snapshot.noteGraph.edges, [NoteGraphEdge(sourceID: "Root.md", targetID: "Projects/Plan.md")])
    }

    func testNoteGraphResolvesDuplicateNamedEdgesRelativeToSourceFolder() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Journal/Today.md", title: "Today", outboundLinks: ["Daily"]),
                .fixture(relativePath: "Journal/Daily.md", title: "Daily"),
                .fixture(relativePath: "Projects/Today.md", title: "Today", outboundLinks: ["Daily"]),
                .fixture(relativePath: "Projects/Daily.md", title: "Daily"),
            ],
            attachments: []
        )

        XCTAssertEqual(
            snapshot.noteGraph.outboundNoteIDs(from: "Journal/Today.md"),
            ["Journal/Daily.md"]
        )
        XCTAssertEqual(
            snapshot.noteGraph.outboundNoteIDs(from: "Projects/Today.md"),
            ["Projects/Daily.md"]
        )
    }

    func testNoteGraphBuildsBacklinksAndLocalNeighborhood() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Root.md", title: "Root", outboundLinks: ["Projects/Plan"]),
                .fixture(relativePath: "Journal/Today.md", title: "Today", outboundLinks: ["Projects/Plan"]),
                .fixture(relativePath: "Projects/Plan.md", title: "Plan", outboundLinks: ["Root"]),
            ],
            attachments: []
        )

        XCTAssertEqual(snapshot.noteGraph.inboundNoteIDs(to: "Projects/Plan.md"), ["Journal/Today.md", "Root.md"])
        XCTAssertEqual(snapshot.noteGraph.outboundNoteIDs(from: "Projects/Plan.md"), ["Root.md"])

        let subgraph = snapshot.noteGraph.localSubgraph(around: "Projects/Plan.md")

        XCTAssertEqual(subgraph.centerNodeID, "Projects/Plan.md")
        XCTAssertEqual(Set(subgraph.nodes.map(\.id)), ["Root.md", "Journal/Today.md", "Projects/Plan.md"])
        XCTAssertEqual(
            Set(subgraph.edges),
            [
                NoteGraphEdge(sourceID: "Root.md", targetID: "Projects/Plan.md"),
                NoteGraphEdge(sourceID: "Journal/Today.md", targetID: "Projects/Plan.md"),
                NoteGraphEdge(sourceID: "Projects/Plan.md", targetID: "Root.md"),
            ]
        )
    }

    func testLocalSubgraphExpandsNeighborhoodForSmallGraphs() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Center.md", title: "Center", outboundLinks: ["Left", "Right"]),
                .fixture(relativePath: "Left.md", title: "Left", outboundLinks: ["Far Left"]),
                .fixture(relativePath: "Far Left.md", title: "Far Left"),
                .fixture(relativePath: "Right.md", title: "Right", outboundLinks: ["Far Right"]),
                .fixture(relativePath: "Far Right.md", title: "Far Right"),
            ],
            attachments: []
        )

        let subgraph = snapshot.noteGraph.localSubgraph(around: "Center.md")

        XCTAssertEqual(
            Set(subgraph.nodes.map(\.id)),
            ["Center.md", "Left.md", "Right.md", "Far Left.md", "Far Right.md"]
        )
    }

    func testGlobalSubgraphFiltersNodesAndEdges() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Root.md", title: "Root", outboundLinks: ["Projects/Plan"]),
                .fixture(relativePath: "Journal/Today.md", title: "Today", outboundLinks: ["Projects/Plan"]),
                .fixture(relativePath: "Projects/Plan.md", title: "Plan", outboundLinks: ["Root"]),
            ],
            attachments: []
        )

        let subgraph = snapshot.noteGraph.globalSubgraph(
            visibleNoteIDs: ["Root.md", "Projects/Plan.md"],
            highlightedIDs: ["Root.md"],
            centerNodeID: "Projects/Plan.md"
        )

        XCTAssertEqual(subgraph.centerNodeID, "Projects/Plan.md")
        XCTAssertEqual(Set(subgraph.nodes.map(\.id)), ["Root.md", "Projects/Plan.md"])
        XCTAssertEqual(subgraph.highlightedNodeIDs, ["Root.md"])
        XCTAssertEqual(
            Set(subgraph.edges),
            [
                NoteGraphEdge(sourceID: "Root.md", targetID: "Projects/Plan.md"),
                NoteGraphEdge(sourceID: "Projects/Plan.md", targetID: "Root.md"),
            ]
        )
    }

    func testGlobalSubgraphFallsBackToAllNodesWhenVisibleSetIsEmpty() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Root.md", title: "Root", outboundLinks: ["Projects/Plan"]),
                .fixture(relativePath: "Journal/Today.md", title: "Today", outboundLinks: ["Projects/Plan"]),
                .fixture(relativePath: "Projects/Plan.md", title: "Plan", outboundLinks: ["Root"]),
            ],
            attachments: []
        )

        let subgraph = snapshot.noteGraph.globalSubgraph(visibleNoteIDs: [])

        XCTAssertEqual(Set(subgraph.nodes.map(\.id)), ["Root.md", "Journal/Today.md", "Projects/Plan.md"])
        XCTAssertEqual(Set(subgraph.edges), Set(snapshot.noteGraph.edges))
    }

    func testLocalSubgraphReturnsEmptyWhenCenterNoteIsMissing() {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests"),
            notes: [
                .fixture(relativePath: "Root.md", title: "Root"),
            ],
            attachments: []
        )

        let subgraph = snapshot.noteGraph.localSubgraph(around: "Missing.md", highlightedIDs: ["Root.md"])

        XCTAssertTrue(subgraph.nodes.isEmpty)
        XCTAssertTrue(subgraph.edges.isEmpty)
        XCTAssertEqual(subgraph.highlightedNodeIDs, ["Root.md"])
        XCTAssertNil(subgraph.centerNodeID)
    }
}

private extension VaultNote {
    static func fixture(
        relativePath: String,
        title: String,
        outboundLinks: [String] = []
    ) -> VaultNote {
        VaultNote(
            id: relativePath,
            title: title,
            relativePath: relativePath,
            folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                ? ""
                : (relativePath as NSString).deletingLastPathComponent,
            previewText: title,
            frontmatter: NoteFrontmatter(),
            tags: [],
            outboundLinks: outboundLinks,
            tableOfContents: [],
            blocks: [],
            wordCount: 0,
            readingTimeMinutes: 1,
            modifiedAt: .distantPast
        )
    }
}
