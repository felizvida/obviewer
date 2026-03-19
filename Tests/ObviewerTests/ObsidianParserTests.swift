import Testing
@testable import Obviewer

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
    }

    @Test
    func parserRecognizesCalloutsAndImages() {
        let markdown = """
        > [!warning] Handle Carefully
        > This should stay read only.

        ![[cover.png]]
        """

        let result = ObsidianParser().parse(markdown: markdown, fallbackTitle: "Fallback")

        #expect(result.blocks.contains { block in
            if case .callout(let kind, let title, let body) = block {
                return kind == .warning && title == "Handle Carefully" && body == "This should stay read only."
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
}
