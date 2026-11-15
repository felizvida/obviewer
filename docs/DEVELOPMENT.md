# Development Guide

How to build, test, verify and release Obviewer 0.3. The v0.2.8 guide is in [`history/DEVELOPMENT_v0.2.8.md`](./history/DEVELOPMENT_v0.2.8.md).

## Prerequisites

| Tool | Needed for |
| --- | --- |
| macOS 14 or later, full Xcode 15 or later | Building and running the app (`xcode-select -p` must point at Xcode, not the Command Line Tools) |
| XcodeGen (`brew install xcodegen`) | Generating `Obviewer.xcodeproj` from `project.yml` |
| Node 20 or later and npm | Changing the renderer or running its tests. Not needed just to build the app, because the bundle is committed. |
| tesseract and pdftotext (`brew install tesseract poppler`) | Running the publication check locally (CI installs them) |

## Everyday commands

```bash
make try-local            # check Xcode, install XcodeGen if needed, generate and open the project
make xcodeproj            # regenerate the project after adding or moving files
swift build && swift test # Swift package build and tests

cd Renderer && npm ci --ignore-scripts   # once, or after package-lock changes
npm test                  # renderer, publication-check and release-script tests
npm run build             # rebuild Sources/ObviewerReaderKit/Resources/Reader
node build.mjs --check    # fail if the committed bundle is stale

make publication-check    # scan tracked files against the publication policy
make demo-vault           # generate build/SampleVault (Obsidian)
make benchmark-vault      # indexing benchmarks (see the Makefile for PROFILE, BUDGET, ...)
```

## Changing the renderer

1. Edit `Renderer/src/` and add tests in `Renderer/test/`.
2. Run `npm test`, then `npm run build`, and commit the source **and** the regenerated `Sources/ObviewerReaderKit/Resources/Reader/` together. CI runs `node build.mjs --check` and fails if they disagree. The bundle includes `manifest.json` (hashes and versions) and `THIRD_PARTY_NOTICES.txt`.
3. If you change how links are recognized, add a case to `Fixtures/notes/expectations.json`. The renderer tests and `SharedFixtureLinkTests` both check it.
4. The Quick Look bundle (`quicklook.js`) runs in bare JavaScriptCore with no DOM. Keep `src/core/` free of browser APIs, and use `test/quicklook.test.js` to confirm.

`build.mjs` loads `esbuild` from `node_modules`, or from the path in `OBVIEWER_ESBUILD`. The esbuild version is pinned exactly so the bundle can be reproduced.

## Changing Swift code

- `ObviewerCore` has no UI dependency; keep it that way.
- New files need `make xcodeproj` before Xcode sees them.
- The packages build in Swift 5 language mode (`SWIFT_VERSION 5.0`). Newer Xcodes default to Swift 6, so the setting is pinned.
- WebKit behavior (rendering, sandbox, Quick Look, printing) can only be checked by running the app; see [`VERIFICATION.md`](./VERIFICATION.md).
- If the reader is blank or misbehaves, use Help › Copy Reader Diagnostics, or stream the log with `log stream --predicate 'subsystem == "com.felizvida.obviewer"'`. The Web Inspector is enabled in Debug builds; attach via Safari › Develop.

## Entitlements policy

`Configuration/Obviewer.entitlements` and `Configuration/ObviewerQuickLook.entitlements` are allow-lists checked by `ReleaseHardeningTests` and by `scripts/release_common.sh` on signed builds:

- **App:** `app-sandbox`, `files.user-selected.read-only`, `print`, and `network.client` (required by WebKit in the sandbox; the reader blocks remote loads itself).
- **Quick Look extension:** `app-sandbox` and `files.user-selected.read-only` only.
- **Never:** any read-write file entitlement, `network.server`, or `get-task-allow` in a Release build. Release configurations set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`.

Changing these requires a deliberate review. Explain the change in the pull request.

## Publication policy

Everything pushed to GitHub, and everything attached to a release, is checked by `scripts/publication-check.mjs` against `Configuration/publication-policy.json`.

- The policy holds only SHA-256 fingerprints of prohibited terms. The terms themselves are not in the repository, and shouldn't be written into code, docs, tests or commit messages.
- The scanner covers text, printable strings in binaries, file names, zip/tar archives, DMGs (mounted read-only on macOS), PDFs and images (OCR), plus commit metadata with `--git-range`.
- Findings report location and rule ID only. Any file that can't be fully inspected fails the check (exit code 2).
- Supported formats: UTF-8 text; PNG in a strict profile (IHDR, PLTE only in palette images with every entry used, tRNS only in palette images, one fully consumed zlib stream in back-to-back IDAT chunks, zero padding bits, IEND last, valid CRCs, not interlaced, plus tEXt/zTXt/iTXt read in full, at most 1 MiB of text per image; every other chunk refused), with the pixels OCRed as luminance and per colour channel, and on white, on black and ignoring transparency when transparent; ICNS icons holding only PNG renditions in known slots at their exact sizes, in a strict profile (8-bit RGBA, only IHDR/IDAT/IEND, valid CRCs, nothing after IEND, one zlib stream consumed to its end); each rendition is decoded and OCRed like any transparent PNG, and anything else in the container is refused; PDF (text layer, metadata, and OCR of every page); Mach-O (string sections, symbol table, load commands, signature blobs); TTF/OTF/WOFF/WOFF2 (name and glyph-name tables); binary plists (via `plutil`, macOS); zip, tar and gzip (parsed in-process, scanned in memory); and DMGs (mounted read-only, macOS). JPEG, SVG and compiled asset catalogs (`Assets.car`) are refused, because they can't be inspected completely; publish plain PNGs (`python3 -c "from PIL import Image; im=Image.open('in.png'); Image.frombytes(im.mode, im.size, im.tobytes()).save('out.png')"` strips everything but the pixels). That is also why the app icon ships as `App/AppIcon.icns` and the packaging gate rejects any `Assets.car`.
- Anything else fails as unsupported: unknown binaries, SVG, Git LFS pointers, encrypted or ZIP64 archives, and archive members with absolute paths, `..`, links or devices. Size and nesting limits apply.
- Known limits: compiled code can hold short string literals inside machine instructions, and glyph outlines are shapes. Both are covered by scanning the sources.
- Gates and their scope:
  - **CI:** tracked files; commit metadata on pull requests. CI publishes no generated files (no artifacts, no job summaries).
  - **Release verification workflow (on a version tag):** the tree, the notes, the release title, the tag name, tagger and message, the commit messages and identities since the previous release tag, and every file a release would contain, with the DMG mounted. It uploads nothing.
  - **Local release payload** (`scripts/make_release_payload.sh`): the same checks on the exact files to be uploaded.
  - History contents, and the exact release files, are checked before push or upload by the maintainer's own pre-publication guard. The publication check in this repository does not replace it.
- To add a rule, generate a fingerprint locally (`node scripts/publication-check.mjs --fingerprint --mode token|stream < terms.txt`) and keep `terms.txt` out of the repository.
- Tests use random synthetic terms generated at runtime.

## CI

`.github/workflows/ci.yml` runs on pushes to `main`, `codex/**` and `redesign/**`, and on pull requests:

- **Publication policy:** Ubuntu with tesseract and poppler.
- **Renderer:** Node 22: `npm ci`, `npm test`, bundle check.
- **Swift Package:** `swift build` and `swift test` on GitHub's Apple silicon macOS 15 runner (`macos-15`). Intel Macs aren't supported after `v0.3.0-beta.1`, so there is no Intel job (the beta's tag still ran one). GitHub retired its macOS 14 runners on November 2, 2026, so nothing in CI runs on macOS 14, even though it is the deployment target.
- **Scaffolding:** entitlement checks, script syntax, XcodeGen, and an unsigned Xcode compile of the app.
- **Benchmarks:** the smoke profile is enforced by `Configuration/benchmark-smoke-budget.json`; the integration profile reports only. Reports stay on the runner.

CI compiles and tests but never launches the app, so UI behavior is covered by the manual verification.

## Releases

Release files are built and checked locally and uploaded by hand, so nothing generated reaches GitHub without the maintainer's pre-publication guard. (Up to `v0.3.0-beta.1`, the tag-driven workflow built and uploaded them itself.)

1. Update `MARKETING_VERSION` in `project.yml` (numeric `x.y.z`) if needed.
2. Write the reviewed notes at `docs/RELEASE_NOTES_<tag>.md`, and update `CHANGELOG.md` and `docs/STATUS.md`. Never edit a notes file after its tag exists.
3. Declare the channel on the first line of the notes: `<!-- release-channel: prerelease -->` or `<!-- release-channel: stable -->`. A hyphenated tag (for example `v0.3.0-beta.2`) must be a pre-release.
4. In a clean checkout of the release commit, run `scripts/make_release_payload.sh <tag> <build-number>`. It applies the same gates as the workflow (version, notes, channel, a clean tree, the publication check on the tree and notes), builds the source archives and the ad-hoc DMG (`make package-adhoc` with the release version and build number), copies the install guide, writes the SHA-256 files into `dist/<tag>/`, scans every file with the DMG mounted, and prints the upload command. It uploads nothing.
5. Run the maintainer's pre-publication guard on the same files, the notes, the tag text and the history being pushed.
6. Push the commit and the tag. The **Release verification** workflow (`.github/workflows/release.yml`) then repeats every gate on GitHub's runner and builds a DMG, but uploads nothing; with all four Developer ID secrets it signs (and notarizes, if the notary secrets are present), and partial secrets fail the run.
7. Upload the checked files with the printed `gh release create … --verify-tag` command.

Locally, `make package-adhoc` builds the same ad-hoc DMG: `scripts/build_app.sh`, then `scripts/package_release_dmg.sh`. Packaging verifies the app three times: in the staging folder, on the writable image volume before sealing, and inside the finished, read-only-mounted DMG. Each time it checks:

- the strict signature
- the hardened runtime
- the entitlement allow-lists, with no `get-task-allow`
- system-only library dependencies, with no bundled frameworks or dylibs
- an app icon byte-identical to `App/AppIcon.icns` as committed in HEAD, and no compiled asset catalog (`*.car`) anywhere in the app
- the absence of Finder info or resource forks

The image is built by copying into a fresh APFS volume, not with `hdiutil create -srcfolder`. Before the volume is sealed:

- markers stop the OS from writing a Spotlight index or file-event logs into it (`.metadata_never_index`, `.fseventsd/no_log`)
- OS-generated entries are removed
- extended attributes are cleared from the copied content
- the app is verified on the writable volume itself

The final image root is an allow-list: the app, the Applications link, the install guide and the two empty markers. Anything else fails. From the next version on, Obviewer supports Apple silicon Macs only. `v0.3.0-beta.1` was published before that decision as a universal build (arm64 and x86_64), with Intel runtime unverified; the next version will be built for arm64 only.

### Why the modules are static libraries

`ObviewerCore`, `ObviewerReaderKit`, `ObviewerMacApp` and `ObviewerFixtureSupport` are static libraries in the Xcode project. The hardened runtime validates every library a process loads, and ad-hoc signatures carry no Team ID, so an ad-hoc app can't load ad-hoc-signed frameworks. Debug builds hide this, because they carry the debugger entitlement. Linking statically keeps the hardened runtime without any library-validation exception. The reader bundle (`Resources/Reader`) is copied into the app, the Quick Look extension and the ReaderKit test bundle, and `ReaderAssets` finds it with `Bundle(for:)`.

## Common problems

- **Xcode doesn't see new files:** run `make xcodeproj`.
- **`node build.mjs --check` fails in CI:** someone changed `Renderer/src` without rebuilding, or used a different esbuild version. Run `npm ci` and `npm run build`, then commit.
- **The reader is blank:** Help › Copy Reader Diagnostics. A WebContent process that keeps terminating usually means the app was built without its entitlements.
- **The publication check reports INCOMPLETE:** install tesseract or poppler, or check that the archive or DMG can be opened. It never passes a file it couldn't read.
