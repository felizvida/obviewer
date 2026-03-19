# Architecture

This document explains how the current repository is structured and why it is structured that way.

## Architectural Goals

The architecture is optimized for four things:

1. Enforcing a read-only mental model
2. Keeping vault access logic separate from UI logic
3. Making the reader experience feel native and premium on macOS
4. Making core logic portable and testable outside the macOS shell

## Module Layout

The package is now split into three targets:

1. `ObviewerCore`
2. `ObviewerMacApp`
3. `Obviewer`

`ObviewerCore` contains the domain types and logic that should remain portable across future platforms.

`ObviewerMacApp` contains the platform shell for macOS only:

- `AppModel`
- bookmark persistence
- vault picking
- security-scoped access lifecycle
- SwiftUI and AppKit rendering

`Obviewer` is intentionally thin and only launches the app.

## High-Level Data Flow

The current flow looks like this:

1. The app launches.
2. `ContentView` asks `AppModel` to restore the last vault if a bookmark exists.
3. If the user chooses a vault, `VaultPicker` returns a directory URL.
4. `AppModel` starts security-scoped access for that URL.
5. `VaultReader` enumerates the vault folder.
6. Markdown files are parsed by `ObsidianParser`.
7. Parsed notes and attachment metadata are assembled into a `VaultSnapshot`.
8. `ContentView` shows the note list.
9. `ReaderView` renders the selected note.
10. Outbound links are resolved back into note IDs through `VaultSnapshot`.

## Top-Level Components

### Application Entry Point

File:

- `Sources/Obviewer/ObviewerApp.swift`

Responsibility:

- Creates the shared `AppModel`
- Defines the main window
- Adds command menu items for opening and reloading the vault

Why it matters:

- This is where app-level behavior should stay centralized instead of leaking into random views.

### AppModel

File:

- `Sources/ObviewerMacApp/AppModel.swift`

Responsibility:

- Owns the current `VaultSnapshot`
- Tracks the current vault URL
- Tracks loading and error state
- Holds search state and selected note state
- Loads the vault asynchronously
- Restores persisted bookmark access
- Starts and swaps security-scoped access
- Resolves navigation from outbound links

Why it matters:

- `AppModel` is the current orchestration layer.
- If future contributors are unsure where a behavior belongs, this is usually the first place to inspect.

Important design choice:

- The UI does not read the file system directly.
- All vault loading flows through the model and the reader service.
- `AppModel` now receives its platform services through injected protocols, which keeps orchestration testable without `NSOpenPanel`, `UserDefaults`, or live security-scoped URLs.

### Vault Models

File:

- `Sources/ObviewerCore/Models/VaultModels.swift`

Responsibility:

- Defines `VaultSnapshot`, `VaultNote`, `VaultAttachment`, `RenderBlock`, and `CalloutKind`
- Provides link normalization and lookup logic

Why it matters:

- These types are the contract between the parser, the file reader, and the UI.
- Any rendering feature usually starts with a model change here.

Important design choice:

- `RenderBlock` is intentionally simplified.
- It is not a complete markdown AST.
- It is a presentation-friendly intermediate format for the current UI.

### BookmarkStore

File:

- `Sources/ObviewerMacApp/Services/BookmarkStore.swift`

Responsibility:

- Saves and restores a security-scoped bookmark to the chosen vault

Why it matters:

- This gives the app a smooth reopen experience without widening file access permissions.

Important design choice:

- Bookmark storage goes through `UserDefaults` for simplicity.
- If bookmark management gets more complex later, this service is the right place to evolve it.

### VaultPicker

File:

- `Sources/ObviewerMacApp/Services/VaultPicker.swift`

Responsibility:

- Presents `NSOpenPanel` configured for directory selection only

Why it matters:

- User-selected access is part of the security story.
- The project should not silently assume access to arbitrary filesystem locations.

### VaultReader

File:

- `Sources/ObviewerCore/Services/VaultReader.swift`

Responsibility:

- Enumerates the vault directory
- Distinguishes notes from supported attachments
- Reads markdown file contents
- Parses notes via `ObsidianParser`
- Produces a `VaultSnapshot`

Why it matters:

- This is the main read-only filesystem boundary.

Important design choices:

- Hidden files and package descendants are skipped.
- Attachments are indexed broadly, but only some kinds currently receive richer reader treatment.
- File reading uses `FileHandle(forReadingFrom:)`, which reinforces the read-only intent.

What it does not do yet:

- No file watching
- No incremental indexing
- No caching
- No frontmatter field extraction beyond stripping the frontmatter block
- No embedded PDF/audio/video rendering

### ObsidianParser

File:

- `Sources/ObviewerCore/Services/ObsidianParser.swift`

Responsibility:

- Converts markdown text into simplified render blocks
- Extracts a display title
- Extracts preview text
- Extracts outbound wiki links
- Extracts inline tags
- Estimates reading time

Supported constructs today:

- YAML frontmatter stripping
- ATX headings
- Paragraphs
- Bullet lists
- Inline wiki links
- Inline markdown links
- Inline emphasis and strong emphasis
- Inline code spans
- Block quotes
- Obsidian callouts
- Fenced code blocks
- Standalone image embeds
- GFM-style tables
- Horizontal dividers
- Inline tags like `#research`

Why it matters:

- This is the largest current gap between "starter" and "polished product."
- The UI quality will quickly hit a ceiling unless parser fidelity improves.

What it does not do yet:

- Ordered lists
- Nested lists
- Task lists
- Footnotes
- Nested emphasis handling
- Mermaid blocks
- Embedded PDFs/audio/video
 - More advanced inline formatting combinations

### ContentView

File:

- `Sources/ObviewerMacApp/Views/ContentView.swift`

Responsibility:

- Builds the split-view shell
- Hosts the sidebar
- Drives the open/reload UI
- Displays the empty state and loading state
- Connects current app state to the reader surface

Design intent:

- The sidebar should feel lighter and more atmospheric than a typical productivity app.
- The app should open into a calm library-plus-reading-room layout.

### ReaderView

File:

- `Sources/ObviewerMacApp/Views/ReaderView.swift`

Responsibility:

- Renders the selected note
- Styles headings, paragraphs, quotes, code, callouts, and images
- Shows metadata pills
- Displays linked-note navigation

Design intent:

- Reading should feel more like a designed article than a note database.
- Large serif typography and warm surfaces are intentional.
- A right-side outline rail should make long notes easier to navigate without overwhelming the main reading column.

## Security Model

The current security model has two layers:

### Layer 1: Architectural Intent

- The codebase has no vault write API.
- Vault access is concentrated in `VaultReader`.
- The picker grants scoped access to a user-chosen folder.

### Layer 2: Platform Enforcement

- The shipping app target must be sandboxed.
- The app target must include only `com.apple.security.files.user-selected.read-only`.

This second layer is mandatory.

Without it, the product goal of "absolute read only" is only partially satisfied.

## Why The App Is Not Yet Finished Architecturally

The current architecture is appropriate for a scaffold, but not yet the final form.

There are at least three likely future evolutions:

1. Replace `RenderBlock` with a richer render tree or markdown AST bridge
2. Introduce a dedicated navigation and indexing layer when the vault gets large
3. Move from package bootstrap to a full Xcode app target with shipping settings

## Extension Guidelines

If you need to extend the app, prefer these patterns:

### When adding new markdown features

- Start with parser output shape
- Then update the render model
- Then add `ReaderView` support
- Finally add regression tests

### When adding new vault behaviors

- Keep filesystem access inside services
- Do not read files directly from views
- Do not introduce write code paths casually

### When adding new UI features

- Prefer premium readability over feature density
- Preserve the calm split-view structure unless there is a strong reason to change it
- Keep metadata secondary to the content body

## Architecture Summary

The current codebase is small on purpose:

- One model/orchestrator
- A few focused services
- A simple render model
- A premium reader UI

That small size is a feature. It should stay understandable even after the next maintainer has been away from it for months.
