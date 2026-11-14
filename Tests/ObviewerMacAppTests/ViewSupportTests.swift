import XCTest
@testable import ObviewerMacApp

final class ViewSupportTests: XCTestCase {
    func testStablePaletteIndexIsDeterministicAndBounded() {
        let first = StablePaletteIndex.index(for: "Projects", modulo: 6)
        let second = StablePaletteIndex.index(for: "Projects", modulo: 6)
        let longValue = StablePaletteIndex.index(for: String(repeating: "folder/", count: 64), modulo: 6)

        XCTAssertEqual(first, second)
        XCTAssertTrue((0..<6).contains(first))
        XCTAssertTrue((0..<6).contains(longValue))
    }

    func testGraphPaletteBucketsByTopLevelFolder() {
        XCTAssertEqual(GraphPalette.bucketName(for: ""), "Vault Root")
        XCTAssertEqual(GraphPalette.bucketName(for: "Projects/Alpha"), "Projects")
        XCTAssertEqual(GraphPalette.bucketName(for: "Journal"), "Journal")
    }
}
