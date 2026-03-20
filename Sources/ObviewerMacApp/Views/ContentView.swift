import ObviewerCore
import SwiftUI

public struct ContentView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(backgroundGradient)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open Vault") {
                    Task {
                        await model.chooseVault()
                    }
                }

                Button("Reload") {
                    Task {
                        await model.reloadVault()
                    }
                }
                .disabled(model.vaultURL == nil)
            }
        }
        .task {
            await model.restoreVaultIfNeeded()
        }
        .alert("Unable to Open Vault", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if newValue == false {
                    model.dismissError()
                }
            }
        )) {
            Button("Dismiss") {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .padding(16)

            VStack(alignment: .leading, spacing: 20) {
                header
                search
                librarySummary
                noteList
            }
            .padding(28)
        }
        .background(backgroundGradient)
    }

    private var detail: some View {
        ZStack {
            backgroundGradient

            if model.isLoading {
                LoadingVaultState(progress: model.loadingProgress)
            } else if let snapshot = model.snapshot, let note = model.selectedNote {
                ReaderView(
                    note: note,
                    snapshot: snapshot,
                    onNavigate: { target, anchor in
                        model.navigate(to: target, anchor: anchor, from: note.id)
                    },
                    onSelectTag: model.select(tag:),
                    pendingAnchorID: model.pendingAnchor(for: note.id),
                    onConsumePendingAnchor: {
                        model.clearPendingAnchor(for: note.id)
                    }
                )
            } else {
                EmptyReaderState {
                    Task {
                        await model.chooseVault()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Obviewer")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("A read-only Obsidian reader for macOS.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if let vaultURL = model.vaultURL {
                Label(vaultURL.lastPathComponent, systemImage: "books.vertical")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.06))
                    )
            }
        }
    }

    private var librarySummary: some View {
        HStack(spacing: 10) {
            summaryPill(text: "\(model.filteredNotes.count) notes", systemImage: "doc.text")
            if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                summaryPill(text: "Filtered", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            TextField("Search notes, tags, or paths", text: $model.searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private var noteList: some View {
        List(selection: $model.selectedNoteID) {
            ForEach(model.noteSections) { section in
                Section(section.title) {
                    ForEach(section.notes) { note in
                        noteRow(note)
                            .tag(note.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func noteRow(_ note: VaultNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(2)

            Text(note.previewText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(note.folderPath.isEmpty ? "Vault Root" : note.folderPath)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)

            HStack(spacing: 8) {
                Label("\(note.readingTimeMinutes)m", systemImage: "clock")
                Label("\(note.wordCount)", systemImage: "text.word.spacing")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private func summaryPill(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.96, blue: 0.92),
                Color(red: 0.94, green: 0.93, blue: 0.89),
                Color(red: 0.90, green: 0.92, blue: 0.90),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct LoadingVaultState: View {
    let progress: VaultLoadingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView("Indexing vault...")
                .controlSize(.large)

            Text(summaryText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if let currentPath = progress?.currentPath, currentPath.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Currently scanning")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(currentPath)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var summaryText: String {
        guard let progress else {
            return "Preparing vault scan..."
        }

        let fileWord = progress.processedFileCount == 1 ? "file" : "files"
        let noteWord = progress.noteCount == 1 ? "note" : "notes"
        let attachmentWord = progress.attachmentCount == 1 ? "attachment" : "attachments"
        return "\(progress.processedFileCount) \(fileWord) scanned, \(progress.noteCount) \(noteWord), \(progress.attachmentCount) \(attachmentWord)"
    }
}

private struct EmptyReaderState: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A premium local reading room for your vault.")
                .font(.system(size: 38, weight: .bold, design: .serif))
                .frame(maxWidth: 700, alignment: .leading)

            Text("Open an Obsidian folder and browse your notes with a strict read-only access model, elegant typography, and a focused macOS-native layout.")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)

            Button("Choose Vault", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
