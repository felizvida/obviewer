<!-- release-channel: prerelease -->
# Obviewer v0.3.0-beta.1 (pre-release)

A redesigned reader. Notes now render faithfully, including Mermaid diagrams and math, entirely offline. Obviewer also opens single Markdown files from Finder, previews them in Quick Look, hands editing off to your editor, and reads DokuWiki.

This is a **pre-release**. It was verified on one Mac (Apple silicon, macOS 26). Installing on other Macs, on Intel, and on macOS 14 or 15 hasn't been verified yet. See [STATUS](https://github.com/felizvida/obviewer/blob/main/docs/STATUS.md) for exactly what was checked.

## Install

Download `Obviewer-v0.3.0-beta.1-macOS-adhoc.dmg` and follow [INSTALL](https://github.com/felizvida/obviewer/blob/main/docs/INSTALL.md). The app is **ad-hoc signed and not notarized by Apple**, so macOS asks you to approve it in System Settings › Privacy & Security. Managed Macs may not allow it. You can compare the DMG against the published SHA-256 checksum.

## What's new

- **A new reader.** It's built on WebKit with a bundled, offline renderer. It covers GitHub Flavored Markdown and common Obsidian syntax: wiki links, `![[embeds]]` of notes, headings and blocks, callouts, highlights, comments, tags, task states, footnotes, KaTeX math, Mermaid diagrams and highlighted code.
- **DokuWiki.** Pages under `data/pages` are detected, indexed and rendered, including namespaced links, media, tables and footnotes.
- **Finder integration.** `.md` files open in their own windows, and there's Open Recent. A banner offers read-only folder access for notes with relative images. A static Quick Look preview appears when you press Space.
- **Reading tools.** Back/forward, an outline menu, find in note, linked mentions under each note, dark mode, and text-size and line-length controls.
- **Edit in… (⌘E).** It opens Sublime Text by default (configurable). Obviewer refreshes when you save, in single-file and folder mode.
- **Sharing.** Copy as Rich Text (Mail, Word), Copy for Slack, Print, Open as PDF in Preview, and Share as PDF.
- **Flavor badge.** It shows the detected flavor (Markdown, Obsidian, DokuWiki) and lets you switch.

## Permissions and safety

- **Your notes are read-only, enforced by macOS** (App Sandbox, read-only user-selected files).
- The app also holds **print** and **outgoing network** permissions. WebKit requires the network permission to start inside the sandbox, but Obviewer makes no network requests, and its reader blocks every remote load. That blocking is enforced by the app, not by macOS. The Quick Look extension has no network permission.
- HTML in notes is sanitized, and scripts can't run.
- Release builds carry no debugger entitlement and keep the hardened runtime. The app's own modules are linked into its executables, so no separately signed frameworks are loaded.

## Known limitations

- Slack turns headings and bold into italics and flattens nested bullets when you paste.
- The print dialog's "Save as PDF" can't work in a read-only app. Use ⌥⌘P (Open as PDF in Preview) instead.
- The Quick Look preview is static: diagrams appear as source, and images as placeholders.
- Remote images never load. Plugin queries, such as Dataview, aren't run.
- After an update, macOS may ask again to approve the app and to let it access its own data, and may forget folder access.
- No accessibility audit yet. The classic native reader is still available in Settings for one release.

## Checks for this release

- Automated:
  - Swift and renderer test suites
  - a renderer bundle reproducibility check
  - entitlement allow-list tests
  - a publication-policy scan of the source tree and of every uploaded file
- Manual, on the maintainer's Mac:
  - a 20-item checklist: reader, a hostile-content test, navigation, Finder, Quick Look, Edit in…, sharing, PDF and DokuWiki
  - a Release-build signature and entitlement review

Full changes: [CHANGELOG](https://github.com/felizvida/obviewer/blob/main/CHANGELOG.md).
