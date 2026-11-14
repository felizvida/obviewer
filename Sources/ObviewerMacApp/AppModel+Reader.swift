import AppKit
import Foundation
import ObviewerCore
import ObviewerReaderKit
import UniformTypeIdentifiers

struct ReaderNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct ExternalOpenRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String
}

// MARK: - History

extension AppModel {
    var canGoBack: Bool { backStack.isEmpty == false }
    var canGoForward: Bool { forwardStack.isEmpty == false }

    func recordHistory(from previous: String?) {
        guard isRestoringHistory == false, let previous, previous != selectedNoteID else { return }
        backStack.append(previous)
        if backStack.count > 200 { backStack.removeFirst(backStack.count - 200) }
        forwardStack.removeAll()
    }

    func goBack() {
        guard let target = backStack.popLast() else { return }
        if let current = selectedNoteID { forwardStack.append(current) }
        restoreHistorySelection(target)
    }

    func goForward() {
        guard let target = forwardStack.popLast() else { return }
        if let current = selectedNoteID { backStack.append(current) }
        restoreHistorySelection(target)
    }

    private func restoreHistorySelection(_ noteID: String) {
        isRestoringHistory = true
        selectedNoteID = noteID
        isRestoringHistory = false
        detailMode = .reader
    }
}

// MARK: - Rendering

extension AppModel {
    var readerFlavor: ReaderFlavor {
        switch readingProfile {
        case .markdown: return .markdown
        case .obsidian: return .obsidian
        case .dokuwiki: return .dokuwiki
        }
    }

    var dokuWikiInfo: ReaderDokuWikiInfo? {
        readingInput?.dokuWikiLayout.map { ReaderDokuWikiInfo(pagesBase: $0.pagesBase, mediaBase: $0.mediaBase) }
    }

    /// Builds the payload for the selected note off the main thread and hands it to the web reader.
    func refreshReader(scrollingTo anchor: String? = nil) {
        guard let snapshot, let note = selectedNote else { return }
        let builder = ReaderPayloadBuilder(snapshot: snapshot, flavor: readerFlavor, dokuwiki: dokuWikiInfo)
        let options = ReaderRenderOptions(
            showHeader: true,
            showBacklinks: true,
            preserveScroll: anchor == nil,
            anchor: anchor
        )
        let reader = self.reader
        reader.setAssetResolver(VaultAssetResolver(rootURL: snapshot.rootURL, snapshot: snapshot))

        readerRenderTask?.cancel()
        readerRenderTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try builder.build(for: note, options: options) }
            }.value
            guard Task.isCancelled == false, let self else { return }
            switch result {
            case .success(let payload):
                reader.render(payload)
            case .failure(let error):
                self.readerNotice = ReaderNotice(message: error.localizedDescription)
            }
        }
    }

    func applyReaderAppearance(textScale: Double, measure: Int, theme: String) {
        reader.apply(ReaderAppearance(textScale: textScale, measure: measure, theme: theme))
    }

    func scrollReader(to anchor: String) {
        Task { await reader.scrollTo(anchor: anchor) }
    }
}

// MARK: - Events and navigation

extension AppModel {
    func handleReaderEvent(_ event: ReaderEvent) {
        switch event {
        case .link(let request):
            route(request)
        case .assetError:
            if readingInput?.kind == .markdownFile {
                needsFolderAccess = true
            }
        case .copy(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .rendered(_, let headings):
            outlineHeadings = headings
        case .ready, .diagramsRendered, .jsError, .cspViolation:
            break
        }
    }

    func route(_ request: ReaderLinkRequest) {
        switch request.kind {
        case .tag:
            select(tag: request.target)
        case .noteID:
            open(noteID: request.target, anchor: request.anchor)
        case .wiki:
            openWikiTarget(request.target, anchor: request.anchor, from: request.sourceNoteID)
        case .path:
            openRelativePath(request.target, anchor: request.anchor, from: request.sourceNoteID)
        case .external:
            openExternal(request.target)
        }
    }

    func open(noteID: String, anchor: String?) {
        guard snapshot?.note(withID: noteID) != nil else { return }
        detailMode = .reader
        if noteID == selectedNoteID {
            if let anchor { scrollReader(to: anchor) }
            return
        }
        selectedNoteID = noteID
        if let anchor, anchor.isEmpty == false {
            setPendingAnchor(noteID: noteID, anchor: anchor)
        }
    }

    func openWikiTarget(_ target: String, anchor: String?, from sourceID: String?) {
        guard let snapshot else { return }
        if target.isEmpty {
            if let anchor { scrollReader(to: anchor) }
            return
        }

        let noteID: String?
        if readingProfile == .dokuwiki {
            noteID = DokuWikiSyntax.noteID(forPageID: target, in: snapshot, pagesBase: dokuWikiInfo?.pagesBase ?? "")
        } else {
            noteID = snapshot.resolveNoteID(for: target, from: sourceID)
        }
        if let noteID {
            open(noteID: noteID, anchor: anchor)
            return
        }
        if let attachment = snapshot.attachment(for: target, from: sourceID) {
            requestExternalOpen(attachment.url, title: (attachment.relativePath as NSString).lastPathComponent)
            return
        }
        readerNotice = ReaderNotice(message: "“\(target)” isn’t in this \(readingInput?.kind == .markdownFile ? "folder yet. Allow access to the folder to follow links." : "vault.")")
        if readingInput?.kind == .markdownFile { needsFolderAccess = true }
    }

    func openRelativePath(_ target: String, anchor: String?, from sourceID: String?) {
        guard let snapshot else { return }
        let folder = sourceID.flatMap { snapshot.note(withID: $0)?.folderPath } ?? ""
        let joined = target.hasPrefix("/") ? String(target.dropFirst()) : (folder.isEmpty ? target : "\(folder)/\(target)")
        let normalized = Self.normalizeRelativePath(joined)

        if let normalized {
            for candidate in [normalized, normalized + ".md"] where snapshot.note(withID: candidate) != nil {
                open(noteID: candidate, anchor: anchor)
                return
            }
        }
        if let noteID = snapshot.resolveNoteID(for: target, from: sourceID) {
            open(noteID: noteID, anchor: anchor)
            return
        }
        if let attachment = (normalized.flatMap { snapshot.attachment(for: $0) }) ?? snapshot.attachment(for: target, from: sourceID) {
            requestExternalOpen(attachment.url, title: (attachment.relativePath as NSString).lastPathComponent)
            return
        }
        if let normalized,
           let fileURL = VaultAssetResolver.containedURL(forRelativePath: normalized, in: snapshot.rootURL),
           FileManager.default.isReadableFile(atPath: fileURL.path) {
            if NoteFileTypes.isNoteFile(fileURL) {
                OpenRequestRouter.shared.open([fileURL])
            } else {
                requestExternalOpen(fileURL, title: fileURL.lastPathComponent)
            }
            return
        }
        readerNotice = ReaderNotice(message: "Couldn’t find “\(target)”.")
        if readingInput?.kind == .markdownFile { needsFolderAccess = true }
    }

    func openExternal(_ href: String) {
        guard let url = URL(string: href), let scheme = url.scheme?.lowercased() else { return }
        switch scheme {
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        case "obsidian", "zotero", "x-devonthink-item", "tel":
            // These can make another app act (an obsidian:// link can create or overwrite notes), so ask first.
            pendingExternalOpen = ExternalOpenRequest(url: url, title: "this \(scheme): link")
        default:
            readerNotice = ReaderNotice(message: "Obviewer doesn’t open “\(scheme):” links.")
        }
    }

    func requestExternalOpen(_ url: URL, title: String) {
        guard Self.isSafeToHandOff(url) else {
            readerNotice = ReaderNotice(message: "Obviewer won’t launch apps, installers, or scripts from a note.")
            return
        }
        pendingExternalOpen = ExternalOpenRequest(url: url, title: title)
    }

    /// Files Obviewer may pass to another app: documents, not executables.
    nonisolated static func isSafeToHandOff(_ url: URL) -> Bool {
        guard url.isFileURL else { return true }
        let blockedExtensions: Set<String> = [
            "app", "command", "tool", "terminal", "sh", "bash", "zsh", "csh", "ksh", "py", "rb", "pl", "php",
            "scpt", "scptd", "applescript", "workflow", "action", "pkg", "mpkg", "dmg", "jar", "webloc",
            "inetloc", "fileloc", "url", "prefpane", "saver", "kext", "plugin", "bundle", "framework", "dylib",
            "mobileconfig", "shortcut",
        ]
        if blockedExtensions.contains(url.pathExtension.lowercased()) { return false }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            for unsafe in [UTType.executable, .application, .applicationBundle, .script, .shellScript, .unixExecutable, .package] {
                if type.conforms(to: unsafe) { return false }
            }
        }
        if FileManager.default.isExecutableFile(atPath: url.path),
           (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            return false
        }
        return true
    }

    func confirmExternalOpen() {
        guard let request = pendingExternalOpen else { return }
        pendingExternalOpen = nil
        guard Self.isSafeToHandOff(request.url) else { return }
        NSWorkspace.shared.open(request.url)
    }

    nonisolated static func normalizeRelativePath(_ path: String) -> String? {
        var parts = [String]()
        for segment in path.split(separator: "/") {
            if segment == "." || segment.isEmpty { continue }
            if segment == ".." {
                guard parts.isEmpty == false else { return nil }
                parts.removeLast()
            } else {
                parts.append(String(segment).removingPercentEncoding ?? String(segment))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }
}

// MARK: - Find

extension AppModel {
    func showFindBar() {
        detailMode = .reader
        isFindBarVisible = true
    }

    func hideFindBar() {
        isFindBarVisible = false
    }

    func findNext(backwards: Bool = false) {
        let query = findQuery
        guard query.isEmpty == false else { return }
        Task {
            findMatched = await reader.find(query, backwards: backwards)
        }
    }
}

// MARK: - Sharing (never writes to the source folder)

extension AppModel {
    func copyAsRichText() {
        Task {
            do {
                let export = try await reader.exportRichText()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                var types: [NSPasteboard.PasteboardType: Data] = [:]
                if let html = export.html.data(using: .utf8) {
                    types[.html] = html
                    if let attributed = NSAttributedString(html: html, documentAttributes: nil),
                       let rtf = try? attributed.data(
                           from: NSRange(location: 0, length: attributed.length),
                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                       ) {
                        types[.rtf] = rtf
                    }
                }
                pasteboard.declareTypes(Array(types.keys) + [.string], owner: nil)
                for (type, data) in types { pasteboard.setData(data, forType: type) }
                pasteboard.setString(export.text, forType: .string)
                readerNotice = ReaderNotice(message: "Copied as rich text.")
            } catch {
                readerNotice = ReaderNotice(message: error.localizedDescription)
            }
        }
    }

    func copyForSlack() {
        Task {
            do {
                let export = try await reader.exportForSlack()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.declareTypes([.html, .string], owner: nil)
                pasteboard.setString(export.html, forType: .html)
                pasteboard.setString(export.text, forType: .string)
                readerNotice = ReaderNotice(message: "Copied for Slack. Paste into a message.")
            } catch {
                readerNotice = ReaderNotice(message: error.localizedDescription)
            }
        }
    }

    func printSelectedNote() {
        guard let note = selectedNote else { return }
        reader.printDocument(in: reader.webView.window, jobTitle: note.title)
    }

    /// Generates a PDF in the app's temporary directory and opens the share picker.
    func shareSelectedNoteAsPDF(from anchorView: NSView?) {
        Task {
            guard let url = await makeTemporaryPDF() else { return }
            showSharePicker(items: [url], from: anchorView)
        }
    }

    /// "Save as PDF" can't work here: a save panel needs the read-write file
    /// entitlement, which would break the read-only guarantee. Instead the PDF
    /// is written into the app's own container and opened in Preview, where the
    /// user can save or export it anywhere.
    func openSelectedNoteAsPDFInPreview() {
        Task {
            guard let url = await makeTemporaryPDF() else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let previewURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview")
                ?? NSWorkspace.shared.urlForApplication(toOpen: url)
            guard let previewURL else {
                readerNotice = ReaderNotice(message: "No app is available to open PDFs.")
                return
            }
            NSWorkspace.shared.open([url], withApplicationAt: previewURL, configuration: configuration) { _, error in
                guard let error else { return }
                let message = "Couldn’t open the PDF: \(error.localizedDescription)"
                Task { @MainActor [weak self] in self?.readerNotice = ReaderNotice(message: message) }
            }
        }
    }

    /// Writes a paginated PDF of the selected note inside the app's container (never the vault).
    func makeTemporaryPDF() async -> URL? {
        guard let note = selectedNote else { return nil }
        let directory = Self.temporaryExportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = note.title.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
        let url = directory.appendingPathComponent("\(safeName.isEmpty ? "Note" : safeName).pdf")
        try? FileManager.default.removeItem(at: url)
        let success = await reader.writePDF(to: url, in: reader.webView.window, jobTitle: note.title)
        guard success, FileManager.default.fileExists(atPath: url.path) else {
            readerNotice = ReaderNotice(message: "Couldn’t create a PDF of this note.")
            return nil
        }
        return url
    }

    nonisolated static var temporaryExportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Obviewer Export", isDirectory: true)
    }

    func shareSelectedNoteFile(from anchorView: NSView?) {
        guard let url = selectedNoteFileURL else { return }
        showSharePicker(items: [url], from: anchorView)
    }

    private func showSharePicker(items: [Any], from anchorView: NSView?) {
        let view: NSView = anchorView ?? reader.webView
        let picker = NSSharingServicePicker(items: items)
        let rect = NSRect(x: view.bounds.maxX - 40, y: view.bounds.maxY - 8, width: 1, height: 1)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    var selectedNoteFileURL: URL? {
        guard let snapshot, let note = selectedNote else { return nil }
        return snapshot.rootURL.appendingPathComponent(note.relativePath)
    }

    func copyReaderDiagnostics() {
        let text = hasReader ? reader.diagnostics : "The web reader hasn't been started in this window."
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        readerNotice = ReaderNotice(message: "Reader diagnostics copied.")
    }

    func revealSelectedNoteInFinder() {
        guard let url = selectedNoteFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Edit in…

extension AppModel {
    func editSelectedNote() {
        guard let url = selectedNoteFileURL else { return }
        let isObsidianVault = readingProfile == .obsidian && readingInput?.kind == .folder
        EditorHandoff.shared.open(fileURL: url, preferObsidian: isObsidianVault) { [weak self] message in
            self?.readerNotice = ReaderNotice(message: message)
        }
    }
}

// MARK: - Single-file watching, folder access, recents

extension AppModel {
    func startWatchingFile(at url: URL) {
        fileWatchSession?.invalidate()
        fileWatchSession = fileWatcher.beginWatching(fileURL: url) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleWatchedFileChange()
            }
        }
        setLiveReloadEnabled(true)
    }

    func stopWatchingFile() {
        fileWatchSession?.invalidate()
        fileWatchSession = nil
    }

    /// Asks for read-only access to the folder around a single open file so
    /// relative images, embeds and links work, then reopens it as a folder.
    func requestFolderAccess() {
        guard let input = readingInput, input.kind == .markdownFile else { return }
        let parent = input.url.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = parent
        panel.prompt = "Allow Read-Only Access"
        panel.message = "Choose the folder that contains “\(input.url.lastPathComponent)” and its images. Obviewer only reads it."
        guard panel.runModal() == .OK, let folder = panel.url?.standardizedFileURL else { return }

        let filePath = input.url.standardizedFileURL.path
        guard filePath.hasPrefix(folder.path.hasSuffix("/") ? folder.path : folder.path + "/") else {
            readerNotice = ReaderNotice(message: "That folder doesn’t contain this file.")
            return
        }
        let relative = String(filePath.dropFirst(folder.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let profile = DefaultReadingInputAdapter().detectedFolderProfile(for: folder)
        needsFolderAccess = false
        Task {
            await open(ReadingInputSource(url: folder, kind: .folder, profile: profile, preferredFocusPath: relative), persistBookmark: false)
        }
    }

    func reopen(with profile: ReadingProfile) {
        guard let input = readingInput, input.profile != profile else { return }
        let focus = input.kind == .folder ? selectedNoteID : nil
        Task {
            await open(input.with(profile: profile).with(focus: focus), persistBookmark: false)
        }
    }
}
