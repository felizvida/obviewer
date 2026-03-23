import Foundation
import ObviewerCore
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published private(set) var snapshot: VaultSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isLiveReloadEnabled = false
    @Published private(set) var loadingProgress: VaultLoadingProgress?
    @Published public private(set) var vaultURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingAnchor = PendingAnchor.none
    @Published var detailMode: DetailMode = .reader
    @Published var graphScope: GraphScope = .local
    @Published var selectedNoteID: String?
    @Published var searchText = ""

    private let bookmarkStore: any VaultBookmarkStoring
    private let picker: any VaultChoosing
    private let reader: any VaultLoading
    private let securityScopeManager: any SecurityScopeManaging
    private let noteCache: any VaultNoteCaching
    private let watcher: any VaultWatching

    private var didAttemptRestore = false
    private var watchSession: (any VaultWatchSession)?
    private var pendingWatchedChanges = VaultReloadChanges.none

    public convenience init() {
        self.init(
            bookmarkStore: BookmarkStore(),
            picker: VaultPicker(),
            reader: VaultReader(),
            securityScopeManager: SecurityScopedAccessController(),
            noteCache: VaultNoteCacheStore(),
            watcher: VaultWatcher()
        )
    }

    init(
        bookmarkStore: any VaultBookmarkStoring,
        picker: any VaultChoosing,
        reader: any VaultLoading,
        securityScopeManager: any SecurityScopeManaging,
        noteCache: any VaultNoteCaching = NullVaultNoteCache(),
        watcher: (any VaultWatching)? = nil
    ) {
        self.bookmarkStore = bookmarkStore
        self.picker = picker
        self.reader = reader
        self.securityScopeManager = securityScopeManager
        self.noteCache = noteCache
        self.watcher = watcher ?? VaultWatcher()
    }

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
                from: restoredURL,
                persistBookmark: false,
                previousSnapshot: snapshot,
                changes: nil,
                restartWatcher: true
            )
        } catch {
            errorMessage = error.localizedDescription
            snapshot = nil
            vaultURL = nil
            selectedNoteID = nil
            stopWatchingVault()
            return
        }
    }

    public func chooseVault() async {
        guard let url = picker.chooseVault() else { return }
        await loadVault(
            from: url,
            persistBookmark: true,
            previousSnapshot: snapshot?.rootURL == url ? snapshot : nil,
            changes: nil,
            restartWatcher: true
        )
    }

    public func reloadVault() async {
        guard let vaultURL else { return }
        await loadVault(
            from: vaultURL,
            persistBookmark: false,
            previousSnapshot: snapshot,
            changes: nil,
            restartWatcher: false
        )
    }

    func dismissError() {
        errorMessage = nil
    }

    func navigate(to linkTarget: String, anchor: String? = nil, from sourceNoteID: String? = nil) {
        guard let snapshot else { return }
        guard let noteID = snapshot.resolveNoteID(for: linkTarget, from: sourceNoteID) else { return }
        selectedNoteID = noteID
        if let anchor, anchor.isEmpty == false {
            pendingAnchor = PendingAnchor(noteID: noteID, anchor: anchor)
        } else {
            pendingAnchor = .none
        }
    }

    func select(tag: String) {
        searchText = "#\(tag)"
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
        from url: URL,
        persistBookmark: Bool,
        previousSnapshot: VaultSnapshot?,
        changes: VaultReloadChanges?,
        restartWatcher: Bool
    ) async {
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

        securityScopeManager.activate(url: url)

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
                [reader, noteCache, url, progressContinuation, previousSnapshot, changes]
                in
                defer {
                    progressContinuation.finish()
                }

                let seedSnapshot = previousSnapshot ?? noteCache.loadSeedSnapshot(for: url)
                return try reader.reloadVault(
                    at: url,
                    previousSnapshot: seedSnapshot,
                    changes: changes
                ) { progress in
                    progressContinuation.yield(progress)
                }
            }.value

            if persistBookmark {
                try bookmarkStore.save(url: url)
            }

            noteCache.saveSeedSnapshot(snapshot)

            self.snapshot = snapshot
            vaultURL = url
            if let previousSelection, snapshot.note(withID: previousSelection) != nil {
                selectedNoteID = previousSelection
            } else {
                selectedNoteID = snapshot.notes.first?.id
            }

            if restartWatcher || watchSession == nil {
                startWatchingVault(at: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        loadingProgress = nil

        if pendingWatchedChanges.isEmpty == false, let vaultURL {
            let queuedChanges = pendingWatchedChanges
            pendingWatchedChanges = .none
            await loadVault(
                from: vaultURL,
                persistBookmark: false,
                previousSnapshot: snapshot,
                changes: queuedChanges,
                restartWatcher: false
            )
        }
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
        isLiveReloadEnabled = false
        pendingWatchedChanges = .none
    }

    private func handleWatchedVaultChange(_ changes: VaultReloadChanges) async {
        guard let vaultURL else { return }
        guard isLoading == false else {
            pendingWatchedChanges = pendingWatchedChanges.merged(with: changes)
            return
        }

        await loadVault(
            from: vaultURL,
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
