import Foundation
import XCTest
import ObviewerCore
@testable import ObviewerReaderKit

final class ReaderPayloadBuilderTests: XCTestCase {
    private var vaultURL: URL!

    override func setUpWithError() throws {
        vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultURL.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try write("Home.md", """
        # Home

        Links to [[Plan]], [[Missing Note]] and [[folder/Deep]].

        ![[Plan#Timeline]]
        ![[chart.png|300]]
        ![[Loop]]
        ![[Nowhere]]
        `![[InCode]]`
        """)
        try write("Plan.md", "# Plan\n\nIntro\n\n## Timeline\n\n- Q1\n\n![[Home]]\n")
        try write("Loop.md", "Loop body ![[Loop]]")
        try write("folder/Deep.md", "Deep note linking back to [[Home]].")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: vaultURL.appendingPathComponent("assets/chart.png"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vaultURL)
    }

    private func write(_ path: String, _ text: String) throws {
        try text.write(to: vaultURL.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func loadSnapshot() throws -> VaultSnapshot {
        try VaultReader().loadVault(at: vaultURL)
    }

    func testEmbedsResolveNotesAttachmentsCyclesAndMissing() throws {
        let snapshot = try loadSnapshot()
        let home = try XCTUnwrap(snapshot.note(withID: "Home.md"))
        let payload = try ReaderPayloadBuilder(snapshot: snapshot, flavor: .obsidian).build(for: home)

        let plan = try XCTUnwrap(payload.embeds["Plan#Timeline"])
        XCTAssertEqual(plan.status, .ok)
        XCTAssertEqual(plan.kind, .note)
        XCTAssertEqual(plan.noteID, "Plan.md")
        XCTAssertTrue(plan.markdown?.contains("Timeline") == true)
        // Plan embeds Home, which is an ancestor: a cycle, not infinite recursion.
        XCTAssertEqual(plan.embeds?["Home"]?.status, .cycle)

        let chart = try XCTUnwrap(payload.embeds["chart.png"])
        XCTAssertEqual(chart.kind, .image)
        XCTAssertEqual(chart.path, "assets/chart.png")

        XCTAssertEqual(payload.embeds["Loop"]?.status, .ok)
        XCTAssertEqual(payload.embeds["Loop"]?.embeds?["Loop"]?.status, .cycle)
        XCTAssertEqual(payload.embeds["Nowhere"]?.status, .missing)
        XCTAssertNil(payload.embeds["InCode"], "Embeds inside code are ignored")
    }

    func testResolvedLinksAndBacklinks() throws {
        let snapshot = try loadSnapshot()
        let home = try XCTUnwrap(snapshot.note(withID: "Home.md"))
        let payload = try ReaderPayloadBuilder(snapshot: snapshot, flavor: .obsidian).build(for: home)

        XCTAssertEqual(payload.resolvedLinks["Plan"], true)
        XCTAssertEqual(payload.resolvedLinks["Missing Note"], false)
        XCTAssertEqual(payload.resolvedLinks["folder/Deep"], true)
        XCTAssertEqual(Set(payload.backlinks.map(\.noteID)), ["Plan.md", "folder/Deep.md"])
        XCTAssertEqual(payload.header?.path, "Home.md")
    }

    func testOptionsHideHeaderAndBacklinks() throws {
        let snapshot = try loadSnapshot()
        let home = try XCTUnwrap(snapshot.note(withID: "Home.md"))
        let payload = try ReaderPayloadBuilder(snapshot: snapshot, flavor: .markdown)
            .build(for: home, options: ReaderRenderOptions(showHeader: false, showBacklinks: false))
        XCTAssertNil(payload.header)
        XCTAssertTrue(payload.backlinks.isEmpty)
    }

    func testPayloadJSONUsesRendererFieldNames() throws {
        let payload = ReaderRenderPayload(
            noteID: "a.md",
            relativePath: "a.md",
            title: "A",
            flavor: .obsidian,
            source: "# A",
            embeds: ["B": .problem(.missing)]
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.jsonString().utf8)) as? [String: Any])
        XCTAssertEqual(object["flavor"] as? String, "obsidian")
        XCTAssertEqual(object["source"] as? String, "# A")
        XCTAssertEqual((object["embeds"] as? [String: [String: Any]])?["B"]?["status"] as? String, "missing")
        XCTAssertNotNil(object["options"] as? [String: Any])
    }

    func testAssetResolverStaysInsideTheVault() throws {
        let snapshot = try loadSnapshot()
        let resolver = VaultAssetResolver(rootURL: vaultURL, snapshot: snapshot)

        XCTAssertEqual(
            resolver.resolveAsset(path: "assets/chart.png", raw: nil, fromNoteID: nil)?.standardizedFileURL.path,
            vaultURL.appendingPathComponent("assets/chart.png").standardizedFileURL.path
        )
        // Obsidian-style lookup by file name from a note.
        XCTAssertNotNil(resolver.resolveAsset(path: "chart.png", raw: "chart.png", fromNoteID: "Home.md"))
        // Escapes are refused before touching the file system.
        XCTAssertNil(VaultAssetResolver.containedURL(forRelativePath: "../outside.png", in: vaultURL))
        XCTAssertNil(VaultAssetResolver.containedURL(forRelativePath: "assets/../../outside.png", in: vaultURL))
        XCTAssertNil(resolver.resolveAsset(path: "../../etc/hosts", raw: "/etc/hosts", fromNoteID: nil))
    }

    func testSourceLoaderHandlesNonUTF8Text() {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in Windows-1252
        XCTAssertEqual(NoteSourceLoader.decode(latin1), "café")
        XCTAssertEqual(NoteSourceLoader.decode(Data([0xEF, 0xBB, 0xBF, 0x41])), "A")
    }
}

final class ReaderEventTests: XCTestCase {
    func testParsesLinkMessages() {
        let event = ReaderEvent(messageBody: [
            "type": "link", "kind": "wiki", "target": "Plan", "anchor": "Timeline", "from": "Home.md", "newWindow": false,
        ])
        XCTAssertEqual(event, .link(ReaderLinkRequest(kind: .wiki, target: "Plan", anchor: "Timeline", sourceNoteID: "Home.md")))

        let external = ReaderEvent(messageBody: ["type": "link", "kind": "external", "href": "https://example.org"])
        XCTAssertEqual(external, .link(ReaderLinkRequest(kind: .external, target: "https://example.org")))
    }

    func testParsesDiagnosticMessages() {
        XCTAssertEqual(ReaderEvent(messageBody: ["type": "jsError", "message": "boom"]), .jsError("boom"))
        XCTAssertEqual(ReaderEvent(messageBody: ["type": "cspViolation", "message": "img-src blocked https://x"]), .cspViolation("img-src blocked https://x"))
    }

    func testRejectsUnknownMessages() {
        XCTAssertNil(ReaderEvent(messageBody: "nope"))
        XCTAssertNil(ReaderEvent(messageBody: ["type": "writeFile", "path": "/etc/passwd"]))
        XCTAssertNil(ReaderEvent(messageBody: ["type": "link", "kind": "delete", "target": "x"]))
    }

    func testParsesHeadings() {
        let event = ReaderEvent(messageBody: [
            "type": "rendered", "noteID": "a.md",
            "headings": [["level": 2, "text": "Setup", "id": "setup"]],
        ])
        XCTAssertEqual(event, .rendered(noteID: "a.md", headings: [ReaderHeading(level: 2, text: "Setup", id: "setup")]))
    }
}

final class ReaderAssetsTests: XCTestCase {
    func testBundledReaderIsPresentAndComplete() throws {
        XCTAssertTrue(ReaderAssets.isAvailable, "Run `npm run build` in Renderer/ to generate the reader bundle.")
        for file in ["reader.html", "reader.js", "reader.css", "mermaid.min.js", "katex/katex.min.css", "manifest.json"] {
            XCTAssertNotNil(ReaderAssets.data(forRelativePath: file), "Missing \(file)")
        }
        XCTAssertNil(ReaderAssets.data(forRelativePath: "../Info.plist"))
    }

    func testReaderPageDeclaresAStrictContentSecurityPolicy() throws {
        let html = String(decoding: try XCTUnwrap(ReaderAssets.data(forRelativePath: "reader.html")), as: UTF8.self)
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("script-src obviewer-asset:"))
        XCTAssertFalse(html.contains("unsafe-eval"))
        XCTAssertFalse(html.contains("http:"))
        XCTAssertFalse(html.contains("https:"))
    }

    func testContentRulesBlockEverythingButLocalSchemes() throws {
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ReaderContentRules.json.utf8)) as? [[String: Any]])
        let first = try XCTUnwrap(rules.first)
        XCTAssertEqual((first["action"] as? [String: String])?["type"], "block")
        XCTAssertEqual((first["trigger"] as? [String: String])?["url-filter"], ".*")
        let exceptions = rules.dropFirst().compactMap { ($0["trigger"] as? [String: String])?["url-filter"] }
        XCTAssertEqual(Set(exceptions), ["^obviewer-asset:", "^data:", "^blob:", "^about:"])
    }
}

final class StaticPreviewRendererTests: XCTestCase {
    private func payload(_ source: String, flavor: ReaderFlavor = .markdown) -> ReaderRenderPayload {
        ReaderRenderPayload(
            noteID: "note.md",
            relativePath: "note.md",
            title: "Note <Title>",
            flavor: flavor,
            source: source,
            options: ReaderRenderOptions(showHeader: false, showBacklinks: false)
        )
    }

    func testRendersMarkdownToStaticHTMLWithJavaScriptCore() throws {
        let html = try StaticPreviewRenderer.document(for: payload("""
        # Heading

        > [!tip] Callout
        > Body with **bold** and $x^2$.

        ```mermaid
        graph TD; A-->B
        ```
        """))
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("data-callout=\"tip\""))
        XCTAssertTrue(html.contains("<math"), "math becomes MathML in static previews")
        XCTAssertTrue(html.contains("open in Obviewer"), "diagrams stay as source with a hint")
        XCTAssertTrue(html.contains("Note &lt;Title&gt;"), "title is escaped")
        XCTAssertTrue(html.contains("default-src 'none'"))
    }

    func testRawHTMLIsShownAsText() throws {
        let html = try StaticPreviewRenderer.document(for: payload("<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>"))
        let body = html.components(separatedBy: "<main class=\"ob-page\">").last ?? ""
        XCTAssertFalse(body.contains("<script"))
        XCTAssertFalse(body.contains("<img"))
        XCTAssertTrue(body.contains("&lt;script&gt;"))
    }

    func testRendersDokuWiki() throws {
        let html = try StaticPreviewRenderer.document(for: payload("====== Title ======\n\n^ A ^ B ^\n| 1 | 2 |", flavor: .dokuwiki))
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("<table>"))
    }
}
