import Foundation
import XCTest
@testable import ObviewerCore

/// Runs the same link expectations as `Renderer/test/fixtures.test.js`, so the
/// Swift indexer (search, backlinks, graph) and the web renderer agree on
/// which links a note contains.
final class SharedFixtureLinkTests: XCTestCase {
    private struct Expectation: Decodable {
        let flavor: String
        let pagesBase: String?
        let links: [String]
    }

    func testIndexerAgreesWithRendererOnSharedFixtures() throws {
        let data = try Data(contentsOf: fixturesURL.appendingPathComponent("expectations.json"))
        let expectations = try JSONDecoder().decode([String: Expectation].self, from: data)
        XCTAssertFalse(expectations.isEmpty)

        for (name, expected) in expectations.sorted(by: { $0.key < $1.key }) {
            let source = try String(contentsOf: fixturesURL.appendingPathComponent(name), encoding: .utf8)
            let links: [String]
            if expected.flavor == "dokuwiki" {
                links = DokuWikiSyntax.linkIDs(in: source, fromNoteID: name, pagesBase: expected.pagesBase ?? "")
            } else {
                links = ObsidianParser().parse(markdown: source, fallbackTitle: name).outboundLinks
            }
            XCTAssertEqual(
                Set(links.map(normalize)),
                Set(expected.links.map(normalize)),
                "Link mismatch for \(name)"
            )
        }
    }

    func testWikiSyntaxMatchesRendererParsing() {
        let target = WikiSyntax.parseTarget("Note#H1#H2|Alias")
        XCTAssertEqual(target.raw, "Note#H1#H2")
        XCTAssertEqual(target.note, "Note")
        XCTAssertEqual(target.anchor, "H2")
        XCTAssertEqual(target.alias, "Alias")
        XCTAssertEqual(WikiSyntax.parseTarget("Glossary\\|the glossary").alias, "the glossary")

        let source = "![[Embed]] [[Link]] `[[Code]]` \\[[Escaped]]\n```\n![[Fenced]]\n```"
        XCTAssertEqual(WikiSyntax.embedContents(in: source), ["Embed"])
        XCTAssertEqual(WikiSyntax.wikiLinkContents(in: source), ["Embed", "Link"])
        XCTAssertEqual(WikiSyntax.embedKind(forPath: "a/b.PNG"), .image)
        XCTAssertEqual(WikiSyntax.embedKind(forPath: "Note"), .note)
    }

    func testDokuWikiIDsResolveLikeTheRenderer() {
        XCTAssertEqual(DokuWikiSyntax.resolveID("start", namespace: ["lab"]), "lab:start")
        XCTAssertEqual(DokuWikiSyntax.resolveID(":start", namespace: ["lab"]), "start")
        XCTAssertEqual(DokuWikiSyntax.resolveID("..:other", namespace: ["lab", "sub"]), "lab:other")
        XCTAssertEqual(DokuWikiSyntax.resolveID("ns:", namespace: []), "ns:start")
        XCTAssertEqual(DokuWikiSyntax.cleanID(" My Page "), "my_page")
        XCTAssertEqual(DokuWikiSyntax.namespace(ofNoteID: "data/pages/a/b/c.txt", pagesBase: "data/pages"), ["a", "b"])
    }

    func testDokuWikiIndexingFindsTitleTagsAndLinks() throws {
        let name = "dokuwiki/data/pages/lab/protocols.txt"
        let source = try String(contentsOf: fixturesURL.appendingPathComponent(name), encoding: .utf8)
        let parsed = DokuWikiSyntax.parse(text: source, noteID: name, pagesBase: "dokuwiki/data/pages", fallbackTitle: "protocols")
        XCTAssertEqual(parsed.title, "Lab Protocols")
        XCTAssertEqual(parsed.tags, ["lab", "sop"])
        XCTAssertTrue(parsed.outboundLinks.contains("dokuwiki/data/pages/safety/training"))
        XCTAssertEqual(parsed.tableOfContents.map(\.title), ["Lab Protocols", "Equipment"])
    }

    private func normalize(_ link: String) -> String {
        var value = link.removingPercentEncoding ?? link
        for suffix in [".md", ".markdown"] where value.lowercased().hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        return value.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var fixturesURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // ObviewerCoreTests
        url.deleteLastPathComponent() // Tests
        url.deleteLastPathComponent() // repo root
        return url.appendingPathComponent("Fixtures/notes", isDirectory: true)
    }
}
