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
- Supported formats: UTF-8 text; PNG and JPEG (structured metadata plus OCR); PDF (text layer, metadata, and OCR of every page); Mach-O (string sections, symbol table, load commands, signature blobs); TTF/OTF/WOFF/WOFF2 (name and glyph-name tables); binary plists (via `plutil`, macOS); zip, tar and gzip (parsed in-process, scanned in memory); and DMGs (mounted read-only, macOS).
- Anything else fails as unsupported: unknown binaries, SVG, Git LFS pointers, encrypted or ZIP64 archives, and archive members with absolute paths, `..`, links or devices. Size and nesting limits apply.
- Known limits: compiled code can hold short string literals inside machine instructions, and glyph outlines are shapes. Both are covered by scanning the sources.
- Gates and their scope:
  - **CI:** tracked files; commit metadata on pull requests; generated benchmark reports before they're published.
  - **Release workflow, before building:** the tree, the notes, the release title, the tag name, tagger and message, and the commit messages and identities since the previous release tag.
  - **Release workflow, before uploading:** every file to be uploaded, with the DMG mounted.
  - History contents are checked before push by the maintainer's local guard.
- To add a rule, generate a fingerprint locally (`node scripts/publication-check.mjs --fingerprint --mode token|stream < terms.txt`) and keep `terms.txt` out of the repository.
- Tests use random synthetic terms generated at runtime.

## CI

`.github/workflows/ci.yml` runs on pushes to `main`, `codex/**` and `redesign/**`, and on pull requests:

- **Publication policy:** Ubuntu with tesseract and poppler.
- **Renderer:** Node 22: `npm ci`, `npm test`, bundle check.
- **Swift Package:** GitHub's macOS 14 and 15 runners run `swift build` and `swift test`.
- **Scaffolding:** entitlement checks, script syntax, XcodeGen, and an unsigned Xcode compile of the app.
- **Benchmarks:** the smoke profile is enforced by `Configuration/benchmark-smoke-budget.json`; the integration profile reports only.

CI compiles and tests but never launches the app, so UI behavior is covered by the manual verification.

## Releases

Releases are tag-driven (`.github/workflows/release.yml`):

1. Update `MARKETING_VERSION` in `project.yml` (numeric `x.y.z`).
2. Write the reviewed notes at `docs/RELEASE_NOTES_<tag>.md`, and update `CHANGELOG.md` and `docs/STATUS.md`.
3. Declare the channel on the first line of the notes: `<!-- release-channel: prerelease -->` or `<!-- release-channel: stable -->`. A hyphenated tag (for example `v0.3.0-beta.1`) must be a pre-release.
4. Tag `v<x.y.z>` or `v<x.y.z>-<label>`.

The workflow then:

- Fails unless the tag matches `MARKETING_VERSION`, the notes file exists, and the signing secrets are either complete or entirely absent. **Partial Developer ID secrets fail the run** instead of falling back to ad-hoc.
- Runs the publication check on the tree, notes, commit and tag. Then come the renderer tests and bundle check, entitlement checks, and `swift build` / `swift test`.
- Builds the DMG. With all four Developer ID secrets it signs (and notarizes, if the notary secrets are present). With none, it builds an **ad-hoc** DMG and attaches `docs/INSTALL.md`.
- Runs the publication check on everything in `dist/`, including the mounted DMG, before uploading.
- Creates the GitHub release from the notes file, on the declared channel. If a release already exists (for example a reviewed draft), it only attaches the files.

Locally, `make package-adhoc` builds the same ad-hoc DMG: `scripts/build_app.sh`, then `scripts/package_release_dmg.sh`. Packaging verifies the app three times: in the staging folder, on the writable image volume before sealing, and inside the finished, read-only-mounted DMG. Each time it checks:

- the strict signature
- the hardened runtime
- the entitlement allow-lists, with no `get-task-allow`
- system-only library dependencies, with no bundled frameworks or dylibs
- the absence of Finder info or resource forks

The image is built by copying into a fresh APFS volume, not with `hdiutil create -srcfolder`. Before the volume is sealed:

- markers stop the OS from writing a Spotlight index or file-event logs into it (`.metadata_never_index`, `.fseventsd/no_log`)
- OS-generated entries are removed
- extended attributes are cleared from the copied content
- the app is verified on the writable volume itself

The final image root is an allow-list: the app, the Applications link, the install guide and the two empty markers. Anything else fails. The Release build is universal (arm64 and x86_64), but 0.3.0 was run only on Apple silicon.

### Why the modules are static libraries

`ObviewerCore`, `ObviewerReaderKit`, `ObviewerMacApp` and `ObviewerFixtureSupport` are static libraries in the Xcode project. The hardened runtime validates every library a process loads, and ad-hoc signatures carry no Team ID, so an ad-hoc app can't load ad-hoc-signed frameworks. Debug builds hide this, because they carry the debugger entitlement. Linking statically keeps the hardened runtime without any library-validation exception. The reader bundle (`Resources/Reader`) is copied into the app, the Quick Look extension and the ReaderKit test bundle, and `ReaderAssets` finds it with `Bundle(for:)`.

## Common problems

- **Xcode doesn't see new files:** run `make xcodeproj`.
- **`node build.mjs --check` fails in CI:** someone changed `Renderer/src` without rebuilding, or used a different esbuild version. Run `npm ci` and `npm run build`, then commit.
- **The reader is blank:** Help › Copy Reader Diagnostics. A WebContent process that keeps terminating usually means the app was built without its entitlements.
- **The publication check reports INCOMPLETE:** install tesseract or poppler, or check that the archive or DMG can be opened. It never passes a file it couldn't read.
