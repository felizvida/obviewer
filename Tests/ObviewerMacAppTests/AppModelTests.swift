import Foundation
import XCTest
@testable import ObviewerCore
@testable import ObviewerMacApp
import ObviewerFixtureSupport

final class AppModelTests: XCTestCase {
    @MainActor
    func testChooseVaultDoesNothingWhenPickerReturnsNil() async {
        let bookmarkStore = BookmarkStoreSpy()
        let loader = VaultLoaderSpy(result: .success(makeSnapshot()))
        let securityScope = SecurityScopeSpy()
        let model = AppModel(
            bookmarkStore: bookmarkStore,
            picker: VaultPickerStub(url: nil),
            reader: loader,
            securityScopeManager: securityScope
        )

        await model.chooseVault()

        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.vaultURL)
        XCTAssertTrue(bookmarkStore.savedURLs.isEmpty)
        XCTAssertTrue(loader.recordedURLs.isEmpty)
        XCTAssertTrue(securityScope.activatedURLs.isEmpty)
    }

    @MainActor
    func testChooseVaultLoadsSnapshotPersistsBookmarkAndActivatesScope() async {
        let vaultURL = URL(fileURLWithPath: "/tmp/obviewer-tests/vault")
        let snapshot = makeSnapshot()
        let bookmarkStore = BookmarkStoreSpy()
        let picker = VaultPickerStub(url: vaultURL)
        let loader = VaultLoaderSpy(result: .success(snapshot))
        let securityScope = SecurityScopeSpy()
        let model = AppModel(
            bookmarkStore: bookmarkStore,
            picker: picker,
            reader: loader,
            securityScopeManager: securityScope
        )

        await model.chooseVault()

        XCTAssertEqual(model.vaultURL, vaultURL)
        XCTAssertEqual(model.selectedNoteID, snapshot.notes.first?.id)
        XCTAssertEqual(bookmarkStore.savedURLs, [vaultURL])
        XCTAssertEqual(securityScope.activatedURLs, [vaultURL])
        XCTAssertEqual(loader.recordedURLs, [vaultURL])
    }

    @MainActor
    func testRestoreVaultLoadsOnlyOnce() async {
        let vaultURL = URL(fileURLWithPath: "/tmp/obviewer-tests/restored")
        let bookmarkStore = BookmarkStoreSpy(restoredURL: vaultURL)
        let loader = VaultLoaderSpy(result: .success(makeSnapshot()))
        let model = AppModel(
            bookmarkStore: bookmarkStore,
            picker: VaultPickerStub(url: nil),
            reader: loader,
            securityScopeManager: SecurityScopeSpy()
        )

        await model.restoreVaultIfNeeded()
        await model.restoreVaultIfNeeded()

        XCTAssertEqual(loader.recordedURLs, [vaultURL])
        XCTAssertTrue(bookmarkStore.savedURLs.isEmpty)
    }

    @MainActor
    func testRestoreVaultDoesNothingWhenNoBookmarkExists() async {
        let loader = VaultLoaderSpy(result: .success(makeSnapshot()))
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(restoredURL: nil),
            picker: VaultPickerStub(url: nil),
            reader: loader,
            securityScopeManager: SecurityScopeSpy()
        )

        await model.restoreVaultIfNeeded()

        XCTAssertNil(model.snapshot)
        XCTAssertTrue(loader.recordedURLs.isEmpty)
    }

    @MainActor
    func testRestoreVaultFailureSurfacesErrorAndSkipsLoading() async {
        let bookmarkStore = BookmarkStoreSpy(restoreError: FixtureError.sample)
        let loader = VaultLoaderSpy(result: .success(makeSnapshot()))
        let model = AppModel(
            bookmarkStore: bookmarkStore,
            picker: VaultPickerStub(url: nil),
            reader: loader,
            securityScopeManager: SecurityScopeSpy()
        )

        await model.restoreVaultIfNeeded()

        XCTAssertEqual(model.errorMessage, FixtureError.sample.localizedDescription)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.vaultURL)
        XCTAssertNil(model.selectedNoteID)
        XCTAssertTrue(loader.recordedURLs.isEmpty)
    }

    @MainActor
    func testNavigateStoresPendingAnchorForResolvedNote() async {
        let snapshot = makeSnapshot()
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.navigate(to: "Plan", anchor: "details", from: "Journal/Today.md")

        XCTAssertEqual(model.selectedNoteID, "Projects/Plan.md")
        XCTAssertEqual(model.pendingAnchor(for: "Projects/Plan.md"), "details")
    }

    @MainActor
    func testNavigateToMissingNoteLeavesSelectionUnchanged() async {
        let snapshot = makeSnapshot()
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        let originalSelection = model.selectedNoteID

        model.navigate(to: "Missing Note", anchor: "details", from: "Journal/Today.md")

        XCTAssertEqual(model.selectedNoteID, originalSelection)
        XCTAssertNil(originalSelection.flatMap { model.pendingAnchor(for: $0) })
    }

    @MainActor
    func testSearchAndSectionsSupportTagFilteringAndFolderGrouping() async {
        let snapshot = makeSnapshot()
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.select(tag: "research")

        XCTAssertEqual(model.searchText, "#research")
        XCTAssertEqual(model.filteredNotes.map(\.id), ["Journal/Today.md"])

        model.searchText = ""
        XCTAssertEqual(model.noteSections.map(\.title), ["Vault Root", "Journal", "Projects"])
    }

    @MainActor
    func testSearchMatchesTitlePathAndPreviewText() async {
        let snapshot = VaultSnapshot(
            rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests/vault"),
            notes: [
                .fixture(
                    relativePath: "Root.md",
                    title: "Root",
                    tags: ["home"],
                    previewText: "Vault home screen",
                    modifiedAt: .distantPast
                ),
                .fixture(
                    relativePath: "Projects/Plan.md",
                    title: "Launch Plan",
                    tags: ["roadmap"],
                    previewText: "Ship the root handoff checklist",
                    modifiedAt: .distantPast
                ),
            ],
            attachments: []
        )
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()

        model.searchText = "launch"
        XCTAssertEqual(model.filteredNotes.map(\.id), ["Projects/Plan.md"])

        model.searchText = "projects/plan"
        XCTAssertEqual(model.filteredNotes.map(\.id), ["Projects/Plan.md"])

        model.searchText = "root"
        XCTAssertEqual(Set(model.filteredNotes.map(\.id)), ["Root.md", "Projects/Plan.md"])
    }

    @MainActor
    func testGraphSubgraphTracksLocalAndGlobalModes() async throws {
        let snapshot = makeSnapshot()
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.selectedNoteID = "Projects/Plan.md"
        model.graphScope = .local

        let localSubgraph = try XCTUnwrap(model.graphSubgraph)
        XCTAssertEqual(localSubgraph.centerNodeID, "Projects/Plan.md")
        XCTAssertEqual(
            Set(localSubgraph.nodes.map(\.id)),
            ["Root.md", "Journal/Today.md", "Projects/Plan.md"]
        )

        model.graphScope = .global
        model.searchText = "#research"

        let globalSubgraph = try XCTUnwrap(model.graphSubgraph)
        XCTAssertEqual(
            Set(globalSubgraph.nodes.map(\.id)),
            ["Journal/Today.md", "Projects/Plan.md"]
        )
        XCTAssertEqual(globalSubgraph.highlightedNodeIDs, ["Journal/Today.md"])
        XCTAssertEqual(globalSubgraph.centerNodeID, "Projects/Plan.md")
    }

    @MainActor
    func testGraphStateUsesSelectionWhenSearchIsEmpty() async throws {
        let snapshot = makeSnapshot()
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.selectedNoteID = "Projects/Plan.md"

        let selectedGraphNode = try XCTUnwrap(model.selectedGraphNode)
        XCTAssertEqual(selectedGraphNode.id, "Projects/Plan.md")
        XCTAssertEqual(model.graphHighlightedNoteIDs, ["Projects/Plan.md"])
    }

    @MainActor
    func testReloadVaultKeepsExistingSelectionWhenNoteStillExists() async {
        let vaultURL = URL(fileURLWithPath: "/tmp/obviewer-tests/vault")
        let firstSnapshot = makeSnapshot()
        let secondSnapshot = makeSnapshot(
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let loader = VaultLoaderSpy(results: [
            .success(firstSnapshot),
            .success(secondSnapshot),
        ])
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: vaultURL),
            reader: loader,
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.selectedNoteID = "Projects/Plan.md"

        await model.reloadVault()

        XCTAssertEqual(model.selectedNoteID, "Projects/Plan.md")
        XCTAssertEqual(loader.recordedURLs, [vaultURL, vaultURL])
    }

    @MainActor
    func testReloadVaultFallsBackToFirstNoteWhenPreviousSelectionDisappears() async {
        let vaultURL = URL(fileURLWithPath: "/tmp/obviewer-tests/vault")
        let firstSnapshot = makeSnapshot()
        let secondSnapshot = VaultSnapshot(
            rootURL: vaultURL,
            notes: [
                .fixture(
                    relativePath: "Archive/Replacement.md",
                    title: "Replacement",
                    tags: ["archive"],
                    modifiedAt: Date(timeIntervalSince1970: 3_000)
                ),
            ],
            attachments: []
        )
        let loader = VaultLoaderSpy(results: [
            .success(firstSnapshot),
            .success(secondSnapshot),
        ])
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: vaultURL),
            reader: loader,
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.selectedNoteID = "Projects/Plan.md"

        await model.reloadVault()

        XCTAssertEqual(model.selectedNoteID, "Archive/Replacement.md")
    }

    @MainActor
    func testReloadVaultDoesNothingWhenNoVaultIsLoaded() async {
        let loader = VaultLoaderSpy(result: .success(makeSnapshot()))
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: nil),
            reader: loader,
            securityScopeManager: SecurityScopeSpy()
        )

        await model.reloadVault()

        XCTAssertTrue(loader.recordedURLs.isEmpty)
        XCTAssertNil(model.snapshot)
    }

    @MainActor
    func testLoadFailureSurfacesErrorAndLeavesBookmarkUntouched() async {
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .failure(FixtureError.sample)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()

        XCTAssertEqual(model.errorMessage, FixtureError.sample.localizedDescription)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.snapshot)
    }

    @MainActor
    func testDismissErrorClearsErrorMessage() async {
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .failure(FixtureError.sample)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        XCTAssertEqual(model.errorMessage, FixtureError.sample.localizedDescription)

        model.dismissError()

        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testChooseVaultClearsLoadingProgressWhenFinished() async {
        let progress = [
            VaultLoadingProgress(processedFileCount: 1, noteCount: 1, attachmentCount: 0, currentPath: "Root.md"),
            VaultLoadingProgress(processedFileCount: 2, noteCount: 1, attachmentCount: 1, currentPath: "cover.png"),
        ]
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(makeSnapshot()), progressEvents: progress),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadingProgress)
        XCTAssertNotNil(model.snapshot)
    }

    @MainActor
    func testChooseVaultLoadsRealGeneratedVaultFromDisk() async throws {
        let fixture = try TemporaryDemoVault(profile: .smoke)
        defer { fixture.cleanup() }

        let bookmarkStore = BookmarkStoreSpy()
        let securityScope = SecurityScopeSpy()
        let model = AppModel(
            bookmarkStore: bookmarkStore,
            picker: VaultPickerStub(url: fixture.rootURL),
            reader: VaultReader(),
            securityScopeManager: securityScope
        )

        await model.chooseVault()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.vaultURL, fixture.rootURL)
        XCTAssertEqual(model.snapshot?.notes.count, fixture.manifest.noteCount)
        XCTAssertEqual(model.snapshot?.attachments.count, fixture.manifest.attachmentCount)
        XCTAssertEqual(model.selectedNoteID, fixture.manifest.homeNoteID)
        XCTAssertEqual(bookmarkStore.savedURLs, [fixture.rootURL])
        XCTAssertEqual(securityScope.activatedURLs, [fixture.rootURL])

        model.navigate(to: "Daily", from: fixture.manifest.alphaOverviewNoteID)

        XCTAssertEqual(model.selectedNoteID, fixture.manifest.alphaDailyNoteID)

        model.navigate(to: "Knowledge/Architecture/Index.md", anchor: "patterns")
        XCTAssertEqual(model.pendingAnchor(for: fixture.manifest.architectureIndexNoteID), "patterns")
        model.clearPendingAnchor(for: fixture.manifest.architectureIndexNoteID)
        XCTAssertNil(model.pendingAnchor(for: fixture.manifest.architectureIndexNoteID))

        model.searchText = "#alpha"
        XCTAssertTrue(model.filteredNotes.contains(where: { $0.id == fixture.manifest.alphaOverviewNoteID }))

        model.searchText = ""
        XCTAssertTrue(model.noteSections.contains(where: { $0.title == "Vault Root" }))
        XCTAssertTrue(model.noteSections.contains(where: { $0.title == "Projects/Alpha" }))
    }
}

@MainActor
private final class BookmarkStoreSpy: VaultBookmarkStoring {
    private(set) var savedURLs = [URL]()
    private let restoredURL: URL?
    private let restoreError: Error?

    init(restoredURL: URL? = nil, restoreError: Error? = nil) {
        self.restoredURL = restoredURL
        self.restoreError = restoreError
    }

    func save(url: URL) throws {
        savedURLs.append(url)
    }

    func restore() throws -> URL? {
        if let restoreError {
            throw restoreError
        }

        return restoredURL
    }
}

@MainActor
private struct VaultPickerStub: VaultChoosing {
    let url: URL?

    func chooseVault() -> URL? {
        url
    }
}

@MainActor
private final class SecurityScopeSpy: SecurityScopeManaging {
    private(set) var activatedURLs = [URL]()

    func activate(url: URL) {
        activatedURLs.append(url)
    }
}

private final class VaultLoaderSpy: @unchecked Sendable, VaultLoading {
    private let lock = NSLock()
    private var results: [Result<VaultSnapshot, Error>]
    private var urls = [URL]()
    private let progressEvents: [VaultLoadingProgress]

    init(result: Result<VaultSnapshot, Error>) {
        self.results = [result]
        self.progressEvents = []
    }

    init(results: [Result<VaultSnapshot, Error>]) {
        self.results = results
        self.progressEvents = []
    }

    init(result: Result<VaultSnapshot, Error>, progressEvents: [VaultLoadingProgress]) {
        self.results = [result]
        self.progressEvents = progressEvents
    }

    var recordedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    func loadVault(
        at url: URL,
        progress: (@Sendable (VaultLoadingProgress) -> Void)?
    ) throws -> VaultSnapshot {
        lock.lock()
        urls.append(url)
        let current = results.count > 1 ? results.removeFirst() : results[0]
        lock.unlock()
        progressEvents.forEach { progress?($0) }
        return try current.get()
    }
}

private enum FixtureError: LocalizedError {
    case sample

    var errorDescription: String? {
        "Fixture failure."
    }
}

private func makeSnapshot(modifiedAt: Date = .distantPast) -> VaultSnapshot {
    VaultSnapshot(
        rootURL: URL(fileURLWithPath: "/tmp/obviewer-tests/vault"),
        notes: [
            .fixture(
                relativePath: "Root.md",
                title: "Root",
                tags: ["home"],
                outboundLinks: ["Projects/Plan"],
                modifiedAt: modifiedAt
            ),
            .fixture(
                relativePath: "Journal/Today.md",
                title: "Today",
                tags: ["research"],
                outboundLinks: ["Projects/Plan"],
                modifiedAt: modifiedAt
            ),
            .fixture(
                relativePath: "Projects/Plan.md",
                title: "Plan",
                tags: ["roadmap"],
                outboundLinks: ["Root"],
                modifiedAt: modifiedAt
            ),
        ],
        attachments: [
            .fixture(relativePath: "Projects/manual.pdf", kind: .pdf),
        ]
    )
}

private extension VaultNote {
    static func fixture(
        relativePath: String,
        title: String,
        tags: [String],
        outboundLinks: [String] = [],
        previewText: String? = nil,
        modifiedAt: Date
    ) -> VaultNote {
        VaultNote(
            id: relativePath,
            title: title,
            relativePath: relativePath,
            folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                ? ""
                : (relativePath as NSString).deletingLastPathComponent,
            previewText: previewText ?? title,
            tags: tags,
            outboundLinks: outboundLinks,
            tableOfContents: [
                TableOfContentsItem(id: "details", level: 2, title: "Details"),
            ],
            blocks: [],
            wordCount: 42,
            readingTimeMinutes: 1,
            modifiedAt: modifiedAt
        )
    }
}

private extension VaultAttachment {
    static func fixture(relativePath: String, kind: Kind) -> VaultAttachment {
        VaultAttachment(
            relativePath: relativePath,
            url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault/\(relativePath)"),
            kind: kind
        )
    }
}
