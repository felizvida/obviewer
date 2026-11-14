# Reader Architecture (v0.3)

This document describes how a note gets from disk to the screen in the redesigned reader, and where each guarantee is enforced. It complements [`ARCHITECTURE.md`](./ARCHITECTURE.md), which still covers indexing, caching, and the graph.

## Pieces

**`Renderer/` (JavaScript).** Converts note source to HTML. `src/core/markdown.js` configures markdown-it with GitHub and Obsidian plugins (`src/core/plugins/`). `src/core/dokuwiki.js` is a separate DokuWiki renderer. `src/core/export.js` turns rendered HTML into Slack text and portable rich text, and `src/core/page.js` assembles the header, body, and backlinks. `src/reader.js` is the browser entry: it sanitizes with DOMPurify, wires clicks, lazily loads Mermaid, and exposes `window.obviewer`. `build.mjs` bundles everything with esbuild into `Sources/ObviewerReaderKit/Resources/Reader/` and writes a `manifest.json` of file hashes. The bundle is committed, so building the app never needs Node.

**`ObviewerReaderKit` (Swift).** Hosts the renderer and is shared by the app and the Quick Look extension.

- `ReaderWebController` owns the `WKWebView` and enforces the limits listed under Guarantees.
- `ReaderSchemeHandler` serves `obviewer-asset://app/…` from the bundle and `obviewer-asset://vault/…` through a `VaultAssetResolving`.
- `VaultAssetResolver` maps requests to files inside the open folder. It refuses `..` escapes and files outside the root, and falls back to Obsidian-style lookup by file name.
- `ReaderPayloadBuilder` reads the note and assembles the payload: header metadata, backlinks, which wiki links resolve, and the tree of `![[embeds]]`. Embeds are capped at depth 4, 64 per note, and 6 MB in total, with cycle detection.
- `ReaderEvent` parses page messages; anything unexpected is dropped. The accepted messages are:
  - **Behavior:** `ready`, `rendered` (with outline headings), `diagramsRendered`, `link`, `assetError` and `copy`.
  - **Diagnostics only, logged and never acted on:** `jsError` and `cspViolation`.
- `StaticPreviewRenderer` produces the Quick Look HTML with JavaScriptCore. This is a design choice. A WKWebView in the extension would most likely need the same `network.client` entitlement the app needs: we observed that requirement for the app on November 13, 2026, but haven't tested it for an extension. We chose to keep the extension network-free and WebKit-free. Older reports of WKWebView failing in Quick Look (for example WebKit bug 219632) describe a 2020 regression that has since been fixed, so they don't show a current restriction.

**`ObviewerCore` (Swift).** The indexer. `ObsidianParser` still extracts titles, links, tags, frontmatter, and headings for search, backlinks, and the graph. It walks each note's blocks to do that, but the blocks are discarded rather than stored; all rendering happens in the web reader. `WikiSyntax` and `DokuWikiSyntax` mirror the renderer's link rules. `VaultReader` takes a `VaultNoteFormat` (Markdown or DokuWiki), and `ReadingInput` detects the flavor.

**`ObviewerMacApp`.** SwiftUI shell. `AppModel` (plus `AppModel+Reader.swift`) holds navigation history, link routing, find, sharing, Edit-in, folder access, and live reload. `WebReaderView` hosts the reader. `NoteWindowView` is the window for a single file opened from Finder. `OpenRequestRouter` and `ObviewerAppDelegate` route Finder opens. `EditorHandoff` implements "Edit in…", `SingleFileWatcher` provides live reload for single files, and `RecentItemsStore` holds read-only bookmarks.

## Rendering a note

1. Selecting a note, or a reload bumping `renderRevision`, calls `AppModel.refreshReader`.
2. `ReaderPayloadBuilder.build` runs off the main thread. It reads the file read-only (`NoteSourceLoader` caps size at 16 MB and handles non-UTF-8 text) and resolves embeds and links against the `VaultSnapshot`.
3. The payload is passed as JSON to `window.obviewer.render`.
4. The page renders and sanitizes the note, rewrites relative image paths to `obviewer-asset://vault/<path>?from=<note>&raw=<as written>`, and draws Mermaid diagrams asynchronously.
5. The page posts `rendered` with the outline headings.
6. Clicks post `link` events, which Swift resolves:
   - Wiki targets go through the snapshot, or the DokuWiki ID rules. Relative paths resolve against the note's folder.
   - `http`, `https` and `mailto` links open directly in their default apps.
   - `obsidian:`, `zotero:`, `x-devonthink-item:` and `tel:` links open only after a confirmation, because they make another app act.
   - Any other scheme is refused with a notice.
   - Attachments open in their default app after a confirmation.
   - Apps, installers, packages, scripts and executable files are never opened (`AppModel.isSafeToHandOff`).

## Guarantees and where they live

| Guarantee | Enforced by |
| --- | --- |
| Can't write user files | App Sandbox + `user-selected.read-only` only (`Configuration/*.entitlements`); `ReleaseHardeningTests`; `scripts/release_common.sh` checks the signed app and Quick Look extension |
| No network (app-enforced) | On the test Mac (macOS 26), WebKit's WebContent, GPU and Networking helpers exited at launch with "Application does not have permission to communicate with network resources" until the app held `com.apple.security.network.client` (observed November 13, 2026). So this guarantee comes from the app, not macOS: `ReaderContentRules` blocks every non-`obviewer-asset`/`data`/`blob`/`about` load, and the reader refuses to show notes if the rules fail to compile; CSP `default-src 'none'` in `reader.html`; the navigation policy cancels everything except the reader page; Obviewer's own code makes no network calls. `network.server` stays forbidden. |
| Quick Look has no network | The extension has no network entitlement and no web view: `StaticPreviewRenderer` runs the renderer's DOM-free `quicklook.js` in JavaScriptCore and returns static HTML (raw HTML as text, MathML math, diagrams as source) |
| Page can't act on its own | `ReaderEvent` accepts only the messages listed above; none triggers a write. The page can ask Swift to copy text to the clipboard (code-block Copy buttons). |
| No file access outside the open folder | `VaultAssetResolver.containedURL`/`isContained` (symlinks resolved) plus the sandbox |
| Note HTML can't run code | DOMPurify (scripts, forms, iframes, objects stripped) plus CSP `script-src obviewer-asset:` (no inline scripts, no `eval`) |

## Testing

- `cd Renderer && npm test` runs the Node tests: renderer, export, DokuWiki, Quick Look bundle, shared fixtures and the publication check. `node build.mjs --check` fails if the committed bundle is stale.
- `swift test` includes `ObviewerReaderKitTests` (payload builder, embeds and cycles, asset containment, event parsing, bundle presence, CSP and content rules) and `SharedFixtureLinkTests`, which applies the renderer's link expectations to the Swift indexer.
- WebKit behavior inside the sandbox (rendering, scheme loading, printing, Quick Look) needs a real Mac. See [`VERIFICATION.md`](./VERIFICATION.md).
