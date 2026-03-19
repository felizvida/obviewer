import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: VaultSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var vaultURL: URL?
    @Published private(set) var errorMessage: String?
    @Published var selectedNoteID: String?
    @Published var searchText = ""

    private let bookmarkStore = BookmarkStore()
    private let picker = VaultPicker()
    private let reader = VaultReader()

    private var activeScopedURL: URL?
    private var didAttemptRestore = false

    var filteredNotes: [VaultNote] {
        guard let snapshot else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return snapshot.notes }

        let normalizedQuery = query.lowercased()
        return snapshot.notes.filter { note in
            note.title.lowercased().contains(normalizedQuery)
                || note.relativePath.lowercased().contains(normalizedQuery)
                || note.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || note.previewText.lowercased().contains(normalizedQuery)
        }
    }

    var selectedNote: VaultNote? {
        guard let snapshot else { return nil }
        guard let selectedNoteID else { return snapshot.notes.first }
        return snapshot.note(withID: selectedNoteID) ?? snapshot.notes.first
    }

    func restoreVaultIfNeeded() async {
        guard didAttemptRestore == false else { return }
        didAttemptRestore = true

        guard let restoredURL = try? bookmarkStore.restore() else {
            return
        }

        guard let restoredURL else { return }
        await loadVault(from: restoredURL, persistBookmark: false)
    }

    func chooseVault() async {
        guard let url = picker.chooseVault() else { return }
        await loadVault(from: url, persistBookmark: true)
    }

    func reloadVault() async {
        guard let vaultURL else { return }
        await loadVault(from: vaultURL, persistBookmark: false)
    }

    func dismissError() {
        errorMessage = nil
    }

    func navigate(to linkTarget: String) {
        guard let snapshot else { return }
        guard let noteID = snapshot.resolveNoteID(for: linkTarget) else { return }
        selectedNoteID = noteID
    }

    private func loadVault(from url: URL, persistBookmark: Bool) async {
        isLoading = true
        errorMessage = nil

        activateSecurityScope(for: url)

        do {
            let snapshot = try await Task.detached(priority: .userInitiated) { [reader] in
                try reader.loadVault(at: url)
            }.value

            if persistBookmark {
                try bookmarkStore.save(url: url)
            }

            self.snapshot = snapshot
            vaultURL = url
            selectedNoteID = snapshot.notes.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func activateSecurityScope(for url: URL) {
        let standardized = url.standardizedFileURL
        if activeScopedURL?.standardizedFileURL == standardized {
            return
        }

        activeScopedURL?.stopAccessingSecurityScopedResource()
        _ = standardized.startAccessingSecurityScopedResource()
        activeScopedURL = standardized
    }

}
