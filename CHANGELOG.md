# Changelog

## 0.3.0 (pre-release `v0.3.0-beta.1`, November 2026)

A redesign of the reader and of how Obviewer fits into macOS. See [`docs/REDESIGN_PLAN.md`](docs/REDESIGN_PLAN.md) for the decisions and [`docs/STATUS.md`](docs/STATUS.md) for verification.

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
