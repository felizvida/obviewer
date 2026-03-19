# Project Handoff

This file is the single best starting point for a new maintainer.

It is written with an explicit zero-memory assumption: if previous context is not written here or in the linked documentation, it should be treated as unknown.

## What This Project Is

`Obviewer` is intended to become a native macOS reader for local Obsidian vaults.

The project is not trying to become:

- A note editor
- A sync client
- A generic markdown viewer with arbitrary write access
- A web app or cross-platform Electron wrapper

The core promise is simple and strict:

> Open a local Obsidian vault and present it beautifully, while making vault mutation impossible in the shipping product.

## Why This Exists

The design goal is a first-class reading experience rather than a productivity dashboard.

The user requirement that shaped everything else was:

- Native macOS only
- Local files only
- Absolute read-only behavior
- Premium, contemporary, editorial-quality reading experience

In other words, safety is more important than feature count, and the reading experience is more important than editing power.

## Current Project State

The repository currently contains an initial scaffold, not a finished application.

What exists today:

- A Swift package for macOS
- A split package architecture with `ObviewerCore`, `ObviewerMacApp`, and `Obviewer`
- A SwiftUI application entry point
- A split-view UI with searchable, folder-grouped note navigation and a reading surface
- A local vault reader that enumerates markdown notes and vault attachments
- Security-scoped bookmark support to reopen the last selected vault
- An Obsidian-aware parser that now supports inline links, tables, headings, callouts, tags, and image embeds
- A table-of-contents rail in the reader for scalable in-note navigation
- XcodeGen-based app-project scaffolding plus scripts for building a signed release bundle
- Core and app-state regression tests
- GitHub repository metadata, CI, issue templates, and contributor docs

What does not exist yet:

- A full Xcode app project configured for shipping as a notarized `.app`
- A fully compliant CommonMark plus Obsidian parser
- Rich rendering for footnotes, Mermaid, PDFs, audio, or video
- File watching for live vault refresh
- A selected open-source license

## Most Important Invariant

The single most important invariant in the project is:

**The app must never write to the user's vault.**

This is not just a UI requirement. It is a platform, architecture, and testing requirement.

The current strategy is:

1. Use App Sandbox.
2. Grant only `com.apple.security.files.user-selected.read-only`.
3. Acquire vault access via `NSOpenPanel`.
4. Persist access using a security-scoped bookmark.
5. Centralize vault I/O behind a reader-only service with no write API.

If any future change weakens this chain, that change should be treated as a high-risk regression.

## Current Architecture In One Paragraph

`AppModel` is the control center. It asks the user to choose a vault, starts security-scoped access, invokes `VaultReader` to scan the directory and parse markdown files, stores the resulting `VaultSnapshot`, and feeds that data into SwiftUI views. `ContentView` presents the note list and shell chrome. `ReaderView` renders parsed note blocks into a premium reading surface. `BookmarkStore` persists the last chosen vault. `ObsidianParser` converts markdown text into simplified render blocks and extracts links and tags.

For details, read [`ARCHITECTURE.md`](./ARCHITECTURE.md).

## Current Verification Status

Parser tests exist, but full local verification was blocked on the machine used to bootstrap this repo because it had Command Line Tools active instead of a fully matched Xcode toolchain.

Practically, that means:

- The repository is structurally ready for Xcode and GitHub Actions.
- The maintainer taking over should validate the project on a Mac with full Xcode installed before making broader product assumptions.

Read [`DEVELOPMENT.md`](./DEVELOPMENT.md) before spending time on build issues, because the most likely failure mode is toolchain configuration rather than application logic.

## Immediate Recommended Next Steps

If you are picking this project up fresh, do these steps first:

1. Install full Xcode and ensure it is the active developer directory.
2. Open the package and confirm it builds on a clean macOS machine.
3. Convert or wrap the package into a true sandboxed macOS app target.
4. Verify the entitlements are attached and codesigning is correct.
5. Test with a real Obsidian vault containing links, images, callouts, and nested folders.
6. Decide whether the next priority is parser fidelity or shipping the sandboxed app shell.

Recommended default priority:

- Ship the app container and validate the read-only guarantee first
- Improve markdown fidelity second
- Expand media and Obsidian feature coverage third

## What To Be Careful About

There are several traps that a new maintainer could fall into:

### Trap 1: Confusing "no edit button" with read-only safety

Removing edit controls is not enough. The real protection must come from the sandbox entitlement model and the absence of write paths in code.

### Trap 2: Assuming the parser is complete

The parser is intentionally lightweight. It is a useful starting point, not a finished markdown engine.

### Trap 3: Assuming the Swift package is the final app shape

The package is a practical bootstrap format. The intended shipping output is a sandboxed macOS app.

### Trap 4: Treating unsupported Obsidian constructs as bugs in the UI

Some gaps are parser limitations rather than rendering bugs. Distinguish parsing issues from view-layer issues before changing UI code.

## Decisions Already Made

The following decisions are already embodied in the repository:

- Native SwiftUI is the preferred UI direction.
- AppKit interop is acceptable when native macOS behavior requires it.
- The visual design should feel editorial, warm, and deliberate rather than generic utility software.
- Local-only access is intentional.
- The repository should remain easy for a later maintainer to understand from documents alone.

## Decisions Still Open

The following important decisions are not finalized yet:

- Which open-source license, if any, should be applied
- Whether to keep the app as pure SwiftUI or introduce more AppKit for advanced text rendering
- Whether to build a richer parser in-house or adopt an external markdown/rendering package
- How ambitious the first shippable scope should be
- Whether GitHub Discussions should become an active planning surface or remain mostly dormant

## Files To Read Next

If you only have a little time, read these in order:

1. [`../README.md`](../README.md)
2. [`PRODUCT.md`](./PRODUCT.md)
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md)
4. [`DEVELOPMENT.md`](./DEVELOPMENT.md)
5. [`STATUS.md`](./STATUS.md)
