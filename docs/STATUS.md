# Status

Last updated: November 15, 2026. Version: **0.3.0**, published as the pre-releases `v0.3.0-beta.1`, `v0.3.0-beta.2` and `v0.3.0-beta.3` (see [v0.3.0-beta.3](#v030-beta3-security-and-platform)). The beta.2 changes (see the CHANGELOG) were verified at commit `9c277cf` (app) and `a4cba2a` (publication check); see [v0.3.0-beta.2](#v030-beta2-maintenance-and-redesign-9c277cf). `v0.3.0-beta.2` was published on November 15, 2026 from commit `223c5bc` (build 8); see [Published: v0.3.0-beta.2](#published-v030-beta2).

This page records what works and has been checked, what is known to be limited, and what hasn't been verified. The other documents summarize; this one is the ledger.

## How it was checked

- **Automated:** Swift tests (`swift test`: 133 passing on the maintainer's Mac at `9c277cf`, including packaging, linkage and publication-gate tests; 132 at `v0.3.0-beta.1`) and Node tests (`cd Renderer && npm test`: 109 at `a4cba2a`, 104 at `9c277cf`, 86 at `v0.3.0-beta.1`, covering the renderer, the publication check and the release-script gates (run against mock tools)). `node build.mjs --check` confirms that the committed reader bundle matches its source. `node scripts/publication-check.mjs --tracked` passes.
- **Manual:** the checklist in [`VERIFICATION.md`](./VERIFICATION.md), run on the maintainer's Mac (Apple silicon, macOS 26.7, Xcode 27.2) with a Debug build, using the notes in `Fixtures/notes/` and a generated demo vault.
- **Not yet run on:** an Intel Mac, or a second Mac with an installed release build. Intel Macs aren't supported after beta.1. From beta.3, the minimum is macOS 26 (beta.1 and beta.2 declared macOS 14 but were only run on macOS 26). CI builds and runs the Swift tests on GitHub's Apple silicon macOS 26 runner but never launches the app.

## Works and verified on a Mac

| Area | What was checked |
| --- | --- |
| Reader | GitHub and Obsidian Markdown render, including callouts with lists, tasks with custom states, footnotes, tables, highlighted code, KaTeX math, and **Mermaid diagrams drawn offline**. The note title appears once. |
| Safety of note content | A hostile test note (`Fixtures/notes/hostile-html.md`): scripts don't run, there are no form controls or event handlers, `javascript:`/`file:` links are inert, and remote images are blocked and logged by the Content-Security-Policy. Inspected with Safari Web Inspector. |
| Navigation | Wiki links across notes, same-note `[[#heading]]`, missing-link notice, back/forward (⌘[ ⌘]), the Outline menu and Note › Go to Heading, Find (⌘F, ⌘G, ⇧⌘G), and "Mentioned in" (backlinks) under each note |
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

## v0.3.0-beta.3: security and platform

- **What changed:** KaTeX 0.19.1 everywhere (GHSA-238p-pmpm-9mq7 fixed; `npm audit` reports 0); Mermaid 12.3 bundled from source against that KaTeX, without the ELK layout engine; macOS 26 minimum; and generated third-party notices. See the CHANGELOG.
- **Checked by the maintainer's automation on macOS 26:**
  - 133 Swift tests and 114 renderer tests; the bundle check from the repository root and from `Renderer/`; `npm ls` showing one KaTeX copy;
  - a Debug app with `LSMinimumSystemVersion` 26.0 for the app and the extension, and a local ad-hoc package passing every gate, arm64 only;
  - in the app, flowchart, sequence, class, state and ER diagrams; the intended ELK and syntax errors; ordinary math; and the hostile fixture inert.
  - Before the release files are uploaded, their payload and exact files are checked as for beta.2.
- **Known bug:** math inside diagrams is painted off-centre in WebKit. A Safari probe of the final bundle measured the formula boxes correctly centred (and sequence participant math now present), but the glyphs paint against the node's top edge, or near the participant box's top left.
- **Not verified for beta.3:**
  - Quick Look of this build;
  - the Web Inspector console;
  - copying a note with a diagram;
  - the smallest Finder icon and the Dock icon;
  - VoiceOver speech;
  - a second Mac.

## Published: v0.3.0-beta.2

- **Release:** [v0.3.0-beta.2](https://github.com/felizvida/obviewer/releases/tag/v0.3.0-beta.2), a pre-release published on November 15, 2026 from commit `223c5bc` (build 8; arm64 only; ad-hoc signed, not notarized). Six files: the DMG (SHA-256 `fd91e7eeaa7a5688b8286ed91786355a3d94a0a56d19242409f7f532bd26ee2c`), its checksum file, the install guide, two source archives and their checksum file. `v0.3.0-beta.1` and its files were checked unchanged before and after.
- **How it was published:** the files were built locally with `scripts/make_release_payload.sh`, checked by the repository's publication check (470 items, 0 prohibited, 0 incomplete) and by the maintainer's separate pre-publication guard on the exact files, notes, tag and history, then uploaded by hand. GitHub's runners uploaded nothing. The uploaded files' sizes and SHA-256 digests were checked against the local ones after publication.
- **Checks on this build:** 133 Swift tests and 109 Node tests pass. [CI](https://github.com/felizvida/obviewer/actions/runs/43664510032) (six jobs) and [Release verification](https://github.com/felizvida/obviewer/actions/runs/43664584969) passed on the pushed commit and tag. The build-8 Release app launched from the build folder and from the mounted final DMG and rendered a callout, math and a Mermaid diagram; the app and Quick Look extension are arm64 only, strictly signed, with the committed icon and no asset catalog. Both source archives match the tagged tree.
- **Still not verified for beta.2:** Quick Look of this build (an older registered copy kept answering), the smallest Finder icon and the Dock icon, VoiceOver speech, installation on a second Mac, and macOS 14 or 15.
- **Known dependency advisory in beta.2:** it ships KaTeX 0.16.47, in the reader and inside Mermaid, which is affected by the low-severity [GHSA-238p-pmpm-9mq7](https://github.com/advisories/GHSA-238p-pmpm-9mq7). Exploiting it needs prior prototype pollution and unsanitized insertion; the reader passes `trust: false` to KaTeX and sanitizes the generated HTML. **Fixed in beta.3** (KaTeX 0.19.1, with Mermaid bundled against it).

## v0.3.0-beta.2: maintenance and redesign (9c277cf)

Verified on the maintainer's Mac in an isolated checkout of commit `9c277cf` (Debug build 7 and a Release package, build 7):

- **Automated:** 133 Swift tests and 104 Node tests pass; the committed reader bundle matches its source; `publication-check --tracked` passes.
- **Package:** `make package-adhoc` passes every gate, including the new icon gate (the shipped `AppIcon.icns` is byte-identical to `App/AppIcon.icns`, and no `*.car` is in the app). The app and Quick Look executables are arm64 only. A fresh publication check of the final build-7 DMG: 78 items, 0 prohibited, 0 incomplete. That clears only the repository's own scanner: it is not clearance to publish (see below).
- **Live checks that passed:** the redesigned library window and reader in light and dark; flavor round trip; search count, focus and Clear Search; tag filtering; Settings › Reading in 10% steps with live reflow; no Reload button, ⌘R still reloads; the Graph toolbar toggle and ⌥⌘G; Whole Vault on and off (local 3 notes / 4 links, whole vault 133 / 218 in the demo vault); inspector links and Open in Reader; the graph at the default 1380 × 900 and the minimum window size with nothing clipped; the empty graph with no selection and with a search that matches nothing (including with a selection), and labels clipped to the canvas; Open as PDF with the gold fleur-de-lis and highlight wash (checked at `6e7dfb6`; the reader resources are unchanged since); the welcome screen; the new icon in Finder's icon view.
- **Not verified for this candidate:**
  - **Quick Look:** Finder kept launching an older registered copy of the extension, so the candidate's own preview was never confirmed. It was not forced by restarting Finder or removing other copies.
  - **Smallest icons:** Finder's list-view icon was too small to judge; the 16 and 32 px renditions look right when extracted.
  - **Dock icon:** not inspected; the automation could not read the Dock.
  - **VoiceOver:** the accessibility tree was checked (one element per library row with title and reading time), but spoken output was not listened to.
- **Publication:** a repository scanner pass is not publication clearance. The maintainer's separate pre-publication guard was extended to render every ICNS rendition and PNG the same way the scanner does (via a pinned copy of its decoder) and to OCR all of them; it must pass the exact release files, notes, tag and history before anything is pushed or uploaded.

### Publication check hardening (a4cba2a)

After `9c277cf`, the publication check's image inspectors were tightened on the same branch (scanner, tests and docs only; the app is unchanged). Every PNG now gets a strict profile and JPEG is refused; the rules are in [`DEVELOPMENT.md`](./DEVELOPMENT.md). Verified at `a4cba2a`, in a bounded adversarial review with real tesseract on the maintainer's Mac and in a separate review in a Linux sandbox:

- 109 Node tests pass; the committed reader bundle matches its source; `publication-check --tracked` reports 191 items, 0 prohibited, 0 incomplete.
- Probe files that had scanned clean while hiding text are now refused or caught. Refused: bytes after `IEND` or after a zlib stream (in IDAT, zTXt or iTXt); numeric, private and colour-profile chunks; unused palette entries; non-zero row padding; NUL in text; transparency keys; text beyond the 1 MiB per-image budget (including twelve individually legal chunks; it ends INCOMPLETE rather than aborting even with a 64 MiB heap). Caught: white text on transparency, colour hidden under transparent pixels, and red text on grey of equal brightness (per-channel OCR).
- Under this scanner, the unchanged build-7 DMG scans 78 items / 0 / 0 and the built icon 11 / 0 / 0.
- Known limits, out of scope by design: steganography (including text placed only in the low bytes of 16-bit samples), text too small for OCR, and non-ASCII terms in Latin-1 `tEXt`. The review was bounded, not exhaustive.

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
- An accessibility pass (VoiceOver speech, keyboard-only use, contrast)
- Pasting rich text into Outlook or Teams; actually sending through share-sheet services
- Settings › Finder › "Make Obviewer the Default" (Get Info was used instead), and Open Recent

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
