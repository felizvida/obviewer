import Foundation
import ObviewerCore
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published private(set) var snapshot: VaultSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var loadingProgress: VaultLoadingProgress?
    @Published public private(set) var vaultURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingAnchor = PendingAnchor.none
    @Published var selectedNoteID: String?
    @Published var searchText = ""

    private let bookmarkStore: any VaultBookmarkStoring
    private let picker: any VaultChoosing
    private let reader: any VaultLoading
    private let securityScopeManager: any SecurityScopeManaging

    private var didAttemptRestore = false

    public convenience init() {
        self.init(
            bookmarkStore: BookmarkStore(),
            picker: VaultPicker(),
            reader: VaultReader(),
            securityScopeManager: SecurityScopedAccessController()
        )
    }

    init(
        bookmarkStore: any VaultBookmarkStoring,
        picker: any VaultChoosing,
        reader: any VaultLoading,
        securityScopeManager: any SecurityScopeManaging
    ) {
        self.bookmarkStore = bookmarkStore
        self.picker = picker
        self.reader = reader
        self.securityScopeManager = securityScopeManager
    }

    var filteredNotes: [VaultNote] {
        guard let snapshot else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return snapshot.notes }

        let normalizedQuery = query.lowercased()
        let normalizedTagQuery = normalizedQuery.hasPrefix("#")
            ? String(normalizedQuery.dropFirst())
            : normalizedQuery
        return snapshot.notes.filter { note in
            note.title.lowercased().contains(normalizedQuery)
                || note.relativePath.lowercased().contains(normalizedQuery)
                || note.tags.contains(where: { $0.localizedCaseInsensitiveContains(normalizedTagQuery) })
                || note.previewText.lowercased().contains(normalizedQuery)
        }
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

    public func restoreVaultIfNeeded() async {
        guard didAttemptRestore == false else { return }
        didAttemptRestore = true

        do {
            guard let restoredURL = try bookmarkStore.restore() else {
                return
            }

            await loadVault(from: restoredURL, persistBookmark: false)
        } catch {
            errorMessage = error.localizedDescription
            snapshot = nil
            vaultURL = nil
            selectedNoteID = nil
            return
        }
    }

    public func chooseVault() async {
        guard let url = picker.chooseVault() else { return }
        await loadVault(from: url, persistBookmark: true)
    }

    public func reloadVault() async {
        guard let vaultURL else { return }
        await loadVault(from: vaultURL, persistBookmark: false)
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

    private func loadVault(from url: URL, persistBookmark: Bool) async {
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

            let snapshot = try await Task.detached(priority: .userInitiated) { [reader, url, progressContinuation] in
                defer {
                    progressContinuation.finish()
                }

                return try reader.loadVault(at: url) { progress in
                    progressContinuation.yield(progress)
                }
            }.value

            if persistBookmark {
                try bookmarkStore.save(url: url)
            }

            self.snapshot = snapshot
            vaultURL = url
            if let previousSelection, snapshot.note(withID: previousSelection) != nil {
                selectedNoteID = previousSelection
            } else {
                selectedNoteID = snapshot.notes.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        loadingProgress = nil
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
