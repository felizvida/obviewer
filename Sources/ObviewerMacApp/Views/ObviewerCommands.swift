import AppKit
import ObviewerCore
import SwiftUI

/// Menu bar commands. They act on the focused window's model.
public struct ObviewerCommands: Commands {
    @FocusedObject private var model: AppModel?
    @ObservedObject private var recents = RecentItemsStore.shared
    @AppStorage(ReaderPreferenceKeys.textScale) private var textScale = 1.0
    @AppStorage(ReaderPreferenceKeys.measure) private var measure = ReaderMeasure.standard

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open File or Folder…") {
                OpenRequestRouter.shared.chooseAndOpen()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Show Library") {
                OpenRequestRouter.shared.showLibrary()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Menu("Open Recent") {
                ForEach(recents.items) { item in
                    Button(item.displayName) {
                        guard let url = recents.resolve(item) else { return }
                        OpenRequestRouter.shared.open([url])
                    }
                }
                if recents.items.isEmpty == false {
                    Divider()
                    Button("Clear Menu") { recents.clear() }
                }
            }
            .disabled(recents.items.isEmpty)

            Button("Reload") {
                Task { await model?.reloadVault() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model?.vaultURL == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { model?.printSelectedNote() }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(model?.selectedNote == nil)
            Button("Open as PDF in Preview") { model?.openSelectedNoteAsPDFInPreview() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(model?.selectedNote == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Note as Rich Text") { model?.copyAsRichText() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model?.selectedNote == nil)
            Button("Copy Note for Slack") { model?.copyForSlack() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model?.selectedNote == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Note…") { model?.showFindBar() }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(model?.selectedNote == nil)
            Button("Find Next") { model?.findNext() }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(model?.findQuery.isEmpty ?? true)
            Button("Find Previous") { model?.findNext(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model?.findQuery.isEmpty ?? true)
            Button("Search Notes") { model?.focusLibrarySearch() }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandGroup(after: .toolbar) {
            // ⌘= / ⌘+ are also handled by ReaderKeyMonitor, ahead of the web view.
            Button("Bigger Text") { ReaderTextSize.increase() }
                .keyboardShortcut("=", modifiers: [.command])
            Button("Smaller Text") { ReaderTextSize.decrease() }
                .keyboardShortcut("-", modifiers: [.command])
            Button("Actual Size") {
                textScale = 1.0
                measure = ReaderMeasure.standard
            }
            .keyboardShortcut("0", modifiers: [.command])
            Button("Wider Lines") { measure = min(measure + ReaderMeasure.menuStep, ReaderMeasure.maximum) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Button("Narrower Lines") { measure = max(measure - ReaderMeasure.menuStep, ReaderMeasure.minimum) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Divider()
            Button(model?.detailMode == .graph ? "Hide Graph" : "Show Graph") {
                guard let model else { return }
                model.detailMode = model.detailMode == .graph ? .reader : .graph
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(model?.snapshot == nil || model?.isLoading == true)
            Divider()
        }

        CommandGroup(after: .help) {
            Button("Copy Reader Diagnostics") { model?.copyReaderDiagnostics() }
                .disabled(model == nil)
        }

        CommandMenu("Note") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(model?.canGoBack != true)
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(model?.canGoForward != true)
            Divider()
            Menu("Go to Heading") {
                OutlineMenuItems(headings: model?.outlineHeadings ?? []) { heading in
                    model?.scrollReader(to: heading.id)
                }
            }
            .disabled(model?.selectedNote == nil)
            Divider()
            Button("Edit in \(EditorHandoff.shared.displayName(for: EditorHandoff.shared.preferredEditorID))…") {
                model?.editSelectedNote()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(model?.selectedNote == nil)
            Button("Reveal in Finder") { model?.revealSelectedNoteInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model?.selectedNote == nil)
            Divider()
            Button("Share as PDF…") { model?.shareSelectedNoteAsPDF(from: nil) }
                .disabled(model?.selectedNote == nil)
        }
    }
}

extension AppModel {
    /// Asks the library sidebar to focus its search field.
    func focusLibrarySearch() {
        detailMode = .reader
        NotificationCenter.default.post(name: .obviewerFocusSearch, object: self)
    }
}

extension Notification.Name {
    static let obviewerFocusSearch = Notification.Name("obviewer.focusSearch")
}
