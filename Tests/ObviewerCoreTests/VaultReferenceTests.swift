import Testing
@testable import ObviewerCore

struct VaultReferenceTests {
    @Test
    func normalizeVaultReferenceTrimsMarkdownSuffixWithoutTouchingOtherExtensions() {
        #expect(normalizeVaultReference("./Journal/Daily.md") == "journal/daily")
        #expect(normalizeVaultReference("Attachments/cover.png") == "attachments/cover.png")
        #expect(normalizeVaultReference(" Roadmap.MD ") == "roadmap")
    }

    @Test
    func makeAnchorSlugNormalizesHeadingText() {
        #expect(makeAnchorSlug("Deep Dive") == "deep-dive")
        #expect(makeAnchorSlug("Section 2.1 / API") == "section-2-1-api")
        #expect(makeAnchorSlug("!!!") == "section")
    }
}
