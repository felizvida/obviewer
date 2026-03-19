# Obviewer

[![CI](https://github.com/felizvida/obviewer/actions/workflows/ci.yml/badge.svg)](https://github.com/felizvida/obviewer/actions/workflows/ci.yml)

Obviewer is a macOS-native, read-only Obsidian vault viewer built for calm, premium reading.

This starter leans hard into the one requirement that matters most: the vault itself must never be mutated. The intended production app should be sandboxed and granted only user-selected read-only access to the vault directory.

## Product Direction

- Native macOS app built with SwiftUI and selective AppKit bridges
- Local-folder only, no sync layer, no editing affordances
- High-contrast, typography-led reading experience with generous spacing and motion
- Fast vault indexing for Markdown notes plus common attachments
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
- A read-only vault reader service
- Security-scoped bookmark persistence for reopening the selected vault
- An Obsidian-aware parser for headings, lists, callouts, tags, wiki links, and image embeds
- A premium reading surface with note metadata and linked-note navigation

## Quick Start

1. Install full Xcode on macOS.
2. Clone the repository.
3. Open the package in Xcode or run `swift build` from a shell with the full Xcode toolchain selected.
4. Attach `Configuration/Obviewer.entitlements` to the eventual app target before shipping.

## Repository Health

- CI runs on each push and pull request through `.github/workflows/ci.yml`.
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

- Replace the lightweight parser with a full CommonMark plus Obsidian extension pipeline
- Add inline link navigation inside body text
- Add quick switcher and fuzzy command palette
- Add table rendering, footnotes, and Mermaid block previews
- Add live vault change observation through file-system events

## License

No license has been added yet. That choice has legal consequences, so it should be made explicitly by the repository owner.
