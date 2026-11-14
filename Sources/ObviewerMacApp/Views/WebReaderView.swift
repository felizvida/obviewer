import AppKit
import ObviewerCore
import ObviewerReaderKit
import SwiftUI

enum ReaderPreferenceKeys {
    static let textScale = "obviewer.reader.textScale"
    static let measure = "obviewer.reader.measure"
    static let theme = "obviewer.reader.theme"
    static let useClassicReader = "obviewer.reader.useClassic"
}

/// The note reader backed by the offline WebKit renderer.
struct WebReaderView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var reader: ReaderWebController
    let note: VaultNote

    @AppStorage(ReaderPreferenceKeys.textScale) private var textScale = 1.0
    @AppStorage(ReaderPreferenceKeys.measure) private var measure = 68
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = "system"

    init(model: AppModel, note: VaultNote) {
        self.model = model
        self.note = note
        _reader = ObservedObject(wrappedValue: model.reader)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // No accessibility modifiers here: they would collapse the web content into one element.
            ReaderWebView(controller: reader)

            VStack(spacing: 8) {
                if model.isFindBarVisible {
                    ReaderFindBar(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if model.needsFolderAccess {
                    FolderAccessBanner(
                        fileName: model.readingInput?.url.lastPathComponent ?? "this file",
                        onAllow: model.requestFolderAccess,
                        onDismiss: { model.needsFolderAccess = false }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let failure = reader.failureMessage {
                    ReaderFailureBanner(message: failure)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.18), value: model.isFindBarVisible)
            .animation(.easeInOut(duration: 0.18), value: model.needsFolderAccess)
        }
        .overlay(alignment: .bottom) {
            ReaderNoticeToast(notice: $model.readerNotice)
                .padding(.bottom, 18)
        }
        .onAppear {
            applyAppearance()
            render()
        }
        .onChange(of: note.id) { render() }
        .onChange(of: model.renderRevision) { render() }
        .onChange(of: textScale) { applyAppearance() }
        .onChange(of: measure) { applyAppearance() }
        .onChange(of: theme) { applyAppearance() }
    }

    private func render() {
        let anchor = model.pendingAnchor(for: note.id)
        model.refreshReader(scrollingTo: anchor)
        if anchor != nil {
            model.clearPendingAnchor(for: note.id)
        }
    }

    private func applyAppearance() {
        model.applyReaderAppearance(textScale: textScale, measure: measure, theme: theme)
    }
}

struct ReaderFindBar: View {
    @ObservedObject var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in note", text: $model.findQuery)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { model.findNext() }
                .frame(minWidth: 180)
                .accessibilityLabel("Find in note")
            if model.findMatched == false, model.findQuery.isEmpty == false {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                model.findNext(backwards: true)
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Previous match (⇧⌘G)")
            .accessibilityLabel("Previous match")
            Button {
                model.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .help("Next match (⌘G)")
            .accessibilityLabel("Next match")
            Button {
                model.hideFindBar()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .help("Close (Esc)")
            .accessibilityLabel("Close find bar")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08)))
        .frame(maxWidth: 520)
        .onAppear { isFocused = true }
        .onExitCommand { model.hideFindBar() }
    }
}

struct FolderAccessBanner: View {
    let fileName: String
    let onAllow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title3)
                .foregroundStyle(VisualTheme.fern)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some images or linked notes are next to \(fileName).")
                    .font(.callout.weight(.semibold))
                Text("Allow read-only access to its folder to show them. Obviewer never changes your files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Not Now", action: onDismiss)
                .buttonStyle(.borderless)
            Button("Allow Access…", action: onAllow)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
        .frame(maxWidth: 680)
    }
}

struct ReaderFailureBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 680)
    }
}

struct ReaderNoticeToast: View {
    @Binding var notice: ReaderNotice?

    var body: some View {
        Group {
            if let notice {
                Text(notice.message)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(3.5))
                        if self.notice?.id == notice.id {
                            withAnimation { self.notice = nil }
                        }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
    }
}

/// Menu items for the rendered note's headings. A native menu (rather than a List
/// in a popover) so activation works reliably by mouse, keyboard and accessibility.
struct OutlineMenuItems: View {
    let headings: [ReaderHeading]
    let onSelect: (ReaderHeading) -> Void

    var body: some View {
        if headings.isEmpty {
            Text("No headings in this note")
        } else {
            ForEach(headings) { heading in
                Button(String(repeating: "    ", count: max(0, heading.level - 1)) + heading.text) {
                    onSelect(heading)
                }
            }
        }
    }
}

/// Toolbar items shared by the library window and single-note windows.
struct ReaderToolbarItems: ToolbarContent {
    @ObservedObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.goBack()
            } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .disabled(model.canGoBack == false)
            .help("Back (⌘[)")

            Button {
                model.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.forward")
            }
            .disabled(model.canGoForward == false)
            .help("Forward (⌘])")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                OutlineMenuItems(headings: model.outlineHeadings) { heading in
                    model.scrollReader(to: heading.id)
                }
            } label: {
                Label("Outline", systemImage: "list.bullet.indent")
            }
            .help("Jump to a heading")
            .disabled(model.selectedNote == nil)

            Button {
                model.editSelectedNote()
            } label: {
                Label("Edit in…", systemImage: "square.and.pencil")
            }
            .help("Open in your editor (⌘E). Obviewer refreshes when you save.")
            .disabled(model.selectedNote == nil)

            Menu {
                Button("Copy as Rich Text") { model.copyAsRichText() }
                Button("Copy for Slack") { model.copyForSlack() }
                Divider()
                Button("Open as PDF in Preview") { model.openSelectedNoteAsPDFInPreview() }
                Button("Share as PDF…") { model.shareSelectedNoteAsPDF(from: nil) }
                Button("Share Markdown File…") { model.shareSelectedNoteFile(from: nil) }
                Divider()
                Button("Print…") { model.printSelectedNote() }
                Button("Reveal in Finder") { model.revealSelectedNoteInFinder() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share or copy this note")
            .disabled(model.selectedNote == nil)
        }
    }
}

/// A window showing one note file opened from Finder.
public struct NoteWindowView: View {
    let request: NoteWindowRequest?
    @StateObject private var model = AppModel()
    @State private var url: URL?
    @Environment(\.openWindow) private var openWindow
    @AppStorage(ReaderPreferenceKeys.useClassicReader) private var useClassicReader = false

    public init(request: NoteWindowRequest?) {
        self.request = request
    }

    public var body: some View {
        content
            .frame(minWidth: 560, minHeight: 480)
            .background(VisualTheme.readerBackground)
            .toolbar { ReaderToolbarItems(model: model) }
            .navigationTitle(model.selectedNote?.title ?? url?.lastPathComponent ?? "Obviewer")
            .navigationSubtitle(model.readingInput.map { "\($0.profile.displayName) · Read-only" } ?? "")
            .focusedSceneObject(model)
            .onAppear { OpenRequestRouter.shared.attach(openWindow) }
            .task(id: request) {
                guard let request else { return }
                let resolved = request.resolveURL()
                url = resolved
                await model.open(resolved, preferredProfile: nil, persistBookmark: false)
            }
            .onDisappear {
                model.stopWatchingFile()
                model.stopWatchingForWindowClose()
            }
            .modifier(ReaderAlertsModifier(model: model))
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView("Opening…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot = model.snapshot, let note = model.selectedNote {
            if useClassicReader || ReaderAssets.isAvailable == false {
                ReaderView(
                    note: note,
                    snapshot: snapshot,
                    onNavigate: { target, anchor in model.navigate(to: target, anchor: anchor, from: note.id) },
                    onSelectTag: model.select(tag:),
                    pendingAnchorID: model.pendingAnchor(for: note.id),
                    onConsumePendingAnchor: { model.clearPendingAnchor(for: note.id) }
                )
            } else {
                WebReaderView(model: model, note: note)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(request == nil ? "No file" : "This file couldn’t be opened.")
                    .font(.headline)
                Text("Reopen it from Finder or with File › Open.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Error alert and the "open outside Obviewer?" confirmation, shared by all windows.
struct ReaderAlertsModifier: ViewModifier {
    @ObservedObject var model: AppModel

    func body(content: Content) -> some View {
        content
            .alert("Unable to Open", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if $0 == false { model.dismissError() } }
            )) {
                Button("Dismiss") { model.dismissError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .confirmationDialog(
                "Open outside Obviewer?",
                isPresented: Binding(
                    get: { model.pendingExternalOpen != nil },
                    set: { if $0 == false { model.pendingExternalOpen = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Open in Default App") { model.confirmExternalOpen() }
                Button("Cancel", role: .cancel) { model.pendingExternalOpen = nil }
            } message: {
                Text("Obviewer won’t modify \(model.pendingExternalOpen?.title ?? "this file"). The other app may allow editing, so continue only if you trust it.")
            }
    }
}
