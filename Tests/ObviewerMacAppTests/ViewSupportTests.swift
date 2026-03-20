import XCTest
@testable import ObviewerCore
@testable import ObviewerMacApp

final class ViewSupportTests: XCTestCase {
    func testInlineFlowTokenBuilderDoesNotInsertExtraWhitespaceBeforeTags() {
        let tokens = InlineFlowTokenBuilder.tokens(
            from: RichText(
                runs: [
                    .text("Before "),
                    .image(path: "cover.png", alt: nil, sizeHint: nil),
                    .text(" "),
                    .tag("alpha"),
                ]
            )
        )

        XCTAssertEqual(
            tokens,
            [
                .plain("Before "),
                .image(path: "cover.png", alt: nil, sizeHint: nil),
                .plain(" "),
                .tag("#alpha", "alpha"),
            ]
        )
    }

    func testStablePaletteIndexIsDeterministicAndBounded() {
        let first = StablePaletteIndex.index(for: "Projects", modulo: 6)
        let second = StablePaletteIndex.index(for: "Projects", modulo: 6)
        let longValue = StablePaletteIndex.index(for: String(repeating: "folder/", count: 64), modulo: 6)

        XCTAssertEqual(first, second)
        XCTAssertTrue((0..<6).contains(first))
        XCTAssertTrue((0..<6).contains(longValue))
    }
}
