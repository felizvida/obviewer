import AppKit
import Foundation
import ObviewerCore
import ObviewerReaderKit
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published private(set) var snapshot: VaultSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isLiveReloadEnabled = false
    @Published private(set) var loadingProgress: VaultLoadingProgress?
    @Published private(set) var indexDiagnostics: VaultIndexDiagnostics?
    @Published private(set) var readingInput: ReadingInputSource?
    @Published private(set) var readingProfile: ReadingProfile = .obsidian
    @Published public private(set) var vaultURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingAnchor = PendingAnchor.none
    @Published var detailMode: DetailMode = .reader
    @Published var graphScope: GraphScope = .local
    @Published var selectedNoteID: String? {
        didSet { recordHistory(from: oldValue) }
    }
    @Published var searchText = ""

    // Reader state (web renderer).
    @Published var backStack = [String]()
    @Published var forwardStack = [String]()
    /// Bumped after every (re)load so the reader re-renders even when the selected note is unchanged.
    @Published private(set) var renderRevision = 0
    @Published var readerNotice: ReaderNotice?
    @Published var pendingExternalOpen: ExternalOpenRequest?
    @Published var needsFolderAccess = false
    @Published var isFindBarVisible = false
    @Published var findQuery = ""
    @Published var findMatched = true
    /// Headings of the rendered note, for the Outline menus.
    @Published var outlineHeadings = [ReaderHeading]()

    var isRestoringHistory = false
    var readerRenderTask: Task<Void, Never>?
    var fileWatchSession: (any VaultWatchSession)?
    private var readerControllerStorage: ReaderWebController?
    let fileWatcher: any SingleFileWatching
    private let recordRecent: ((URL) -> Void)?

    private let bookmarkStore: any VaultBookmarkStoring
    private let picker: any VaultChoosing
    private let inputAdapter: any ReadingInputAdapting
    private let inputLoader: any ReadingInputLoading
    private let securityScopeManager: any SecurityScopeManaging
    private let noteCache: any VaultNoteCaching
    private let watcher: any VaultWatching

    private var didAttemptRestore = false
    private var didConsumeLaunchInput = false
    private var watchSession: (any VaultWatchSession)?
    private var pendingWatchedChanges = VaultReloadChanges.none
    private var loadGeneration = 0

    public convenience init() {
        self.init(
            bookmarkStore: BookmarkStore(),
            picker: VaultPicker(),
            reader: VaultReadingInputLoader(),
            securityScopeManager: SecurityScopedAccessController(),
            noteCache: VaultNoteCacheStore(),
            watcher: VaultWatcher(),
            fileWatcher: SingleFileWatcher(),
            recordRecent: { RecentItemsStore.shared.record($0) }
        )
    }

    convenience init(
        bookmarkStore: any VaultBookmarkStoring,
        picker: any VaultChoosing,
        reader: any VaultLoading,
        securityScopeManager: any SecurityScopeManaging,
        noteCache: any VaultNoteCaching = NullVaultNoteCache(),
        watcher: (any VaultWatching)? = nil,
        inputAdapter: any ReadingInputAdapting = DefaultReadingInputAdapter(),
        fileWatcher: (any SingleFileWatching)? = nil
    ) {
        self.init(
            bookmarkStore: bookmarkStore,
            picker: picker,
            reader: VaultLoadingInputLoader(vaultLoader: reader),
            securityScopeManager: securityScopeManager,
            noteCache: noteCache,
            watcher: watcher,
            inputAdapter: inputAdapter,
            fileWatcher: fileWatcher
        )
    }

    init(
        bookmarkStore: any VaultBookmarkStoring,
        picker: any VaultChoosing,
        reader: any ReadingInputLoading,
        securityScopeManager: any SecurityScopeManaging,
        noteCache: any VaultNoteCaching = NullVaultNoteCache(),
        watcher: (any VaultWatching)? = nil,
        inputAdapter: any ReadingInputAdapting = DefaultReadingInputAdapter(),
        fileWatcher: (any SingleFileWatching)? = nil,
        recordRecent: ((URL) -> Void)? = nil
    ) {
        self.fileWatcher = fileWatcher ?? SingleFileWatcher()
        self.recordRecent = recordRecent
        self.bookmarkStore = bookmarkStore
        self.picker = picker
        self.inputLoader = reader
        self.inputAdapter = inputAdapter
        self.securityScopeManager = securityScopeManager
        self.noteCache = noteCache
        self.watcher = watcher ?? VaultWatcher()
    }

    /// The window's web reader, created on first use so tests and the classic view never spin up WebKit.
    var reader: ReaderWebController {
        if let readerControllerStorage {
            return readerControllerStorage
        }
        let controller = ReaderWebController()
        controller.onEvent = { [weak self] event in
            self?.handleReaderEvent(event)
        }
        readerControllerStorage = controller
        return controller
    }

    var hasReader: Bool { readerControllerStorage != nil }

    var filteredNotes: [VaultNote] {
        guard let snapshot else { return [] }
        return snapshot.searchNotes(matching: searchText)
    }

    var noteSections: [NoteListSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filteredNotes.isEmpty == false else { return [] }

        if query.isEmpty == false {
            return [
                NoteListSection(title: "Results", notes: filteredNotes),
            ]
        }

        let grouped = Dictionary(grouping: filteredNotes) { note in
            note.folderPath.isEmpty ? "Vault Root" : note.folderPath
        }

        return grouped.keys.sorted { lhs, rhs in
            if lhs == "Vault Root" { return true }
            if rhs == "Vault Root" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.map { key in
            NoteListSection(title: key, notes: grouped[key] ?? [])
        }
    }

    var selectedNote: VaultNote? {
        guard let snapshot else { return nil }
        guard let selectedNoteID else { return snapshot.notes.first }
        return snapshot.note(withID: selectedNoteID) ?? snapshot.notes.first
    }

    var selectedGraphNode: NoteGraphNode? {
        guard let snapshot, let selectedNoteID else { return nil }
        return snapshot.noteGraph.node(withID: selectedNoteID)
    }

    var graphHighlightedNoteIDs: Set<String> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return selectedNoteID.map { [$0] } ?? []
        }
        return Set(filteredNotes.map(\.id))
    }

    var graphSubgraph: NoteGraphSubgraph? {
        guard let snapshot else { return nil }

        switch graphScope {
        case .local:
            if let selectedNoteID {
                return snapshot.noteGraph.localSubgraph(
                    around: selectedNoteID,
                    highlightedIDs: graphHighlightedNoteIDs
                )
            }

            return snapshot.noteGraph.globalSubgraph(
                visibleNoteIDs: Set(snapshot.notes.map(\.id)),
                highlightedIDs: graphHighlightedNoteIDs,
                centerNodeID: nil
            )

        case .global:
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            var visibleNoteIDs = query.isEmpty
                ? Set(snapshot.notes.map(\.id))
                : Set(filteredNotes.map(\.id))
            if let selectedNoteID {
                visibleNoteIDs.insert(selectedNoteID)
            }

            return snapshot.noteGraph.globalSubgraph(
                visibleNoteIDs: visibleNoteIDs,
                highlightedIDs: graphHighlightedNoteIDs,
                centerNodeID: selectedNoteID
            )
        }
    }

    public func restoreVaultIfNeeded() async {
        guard didAttemptRestore == false else { return }
        didAttemptRestore = true

        do {
            guard let restoredURL = try bookmarkStore.restore() else {
                return
            }

            await loadVault(
                input: inputAdapter.makeInputSource(for: restoredURL, preferredProfile: nil),
                persistBookmark: false,
                previousSnapshot: snapshot,
                changes: nil,
                restartWatcher: true
            )
        } catch {
            errorMessage = error.localizedDescription
            snapshot = nil
            indexDiagnostics = nil
            readingInput = nil
            vaultURL = nil
            selectedNoteID = nil
            stopWatchingVault()
            return
        }
    }

    /// Call when a Finder open request supersedes restoring the last vault.
    public func markRestoreHandled() {
        didAttemptRestore = true
    }

    public func chooseVault() async {
        guard let url = picker.chooseVault() else { return }
        await open(url, preferredProfile: nil, persistBookmark: true)
    }

    public func openLaunchInputOrRestore(_ request: LaunchReadingInputRequest?) async {
        if let request {
            guard didConsumeLaunchInput == false else { return }
            didConsumeLaunchInput = true
            didAttemptRestore = true
            await open(
                request.url,
                preferredProfile: request.preferredProfile,
                persistBookmark: true
            )
            return
        }

        await restoreVaultIfNeeded()
    }

    public func open(
        _ url: URL,
        preferredProfile: ReadingProfile? = nil,
        persistBookmark: Bool = true
    ) async {
        let input = inputAdapter.makeInputSource(for: url, preferredProfile: preferredProfile)
        await open(input, persistBookmark: persistBookmark)
    }

    public func open(
        _ input: ReadingInputSource,
        persistBookmark: Bool = true
    ) async {
        await loadVault(
            input: input,
            persistBookmark: persistBookmark,
            previousSnapshot: readingInput == input ? snapshot : nil,
            changes: nil,
            restartWatcher: true
        )
    }

    public func reloadVault() async {
        guard let readingInput else { return }
        await loadVault(
            input: readingInput,
            persistBookmark: false,
            previousSnapshot: snapshot,
            changes: nil,
            restartWatcher: false
        )
    }

    func dismissError() {
        errorMessage = nil
    }

    func select(tag: String) {
        searchText = "#\(tag)"
    }

    func setPendingAnchor(noteID: String, anchor: String) {
        pendingAnchor = PendingAnchor(noteID: noteID, anchor: anchor)
    }

    func pendingAnchor(for noteID: String) -> String? {
        pendingAnchor.noteID == noteID ? pendingAnchor.anchor : nil
    }

    func clearPendingAnchor(for noteID: String) {
        if pendingAnchor.noteID == noteID {
            pendingAnchor = .none
        }
    }

    private func loadVault(
        input: ReadingInputSource,
        persistBookmark: Bool,
        previousSnapshot: VaultSnapshot?,
        changes: VaultReloadChanges?,
        restartWatcher: Bool
    ) async {
        loadGeneration += 1
        let currentLoadGeneration = loadGeneration
        isLoading = true
        loadingProgress = VaultLoadingProgress(
            processedFileCount: 0,
            noteCount: 0,
            attachmentCount: 0,
            currentPath: nil
        )
        errorMessage = nil
        let previousSelection = selectedNoteID
        pendingAnchor = .none

        securityScopeManager.activate(url: input.url)

        do {
            let progressStream = AsyncStream.makeStream(of: VaultLoadingProgress.self)
            let progressContinuation = progressStream.continuation

            let progressTask = Task { @MainActor [weak self] in
                for await progress in progressStream.stream {
                    self?.loadingProgress = progress
                }
            }
            defer {
                progressTask.cancel()
            }

            let snapshot = try await Task.detached(priority: .userInitiated) {
                [inputLoader, noteCache, input, progressContinuation, previousSnapshot, changes]
                in
                defer {
                    progressContinuation.finish()
                }

                let seedSnapshot = previousSnapshot ?? (
                    input.kind == .folder ? noteCache.loadSeedSnapshot(for: input.url) : nil
                )
                return try inputLoader.reloadInput(
                    input,
                    previousSnapshot: seedSnapshot,
                    changes: changes
                ) { progress in
                    progressContinuation.yield(progress)
                }
            }.value

            guard isCurrentLoad(currentLoadGeneration) else {
                return
            }

            if persistBookmark {
                try bookmarkStore.save(url: input.url)
            }

            if input.kind == .folder {
                noteCache.saveSeedSnapshot(snapshot)
            }

            if readingInput?.url != input.url {
                isRestoringHistory = true
                backStack = []
                forwardStack = []
                needsFolderAccess = false
                recordRecent?(input.url)
            }
            self.snapshot = snapshot
            indexDiagnostics = snapshot.indexDiagnostics(topFolderCount: 3)
            // The focus applies to this load only; later reloads keep the user's selection.
            readingInput = input.with(focus: nil)
            readingProfile = input.profile
            vaultURL = input.rootURL
            if let focusRelativePath = input.focusRelativePath,
               snapshot.note(withID: focusRelativePath) != nil {
                selectedNoteID = focusRelativePath
            } else if let previousSelection, snapshot.note(withID: previousSelection) != nil {
                selectedNoteID = previousSelection
            } else {
                selectedNoteID = snapshot.notes.first?.id
            }

            isRestoringHistory = false
            renderRevision += 1

            if restartWatcher || (watchSession == nil && fileWatchSession == nil) {
                if let watchURL = input.watchURL {
                    stopWatchingFile()
                    startWatchingVault(at: watchURL)
                } else if let fileURL = input.watchedFileURL {
                    stopWatchingVault()
                    startWatchingFile(at: fileURL)
                } else {
                    stopWatchingVault()
                }
            }
        } catch {
            guard isCurrentLoad(currentLoadGeneration) else {
                return
            }
            errorMessage = error.localizedDescription
        }

        guard isCurrentLoad(currentLoadGeneration) else {
            return
        }

        isLoading = false
        loadingProgress = nil

        if pendingWatchedChanges.isEmpty == false {
            guard let readingInput else { return }
            let queuedChanges = pendingWatchedChanges
            pendingWatchedChanges = .none
            await loadVault(
                input: readingInput,
                persistBookmark: false,
                previousSnapshot: snapshot,
                changes: queuedChanges,
                restartWatcher: false
            )
        }
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration
    }

    private func startWatchingVault(at url: URL) {
        watchSession?.invalidate()
        pendingWatchedChanges = .none
        watchSession = watcher.beginWatching(url: url) { [weak self] changes in
            Task { @MainActor [weak self] in
                await self?.handleWatchedVaultChange(changes)
            }
        }
        isLiveReloadEnabled = true
    }

    private func stopWatchingVault() {
        watchSession?.invalidate()
        watchSession = nil
        isLiveReloadEnabled = fileWatchSession != nil
        pendingWatchedChanges = .none
    }

    /// Stops folder watching when a window closes (its model may outlive the window briefly).
    func stopWatchingForWindowClose() {
        stopWatchingVault()
    }

    func setLiveReloadEnabled(_ enabled: Bool) {
        isLiveReloadEnabled = enabled
    }

    /// Reloads after the watched single file changed on disk (e.g. saved in an external editor).
    func handleWatchedFileChange() async {
        guard let readingInput, readingInput.kind == .markdownFile else { return }
        guard isLoading == false else {
            pendingWatchedChanges = pendingWatchedChanges.merged(with: VaultReloadChanges(modifiedPaths: [readingInput.url.lastPathComponent]))
            return
        }
        await loadVault(
            input: readingInput,
            persistBookmark: false,
            previousSnapshot: snapshot,
            changes: nil,
            restartWatcher: false
        )
    }

    private func handleWatchedVaultChange(_ changes: VaultReloadChanges) async {
        guard let readingInput else { return }
        guard isLoading == false else {
            pendingWatchedChanges = pendingWatchedChanges.merged(with: changes)
            return
        }

        await loadVault(
            input: readingInput,
            persistBookmark: false,
            previousSnapshot: snapshot,
            changes: changes,
            restartWatcher: false
        )
    }

}

struct NoteListSection: Identifiable {
    let title: String
    let notes: [VaultNote]

    var id: String { title }
}

struct PendingAnchor: Equatable {
    let noteID: String?
    let anchor: String?

    static let none = PendingAnchor(noteID: nil, anchor: nil)
}

enum DetailMode: String, CaseIterable, Identifiable {
    case reader = "Reader"
    case graph = "Graph"

    var id: Self { self }
}

enum GraphScope: String, CaseIterable, Identifiable {
    case local = "Local"
    case global = "Global"

    var id: Self { self }
}
