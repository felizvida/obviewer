import Foundation
import Testing
@testable import ObviewerCore
@testable import ObviewerMacApp

@MainActor
struct AppModelTests {
    @Test
    func chooseVaultLoadsSnapshotPersistsBookmarkAndActivatesScope() async {
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

        #expect(model.vaultURL == vaultURL)
        #expect(model.selectedNoteID == snapshot.notes.first?.id)
        #expect(bookmarkStore.savedURLs == [vaultURL])
        #expect(securityScope.activatedURLs == [vaultURL])
        #expect(loader.recordedURLs == [vaultURL])
    }

    @Test
    func restoreVaultLoadsOnlyOnce() async {
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

        #expect(loader.recordedURLs == [vaultURL])
        #expect(bookmarkStore.savedURLs.isEmpty)
    }

    @Test
    func navigateStoresPendingAnchorForResolvedNote() async {
        let snapshot = makeSnapshot()
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.navigate(to: "Plan", anchor: "details", from: "Journal/Today.md")

        #expect(model.selectedNoteID == "Projects/Plan.md")
        #expect(model.pendingAnchor(for: "Projects/Plan.md") == "details")
    }

    @Test
    func searchAndSectionsSupportTagFilteringAndFolderGrouping() async {
        let snapshot = makeSnapshot()
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .success(snapshot)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()
        model.select(tag: "research")

        #expect(model.searchText == "#research")
        #expect(model.filteredNotes.map(\.id) == ["Journal/Today.md"])

        model.searchText = ""
        #expect(model.noteSections.map(\.title) == ["Vault Root", "Journal", "Projects"])
    }

    @Test
    func reloadVaultKeepsExistingSelectionWhenNoteStillExists() async {
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

        #expect(model.selectedNoteID == "Projects/Plan.md")
        #expect(loader.recordedURLs == [vaultURL, vaultURL])
    }

    @Test
    func loadFailureSurfacesErrorAndLeavesBookmarkUntouched() async {
        let model = AppModel(
            bookmarkStore: BookmarkStoreSpy(),
            picker: VaultPickerStub(url: URL(fileURLWithPath: "/tmp/obviewer-tests/vault")),
            reader: VaultLoaderSpy(result: .failure(FixtureError.sample)),
            securityScopeManager: SecurityScopeSpy()
        )

        await model.chooseVault()

        #expect(model.errorMessage == FixtureError.sample.localizedDescription)
        #expect(model.isLoading == false)
        #expect(model.snapshot == nil)
    }
}

@MainActor
private final class BookmarkStoreSpy: VaultBookmarkStoring {
    private(set) var savedURLs = [URL]()
    private let restoredURL: URL?

    init(restoredURL: URL? = nil) {
        self.restoredURL = restoredURL
    }

    func save(url: URL) throws {
        savedURLs.append(url)
    }

    func restore() throws -> URL? {
        restoredURL
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

    init(result: Result<VaultSnapshot, Error>) {
        self.results = [result]
    }

    init(results: [Result<VaultSnapshot, Error>]) {
        self.results = results
    }

    var recordedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    func loadVault(at url: URL) throws -> VaultSnapshot {
        lock.lock()
        urls.append(url)
        let current = results.count > 1 ? results.removeFirst() : results[0]
        lock.unlock()
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
            .fixture(relativePath: "Root.md", title: "Root", tags: ["home"], modifiedAt: modifiedAt),
            .fixture(relativePath: "Journal/Today.md", title: "Today", tags: ["research"], modifiedAt: modifiedAt),
            .fixture(relativePath: "Projects/Plan.md", title: "Plan", tags: ["roadmap"], modifiedAt: modifiedAt),
        ],
        attachments: [
            .fixture(relativePath: "Projects/manual.pdf", kind: .pdf),
        ]
    )
}

private extension VaultNote {
    static func fixture(relativePath: String, title: String, tags: [String], modifiedAt: Date) -> VaultNote {
        VaultNote(
            id: relativePath,
            title: title,
            relativePath: relativePath,
            folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                ? ""
                : (relativePath as NSString).deletingLastPathComponent,
            previewText: title,
            tags: tags,
            outboundLinks: [],
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
