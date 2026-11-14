# Manual Verification

CI compiles and tests Obviewer but never launches it. WebKit, sandbox, Finder and Quick Look behavior must be checked in a running build. This is the checklist, with the result of the latest run.

**Latest run:** November 13–14, 2026, Debug build on Apple silicon, macOS 26.7, Xcode 27.2, by an automated assistant on the maintainer's Mac with the maintainer's approval for each system-level step. Rules followed:

- disposable copies of fixtures
- no product changes during testing
- settings restored afterwards

## Setup

```bash
make xcodeproj
xcodebuild -project Obviewer.xcodeproj -scheme Obviewer -configuration Debug -destination 'platform=macOS' build
```

Test data:

- `Fixtures/notes/`, opened as a folder
- `Fixtures/notes/dokuwiki`
- `make demo-vault`, which produces `build/SampleVault` (Obsidian)

For diagnostics, use Help › Copy Reader Diagnostics, or `log stream --predicate 'subsystem == "com.felizvida.obviewer"'`. The Web Inspector is available via Safari › Develop.

## Checklist

| # | Check | Latest result |
| --- | --- | --- |
| 1 | `obsidian-basics.md` renders: bold containing a link, a foldable callout with a list, the tip callout, three tasks, inline and display math, a drawn Mermaid diagram, Python highlighting, a footnote, and the title shown once | Pass |
| 2 | `tricky-emphasis.md`: no stray italics; "$5 and $10" stays text | Pass |
| 3 | `gfm-readme.md`: two GitHub alerts, a table with a pipe inside code, `<details>`, and the remote badge shown as "Remote image not loaded" | Pass |
| 4 | `hostile-html.md`: no script runs; no inputs, forms, iframes or event handlers; `javascript:`/`file:` links inert; remote loads blocked (CSP entries in the reader log); `<details>` works | Pass (Web Inspector DOM query) |
| 5 | Links: cross-note wiki links, `[[#Tasks]]`, missing-note notice, web link opens the browser, `obsidian://` asks first | Pass |
| 6 | Back/forward: ⌘[ ⌘] and toolbar | Pass |
| 7 | Outline: toolbar menu and Note › Go to Heading jump to headings | Pass |
| 8 | Find: ⌘F, Return, ⌘G, ⇧⌘G, Esc | Pass |
| 9 | Linked mentions under a well-linked demo-vault note | Pass |
| 10 | Dark mode (Settings › Reading › Appearance): sidebar, reader, code, callouts, diagrams readable | Pass |
| 11 | Sidebar has a sensible width and resizes | Pass |
| 12 | ⌘= ⇧⌘= ⌘- ⌘0 and ⌥⌘] ⌥⌘[ | Pass |
| 13 | Edit in… (⌘E) opens Sublime Text (never Spyder); a save refreshes Obviewer in about a second while keeping the scroll position, in folder and single-file mode | Pass |
| 14 | `open -a Obviewer note.md` opens a note window; relative images trigger the folder-access banner; Allow Access fixes them | Pass |
| 15 | After Get Info › Open with › Obviewer › Change All, double-clicking a `.md` file opens a note window | Pass. The Settings button wasn't tested. |
| 16 | Quick Look (Space): static preview; raw HTML in `hostile-html.md` appears as literal text | Pass |
| 17 | Copy for Slack into Slack; Copy as Rich Text into Mail and Word | Mail and Word pass (local images become placeholders; Mail changes the code font). Slack: text, code and tables arrive, but headings and bold become italics and nested bullets flatten. Nothing was sent. |
| 18 | Print (⌘P) previews; Open as PDF in Preview (⌥⌘P) gives a paginated PDF in the container's temporary folder; Share as PDF offers the share sheet; no files appear in the notes folder | Pass. The print dialog's own "Save as PDF" is unsupported by design. |
| 19 | DokuWiki: detection, links, media, flavor badge round trip | Pass |
| 20 | Settings › Reading › classic reader toggles and restores | Pass |

## Release build and distribution

Before publishing a release, also check:

- `make package-adhoc`, then `codesign -dv --verbose=4` and `codesign -d --entitlements :-` on `build/Build/Products/Release/Obviewer.app` and on its `Contents/PlugIns/ObviewerQuickLook.appex`. Expect an ad-hoc signature, the hardened runtime flag, and only the allowed entitlements: **no `get-task-allow`**.
- Mount the DMG read-only and check it contains only the app, an Applications link, "Read Me First - How to Install.md", an empty `.metadata_never_index` and a `.fseventsd` folder holding at most an empty `no_log`. `verify_dmg` enforces this.
- Launch the Release app from the build folder, **and** the copy inside the mounted DMG, and confirm the reader renders. Debug builds can hide loader problems, because they carry the debugger entitlement.
- Quick Look with the Release build: macOS may pick any registered copy of the extension with the same version (for example a Debug build). Build with a distinct `CURRENT_PROJECT_VERSION`, run `pluginkit -m -v -p com.apple.quicklook.preview`, and confirm that the provider path that runs is the Release bundle's before judging the preview.
- `node scripts/publication-check.mjs dist <notes>` on the exact upload set. It must report 0 prohibited references **and 0 incomplete**.

**Latest run (`v0.3.0-beta.1`, build 3):** November 14, 2026, on the same Mac, by the same assistant.

| Check | Result |
| --- | --- |
| Clean Release build, then `make package-adhoc` | Pass: "Verified mounted DMG" (staged app, writable volume and final image gates) |
| Mounted DMG: strict signatures on the app and the Quick Look extension, hardened runtime, exact entitlements | Pass, checked separately from the packaging scripts |
| No Finder info or resource forks | Pass. macOS adds `com.apple.provenance` attributes, which are expected and don't affect signatures. |
| Image root: app, Applications link, install guide, empty `.metadata_never_index`, `.fseventsd` holding only an empty `no_log` | Pass |
| App launched from inside the mounted DMG renders a sample note (callout, tasks, Mermaid, math) | Pass. The running process path was confirmed to be inside the image. |
| Quick Look with the Release extension confirmed as the running provider | Pass on build 2 of the same source; Swift, renderer and resources are unchanged since |
| `publication-check` on the mounted DMG and the release notes | Pass: 67 items, 0 prohibited references, 0 incomplete; no file-event logs in the image |
| Swift 132/132, Node 86/86, bundle check, tracked-tree publication check | Pass |

**Still open:**

- an install on a second Mac, including the update path (does folder access survive?)
- rendering time on a 5,000-line note and on a large vault
- an accessibility pass
