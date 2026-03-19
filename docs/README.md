# Documentation Index

This repository is intentionally documented for zero-memory handoff.

That means the documentation assumes the reader:

- Has never seen the project before
- Does not know what was discussed elsewhere
- Does not know the original motivation unless it is written down here
- Needs enough context to continue the work safely without asking the previous maintainer for missing details

If you are new to the project, read the documents in this order:

1. [`../QUICKSTART.md`](../QUICKSTART.md) to run the app locally with the fewest steps
2. [`HANDOFF.md`](./HANDOFF.md) for the current state, critical context, and immediate next steps
3. [`PRODUCT.md`](./PRODUCT.md) for the project goals, constraints, and UX direction
4. [`ARCHITECTURE.md`](./ARCHITECTURE.md) for how the current codebase is structured
5. [`DEVELOPMENT.md`](./DEVELOPMENT.md) for setup, build, test, and shipping workflow
6. [`STATUS.md`](./STATUS.md) for the current implementation status, known gaps, and recommended roadmap

## Quick Facts

- Project name: `Obviewer`
- Repository URL: `https://github.com/felizvida/obviewer`
- Platform target: macOS
- Language: Swift
- UI framework: SwiftUI with light AppKit interop
- Package format today: Swift package
- Intended shipping format: sandboxed macOS `.app`
- Non-negotiable product requirement: the app must be read-only with respect to the user's Obsidian vault

## Repo Map

- `Sources/Obviewer/ObviewerApp.swift`
  Application entry point
- `Sources/ObviewerCore/`
  Portable domain models, parser, lookup, and vault indexing logic
- `Sources/ObviewerMacApp/`
  macOS app state, platform services, and SwiftUI reader UI
- `Tests/ObviewerCoreTests/`
  Core parser, normalization, snapshot, and vault-reader tests
- `Tests/ObviewerMacAppTests/`
  AppModel orchestration and state tests
- `Configuration/Obviewer.entitlements`
  Minimum sandbox entitlements required for the shipping app target

## Important Note

The codebase currently contains a strong architectural read-only intent, but the strongest guarantee only exists once the code is wrapped in a real sandboxed macOS app target using the entitlements described in this repository. The Swift package by itself is not the final shipping artifact.
