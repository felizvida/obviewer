import XCTest
@testable import ObviewerCore

final class ObsidianParserTests: XCTestCase {
    func testParserUsesFallbackTitlePreviewAndUniqueAnchorsWhenHeadingsRepeat() {
        let markdown = """
        ---
        status: draft
        ---

        ## Intro

        Body text here.

        ## Intro

        More body text.
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback Title")

        XCTAssertEqual(result.title, "Fallback Title")
        XCTAssertEqual(result.previewText, "Intro")
        XCTAssertEqual(
            result.tableOfContents,
            [
                TableOfContentsItem(id: "intro", level: 2, title: "Intro"),
                TableOfContentsItem(id: "intro-2", level: 2, title: "Intro"),
            ]
        )
    }

    func testParserExtractsStructuredFrontmatterAndMergesFrontmatterTags() {
        let markdown = """
        ---
        title: Launch Dashboard
        aliases:
          - Control Center
          - Release Home
        tags: [reader, launch]
        status: active
        priority: 3
        featured: true
        owner: "Platform Experience"
        ---

        Body with #beta.
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.title, "Launch Dashboard")
        XCTAssertEqual(result.frontmatter.aliases, ["Control Center", "Release Home"])
        XCTAssertEqual(result.frontmatter.value(for: "status"), .string("active"))
        XCTAssertEqual(result.frontmatter.value(for: "priority"), .number(3))
        XCTAssertEqual(result.frontmatter.value(for: "featured"), .bool(true))
        XCTAssertEqual(result.frontmatter.value(for: "owner"), .string("Platform Experience"))
        XCTAssertEqual(result.tags, ["reader", "launch", "beta"])
    }

    func testParserUsesFrontmatterTitleForPreviewWhenBodyIsEmpty() {
        let markdown = """
        ---
        title: Metadata Only Note
        status: archived
        ---
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.title, "Metadata Only Note")
        XCTAssertEqual(result.previewText, "Metadata Only Note")
    }

    func testParserExtractsTitleLinksAndTags() {
        let markdown = """
        ---
        aliases: [Demo]
        ---

        # Reader Note

        This links to [[Second Note|the sequel]] and carries #research.

        - First bullet
        - Second bullet
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.title, "Reader Note")
        XCTAssertEqual(result.outboundLinks, ["Second Note"])
        XCTAssertEqual(result.tags, ["research"])
        XCTAssertEqual(result.blocks.count, 3)
        XCTAssertEqual(result.tableOfContents.map(\.title), ["Reader Note"])
        XCTAssertTrue(result.blocks.contains { block in
            guard case .list(let items) = block else { return false }
            return items.count == 2
                && items.allSatisfy { if case .unordered = $0.marker { return true } else { return false } }
                && items.map(\.text.plainText) == ["First bullet", "Second bullet"]
        })
    }

    func testParserRecognizesCalloutsAndStandaloneImagesWithSizingHints() {
        let markdown = """
        > [!warning] Handle Carefully
        > This should stay read only.

        ![[cover.png|300]]
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertTrue(result.blocks.contains { block in
            if case .callout(let kind, let title, let body) = block {
                return kind == .warning
                    && title.plainText == "Handle Carefully"
                    && body.plainText == "This should stay read only."
            }
            return false
        })

        XCTAssertTrue(result.blocks.contains { block in
            if case .image(let path, _, let sizeHint) = block {
                return path == "cover.png"
                    && sizeHint == ImageSizeHint(width: 300, height: nil)
            }
            return false
        })
    }

    func testParserCapturesTwoDimensionalObsidianImageSizeHints() {
        let markdown = """
        ![[boards/plan.png|320x180]]
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertTrue(result.blocks.contains { block in
            if case .image(let path, _, let sizeHint) = block {
                return path == "boards/plan.png"
                    && sizeHint == ImageSizeHint(width: 320, height: 180)
            }
            return false
        })
    }

    func testParserBuildsTableAndInlineLinks() {
        let markdown = """
        ## Data

        Here is [OpenAI](https://openai.com) and [[Vault Note]].

        | Name | Value |
        | --- | --- |
        | Alpha | **42** |
        | Beta | `ready` |
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.outboundLinks, ["Vault Note"])
        XCTAssertEqual(result.tableOfContents.map(\.title), ["Data"])
        XCTAssertTrue(result.blocks.contains { block in
            if case .table(let headers, let rows) = block {
                return headers.map(\.plainText) == ["Name", "Value"]
                    && rows.count == 2
                    && rows[0][1].plainText == "42"
                    && rows[1][1].plainText == "ready"
            }
            return false
        })
    }

    func testParserRecognizesCodeQuoteDividerAndOrderedTagSet() {
        let markdown = """
        # Workshop

        #alpha starts the note and appears again as #alpha later.

        ---

        > A quoted reminder.

        ```swift
        let readerMode = "read only"
        ```
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.tags, ["alpha"])
        XCTAssertTrue(result.wordCount > 0)
        XCTAssertEqual(result.readingTimeMinutes, 1)
        XCTAssertTrue(result.blocks.contains { block in
            if case .divider = block {
                return true
            }
            return false
        })
        XCTAssertTrue(result.blocks.contains { block in
            if case .quote(let text) = block {
                return text.plainText == "A quoted reminder."
            }
            return false
        })
        XCTAssertTrue(result.blocks.contains { block in
            if case .code(let language, let code) = block {
                return language == "swift" && code.contains("readerMode")
            }
            return false
        })
    }

    func testParserKeepsInlineEmbedsVisible() {
        let markdown = """
        Before ![[cover.png|300]] and ![Poster](images/poster.jpg) after.
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertTrue(result.blocks.contains { block in
            guard case .paragraph(let text) = block else { return false }

            let images = text.runs.compactMap { run -> (String, String?, ImageSizeHint?)? in
                guard case .image(let path, let alt, let sizeHint) = run else { return nil }
                return (path, alt, sizeHint)
            }

            return images.contains(where: { path, alt, sizeHint in
                path == "cover.png"
                    && alt == nil
                    && sizeHint == ImageSizeHint(width: 300, height: nil)
            }) && images.contains(where: { path, alt, sizeHint in
                path == "images/poster.jpg"
                    && alt == "Poster"
                    && sizeHint == nil
            })
        })
    }

    func testParserClassifiesAttachmentAndAnchorLinks() {
        let markdown = """
        See [Manual](manual.pdf), [Cover](images/cover.png), [Jump](#Deep Dive), and [Next](note.md#Part Two).
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertTrue(result.blocks.contains { block in
            guard case .paragraph(let text) = block else { return false }

            let links = text.runs.compactMap { run -> (String, LinkDestination)? in
                guard case .link(let label, let destination) = run else { return nil }
                return (label, destination)
            }

            return links.contains(where: { label, destination in
                label == "Manual" && destination == .attachment("manual.pdf")
            }) && links.contains(where: { label, destination in
                label == "Cover" && destination == .attachment("images/cover.png")
            }) && links.contains(where: { label, destination in
                label == "Jump" && destination == .anchor("deep-dive")
            }) && links.contains(where: { label, destination in
                label == "Next" && destination == .note(target: "note.md", anchor: "part-two")
            })
        })
    }

    func testParserRecordsOutboundLinksOnlyForNoteDestinations() {
        let markdown = """
        [[Daily]]
        [Manual](manual.pdf)
        [Jump](#Section)
        [Web](https://example.com)
        [Next](Note.md#Details)
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.outboundLinks, ["Daily", "Note.md"])
    }

    func testParserBuildsOrderedTaskAndNestedLists() {
        let markdown = """
        3. Ship beta
        4. Verify rollout
           - Capture screenshots
           - Update notes
        - [ ] Follow up with design
        - [x] Confirm read-only guarantee
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        guard case .list(let items)? = result.blocks.first else {
            return XCTFail("Expected first block to be a list")
        }

        XCTAssertEqual(items.count, 4)

        XCTAssertEqual(items[0].marker, .ordered(3))
        XCTAssertEqual(items[0].text.plainText, "Ship beta")
        XCTAssertTrue(items[0].children.isEmpty)

        XCTAssertEqual(items[1].marker, .ordered(4))
        XCTAssertEqual(items[1].text.plainText, "Verify rollout")
        XCTAssertEqual(items[1].children.count, 2)
        XCTAssertEqual(items[1].children.map(\.marker), [.unordered, .unordered])
        XCTAssertEqual(items[1].children.map(\.text.plainText), ["Capture screenshots", "Update notes"])

        XCTAssertEqual(items[2].marker, .task(isCompleted: false))
        XCTAssertEqual(items[2].text.plainText, "Follow up with design")

        XCTAssertEqual(items[3].marker, .task(isCompleted: true))
        XCTAssertEqual(items[3].text.plainText, "Confirm read-only guarantee")
    }

    func testParserTreatsIndentedContinuationLinesAsPartOfSameListItem() {
        let markdown = """
        - Reader baseline
          Includes follow-up detail on the next line.
          And one more continuation sentence.
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        guard case .list(let items)? = result.blocks.first else {
            return XCTFail("Expected first block to be a list")
        }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(
            items[0].text.plainText,
            "Reader baseline Includes follow-up detail on the next line. And one more continuation sentence."
        )
    }

    func testParserBuildsFootnoteReferencesAndSection() {
        let markdown = """
        Reader note with a footnote[^alpha].

        [^alpha]: Footnote detail with [[Plan]] and #research.
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertEqual(result.outboundLinks, ["Plan"])
        XCTAssertEqual(result.tags, ["research"])

        XCTAssertTrue(result.blocks.contains { block in
            guard case .paragraph(let text) = block else { return false }
            return text.runs.contains { run in
                if case .link(let label, let destination) = run {
                    return label == "[alpha]" && destination == .anchor("footnote-alpha")
                }
                return false
            }
        })

        XCTAssertTrue(result.blocks.contains { block in
            guard case .footnotes(let items) = block else { return false }
            return items.count == 1
                && items[0].id == "footnote-alpha"
                && items[0].label == "alpha"
                && items[0].text.plainText == "Footnote detail with Plan and #research."
        })
    }

    func testParserCreatesUnsupportedFallbackBlocksForMermaidAndStandaloneMediaEmbeds() {
        let markdown = """
        ```mermaid
        graph TD
          A --> B
        ```

        ![[manual.pdf]]
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        XCTAssertTrue(result.blocks.contains { block in
            guard case .unsupported(let unsupported) = block else { return false }
            return unsupported.title == "Mermaid Diagram Preview Unavailable"
                && unsupported.body.contains("graph TD")
                && unsupported.attachmentPath == nil
        })

        XCTAssertTrue(result.blocks.contains { block in
            guard case .unsupported(let unsupported) = block else { return false }
            return unsupported.title == "Embedded PDF Preview Unavailable"
                && unsupported.body == "manual.pdf"
                && unsupported.attachmentPath == "manual.pdf"
        })
    }
}
