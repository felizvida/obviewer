# Architecture

This document explains how the repository is structured today, why it is structured that way, and where the current pressure points are.

## Architectural Goals

The architecture is optimized for five things:

1. preserving a read-only vault access model
2. keeping vault access and parsing separate from UI rendering
3. making the reader experience feel native and premium on macOS
4. keeping the core logic portable and testable
5. supporting future modernization without rewriting the entire app

## Module Layout

The package is split into these primary products:

1. `ObviewerCore`
2. `ObviewerFixtureSupport`
3. `ObviewerMacApp`
4. `ObviewerFixtureTool`
5. `ObviewerDocsTool`
6. `Obviewer`

### `ObviewerCore`

Portable models and services:

- vault models and snapshot lookup
- note graph generation
- markdown parsing
- vault indexing and progress reporting

### `ObviewerFixtureSupport`

Shared tooling for synthetic vault generation. This is intentionally separate so tests, manual smoke runs, and documentation tooling can all use the same fixtures.

### `ObviewerMacApp`

macOS shell and UI:

- `AppModel`
- security-scoped access lifecycle
- bookmark persistence
- vault picker integration
- SwiftUI/AppKit views
- documentation screenshot renderer

### `ObviewerFixtureTool`

CLI for generating rich sample vaults.

### `ObviewerDocsTool`

CLI for generating the screenshots used by the docs.

### `Obviewer`

Thin executable that launches the macOS app.

## High-Level Data Flow

The main runtime flow is:

1. the app launches and creates `AppModel`
2. `AppModel` attempts bookmark restore if applicable
3. the user chooses a vault through `VaultPicker`
4. security-scoped access starts
5. `VaultReader` enumerates files and emits loading progress
6. markdown notes are parsed by `ObsidianParser`
7. notes and attachments become a `VaultSnapshot`
8. `VaultSnapshot` derives lookup tables and a `NoteGraph`
9. `AppModel` starts a vault watcher after a successful load
10. filesystem changes trigger debounced, path-aware reload batches through the same loader boundary
11. `ContentView` renders the library shell
12. `ReaderView` renders note content and attachment flows
13. `GraphView` renders local/global graph exploration
14. link navigation resolves back through `VaultSnapshot`

## Top-Level Components

### Application Entry Point

File:

- `Sources/Obviewer/ObviewerApp.swift`

Responsibilities:

- create the shared `AppModel`
- define the main window
- expose command/menu actions for opening and reloading a vault

### AppModel

File:

- `Sources/ObviewerMacApp/AppModel.swift`

Responsibilities:

- own the current `VaultSnapshot`
- track vault URL, loading state, errors, and current selection
- manage search input and graph scope state
- orchestrate choose, restore, and reload flows
- react to filesystem changes through a watcher service
- seed cold loads from a persisted snapshot cache when safe to do so
- bridge UI actions into core lookup/navigation behavior

Important design choice:

- the UI never reads the filesystem directly
- platform services are injected through protocols, which keeps orchestration testable without `NSOpenPanel`, `UserDefaults`, or live security-scoped URLs

### VaultSnapshot And Models

File:

- `Sources/ObviewerCore/Models/VaultModels.swift`

Responsibilities:

- define `VaultSnapshot`, `VaultNote`, `VaultAttachment`, render models, and graph models
- normalize note and attachment references
- resolve links source-relatively
- provide precomputed note-search matching in core
- build the note graph and graph subgraphs

Important design choices:

- the render model is intentionally presentation-oriented rather than a full markdown AST
- note and attachment lookup prefer source-relative resolution to handle duplicate filenames sanely
- note search is derived in core from a precomputed per-note search corpus instead of ad hoc UI filtering
- graph data is derived and stored with the snapshot instead of being recomputed in the UI

### VaultReader

File:

- `Sources/ObviewerCore/Services/VaultReader.swift`

Responsibilities:

- enumerate vault contents
- classify notes and attachments
- read note contents through read-only APIs
- emit progress updates
- reuse unchanged notes and patch only affected files during watched reloads
- accept warm-start seed snapshots from persistent cache storage
- produce the final snapshot

Important design choices:

- hidden files and package descendants are skipped
- attachments are indexed broadly even if only some kinds get rich rendering today
- file access stays in one service boundary, which is important for the read-only guarantee

Pressure points:

- the current persistent cache stores parsed notes, attachment metadata, and search corpora, but not richer global index state
- reloads are path-aware now, but there is still no deeper persistent index for very large vaults
- frontmatter is still intentionally shallow and does not yet model nested YAML objects

### ObsidianParser

File:

- `Sources/ObviewerCore/Services/ObsidianParser.swift`

Responsibilities:

- convert markdown into render blocks and inline runs
- extract title, preview text, tags, headings, and outbound links
- classify note links, attachment links, and heading anchors
- parse image embeds and sizing hints

Supported constructs today include:

- frontmatter extraction for scalar values and arrays
- headings and heading anchors
- paragraphs
- ordered, unordered, nested, and task lists
- block quotes
- Obsidian callouts
- fenced code blocks
- inline wiki links
- inline markdown links
- inline code, emphasis, and strong emphasis
- image embeds and size hints
- footnotes
- GFM-style tables
- horizontal rules
- inline tags
- graceful fallback blocks for Mermaid, math-like fenced blocks, and standalone non-image embeds

Pressure points:

- still not full CommonMark plus full Obsidian fidelity
- advanced nested formatting is limited
- rendered Mermaid, rendered math, and embedded media still need deeper work even though fallback rendering now exists

### Reader Surfaces

Files:

- `Sources/ObviewerMacApp/Views/ContentView.swift`
- `Sources/ObviewerMacApp/Views/ReaderView.swift`
- `Sources/ObviewerMacApp/Views/RichTextView.swift`

Responsibilities:

- render the split-view shell
- render note metadata and block content
- handle inline navigation
- render inline images and richer attachment actions
- provide table-of-contents navigation and image lightbox behavior

Design intent:

- the UI should feel editorial and calm rather than utilitarian
- the reading surface should stay primary even when the graph and sidebar are visible

### Graph Workspace

File:

- `Sources/ObviewerMacApp/Views/GraphView.swift`

Responsibilities:

- render local and global graph views
- provide graph inspector details
- compute view positions from graph data
- reflect search scope and current note context

Important design choice:

- graph rendering is intentionally derived from `NoteGraphSubgraph`, not from ad hoc UI-only graph calculations

Pressure points:

- the graph is useful today but still early in UX maturity
- large-graph performance, layout polish, filtering, and interaction depth still need work

### Platform Services

Files:

- `Sources/ObviewerMacApp/Services/BookmarkStore.swift`
- `Sources/ObviewerMacApp/Services/SecurityScopedAccessController.swift`
- `Sources/ObviewerMacApp/Services/VaultPicker.swift`
- `Sources/ObviewerMacApp/Services/VaultWatcher.swift`
- `Sources/ObviewerMacApp/Services/VaultNoteCacheStore.swift`

Responsibilities:

- persist and restore vault bookmarks
- own the security-scoped access lifecycle
- bridge to `NSOpenPanel`
- observe vault directories and notify the app model about filesystem changes
- persist warm-start snapshot seeds outside the vault for cold-load reuse

Why this matters:

- these services are part of the actual safety story, not just convenience code

### Documentation And Fixture Tooling

Files:

- `Sources/ObviewerFixtureSupport/DemoVaultBuilder.swift`
- `Sources/ObviewerFixtureTool/main.swift`
- `Sources/ObviewerMacApp/Documentation/DocumentationScreenshotRenderer.swift`
- `Sources/ObviewerDocsTool/main.swift`

Responsibilities:

- generate realistic vaults for manual and automated testing
- render documentation screenshots from the actual app

Why it matters:

- this tooling keeps docs, testing, and product discussion anchored to real UI and real data shapes

## Testing Strategy

Test targets:

- `Tests/ObviewerCoreTests`
- `Tests/ObviewerMacAppTests`

What is covered well:

- parser behavior
- note and attachment resolution
- note graph behavior
- vault enumeration against real temporary directories
- app-model orchestration and state transitions
- selected view-support utilities

What is not covered enough yet:

- SwiftUI snapshot or visual regression tests
- accessibility behavior
- performance benchmarks for very large vaults
- signed distribution validation

## Architectural Strengths

- clear separation between core domain logic and macOS shell concerns
- strong testability for non-UI logic
- read-only mental model is reinforced in the structure, not just the marketing
- fixture and docs tooling reduce hand-wavy product discussion

## Architectural Pressure Points

- parser and render model are becoming feature-rich enough to deserve a more formal structure
- large-vault performance will need incremental indexing, caching, and observation
- the graph stack needs clearer layout and interaction abstractions as it matures
- shipping distribution is still adjacent to the codebase rather than fully integrated into product delivery

## Modernization Direction

The next architectural moves should be:

1. strengthen the shipping app container and distribution path
2. formalize parser/renderer boundaries before content fidelity expands too far
3. add indexing and observation infrastructure for scale
4. harden UI quality with accessibility and snapshot-style regression coverage

Those steps are sequenced in [`MODERNIZATION_PLAN.md`](./MODERNIZATION_PLAN.md).
