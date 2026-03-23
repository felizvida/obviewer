import Foundation
import XCTest
@testable import ObviewerCore
@testable import ObviewerMacApp

final class VaultNoteCacheStoreTests: XCTestCase {
    func testCacheStoreRoundTripsSeedSnapshot() throws {
        let sandbox = try TemporaryCacheDirectory()
        defer { sandbox.cleanup() }

        let store = VaultNoteCacheStore(cachesRootURL: sandbox.rootURL)
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests/vault"),
            notes: [
                .fixture(
                    relativePath: "Projects/Plan.md",
                    title: "Plan",
                    tags: ["roadmap"],
                    modifiedAt: Date(timeIntervalSince1970: 1_234)
                ),
            ],
            attachments: [
                VaultAttachment(
                    relativePath: "Assets/cover.png",
                    url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault/Assets/cover.png"),
                    kind: .image,
                    modifiedAt: Date(timeIntervalSince1970: 1_235)
                ),
            ]
        )

        store.saveSeedSnapshot(snapshot)
        let restored = try XCTUnwrap(store.loadSeedSnapshot(for: snapshot.rootURL))

        XCTAssertEqual(restored.notes, snapshot.notes)
        XCTAssertEqual(restored.attachments, snapshot.attachments)
    }

    func testCacheStoreDropsCorruptPayloads() throws {
        let sandbox = try TemporaryCacheDirectory()
        defer { sandbox.cleanup() }

        let store = VaultNoteCacheStore(cachesRootURL: sandbox.rootURL)
        let vaultURL = URL(fileURLWithPath: "/tmp/obviewer-tests/vault")
        let cacheFileURL = sandbox.rootURL.appending(path: cacheKey(for: vaultURL) + ".plist")
        try FileManager.default.createDirectory(at: sandbox.rootURL, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: cacheFileURL)

        XCTAssertNil(store.loadSeedSnapshot(for: vaultURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFileURL.path))
    }

    private func cacheKey(for vaultURL: URL) -> String {
        let normalizedPath = vaultURL.standardizedFileURL.resolvingSymlinksInPath().path
        return Data(normalizedPath.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct TemporaryCacheDirectory {
    let rootURL: URL

    init() throws {
        let baseURL = FileManager.default.temporaryDirectory
        rootURL = baseURL.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private extension VaultNote {
    static func fixture(
        relativePath: String,
        title: String,
        tags: [String],
        modifiedAt: Date
    ) -> VaultNote {
        VaultNote(
            id: relativePath,
            title: title,
            relativePath: relativePath,
            folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                ? ""
                : (relativePath as NSString).deletingLastPathComponent,
            previewText: title,
            frontmatter: NoteFrontmatter(),
            tags: tags,
            outboundLinks: [],
            tableOfContents: [],
            blocks: [.paragraph(text: .plain("Body"))],
            wordCount: 1,
            readingTimeMinutes: 1,
            modifiedAt: modifiedAt
        )
    }
}
