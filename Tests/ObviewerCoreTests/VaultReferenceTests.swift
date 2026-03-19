import XCTest
@testable import ObviewerCore

final class VaultReferenceTests: XCTestCase {
    func testNormalizeVaultReferenceTrimsMarkdownSuffixWithoutTouchingOtherExtensions() {
        XCTAssertEqual(normalizeVaultReference("./Journal/Daily.md"), "journal/daily")
        XCTAssertEqual(normalizeVaultReference("Attachments/cover.png"), "attachments/cover.png")
        XCTAssertEqual(normalizeVaultReference(" Roadmap.MD "), "roadmap")
    }

    func testMakeAnchorSlugNormalizesHeadingText() {
        XCTAssertEqual(makeAnchorSlug("Deep Dive"), "deep-dive")
        XCTAssertEqual(makeAnchorSlug("Section 2.1 / API"), "section-2-1-api")
        XCTAssertEqual(makeAnchorSlug("!!!"), "section")
    }
}
