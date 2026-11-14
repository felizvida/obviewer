# Architecture

This page describes how Obviewer 0.3 is built. The reader itself (WebKit host, renderer, and where each safety guarantee is enforced) is covered in more depth in [`READER_ARCHITECTURE.md`](./READER_ARCHITECTURE.md). The pre-redesign architecture is preserved in [`history/ARCHITECTURE_v0.2.8.md`](./history/ARCHITECTURE_v0.2.8.md).

## Goals

1. **Notes stay read-only,** enforced by the macOS sandbox rather than by convention.
2. **Faithful rendering** of GitHub, Obsidian and DokuWiki text, including diagrams and math, offline.
3. **A native shell:** SwiftUI windows, menus, Finder and Quick Look integration.
4. **Testable layers:** indexing and link rules have no UI dependency, and the renderer runs in Node tests.

## Modules

| Module | Kind | Responsibility |
| --- | --- | --- |
| `ObviewerCore` | Swift library | Indexing: notes, frontmatter, tags, links, search, the note graph, and the snapshot model. Flavor detection (`ReadingInput`), `VaultReader` (Markdown or DokuWiki formats), and `WikiSyntax`/`DokuWikiSyntax` link rules shared in spirit with the renderer. `ObsidianParser` walks a note's blocks to classify links and tags; the blocks aren't stored. |
| `ObviewerReaderKit` | Swift library + resources | Hosts the renderer: `ReaderWebController` (WKWebView with locked-down configuration), `ReaderSchemeHandler` (`obviewer-asset://`), `VaultAssetResolver`, `ReaderPayloadBuilder` (embeds, backlinks, resolved links), `StaticPreviewRenderer` (JavaScriptCore, for Quick Look). `Resources/Reader/` is the built bundle. |
| `ObviewerMacApp` | Swift library | The app: `AppModel` (+`AppModel+Reader`) for state, history, link routing, find, sharing, Edit in…, live reload. Views: `ContentView`, `WebReaderView`, `NoteWindowView`, graph, settings, commands. Services: watchers, bookmarks, recents, `OpenRequestRouter`, `EditorHandoff`. |
| `Obviewer` | Executable | The SwiftUI `App`: a single library `Window`, a `WindowGroup` of note windows, Settings |
| `ObviewerQuickLook` | App extension (Xcode only) | Data-based Quick Look preview: renders static HTML via `StaticPreviewRenderer` |
| `Renderer/` | JavaScript (not a Swift module) | markdown-it + plugins, DokuWiki renderer, Slack/rich-text export, page assembly. `build.mjs` bundles it into `ObviewerReaderKit/Resources/Reader`. |
| `ObviewerFixtureSupport`, `ObviewerFixtureTool`, `ObviewerBenchmarkTool` | Tooling | Demo vault generation and indexing benchmarks. Screenshots come from the running app, because offscreen capture can't draw WebKit. |

`Package.swift` builds everything except the Quick Look extension. `project.yml` (XcodeGen) generates the Xcode project. There, the internal modules are **static libraries** linked into the app and the extension (see [`DEVELOPMENT.md`](./DEVELOPMENT.md#why-the-modules-are-static-libraries)), and the reader bundle is copied into each of those bundles.

## Opening something

1. A URL arrives from one of: File › Open, Open Recent, Finder (`ObviewerAppDelegate` → `OpenRequestRouter`), a launch argument, or the saved bookmark. Folders go to the library window; note files get their own `NoteWindowView`, each with its own `AppModel`.
2. `DefaultReadingInputAdapter` makes a `ReadingInputSource`: folder or single file, plus a profile.
   - Obsidian if the folder has `.obsidian/`.
   - DokuWiki if it finds `data/pages` (or `pages` + `media`), or for a `.txt` inside a `data/pages` tree.
   - Markdown otherwise.
3. `AppModel` starts security-scoped access and runs `VaultReader` off the main thread. Folders are scanned; for DokuWiki only `pages` and `media` are scanned. A single file becomes a one-note snapshot.
4. The `VaultSnapshot` builds lookup tables (paths, names, titles, aliases) and the `NoteGraph`. Folder snapshots are cached in the app container to speed up the next launch.
5. Watching:
   - Folders use directory kqueues plus a file-level FSEvents stream, which catches in-place saves. Changes trigger debounced, path-aware selective reloads.
   - Single files use `SingleFileWatcher`, which follows atomic replacement.
6. Each load bumps `renderRevision`, and the reader re-renders the selected note while keeping the scroll position.

## Rendering a note

`AppModel.refreshReader` builds a `ReaderRenderPayload` off the main thread with `ReaderPayloadBuilder`:

- the note source, read with `NoteSourceLoader` (16 MB cap, non-UTF-8 tolerant)
- header metadata and backlinks
- which wiki links resolve
- the tree of pre-resolved `![[embeds]]`: depth 4, 64 per note, 6 MB total, cycle detection

The payload goes to `window.obviewer.render` in the WebKit page. The page renders, sanitizes and posts events back, such as link clicks, outline headings and asset errors, which `AppModel` routes. See [`READER_ARCHITECTURE.md`](./READER_ARCHITECTURE.md).

## Two parsers, one set of rules

The Swift indexer and the JS renderer each recognize links. `Fixtures/notes/expectations.json` lists the links each fixture note contains. Both `Renderer/test/fixtures.test.js` and `Tests/ObviewerCoreTests/SharedFixtureLinkTests.swift` check it, so any disagreement fails a test. Add a fixture case whenever you change either side.

## Windows and commands

- **The library window** is a single `Window` scene that owns the app-wide `AppModel` and its web reader.
- **Note windows** are a `WindowGroup(for: NoteWindowRequest.self)`. Each request carries a read-only security-scoped bookmark, so restored windows keep access after relaunch.
- **Menu commands** act on the focused window's model through `@FocusedObject`.
- **⌘= / ⌘+** are handled by a local key monitor, because a focused WKWebView sees key equivalents before the menu does.

## Testing

- Renderer: `cd Renderer && npm test` (renderer, Quick Look bundle, export, DokuWiki, shared fixtures, publication check). `node build.mjs --check` verifies the committed bundle.
- Swift: `swift test` (tests across `ObviewerCoreTests`, `ObviewerReaderKitTests`, `ObviewerMacAppTests`). Highlights:
  - shared fixture link agreement
  - payload builder with embeds and cycles
  - asset path containment
  - page event parsing
  - bundle presence, CSP and content rules
  - the JavaScriptCore static preview
  - the real file watcher (in-place, atomic and new-file saves)
  - history, editor choice, text-size steps
  - entitlement allow-lists
- Manual: [`VERIFICATION.md`](./VERIFICATION.md). Results: [`STATUS.md`](./STATUS.md).
