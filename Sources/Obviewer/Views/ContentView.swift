import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
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
                ProgressView("Indexing vault...")
                    .controlSize(.large)
            } else if let snapshot = model.snapshot, let note = model.selectedNote {
                ReaderView(
                    note: note,
                    snapshot: snapshot,
                    onNavigate: model.navigate(to:)
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
            ForEach(model.filteredNotes) { note in
                noteRow(note)
                    .tag(note.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
