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
                .fixture(
                    relativePath: "Projects/Daily.md",
                    title: "Daily",
                    tags: ["journal"],
                    modifiedAt: Date(timeIntervalSince1970: 1_236)
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
        XCTAssertEqual(restored.indexManifest, snapshot.indexManifest)
        XCTAssertEqual(restored.persistentIndex, snapshot.persistentIndex)
    }

    func testCacheStoreRoundTripsVeryLongVaultPathUsingBoundedFilename() throws {
        let sandbox = try TemporaryCacheDirectory()
        defer { sandbox.cleanup() }

        let store = VaultNoteCacheStore(cachesRootURL: sandbox.rootURL)
        let longComponent = String(repeating: "deep-folder-", count: 30)
        let vaultURL = URL(fileURLWithPath: "/tmp/\(longComponent)/vault")
        let snapshot = VaultSnapshot(
            rootURL: vaultURL,
            notes: [
                .fixture(
                    relativePath: "Projects/Plan.md",
                    title: "Plan",
                    tags: ["roadmap"],
                    modifiedAt: Date(timeIntervalSince1970: 1_234)
                ),
            ],
            attachments: []
        )

        store.saveSeedSnapshot(snapshot)

        let cacheFiles = try FileManager.default.contentsOfDirectory(
            at: sandbox.rootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(cacheFiles.count, 1)
        XCTAssertLessThan(cacheFiles[0].lastPathComponent.count, 100)

        let restored = try XCTUnwrap(store.loadSeedSnapshot(for: vaultURL))
        XCTAssertEqual(restored.notes, snapshot.notes)
        XCTAssertEqual(restored.indexManifest, snapshot.indexManifest)
        XCTAssertEqual(restored.persistentIndex, snapshot.persistentIndex)
    }

    func testCacheStoreDropsCorruptPayloads() throws {
        let sandbox = try TemporaryCacheDirectory()
        defer { sandbox.cleanup() }

        let store = VaultNoteCacheStore(cachesRootURL: sandbox.rootURL)
        let vaultURL = URL(fileURLWithPath: "/tmp/obviewer-tests/vault")
        let snapshot = VaultSnapshot(rootURL: vaultURL, notes: [], attachments: [])
        store.saveSeedSnapshot(snapshot)
        let cacheFileURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: sandbox.rootURL,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("not a plist".utf8).write(to: cacheFileURL)

        XCTAssertNil(store.loadSeedSnapshot(for: vaultURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFileURL.path))
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
