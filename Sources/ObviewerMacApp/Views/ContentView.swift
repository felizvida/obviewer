import ObviewerCore
import SwiftUI

/// The library window: notes on the left, the reader (or graph) on the right.
/// Native chrome, no decoration: the sidebar is a plain macOS source list and the
/// detail pane is the same paper as the reader page.
public struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var router = OpenRequestRouter.shared
    @FocusState private var isSearchFocused: Bool
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .tint(VisualTheme.accent)
        .focusedSceneObject(model)
        .modifier(ReaderAlertsModifier(model: model))
        .onAppear {
            router.attach(openWindow)
            openPendingFolder()
        }
        .onChange(of: router.pendingFolders) { openPendingFolder() }
        .toolbar {
            ReaderToolbarItems(model: model)

            ToolbarItemGroup(placement: .primaryAction) {
                // The reader is the default; the graph is a toggle, not a second mode to pick.
                Toggle(isOn: Binding(
                    get: { model.detailMode == .graph },
                    set: { model.detailMode = $0 ? .graph : .reader }
                )) {
                    Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .toggleStyle(.button)
                .help("Graph of how notes link (⌥⌘G)")
                .disabled(model.snapshot == nil || model.isLoading)

                Button {
                    Task { await model.chooseVault() }
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open a file or folder (⌘O)")
            }
        }
    }

    private func openPendingFolder() {
        guard let folder = router.takePendingFolder() else { return }
        model.markRestoreHandled()
        Task {
            await model.open(folder, preferredProfile: nil, persistBookmark: true)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let input = model.readingInput {
                SidebarHeader(
                    input: input,
                    isLive: model.isLiveReloadEnabled,
                    onChangeProfile: { model.reopen(with: $0) }
                )
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }

            if model.snapshot != nil {
                search
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            noteList
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(searchPlaceholder, text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .disabled(model.isLoading)
                .accessibilityLabel("Search notes")
                .onReceive(NotificationCenter.default.publisher(for: .obviewerFocusSearch)) { notification in
                    if (notification.object as AnyObject?) === model {
                        isSearchFocused = true
                    }
                }

            if model.searchText.isEmpty == false {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var noteList: some View {
        List(selection: $model.selectedNoteID) {
            ForEach(model.noteSections) { section in
                Section(section.title) {
                    ForEach(section.notes) { note in
                        NoteRow(note: note)
                            .tag(note.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.snapshot != nil, model.noteSections.isEmpty {
                LibraryEmptyState(
                    query: model.searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    onClearSearch: { model.searchText = "" },
                    onChooseVault: { Task { await model.chooseVault() } }
                )
            }
        }
    }

    private var searchPlaceholder: String {
        let count = model.snapshot?.notes.count ?? 0
        return count == 1 ? "Search 1 note" : "Search \(count) notes"
    }

    // MARK: - Detail

    private var detail: some View {
        ZStack {
            VisualTheme.readerBackground
                .ignoresSafeArea()

            if model.isLoading {
                LoadingVaultState(
                    name: model.readingInput?.url.lastPathComponent,
                    progress: model.loadingProgress
                )
            } else if let snapshot = model.snapshot {
                switch model.detailMode {
                case .reader:
                    if let note = model.selectedNote {
                        NoteReaderPane(model: model, note: note)
                    } else {
                        NoNoteSelectedState()
                    }

                case .graph:
                    GraphWorkspaceView(
                        snapshot: snapshot,
                        subgraph: model.graphSubgraph,
                        selectedNoteID: model.selectedNoteID,
                        selectedNode: model.selectedGraphNode,
                        graphScope: model.graphScope,
                        searchText: model.searchText,
                        onChangeScope: { model.graphScope = $0 },
                        onSelectNote: { model.selectedNoteID = $0 },
                        onOpenReader: { model.detailMode = .reader }
                    )
                }
            } else {
                WelcomeState {
                    Task { await model.chooseVault() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isLoading)
    }
}

// MARK: - Sidebar pieces

/// The open file or folder by name, with its flavor (a menu to re-read it as
/// another flavor) and a lock that explains the read-only promise.
private struct SidebarHeader: View {
    let input: ReadingInputSource
    let isLive: Bool
    let onChangeProfile: (ReadingProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(input.url.lastPathComponent)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(input.url.path)

            HStack(spacing: 6) {
                Menu {
                    Picker("Read as", selection: Binding(get: { input.profile }, set: onChangeProfile)) {
                        ForEach(ReadingProfile.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(flavorLabel)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.visible)
                .fixedSize()
                .help("Detected flavor. Choose another to re-read this \(input.kind == .folder ? "folder" : "file").")
                .accessibilityLabel("Flavor: \(input.profile.displayName)")

                Spacer(minLength: 0)

                Image(systemName: "lock")
                    .help(isLive
                        ? "Read-only. Obviewer refreshes when the files change, and never writes to them."
                        : "Read-only. Obviewer never writes to these files.")
                    .accessibilityLabel(isLive ? "Read-only, live reload on" : "Read-only")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var flavorLabel: String {
        switch (input.profile, input.kind) {
        case (.obsidian, .folder): return "Obsidian vault"
        case (.dokuwiki, .folder): return "DokuWiki pages"
        case (.markdown, .folder): return "Markdown folder"
        case (let profile, .markdownFile): return "\(profile.displayName) file"
        }
    }
}

private struct NoteRow: View {
    let note: VaultNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            if note.previewText.isEmpty == false, note.previewText != note.title {
                Text(note.previewText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.title)
        .accessibilityValue("\(note.readingTimeMinutes) minute read")
    }
}

private struct LibraryEmptyState: View {
    let query: String
    let onClearSearch: () -> Void
    let onChooseVault: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(query.isEmpty ? "No notes here." : "Nothing matches “\(query)”.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(query.isEmpty ? "Choose Another Folder…" : "Clear Search") {
                query.isEmpty ? onChooseVault() : onClearSearch()
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(20)
    }
}

// MARK: - Detail states

/// First launch, or nothing open: a title page.
private struct WelcomeState: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FleurDeLis()
                .fill(VisualTheme.gold)
                .frame(width: 34, height: 31)
                .accessibilityHidden(true)
                .padding(.bottom, 16)

            Text("Obviewer")
                .font(.system(size: 46, weight: .regular, design: .serif).italic())
                .foregroundStyle(VisualTheme.ink)
                .padding(.bottom, 14)

            Text("Open a Markdown file, an Obsidian vault or a DokuWiki folder to read it here. Obviewer only reads; your files are never changed.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(VisualTheme.softInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            Button("Open File or Folder…", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Text("You can also double-click a .md file in Finder.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .frame(maxWidth: 400, alignment: .leading)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoNoteSelectedState: View {
    var body: some View {
        Text("Choose a note from the list.")
            .font(.system(size: 15, design: .serif).italic())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LoadingVaultState: View {
    let name: String?
    let progress: VaultLoadingProgress?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text(name.map { "Reading “\($0)”" } ?? "Reading your notes")
                .font(.system(size: 17, design: .serif).italic())
                .foregroundStyle(VisualTheme.ink)

            Text(summary)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text("Files are opened for reading only.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        guard let progress else { return "Getting started…" }
        let notes = progress.noteCount == 1 ? "1 note" : "\(progress.noteCount) notes"
        let files = progress.attachmentCount == 1 ? "1 attachment" : "\(progress.attachmentCount) attachments"
        return "\(notes), \(files) so far"
    }
}
