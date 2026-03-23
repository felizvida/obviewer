# Documentation Index

This repository is documented for zero-memory handoff.

Assume the reader:

- has never seen the project before
- does not know the original conversation history
- should not need to ask the previous maintainer for missing context

If you are new to the project, read the documents in this order:

1. [`../QUICKSTART.md`](../QUICKSTART.md) to run the app locally with the fewest steps
2. [`VISUAL_TOUR.md`](./VISUAL_TOUR.md) to understand the current product feel quickly
3. [`HANDOFF.md`](./HANDOFF.md) for the current project state, invariants, and takeover guidance
4. [`STATUS.md`](./STATUS.md) for the current implementation baseline and known gaps
5. [`PRODUCT.md`](./PRODUCT.md) for product scope and design intent
6. [`ARCHITECTURE.md`](./ARCHITECTURE.md) for module boundaries and runtime flow
7. [`DEVELOPMENT.md`](./DEVELOPMENT.md) for setup, test, and release workflow
8. [`MODERNIZATION_PLAN.md`](./MODERNIZATION_PLAN.md) for the phased roadmap from prototype to modern shipping app

## Quick Facts

- Project name: `Obviewer`
- Repository URL: `https://github.com/felizvida/obviewer`
- Platform target: macOS 14+
- Language: Swift
- Primary UI technology: SwiftUI with focused AppKit interop
- Package layout: Swift package plus XcodeGen app-project spec
- Current release line: `v0.2.5`
- Shipping artifact today: source archives on GitHub releases
- Intended next artifact: signed and notarized sandboxed macOS app distribution
- Non-negotiable requirement: the app must remain read-only with respect to the user's Obsidian vault

## Repo Map

- `Sources/Obviewer/ObviewerApp.swift`
  Thin app entry point
- `Sources/ObviewerCore/`
  Portable models and services for notes, parsing, graph construction, and vault indexing
- `Sources/ObviewerMacApp/`
  macOS app state, platform services, documentation rendering, and SwiftUI/AppKit UI
- `Sources/ObviewerFixtureSupport/`
  Synthetic vault generator used by tests and demo tooling
- `Sources/ObviewerFixtureTool/`
  CLI entry point for generating demo vaults
- `Sources/ObviewerDocsTool/`
  CLI entry point for generating documentation screenshots
- `Tests/ObviewerCoreTests/`
  Parser, lookup, graph, and vault-reader tests
- `Tests/ObviewerMacAppTests/`
  AppModel and view-support tests
- `.github/workflows/`
  CI and tag-driven release automation
- `Configuration/Obviewer.entitlements`
  Minimum sandbox entitlements for the shipping app

## Important Note

The architectural read-only model is already strong, but the strongest guarantee only exists when the app is shipped as a signed sandboxed macOS app with the entitlements in this repo. The Swift package itself is a development shape, not the final trust boundary.
