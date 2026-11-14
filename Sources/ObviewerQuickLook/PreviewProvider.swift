import Foundation
import ObviewerCore
import ObviewerReaderKit
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look preview for Markdown and DokuWiki pages (press Space in Finder).
///
/// A data-based preview: the note is rendered to static HTML with JavaScriptCore
/// and handed to Quick Look. The extension never hosts a web view, holds no
/// network permission, and only reads the file Quick Look gives it. Raw HTML in
/// the note is shown as text.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let profile = DefaultReadingInputAdapter().makeInputSource(for: url, preferredProfile: nil).profile
        let flavor: ReaderFlavor = profile == .dokuwiki ? .dokuwiki : .markdown
        let format: VaultNoteFormat = profile == .dokuwiki
            ? .dokuwiki(DokuWikiLayout(pagesBase: "", mediaBase: ""))
            : .markdown

        let snapshot = try VaultReader(noteFormat: format).loadMarkdownFile(at: url)
        guard let note = snapshot.notes.first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let payload = try ReaderPayloadBuilder(snapshot: snapshot, flavor: flavor).build(
            for: note,
            options: ReaderRenderOptions(showHeader: false, showBacklinks: false, preserveScroll: false, staticMode: true)
        )
        let html = try StaticPreviewRenderer.document(for: payload)

        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 860, height: 1_000)) { _ in
            Data(html.utf8)
        }
    }
}
