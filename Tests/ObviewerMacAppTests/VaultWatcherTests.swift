import Foundation
import XCTest
@testable import ObviewerMacApp
import ObviewerCore

/// Exercises the real file-system watcher. Editors save in two ways and both must
/// trigger a reload: in place (Sublime Text's default) and atomic replace.
final class VaultWatcherTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try "# Original\n".write(to: rootURL.appendingPathComponent("folder/Note.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func testInPlaceSaveIsReported() async throws {
        try await assertChangeReported(for: "folder/Note.md") { url in
            // Overwrite the existing file's bytes without replacing the file (no directory change).
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data("# Edited in place\n".utf8))
            try handle.close()
        }
    }

    @MainActor
    func testAtomicReplaceIsReported() async throws {
        try await assertChangeReported(for: "folder/Note.md") { url in
            try "# Replaced atomically\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    func testNewFileIsReported() async throws {
        try await assertChangeReported(for: "folder/New.md") { url in
            try "# New\n".write(to: url, atomically: false, encoding: .utf8)
        }
    }

    @MainActor
    private func assertChangeReported(
        for relativePath: String,
        change: @escaping (URL) throws -> Void
    ) async throws {
        let reported = expectation(description: "change reported for \(relativePath)")
        reported.assertForOverFulfill = false
        let recorder = ChangeRecorder()
        let session = VaultWatcher().beginWatching(url: rootURL) { changes in
            recorder.append(changes)
            if changes.affectedPaths.contains(relativePath) {
                reported.fulfill()
            }
        }
        defer { session.invalidate() }

        // Let the watchers start, and make sure the new modification date differs.
        try await Task.sleep(for: .milliseconds(600))
        try change(rootURL.appendingPathComponent(relativePath))

        await fulfillment(of: [reported], timeout: 5)
        XCTAssertTrue(recorder.affectedPaths.contains(relativePath), "Reported: \(recorder.affectedPaths)")
    }
}

private final class ChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths = Set<String>()

    func append(_ changes: VaultReloadChanges) {
        lock.lock()
        paths.formUnion(changes.affectedPaths)
        lock.unlock()
    }

    var affectedPaths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
}
