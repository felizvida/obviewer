# Project Handoff

This is the best starting point for a new maintainer.

It is written with an explicit zero-memory assumption: if something is not documented here or in the linked docs, treat it as unknown.

## What This Project Is

`Obviewer` is a native macOS reader for local Obsidian vaults.

It is intentionally not:

- a note editor
- a sync client
- a second Obsidian implementation
- a web app or Electron wrapper
- a general-purpose file browser with broad write access

The central promise is simple:

> Open a local Obsidian vault, render it beautifully, and keep the vault read-only by design and by OS enforcement.

## Why This Exists

The product idea is a reading room, not a productivity cockpit.

The original requirement set that shaped the project was:

- macOS native
- local files only
- absolute read-only behavior
- premium, editorial-quality reading experience

Trust outranks feature count. Reading quality outranks management features.

## Current State As Of March 23, 2026

The repository is a working prototype with a healthy development foundation.

What exists today:

- split package architecture: `ObviewerCore`, `ObviewerMacApp`, and `Obviewer`
- SwiftUI app shell with note library, reader workspace, and graph workspace
- vault loading with progress reporting, live watching, and path-aware selective reloads
- security-scoped bookmark restore flow
- Obsidian-aware parsing for links, callouts, tables, tags, headings, footnotes, image embeds, and unsupported-content fallback blocks
- inline image rendering with size hints and image lightbox behavior
- note graph construction with local/global graph exploration
- synthetic-vault generation for realistic manual and integration testing
- documentation screenshot generation from the real app
- local Xcode validation with a working full-Xcode setup
- green GitHub CI and tag-driven source release automation
- warm-start snapshot cache for faster cold launches without writing into the vault
- Apache 2.0 licensing and standard repo governance files

What does not exist yet:

- a published signed/notarized `.app` or `.dmg`
- App Store distribution
- full CommonMark plus Obsidian fidelity
- deeper large-vault incremental indexing and persistent state beyond the current snapshot cache
- accessibility audit and VoiceOver hardening
- UI snapshot testing
- performance instrumentation for very large vaults

## Most Important Invariant

The most important invariant is:

**The app must never write to the user's vault.**

That is not just a UI rule. It is a product, architecture, platform, and release requirement.

The current protection strategy is:

1. keep the shipping app sandboxed
2. request only `com.apple.security.files.user-selected.read-only`
3. acquire vault access through user choice
4. persist access via security-scoped bookmarks
5. funnel vault I/O through reader-only services with no write surface
6. refuse unsigned release packaging that would drop the entitlements story

Any change that weakens this chain should be treated as a high-risk regression.

## Current Architecture In One Paragraph

`AppModel` orchestrates vault loading, bookmark restore, search state, graph state, navigation, watched reloads, and warm-start cache reuse. `VaultWatcher` turns filesystem changes into path-aware reload batches, `VaultNoteCacheStore` persists snapshot seeds outside the vault, and `VaultReader` applies changes by reusing untouched notes and attachments while reparsing only affected files. `ObsidianParser` produces simplified render blocks plus outbound links, tags, headings, and metadata. `VaultSnapshot` stores notes, attachments, lookup tables, a precomputed search corpus, and the derived `NoteGraph`. `ContentView` hosts the split-view shell, `ReaderView` renders notes into the reading surface, `RichTextView` handles inline content, and `GraphView` renders the graph workspace. Supporting tools generate demo vaults and documentation screenshots from the same real UI stack.

For the full breakdown, read [`ARCHITECTURE.md`](./ARCHITECTURE.md).

## Verification Status

Current verification is in a much better place than the original bootstrap period:

- local `swift test` works with full Xcode selected
- local `xcodebuild ... test` works
- GitHub CI is green on `macos-14` and `macos-15`
- GitHub tag releases are publishing source archives successfully

This means the repo is healthy for normal development. The main missing verification layers are distribution validation, accessibility validation, and UI-level regression coverage.

## Immediate Recommended Next Steps

If you are taking the project over, start here:

1. read [`STATUS.md`](./STATUS.md) and [`MODERNIZATION_PLAN.md`](./MODERNIZATION_PLAN.md)
2. run the app locally with `make try-local`
3. generate and browse `build/SampleVault` with `make demo-vault`
4. confirm the sandbox/read-only assumptions in `Configuration/Obviewer.entitlements`
5. choose the next workstream from the modernization plan rather than improvising

Recommended default sequence:

1. finish the shipping distribution path
2. improve parser and renderer fidelity
3. improve performance and live refresh behavior
4. refine graph, media, accessibility, and visual polish

## Things That Can Mislead A New Maintainer

### Trap 1: confusing "no edit button" with true read-only safety

The real protection comes from sandboxing, entitlements, and a codebase with no write path.

### Trap 2: assuming the current parser is a full markdown engine

It is a useful and increasingly capable product parser, but it is still not full CommonMark plus full Obsidian parity.

### Trap 3: assuming green CI means the app is product-complete

The core and orchestration tests are solid, but distribution, accessibility, and large-vault performance still need major work.

### Trap 4: treating every rendering issue as a UI problem

Some defects belong in parsing, some in lookup, and some in rendering. Follow the data flow before patching UI code.

## Decisions Already Made

These decisions are already encoded in the repo:

- macOS-first is intentional
- local-only access is intentional
- SwiftUI is the default UI direction
- AppKit interop is acceptable when native macOS behavior requires it
- editorial visual design is part of the product, not decoration
- Apache 2.0 is the default project license
- the repo should stay understandable from the docs alone

## Decisions Still Open

These choices remain open and should be made deliberately:

- Developer ID direct distribution versus Mac App Store as the primary shipping channel
- in-house parser evolution versus adopting a stronger markdown engine
- whether the next major UI investment stays mostly in SwiftUI or adds deeper AppKit text/layout support
- how ambitious the first public distribution milestone should be
- whether to add an auto-update system before or after App Store evaluation

## Read Next

If you only have limited time, read these in order:

1. [`../README.md`](../README.md)
2. [`STATUS.md`](./STATUS.md)
3. [`PRODUCT.md`](./PRODUCT.md)
4. [`ARCHITECTURE.md`](./ARCHITECTURE.md)
5. [`DEVELOPMENT.md`](./DEVELOPMENT.md)
6. [`MODERNIZATION_PLAN.md`](./MODERNIZATION_PLAN.md)
