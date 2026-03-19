# Development Guide

This document explains how to set up, build, test, validate, and ship the project.

It assumes no prior knowledge of the repo.

## What The Repository Contains Today

Today this repository is a Swift package that bootstraps the code for a future shipping macOS app.

That means:

- The code can be opened and iterated on now
- The package is useful for development and tests
- The final production artifact is still expected to be a sandboxed macOS `.app`

## Prerequisites

Minimum practical requirements:

- A Mac
- Full Xcode installed
- macOS SDK compatible with the selected Xcode version
- Git

Optional but helpful:

- GitHub CLI (`gh`)

## Why Full Xcode Matters

The project uses macOS UI frameworks and is intended to ship as a sandboxed app.

Command Line Tools alone are often not enough for a frictionless workflow here.

During bootstrap, local verification was blocked by a toolchain mismatch because only Command Line Tools were active. Future maintainers should treat "install and select full Xcode" as the first troubleshooting step.

## First-Time Setup

1. Clone the repository.
2. Open Terminal in the repository root.
3. Confirm that full Xcode is selected as the active developer directory.
4. Open the package in Xcode or build from the command line.

For the easiest local trial, use:

```bash
make try-local
```

That target checks for full Xcode, installs `xcodegen` if Homebrew is available, generates `Obviewer.xcodeproj`, and opens it in Xcode.

Useful commands:

```bash
xcode-select -p
swift --version
```

If the active developer directory points to Command Line Tools instead of Xcode, switch it before debugging build issues.

## Opening The Project

There are two common ways to work:

### Option 1: Xcode

- Fastest first-run path:

  ```bash
  make try-local
  ```

- Open the folder or package in Xcode
- Let Xcode resolve the package
- Run tests inside Xcode

### Option 2: Terminal

```bash
swift build
swift test
```

Use terminal builds only after confirming the correct Xcode toolchain is active.

## Current Package Metadata

- Tools version: Swift 5.10
- Platform target: macOS 14+
- Products:
  - `ObviewerCore` library
  - `ObviewerMacApp` library
  - `Obviewer` executable

This metadata lives in `Package.swift`.

## Running The Current App Scaffold

The package contains a SwiftUI app entry point.

Once a compatible Xcode toolchain is active, the usual development loop is:

1. Build the package
2. Run the app from Xcode
3. Choose a local Obsidian vault when prompted
4. Browse notes and inspect rendering behavior

## Current Tests

The repository currently includes parser-focused tests in:

- `Tests/ObviewerCoreTests/ObsidianParserTests.swift`
- `Tests/ObviewerCoreTests/VaultReferenceTests.swift`
- `Tests/ObviewerCoreTests/VaultSnapshotTests.swift`
- `Tests/ObviewerCoreTests/VaultReaderTests.swift`
- `Tests/ObviewerMacAppTests/AppModelTests.swift`

These tests cover:

- Title extraction
- Wiki-link extraction
- Tag extraction
- Callout parsing
- Standalone and inline image embed parsing
- Link classification and heading-anchor handling
- Normalization and anchor slug behavior
- Duplicate note and attachment resolution
- Vault enumeration behavior against real temporary directories
- `AppModel` loading, restore, search, and navigation behavior

## CI

GitHub Actions CI is configured in:

- `.github/workflows/ci.yml`

Current CI behavior:

- Runs on `main`, `codex/**`, pull requests, and manual dispatch
- Builds and tests the package on `macos-14` and `macos-15`
- Lints the entitlements and packaging scripts
- Verifies the `XcodeGen` project can still be generated
- Publishes releases on semantic version tags through `.github/workflows/release.yml`

This is a much stronger safety net than before, but notarized app delivery still requires manual signing configuration.

## Turning The Scaffold Into A Shipping App

The project is not finished until it is wrapped in a real macOS app target with sandboxing enabled.

Recommended path:

1. Install `xcodegen`.
2. Run `make xcodeproj`.
3. Open the generated `Obviewer.xcodeproj` in Xcode.
4. Confirm `Configuration/Obviewer.entitlements` is attached to the app target.
5. Confirm App Sandbox is enabled.
6. Confirm only read-only user-selected file access is granted.
7. Validate behavior with a real vault.
8. Codesign and notarize the resulting `.app`.

Relevant files:

- `project.yml`
- `scripts/generate_xcode_project.sh`
- `scripts/build_app.sh`
- `scripts/package_release_app.sh`

## Entitlements

The current entitlement file intentionally contains only:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-only`

Do not casually broaden these permissions.

If a future maintainer believes broader access is necessary, that change should be justified in a design note and reviewed as a product-level decision, not treated as a routine implementation detail.

## Common Failure Modes

### Failure Mode 1: `swift build` or `swift test` fails with Apple toolchain errors

Likely cause:

- The active developer directory points to Command Line Tools or a mismatched SDK/toolchain combination

What to do:

- Check `xcode-select -p`
- Confirm full Xcode is installed
- Retry after selecting the full Xcode toolchain

### Failure Mode 2: The app opens but cannot reopen the last vault

Likely cause:

- Bookmark resolution is stale or sandbox configuration is incomplete in the app target

What to inspect:

- `BookmarkStore`
- App target entitlements
- Security-scoped access lifecycle

### Failure Mode 3: Notes render incorrectly

Likely cause:

- Parser limitations rather than broken view code

What to inspect:

- `ObsidianParser`
- `RenderBlock`
- The specific note content that reproduces the issue

### Failure Mode 4: The app is "view only" in UI but still able to write on disk

Likely cause:

- Running outside the intended sandboxed app target

What to inspect:

- App target configuration
- Shipping entitlements
- Any newly introduced write code paths

## Suggested Development Workflow

For normal feature work:

1. Read `docs/HANDOFF.md` and `docs/STATUS.md`
2. Decide whether the work touches parser, UI, or app container concerns
3. Add tests first if the behavior is parser-driven
4. Implement the change
5. Validate with a real sample vault
6. Update documentation if product behavior changed

## Release Workflow

The repo has been set up on GitHub, but release management is still lightweight.

For the first real release, the project should eventually have:

- A semantic version tag
- A GitHub release entry
- A signed or notarized app artifact
- Release notes explaining supported scope and known limitations

The repository intentionally does not publish an unsigned app artifact anymore. Release packaging now requires a signed build so the sandbox entitlements remain part of the actual runtime binary.

## Decisions That Need To Be Remembered During Development

- Read-only safety is the top requirement
- UI quality matters, but not more than filesystem safety
- Local-only behavior is intentional
- The current repository is a foundation, not a finished product

## Recommended Near-Term Engineering Work

The highest-value technical work in order is:

1. Create the real sandboxed app target
2. Verify the read-only guarantee on-device
3. Improve parser fidelity
4. Add richer note navigation and media support
5. Improve release automation
