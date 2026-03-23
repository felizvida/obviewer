# Development Guide

This document explains how to set up, build, test, validate, and release the project.

It assumes no prior knowledge of the repo.

## What The Repository Contains Today

Today the repository is a working Swift package application plus XcodeGen app-project spec.

That means:

- the app can be run locally in Xcode right now
- the package is used for development, tests, and release automation
- the final production artifact is still expected to be a signed and sandboxed macOS app distribution

## Prerequisites

Minimum practical requirements:

- a Mac
- full Xcode
- Git

Helpful extras:

- Homebrew
- GitHub CLI (`gh`)

## Why Full Xcode Matters

The project uses macOS UI frameworks, app signing, and Xcode-driven test flows.

Command Line Tools alone are not enough for a reliable day-to-day workflow here. The first thing to check on any machine is whether full Xcode is selected:

```bash
xcode-select -p
xcodebuild -version
swift --version
```

## First-Time Setup

The easiest local trial path is:

```bash
make try-local
```

That target:

- verifies the active Xcode selection
- installs `xcodegen` if Homebrew is available and the tool is missing
- generates `Obviewer.xcodeproj`
- opens the project in Xcode

If you want realistic data for testing:

```bash
make demo-vault
```

## Working Modes

### Option 1: Xcode

Recommended for day-to-day product work.

1. run `make try-local` or `make xcodeproj`
2. open `Obviewer.xcodeproj`
3. run the `Obviewer` scheme
4. use `Product -> Test` for the app and package test targets

Important:

- after pulling source changes, rerun `make xcodeproj` before reopening Xcode
- the generated project is disposable; `project.yml` is the source of truth

### Option 2: Terminal

Recommended for quick local verification and CI parity.

```bash
swift build
swift test
```

For the Xcode-style path:

```bash
xcodebuild -project Obviewer.xcodeproj \
  -scheme Obviewer \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  test
```

## Core Commands

```bash
make try-local
make demo-vault
make docs-screenshots
make xcodeproj
make build-app
make package-app
swift test
```

## Package Metadata

Defined in `Package.swift`:

- Swift tools version: `5.10`
- deployment target: macOS 14+
- core library: `ObviewerCore`
- fixture library: `ObviewerFixtureSupport`
- macOS shell library: `ObviewerMacApp`
- executables: `Obviewer`, `ObviewerFixtureTool`, `ObviewerDocsTool`

## Test Coverage

Current test targets:

- `Tests/ObviewerCoreTests/ObsidianParserTests.swift`
- `Tests/ObviewerCoreTests/VaultReferenceTests.swift`
- `Tests/ObviewerCoreTests/VaultSnapshotTests.swift`
- `Tests/ObviewerCoreTests/VaultReaderTests.swift`
- `Tests/ObviewerCoreTests/NoteGraphTests.swift`
- `Tests/ObviewerMacAppTests/AppModelTests.swift`
- `Tests/ObviewerMacAppTests/VaultNoteCacheStoreTests.swift`
- `Tests/ObviewerMacAppTests/ViewSupportTests.swift`

Current coverage is strongest around:

- parser behavior
- note and attachment resolution
- graph derivation
- vault enumeration against real temporary directories
- live watching and incremental reload orchestration
- warm-start snapshot-cache persistence and cold-load reuse
- app-model orchestration
- selected view-support utilities

Coverage is still weak around:

- UI snapshots
- accessibility behavior
- performance benchmarks
- end-to-end signed distribution validation

## CI And Release Automation

GitHub Actions:

- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

Current CI behavior:

- runs on `main`, `codex/**`, pull requests, and manual dispatch
- builds and tests on `macos-14` and `macos-15`
- validates entitlements and packaging scripts
- verifies that the XcodeGen project can be generated

Current release behavior:

- tag `v*` to trigger the release workflow
- rebuild and retest the repo
- generate source archives and checksums
- publish a GitHub release
- publish a signed DMG as well when Apple signing secrets are configured

Current limitation:

- the release workflow needs Apple signing secrets configured before it can publish a signed/notarized `.dmg`

## Packaging And Shipping

The repository already contains the bones of the shipping pipeline:

- `project.yml`
- `scripts/generate_xcode_project.sh`
- `scripts/build_app.sh`
- `scripts/notarize_release_app.sh`
- `scripts/package_release_app.sh`
- `scripts/package_release_dmg.sh`

Typical local signed build flow:

```bash
brew install xcodegen
export OBVIEWER_CODE_SIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID1234)"
export OBVIEWER_DEVELOPMENT_TEAM="TEAMID1234"
make xcodeproj
make build-app
make package-app
```

Important:

- `make package-app` refuses unsigned packaging
- that is intentional because the sandbox/read-only story depends on code signing carrying the entitlements

Typical local notarized DMG flow:

```bash
export OBVIEWER_CODE_SIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID1234)"
export OBVIEWER_DEVELOPMENT_TEAM="TEAMID1234"
export OBVIEWER_NOTARY_KEYCHAIN_PROFILE="obviewer-notary"
make package-dmg
```

## Entitlements

The current entitlement baseline is intentionally minimal:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-only`

Do not broaden these casually. Any change to permissions should be treated as a product-level decision, not a routine implementation detail.

## Common Failure Modes

### Failure Mode 1: `swift build` or `swift test` fails with Apple toolchain errors

Likely cause:

- Command Line Tools are selected instead of full Xcode
- the active SDK and toolchain do not match

What to do:

- check `xcode-select -p`
- confirm Xcode is installed and opened once
- reselect the full Xcode developer directory if needed

### Failure Mode 2: Xcode runs the app but sandbox/bookmark behavior is wrong

Likely cause:

- the generated app target is not using the intended entitlements
- local signing configuration is incomplete

What to inspect:

- `Configuration/Obviewer.entitlements`
- target signing settings
- bookmark and security-scope service behavior

### Failure Mode 3: Notes render incorrectly

Likely cause:

- parser limitation or link resolution issue rather than a view bug

What to inspect:

- `ObsidianParser`
- `VaultModels`
- the specific note content and attachment paths

### Failure Mode 4: The app feels slow on a large vault

Likely cause:

- current full reindexing model, lack of caching, or graph/layout cost

What to inspect:

- `VaultReader`
- `VaultLoading`
- graph subgraph generation and view layout behavior

## Suggested Development Workflow

For normal work:

1. read `docs/HANDOFF.md`, `docs/STATUS.md`, and `docs/MODERNIZATION_PLAN.md`
2. identify whether the task touches core, UI, distribution, or docs
3. add or update tests first when the behavior is deterministic
4. validate against the demo vault and a real vault when possible
5. update docs whenever the product surface or release story changes

## Decisions To Keep In Mind

- read-only safety is the top requirement
- local-only behavior is intentional
- macOS quality matters
- the current repo is strong enough for serious iteration, but it is not fully modernized yet

## Recommended Near-Term Engineering Work

The highest-value technical work in order is:

1. Create the real sandboxed app target
2. Verify the read-only guarantee on-device
3. Improve parser fidelity
4. Add richer note navigation and media support
5. Improve release automation
