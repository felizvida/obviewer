# Status

Last updated: November 14, 2026. Version: **0.3.0**, first published as the pre-release `v0.3.0-beta.1`.

This page records what works and has been checked, what is known to be limited, and what hasn't been verified. The other documents summarize; this one is the ledger.

## How it was checked

- **Automated:** Swift tests (`swift test`: 132 passing on the maintainer's Mac, including packaging, linkage and publication-gate tests) and Node tests (`cd Renderer && npm test`: 86, covering the renderer, the publication check and the release-script gates (run against mock tools)). `node build.mjs --check` confirms that the committed reader bundle matches its source. `node scripts/publication-check.mjs --tracked` passes.
- **Manual:** the checklist in [`VERIFICATION.md`](./VERIFICATION.md), run on the maintainer's Mac (Apple silicon, macOS 26.7, Xcode 27.2) with a Debug build, using the notes in `Fixtures/notes/` and a generated demo vault.
- **Not yet run on:** macOS 14 or 15, an Intel Mac, or a second Mac with an installed release build. From the next version on, Intel Macs aren't supported. CI builds and runs the Swift tests on GitHub's Apple silicon macOS 15 runner but never launches the app. GitHub no longer offers macOS 14 runners, so macOS 14, the deployment target, is untested.

## Works and verified on a Mac

| Area | What was checked |
| --- | --- |
| Reader | GitHub and Obsidian Markdown render, including callouts with lists, tasks with custom states, footnotes, tables, highlighted code, KaTeX math, and **Mermaid diagrams drawn offline**. The note title appears once. |
| Safety of note content | A hostile test note (`Fixtures/notes/hostile-html.md`): scripts don't run, there are no form controls or event handlers, `javascript:`/`file:` links are inert, and remote images are blocked and logged by the Content-Security-Policy. Inspected with Safari Web Inspector. |
| Navigation | Wiki links across notes, same-note `[[#heading]]`, missing-link notice, back/forward (⌘[ ⌘]), the Outline menu and Note › Go to Heading, Find (⌘F, ⌘G, ⇧⌘G), and Linked mentions under each note |
| Appearance | Dark mode in the sidebar, reader, code, callouts and diagrams; sidebar resizing; text size (⌘= ⌘- ⌘0) and line length (⌥⌘] ⌥⌘[) |
| Formats | Folder of Markdown, Obsidian vault (detected by `.obsidian/`), DokuWiki (`data/pages`) with namespaced links and media, and flavor override from the sidebar badge |
| Finder | Double-click opens a note window, after the user set Obviewer as the `.md` default via Get Info › Open with › Change All. `open -a Obviewer note.md` also works. A single note with relative images shows a banner; granting read-only access to its folder fixes the images. |
| Quick Look | Space bar preview in Finder, rendered as static HTML; raw HTML in the note is shown as text |
| Edit in… (⌘E) | Opens Sublime Text. Saving there refreshes Obviewer in under a second, in both folder and single-file mode, and keeps the scroll position. |
| Copy as Rich Text (⌥⌘C) | Pasted into Apple Mail and Microsoft Word: headings, emphasis, links, nested lists, the table and the diagram (as an image) survive. Task boxes come through as ☐/☑; this was retested in Word only. Mail changes the code font. Local images become "[image: …]" placeholders. |
| Copy for Slack (⇧⌘C) | Pasted into Slack: the text, code and table content arrive, but see Known limitations |
| Print and PDF | Print (⌘P) shows paginated previews. Open as PDF in Preview (⌥⌘P) produces a paginated PDF with math and diagrams. Share as PDF opens the share sheet. |
| Permissions | The signed app holds only the sandbox, read-only user-selected files, print, and outgoing network permissions. The Quick Look extension holds only the sandbox and read-only files. Checked on the built Debug app, and enforced by tests and the release scripts. |

## Measured

- **Indexing benchmark** (`make benchmark-vault PROFILE=integration`, the maintainer's Mac): a synthetic vault of 201 notes and 17 attachments, with 327 links. Results: cold load 781 ms, warm reload 27 ms, search 1.8 ms, global graph 1.2 ms, selective reload 36 ms. This measures the Swift indexer, not WebKit rendering.
- **Release build and DMG:** the Release app builds and signs ad-hoc. `v0.3.0-beta.1` is universal (arm64 + x86_64). At its tag, the Swift package tests also passed on GitHub's Intel macOS 15 runner, but the app has never been run on an Intel Mac. Later versions will be built for Apple silicon only. For `v0.3.0-beta.1` (build 3), a clean `make package-adhoc` passed every packaging gate on the staged app, the writable image volume and the mounted final DMG. Separately from those scripts, the mounted app and Quick Look extension were checked: both pass strict signature verification, have the hardened runtime and exactly the allowed entitlements, and carry no Finder info or resource forks. The image root holds only the expected entries. The app, launched from inside the mounted DMG, rendered a sample note with a callout, tasks, a Mermaid diagram and math. Quick Look was checked with the Release extension confirmed as the running provider (build 2, same source). The publication check of the mounted DMG and notes found 0 prohibited references and 0 unreadable files. Details in [`VERIFICATION.md`](./VERIFICATION.md).

## Known limitations

- **Slack paste formatting.** Slack turns headings and bold into italics and flattens nested bullets. Code and table text survive.
- **No "Save as PDF" in the print dialog.** Saving needs a save panel, which a read-only sandbox can't show. Use ⌥⌘P, or the print dialog's PDF › Open in Preview, and save from Preview.
- **Network blocking is enforced by the app, not by macOS.** WebKit refuses to start in a sandboxed app without the outgoing-network permission, so the app holds it. The reader blocks every non-local load itself. See [`READER_ARCHITECTURE.md`](./READER_ARCHITECTURE.md).
- **Quick Look is static.** Mermaid diagrams appear as source with a hint, images are placeholders, and math uses the system's MathML rendering.
- **Remote images never load,** by design. Audio, video and PDF embeds appear as cards that open in their default app after a confirmation.
- **Plugin content isn't run.** Dataview and similar query blocks appear as code with a note.
- **Obsidian syntax needs the Obsidian flavor.** Single files and plain folders open as Markdown, where `==highlights==`, `%%comments%%` and `#tags` stay literal; switch with the badge. Custom task states such as `[/]` display as checked boxes. The renderer covers common Obsidian syntax, not full Obsidian parity.
- **PDF pagination is plain.** A short last section, such as footnotes, can land alone on its own page.
- **Ad-hoc signature.** The app isn't notarized by Apple. macOS asks once to allow it, may ask again after each update, and managed Macs may refuse it. See [`INSTALL.md`](./INSTALL.md).

## Not yet verified

- Installing the ad-hoc signed DMG on a second Mac, and whether folder access survives an update
- Performance on very long notes (thousands of lines) and very large vaults (thousands of notes) in the new reader. The indexer's benchmarks still run in CI.
- An accessibility pass (VoiceOver, keyboard-only use, contrast)
- Pasting rich text into Outlook or Teams; actually sending through share-sheet services
- Settings › Finder › "Make Obviewer the Default" (Get Info was used instead), and Open Recent
- Running on macOS 14 or 15

## Recently fixed during verification

These were found on the Mac during November 13–14, 2026 testing, then fixed and retested:

- a blank reader, because WebKit needs the outgoing-network permission in the sandbox
- stray footnote lists in callout titles
- a stray `<input>` surviving sanitization
- Outline menu items not responding
- ⌘= not enlarging text
- folder live reload missing in-place saves (such as Sublime Text's)
- an impossible "Save as PDF" path
- Word dropping task boxes
- two indexer and renderer disagreements, caught by the shared fixtures
- the ad-hoc Release app not launching: library validation refused its ad-hoc frameworks, so the modules are now linked statically
- Finder info left on files inside the DMG, which failed strict signature checks; the DMG is now built by copying into a fresh APFS image and verified as mounted
- file-event logs and Finder info written into the image while it was being built; the build now tells macOS not to index or log the writable volume, cleans it before sealing, and the final image is checked against an allow-list

History before v0.3: [`history/STATUS_v0.2.8.md`](./history/STATUS_v0.2.8.md).
