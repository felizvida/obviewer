import Testing
@testable import ObviewerCore

struct ObsidianParserTests {
    @Test
    func parserExtractsTitleLinksAndTags() {
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

        #expect(result.title == "Reader Note")
        #expect(result.outboundLinks == ["Second Note"])
        #expect(result.tags == ["research"])
        #expect(result.blocks.count == 3)
        #expect(result.tableOfContents.map(\.title) == ["Reader Note"])
    }

    @Test
    func parserRecognizesCalloutsAndStandaloneImagesWithSizingHints() {
        let markdown = """
        > [!warning] Handle Carefully
        > This should stay read only.

        ![[cover.png|300]]
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        #expect(result.blocks.contains { block in
            if case .callout(let kind, let title, let body) = block {
                return kind == .warning
                    && title.plainText == "Handle Carefully"
                    && body.plainText == "This should stay read only."
            }
            return false
        })

        #expect(result.blocks.contains { block in
            if case .image(let path, _) = block {
                return path == "cover.png"
            }
            return false
        })
    }

    @Test
    func parserBuildsTableAndInlineLinks() {
        let markdown = """
        ## Data

        Here is [OpenAI](https://openai.com) and [[Vault Note]].

        | Name | Value |
        | --- | --- |
        | Alpha | **42** |
        | Beta | `ready` |
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        #expect(result.outboundLinks == ["Vault Note"])
        #expect(result.tableOfContents.map(\.title) == ["Data"])
        #expect(result.blocks.contains { block in
            if case .table(let headers, let rows) = block {
                return headers.map(\.plainText) == ["Name", "Value"]
                    && rows.count == 2
                    && rows[0][1].plainText == "42"
                    && rows[1][1].plainText == "ready"
            }
            return false
        })
    }

    @Test
    func parserKeepsInlineEmbedsVisible() {
        let markdown = """
        Before ![[cover.png|300]] and ![Poster](images/poster.jpg) after.
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        #expect(result.blocks.contains { block in
            guard case .paragraph(let text) = block else { return false }

            let imageLinks = text.runs.compactMap { run -> (String, LinkDestination)? in
                guard case .link(let label, let destination) = run else { return nil }
                return (label, destination)
            }

            return imageLinks.contains(where: { label, destination in
                label == "[Image: cover.png]" && destination == .attachment("cover.png")
            }) && imageLinks.contains(where: { label, destination in
                label == "[Image: Poster]" && destination == .attachment("images/poster.jpg")
            })
        })
    }

    @Test
    func parserClassifiesAttachmentAndAnchorLinks() {
        let markdown = """
        See [Manual](manual.pdf), [Cover](images/cover.png), [Jump](#Deep Dive), and [Next](note.md#Part Two).
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        #expect(result.blocks.contains { block in
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
}
