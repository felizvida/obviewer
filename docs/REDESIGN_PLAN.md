# Redesign Plan and Outcomes (v0.3)

This records the v0.3 redesign: what was planned in November 2026, what was decided along the way, and how it turned out. For the current state, see [`STATUS.md`](./STATUS.md). The earlier v0.2 roadmap is in [`history/MODERNIZATION_PLAN_v0.2.md`](./history/MODERNIZATION_PLAN_v0.2.md).

## Why the redesign

A review on November 13, 2026 found that notes didn't render faithfully. The v0.2 parser was hand-written and its render model was flat:

- bold text couldn't contain a link
- callouts couldn't contain lists
- a stray `*` italicized the rest of a paragraph
- math and Mermaid showed up as source

At the same time the audience narrowed: the maintainer and a few colleagues, with no Apple Developer ID, wanting a reader for any Markdown file, not just vaults.

## Goal

A Mac reader for Markdown and wiki text. Double-click a file and it's rendered faithfully. Open a folder or vault and you also get search, links, backlinks and a graph. Files are never changed, and macOS enforces that. Editing is handed to the user's editor; sharing goes through the clipboard, print and PDF.

## Decisions

| Date | Decision | Why | Outcome |
| --- | --- | --- | --- |
| Nov 13 | Render notes in an embedded, offline WebKit view. markdown-it and plugins, Mermaid, KaTeX and highlight.js are bundled; the shell stays SwiftUI. | Mermaid needs JavaScript, and markdown-it's plugins cover GitHub and Obsidian syntax far better than the old parser | Done. Verified on a Mac (see STATUS). |
| Nov 13 | The Swift parser becomes the indexer; shared fixtures keep the two parsers in agreement | Search, backlinks and the graph still need Swift-side link data | Done. The fixtures caught two disagreements, which were fixed. |
| Nov 13 | Editing is a handoff ("Edit in…") with live refresh; no editing in Obviewer | Keep the read-only guarantee intact | Done. Sublime Text is the default since Nov 13, at the maintainer's request. Folder live reload was extended to catch in-place saves. |
| Nov 13 | Sharing without write access: clipboard, print, share sheet | A save panel would need read-write file access | Changed, see the PDF row below |
| Nov 13 | Ad-hoc signing for releases; the notarization pipeline stays dormant | No Apple Developer ID | Done. Installing on a second Mac hasn't been verified yet. |
| Nov 13 | Formats: CommonMark + GFM baseline, Obsidian additions, DokuWiki as a separate dialect, automatic detection with an override badge | The maintainer's notes span these | Done |
| Nov 13 | Grant WebKit the outgoing-network permission (`com.apple.security.network.client`) | On the test Mac, WebKit's helper processes exited at launch in the sandbox without it, leaving the reader blank | Approved by the maintainer. Network blocking is now enforced by the app (content rules, CSP, navigation policy, fail-closed) rather than by macOS. |
| Nov 13 | Quick Look renders static HTML with JavaScriptCore instead of a web view | Keeps the extension free of network permission and WebKit | Done. Diagrams appear as source in Quick Look. |
| Nov 13 | PDF via "Open as PDF in Preview" (container file) instead of the print dialog's "Save as PDF" | The print dialog's save panel requires read-write file access | Done and verified |
| Nov 13 | Outline as native menus (toolbar and Note › Go to Heading) instead of a list in a popover | The popover's rows didn't respond reliably | Done and verified |
| Nov 14 | Publication policy: a fingerprint-based scanner gates CI and releases | Maintainer requirement for anything published | Done (`scripts/publication-check.mjs`) |

## Phases as delivered

- **A, reader core:**
  - the web renderer, embeds, Mermaid, math and code highlighting
  - dark mode, back/forward, backlinks under each note, find, outline
  - sidebar width, no duplicated title, 68-character lines
- **B, opens everywhere, edits elsewhere:**
  - Finder document types, note windows, Open Recent, and the default-app helper
  - the folder-access banner, the Quick Look extension, and Edit in… with live refresh
- **C, share and install:**
  - rich text, Slack, print, PDF in Preview, and the share sheet
  - the ad-hoc DMG, the install guide, and entitlement checks for the app and the extension
- **D, dialects:** DokuWiki detection, indexing and rendering, plus the flavor badge.

## Spikes

1. **Ad-hoc install on a second Mac:** not run yet.
2. **WebKit in the sandbox:** run. This led to the network-permission decision. Vault images load through the custom scheme. Indexing-benchmark numbers are in STATUS; long-note and large-vault rendering times are still pending.
3. **Slack paste:** run. Text, code and tables survive. Slack turns headings and bold into italics and flattens nested bullets. Documented as a known limitation.

## Kept from v0.2

The indexer and snapshot cache, the file watcher and selective reloads, bookmarks and security-scoped access, the read-only entitlement checks, fixtures and benchmarks, and the graph view (frozen, no new work). The classic native reader remains as a fallback for one release.
