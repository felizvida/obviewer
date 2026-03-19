# Obviewer

[![CI](https://github.com/felizvida/obviewer/actions/workflows/ci.yml/badge.svg)](https://github.com/felizvida/obviewer/actions/workflows/ci.yml)

Obviewer is a macOS-native, read-only Obsidian vault viewer built for calm, premium reading.

This starter leans hard into the one requirement that matters most: the vault itself must never be mutated. The intended production app should be sandboxed and granted only user-selected read-only access to the vault directory.

## Documentation

This repository includes a full handoff-oriented documentation set for future maintainers.

Start here:

- [`QUICKSTART.md`](./QUICKSTART.md)
- [`docs/README.md`](./docs/README.md)
- [`docs/HANDOFF.md`](./docs/HANDOFF.md)
- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)
- [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md)
- [`docs/PRODUCT.md`](./docs/PRODUCT.md)
- [`docs/STATUS.md`](./docs/STATUS.md)

## Product Direction

- Native macOS app built with SwiftUI and selective AppKit bridges
- Local-folder only, no sync layer, no editing affordances
- High-contrast, typography-led reading experience with generous spacing and motion
- Fast vault indexing for Markdown notes plus vault attachments
- Obsidian-aware viewing for wiki links, callouts, tags, and image embeds

## Safety Model

The UI being "view only" is not enough. The real guarantee comes from platform boundaries:

1. Enable App Sandbox.
2. Grant only `com.apple.security.files.user-selected.read-only`.
3. Do not include `read-write` or broader file exceptions.
4. Open note files with read APIs only.
5. Model vault access behind a dedicated read gateway with no write methods.

The sample entitlements file in [`Configuration/Obviewer.entitlements`](/Users/liux17/codex/obviewer/Configuration/Obviewer.entitlements) shows the minimum shape.

## Current Starter

The package includes:

- A native SwiftUI shell using `NavigationSplitView`
- A reusable `ObviewerCore` module for vault models, parsing, and indexing
- A macOS-specific `ObviewerMacApp` module for app state, security-scoped access, and UI
- Security-scoped bookmark persistence for reopening the selected vault
- An Obsidian-aware parser for inline links, tables, headings, lists, callouts, tags, and image embeds
- A premium reading surface with note metadata, inline links, table rendering, and linked-note navigation
- A right-side contents rail for long-note navigation
- XcodeGen-based app scaffolding and helper scripts for producing a signed release bundle once signing is configured

## Architecture

The codebase is now split into three targets:

- `ObviewerCore`
  Portable domain layer for notes, attachments, parsing, lookup, and vault indexing
- `ObviewerMacApp`
  macOS shell layer for `AppModel`, security-scoped access, bookmark persistence, picker integration, and SwiftUI/AppKit views
- `Obviewer`
  Thin executable entry point that boots the macOS app

This keeps parser and vault logic easier to test, debug, and eventually port to another client shell.

## Quick Start

The fastest path is in [`QUICKSTART.md`](./QUICKSTART.md).

The one-command version is:

```bash
git clone https://github.com/felizvida/obviewer.git
cd obviewer
make try-local
```

That command will:

- verify that full Xcode is selected
- install `xcodegen` with Homebrew if needed
- generate `Obviewer.xcodeproj`
- open the project in Xcode

Then:

1. Select the `Obviewer` scheme.
2. If Xcode asks about signing, choose your Personal Team.
3. Press Run.
4. Choose your local Obsidian vault inside the app.

If you prefer the manual path, you can still open the package in Xcode or run `swift build` and `swift test` from a shell with the full Xcode toolchain selected.

## Easier App Packaging

The repository now includes an `XcodeGen` project spec plus helper scripts so a future maintainer can generate a real macOS app project and package a signed release bundle without reconstructing the project by hand.

Typical flow:

```bash
brew install xcodegen
export OBVIEWER_CODE_SIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID1234)"
export OBVIEWER_DEVELOPMENT_TEAM="TEAMID1234"
make xcodeproj
make build-app
make package-app
```

`make package-app` now refuses to produce an unsigned artifact, because doing so would bypass the sandbox-based read-only guarantee.

## Repository Health

- CI runs on push, pull request, and manual dispatch through `.github/workflows/ci.yml`.
- CI validates the Swift package on `macos-14` and `macos-15`, plus the XcodeGen scaffolding and packaging scripts.
- Tagging `v*` triggers `.github/workflows/release.yml`, which rebuilds, retests, generates source archives, and publishes a GitHub release.
- Bug reports and feature requests are routed through issue forms.
- Contribution, support, and security guidance live in the repository root and `.github/`.
- `CODEOWNERS` is configured so review routing starts with the repository owner.

## Converting This Into a Shipping App

This repository is a Swift package starter. To ship it as a proper `.app` bundle:

1. Open the package in Xcode on a Mac with full Xcode installed.
2. Create a macOS App target or package-generated app container.
3. Attach [`Configuration/Obviewer.entitlements`](/Users/liux17/codex/obviewer/Configuration/Obviewer.entitlements) to the app target.
4. Keep the app sandboxed in Debug and Release.
5. Codesign and notarize as a standard sandboxed macOS app.

## UX Direction

The visual direction in this starter is intentionally not "developer utility gray":

- Warm paper background instead of flat white
- Serif-led note typography with rounded chrome
- Material sidebar surfaces and soft depth
- Dense metadata kept secondary to the reading flow

## Next High-Value Steps

- Replace the lightweight parser with a fuller CommonMark plus Obsidian extension pipeline
- Add quick switcher and fuzzier large-vault navigation
- Add footnotes, Mermaid block previews, and richer media rendering
- Add live vault change observation through file-system events

## License

This repository is licensed under Apache 2.0. See [LICENSE](./LICENSE).
