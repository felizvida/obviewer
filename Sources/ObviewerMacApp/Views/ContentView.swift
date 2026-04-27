import ObviewerCore
import SwiftUI

public struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var hoveredNoteID: String?

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
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.detailMode) {
                    ForEach(DetailMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(model.snapshot == nil || model.isLoading)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        await model.chooseVault()
                    }
                } label: {
                    Label("Open Vault", systemImage: "folder.badge.plus")
                }

                Button {
                    Task {
                        await model.reloadVault()
                    }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
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
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.48), lineWidth: 1)
                )
                .padding(16)
                .shadow(color: Color.black.opacity(0.05), radius: 22, x: 0, y: 12)

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
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let snapshot = model.snapshot {
                switch model.detailMode {
                case .reader:
                    if let note = model.selectedNote {
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
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        EmptyReaderState {
                            Task {
                                await model.chooseVault()
                            }
                        }
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
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            } else {
                EmptyReaderState {
                    Task {
                        await model.chooseVault()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.isLoading)
        .animation(.easeInOut(duration: 0.24), value: model.detailMode)
        .animation(.easeInOut(duration: 0.18), value: model.selectedNoteID)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                BrandMark()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Obviewer")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("Read-only vault viewer")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(VisualTheme.fern)
                }
            }

            Text("A read-only Obsidian reader for macOS.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if let vaultURL = model.vaultURL {
                HStack(spacing: 10) {
                    Label(vaultURL.lastPathComponent, systemImage: "books.vertical")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.06))
                        )

                    LiveSyncBadge(isEnabled: model.isLiveReloadEnabled)
                }
            }
        }
    }

    private var librarySummary: some View {
        HStack(spacing: 10) {
            summaryPill(text: "\(model.filteredNotes.count) notes", systemImage: "doc.text")
            if let snapshot = model.snapshot, snapshot.attachments.isEmpty == false {
                summaryPill(text: "\(snapshot.attachments.count) files", systemImage: "paperclip")
            }
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

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)

                TextField("Search notes, tags, or paths", text: $model.searchText)
                    .textFieldStyle(.plain)

                if model.searchText.isEmpty == false {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .softPanel(cornerRadius: 16, opacity: 0.68)
        }
    }

    private var noteList: some View {
        ZStack(alignment: .topLeading) {
            List(selection: $model.selectedNoteID) {
                ForEach(model.noteSections) { section in
                    Section(section.title) {
                        ForEach(section.notes) { note in
                            noteRow(
                                note,
                                isSelected: note.id == model.selectedNoteID,
                                isHovered: note.id == hoveredNoteID
                            )
                            .tag(note.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onHover { hovering in
                                hoveredNoteID = hovering ? note.id : nil
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if model.noteSections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(VisualTheme.fern)

                    Text("No matching notes")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    Text("Try a title, folder, #tag, or frontmatter value.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softPanel(cornerRadius: 20, opacity: 0.66)
                .padding(.top, 8)
            }
        }
    }

    private func noteRow(_ note: VaultNote, isSelected: Bool, isHovered: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(isSelected ? VisualTheme.fern : Color.clear)
                .frame(width: 3, height: 44)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(note.title)
                    .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(VisualTheme.ink)
                    .lineLimit(2)

                Text(note.previewText)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(note.folderPath.isEmpty ? "Vault Root" : note.folderPath)
                    Text("·")
                    Text("\(note.readingTimeMinutes)m")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.52))
                .lineLimit(1)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(Color.white.opacity(0.84))
                        : AnyShapeStyle(Color.white.opacity(isHovered ? 0.62 : 0.0))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? VisualTheme.fern.opacity(0.24) : Color.black.opacity(isHovered ? 0.04 : 0), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.045 : 0), radius: 10, x: 0, y: 6)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .padding(.vertical, 2)
    }

    private func summaryPill(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private var backgroundGradient: some View {
        Rectangle()
            .fill(VisualTheme.appBackground)
        .ignoresSafeArea()
    }
}

private struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [VisualTheme.ink, VisualTheme.fern],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("O")
                .font(.system(size: 21, weight: .black, design: .serif))
                .foregroundStyle(Color.white.opacity(0.96))
        }
        .frame(width: 42, height: 42)
        .shadow(color: VisualTheme.fern.opacity(0.18), radius: 10, x: 0, y: 5)
    }
}

private struct LiveSyncBadge: View {
    let isEnabled: Bool
    @State private var pulse = false

    var body: some View {
        if isEnabled {
            HStack(spacing: 8) {
                Circle()
                    .fill(VisualTheme.fern)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulse ? 1.22 : 0.88)
                    .opacity(pulse ? 0.48 : 1)

                Text("Live")
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(VisualTheme.softInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .softPanel(cornerRadius: 999, opacity: 0.58)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

private struct LoadingVaultState: View {
    let progress: VaultLoadingProgress?
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(VisualTheme.fern.opacity(0.18), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(VisualTheme.fern, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(pulse ? 360 : 0))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Indexing vault")
                        .font(.system(size: 26, weight: .bold, design: .serif))

                    Text(summaryText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                loadingMetric(value: progress?.processedFileCount ?? 0, label: "Files", systemImage: "tray.full")
                loadingMetric(value: progress?.noteCount ?? 0, label: "Notes", systemImage: "doc.text")
                loadingMetric(value: progress?.attachmentCount ?? 0, label: "Assets", systemImage: "paperclip")
            }

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
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.035))
                )
            }
        }
        .padding(34)
        .softPanel(cornerRadius: 30, opacity: 0.76)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }

    private func loadingMetric(value: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(VisualTheme.fern)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.68))
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
        VStack(alignment: .leading, spacing: 24) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(VisualTheme.readerSurface)
                    .frame(width: 440, height: 190)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(VisualTheme.fern.opacity(0.24))
                            .padding(28)
                    }

                VStack(alignment: .leading, spacing: 10) {
                    Text("A calmer way into your vault.")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .frame(maxWidth: 360, alignment: .leading)

                    Text("Choose a local Obsidian folder to start reading.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(28)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 22, x: 0, y: 12)

            Button(action: action) {
                Label("Choose Vault", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
