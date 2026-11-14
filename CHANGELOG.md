# Changelog

## Unreleased

### Changed

- **Apple silicon Macs only.** Intel Macs aren't supported from the next version on, and CI no longer runs an Intel job. `v0.3.0-beta.1` stays as published: a universal build that has never been run on an Intel Mac.
- Release builds are arm64 only (`ARCHS = arm64` for the Release configuration).
- The toolbar's Reload button is gone; File › Reload (⌘R) and live reload remain. The read-only promise now lives in a lock with a tooltip in the sidebar header.
- **A new look: ink on paper, with a hint of Louisiana.** The reader is set in New York with purple ink links (after LSU purple), an old-gold wash for highlights, Mardi Gras green for tip callouts, and a gold fleur-de-lis closing each note. Metadata is one italic line under the title; backlinks are "Mentioned in". The library uses a plain macOS sidebar (no cards, pills or gradients), a title-page welcome screen, and a quiet loading state.
- **An app icon.** The Dock showed a blank placeholder because the app had no icon. It is now a page with a purple silk bookmark and a gold fleur-de-lis, drawn by `scripts/generate_app_icon.py` into `App/AppIcon.icns` (PNG renditions only, no asset catalog, so the publication check can inspect the exact shipped file).
- VoiceOver reads each library row as one item; the Live pulse and loading spinner respect Reduce Motion. The Settings text-size slider now moves in the same 10% steps as Bigger/Smaller Text.

### Removed

- **The classic native reader** and its Settings › Reading toggle. The web reader is the only reader; if its bundled files are missing, the window says so instead of falling back. Notes in the snapshot cache no longer carry rendered blocks, so the cache is smaller and is rebuilt once (schema 4).
- `ObviewerDocsTool`, `make docs-screenshots` and `scripts/generate_doc_screenshots.sh`. They could only draw the classic reader; screenshots now come from the running app.

## 0.3.0 (pre-release `v0.3.0-beta.1`, November 2026)

A redesign of the reader and of how Obviewer fits into macOS. See [`docs/history/REDESIGN_PLAN_v0.3.md`](docs/history/REDESIGN_PLAN_v0.3.md) for the decisions and [`docs/STATUS.md`](docs/STATUS.md) for verification.

### Added

- An offline WebKit reader with a bundled renderer (markdown-it, Mermaid, KaTeX, highlight.js, DOMPurify). It covers GFM and common Obsidian syntax: note, heading and block embeds, callouts, highlights, comments, tags, task states and footnotes.
- DokuWiki support: detection, indexing, rendering, namespaced links and media.
- Flavor detection with an override badge.
- Note windows for files opened from Finder, Open Recent, a default-app helper, and a folder-access banner for relative assets.
- A Quick Look extension: a static preview rendered with JavaScriptCore, with no network permission.
- Edit in… (⌘E), with Sublime Text as the default and Spyder never chosen automatically. Live refresh for single files and folders, including in-place saves.
- Back/forward, outline menus (toolbar and Note › Go to Heading), find in note, linked mentions, dark mode, text-size and line-length controls.
- Copy as Rich Text, Copy for Slack, Print, Open as PDF in Preview, Share as PDF, and share the Markdown file.
- Help › Copy Reader Diagnostics, plus a startup watchdog that explains a reader that doesn't start.
- Shared link fixtures, checked by both the Swift indexer and the renderer.
- A publication-policy scanner, wired into CI and release.
- An ad-hoc release path (`make package-adhoc`; the release workflow when no Developer ID secrets are set) and an install guide.

### Changed

- The Swift parser is now the indexer. Its native rendering survives as the "classic reader" fallback in Settings.
- The app requests `network.client`, because WebKit won't start in the sandbox without it. Note files stay read-only, enforced by macOS.
- The release workflow now requires reviewed notes, a tag that matches `MARKETING_VERSION`, renderer checks, and complete-or-absent signing secrets, and marks hyphenated tags as pre-releases.
- Release builds no longer include the debugger entitlement.
- The documentation was rewritten for 0.3. The v0.2.8 documents moved to `docs/history/`.

### Fixed

- Bold text containing links, callouts containing lists, stray `*` italics, and `$` amounts parsed as math
- Escaped `\[[` and `\|` in the indexer; link titles in image destinations
- Single-file reloads hidden by cached file metadata

## 0.2.8 and earlier

The native-reader prototype: indexing, search, the graph, live vault watching, the snapshot cache and benchmarks. See the GitHub releases and [`docs/history/`](docs/history/).
