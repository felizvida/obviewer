import XCTest
@testable import ObviewerCore

final class VaultLoadingTests: XCTestCase {
    func testMergedChangesRevalidateRemoveThenRecreateAtSamePath() {
        let first = VaultReloadChanges(removedPaths: ["Projects/Plan.md"])
        let second = VaultReloadChanges(createdPaths: ["Projects/Plan.md"])

        let merged = first.merged(with: second)

        XCTAssertEqual(merged.modifiedPaths, ["Projects/Plan.md"])
        XCTAssertTrue(merged.createdPaths.isEmpty)
        XCTAssertTrue(merged.removedPaths.isEmpty)
    }

    func testMergedChangesKeepRemovalWhenModifiedPathIsLaterDeleted() {
        let first = VaultReloadChanges(modifiedPaths: ["Projects/Plan.md"])
        let second = VaultReloadChanges(removedPaths: ["Projects/Plan.md"])

        let merged = first.merged(with: second)

        XCTAssertTrue(merged.modifiedPaths.isEmpty)
        XCTAssertTrue(merged.createdPaths.isEmpty)
        XCTAssertEqual(merged.removedPaths, ["Projects/Plan.md"])
    }

    func testMergedChangesKeepCreationWhenCreatedPathIsLaterModified() {
        let first = VaultReloadChanges(createdPaths: ["Projects/Plan.md"])
        let second = VaultReloadChanges(modifiedPaths: ["Projects/Plan.md"])

        let merged = first.merged(with: second)

        XCTAssertTrue(merged.modifiedPaths.isEmpty)
        XCTAssertEqual(merged.createdPaths, ["Projects/Plan.md"])
        XCTAssertTrue(merged.removedPaths.isEmpty)
    }

    func testMergedChangesPropagateFullReloadRequirement() {
        let first = VaultReloadChanges(modifiedPaths: ["Projects/Plan.md"])
        let second = VaultReloadChanges(requiresFullReload: true)

        let merged = first.merged(with: second)

        XCTAssertTrue(merged.requiresFullReload)
    }
}
