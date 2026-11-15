<!-- release-channel: prerelease -->
# Obviewer v0.3.0-beta.2 (pre-release)

A quieter, more bookish Obviewer: a redesigned reader and library window, an app icon, fewer controls, and a stricter check on everything the project publishes. This build is for **Apple silicon Macs only**.

This is a **pre-release**. It was verified on one Mac (Apple silicon, macOS 26). Installing on other Macs and on macOS 14 or 15 hasn't been verified yet. See [STATUS](https://github.com/felizvida/obviewer/blob/main/docs/STATUS.md) for exactly what was checked and what wasn't.

## Install

Download `Obviewer-v0.3.0-beta.2-macOS-adhoc.dmg` and follow [INSTALL](https://github.com/felizvida/obviewer/blob/main/docs/INSTALL.md). The app is **ad-hoc signed and not notarized by Apple**, so macOS asks you to approve it in System Settings › Privacy & Security. Managed Macs may not allow it. You can compare the DMG against the published SHA-256 checksum. **Intel Macs aren't supported** from this version on; `v0.3.0-beta.1` remains available as published.

If you're updating from beta.1, macOS may ask again to approve the app and to let it access its own data, and may forget folder access. Reopen your vault with ⌘O.

## What's new

- **A new look: ink on paper.** Notes are set in Apple's New York serif at a comfortable density, with links in a deep purple ink, highlights in a pale gold wash, tip callouts in green, and a small gold fleur-de-lis closing each note. Metadata is one italic line under the title, tags are plain text, and backlinks read "Mentioned in". It prints the same way.
- **A calmer library window.** A plain macOS sidebar shows the open folder's name, its flavor as a small menu, a lock that explains the read-only promise, a search field that says how many notes it covers, and rows of title and preview. Cards, pills and gradients are gone. A simple title page greets you when nothing is open.
- **Fewer controls.** The reader is the default and **Graph** is a toolbar toggle (View › Show Graph, ⌥⌘G). In the graph, one **Whole Vault** toggle replaces the Local/Global picker; local is the default. With nothing selected, or a search that matches nothing, the graph says so instead of drawing everything. The toolbar's Reload button is gone (⌘R and live reload remain).
- **An app icon** instead of the blank placeholder: a page with a purple bookmark and a gold fleur-de-lis.
- **Accessibility basics.** Each library row is exposed to accessibility tools as one item with its title and reading time, and animations respect Reduce Motion. What VoiceOver actually says hasn't been listened to, and a full accessibility audit hasn't been done.

## Removed

- **The classic native reader** and its Settings toggle. The web reader is the only reader. The note cache is rebuilt once, smaller.
- The offscreen screenshot tool, which could only draw the classic reader.

## Permissions and safety

Unchanged from beta.1:

- **Your notes are read-only, enforced by macOS** (App Sandbox, read-only user-selected files).
- The app also holds **print** and **outgoing network** permissions. WebKit needs the network permission to start inside the sandbox, but Obviewer makes no network requests, and its reader blocks every remote load. That blocking is enforced by the app, not by macOS. The Quick Look extension has no network permission.

New in this release:

- Release builds contain no compiled asset catalog. The icon ships as a plain `.icns` file, byte-identical to the one in the source tree.
- The project's publication check now inspects images strictly. Every PNG must be plain, and is decoded and OCR-checked, including against white and black backgrounds where it's transparent and in each colour channel. OCR can still miss very small text. JPEG and SVG are refused.
- Release files are built and checked locally, then uploaded by hand. GitHub's runners verify, but no longer upload anything.

## Known limitations

- Slack turns headings and bold into italics and flattens nested bullets when you paste.
- The print dialog's "Save as PDF" can't work in a read-only app. Use ⌥⌘P (Open as PDF in Preview) instead.
- The Quick Look preview is static: diagrams appear as source, and images as placeholders.
- Remote images never load. Plugin queries, such as Dataview, aren't run.

## Checks for this release

- **Automated:** the Swift and renderer test suites; a renderer bundle reproducibility check; entitlement and icon-payload gates; and the publication check on the source tree, the notes, the history and every uploaded file, with the DMG mounted.
- **Manual,** on the maintainer's Mac:
  - the verification checklist, including the redesigned reader and library, the graph toggles and empty states, the window at its minimum size, light and dark mode, Open as PDF, and the icon in Finder;
  - a Release-build signature, entitlement and architecture (arm64) review.
- **Not verified for this build:**
  - Quick Look of the new build: Finder kept using an older registered copy.
  - The smallest Finder list-view icon and the Dock icon.
  - What VoiceOver actually says aloud.

Full changes: [CHANGELOG](https://github.com/felizvida/obviewer/blob/main/CHANGELOG.md).
