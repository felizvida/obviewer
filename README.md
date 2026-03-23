# Obviewer

[![CI](https://github.com/felizvida/obviewer/actions/workflows/ci.yml/badge.svg)](https://github.com/felizvida/obviewer/actions/workflows/ci.yml)

Obviewer is a native macOS reader for local Obsidian vaults built around one non-negotiable promise: the app must remain read-only with respect to the user's notes.

The project is already a working prototype, not just a sketch. It has a portable core, a macOS app shell, a reader-first interface, a graph workspace, a generated demo vault, documentation screenshots, and green GitHub CI. It is not yet a fully shipped consumer app because signed/notarized app distribution, parser fidelity, accessibility, and large-vault performance still need dedicated modernization work.

## Start Here

- [`QUICKSTART.md`](./QUICKSTART.md) for the fastest local run
- [`docs/VISUAL_TOUR.md`](./docs/VISUAL_TOUR.md) for the current UI and design language
- [`docs/README.md`](./docs/README.md) for the zero-memory documentation index
- [`docs/HANDOFF.md`](./docs/HANDOFF.md) for the current project state and maintainer context
- [`docs/MODERNIZATION_PLAN.md`](./docs/MODERNIZATION_PLAN.md) for the phased roadmap to turn the prototype into a modern shipping product

[![Obviewer visual tour](./docs/images/visual-tour-library-home.png)](./docs/VISUAL_TOUR.md)

## What Works Today

- Native SwiftUI macOS app shell with `NavigationSplitView`
- Portable `ObviewerCore` module for parsing, lookup, vault indexing, and graph construction
- macOS-specific `ObviewerMacApp` module for security-scoped access, bookmarks, app state, and UI
- Local vault loading with progress reporting, live vault watching, and path-aware selective reloads
- Warm-start snapshot cache that reuses parsed notes and attachment metadata across relaunches when files are unchanged
- Search by title, path, tags, preview text, aliases, and frontmatter metadata through a core precomputed search index
- Obsidian-aware parsing for frontmatter, links, tables, headings, ordered/task/nested lists, footnotes, tags, callouts, image embeds, and graceful fallback blocks for Mermaid/math/media embeds
- Inline image rendering with size hints plus a lightbox for image attachments
- Reader workspace with metadata, linked-note navigation, and a contents rail
- Graph workspace with local and global graph views
- Rich synthetic-vault tooling for realistic manual testing
- Large-vault benchmark tooling with index diagnostics for cold load, warm reload, selective reload, search, and graph query profiling
- CI benchmark profiling for smoke and integration fixtures, with the smoke profile enforced by a checked-in budget
- Documentation screenshot generation from the real app
- Green CI on `macos-14` and `macos-15`

## Safety Model

The UI being "view only" is not enough. The guarantee comes from platform boundaries and the code structure:

1. The shipping app must run with App Sandbox enabled.
2. The app must request only `com.apple.security.files.user-selected.read-only`.
3. Vault access must come from user-selected folders, not broad filesystem exceptions.
4. Vault reads must flow through the reader layer, with no write API.
5. Release packaging must preserve the sandbox entitlements through code signing.

The current entitlement baseline lives in [`Configuration/Obviewer.entitlements`](/Users/liux17/codex/obviewer/Configuration/Obviewer.entitlements).

## Quick Start

The shortest local trial path is:

```bash
git clone https://github.com/felizvida/obviewer.git
cd obviewer
make try-local
```

If you want a realistic vault without touching your own notes:

```bash
make demo-vault
```

That generates `build/SampleVault`, which includes nested folders, duplicate filenames, shared and local attachments, tags, tables, links, images, and graph-friendly note relationships.

If you want a repeatable performance read on the synthetic large-vault path:

```bash
make benchmark-vault
```

That runs the benchmark fixture profile and prints index diagnostics plus timings for cold load, warm reload, selective reload, search, and graph queries.

For the same path that CI enforces, use:

```bash
PROFILE=smoke BUDGET=Configuration/benchmark-smoke-budget.json make benchmark-vault
```

CI also publishes an `integration` benchmark report artifact on every run so larger-profile performance trends can be watched before stricter budgets are locked in.

## Current Distribution State

Today the GitHub release workflow always publishes source archives and checksums. It is now also prepared to publish a signed `.dmg` once Apple signing and notarization secrets are configured in GitHub.

The Phase 1 distribution foundation now includes:

- `project.yml` for XcodeGen app-project generation
- `scripts/build_app.sh` for signed app builds
- `scripts/notarize_release_app.sh` for app notarization and stapling
- `scripts/package_release_app.sh` for signed release zip packaging
- `scripts/package_release_dmg.sh` for signed DMG packaging, with optional notarization
- `.github/workflows/release.yml` for tag-driven release automation that can publish a signed/notarized DMG when secrets are present

The next distribution milestone is to configure the Apple credentials in GitHub and validate the first fully notarized public download.

## Architecture Snapshot

The codebase is split into three primary targets:

- `ObviewerCore`
  Portable models and services for notes, attachments, parser output, graph data, and vault indexing
- `ObviewerMacApp`
  macOS app state, platform integrations, SwiftUI/AppKit views, and documentation rendering
- `Obviewer`
  Thin executable entry point that launches the app

This separation keeps the vault and parser logic easier to test, debug, and eventually reuse in another shell.

## Modernization Priorities

The project should modernize in this order:

1. Ship the production-grade app container and distribution path
2. Upgrade markdown and Obsidian fidelity without weakening the read-only boundary
3. Deepen live refresh into truly change-aware indexing, caching, and large-vault performance work
4. Deepen navigation, graph, media, and accessibility polish
5. Add observability and maintenance workflows that keep the project healthy over time

The detailed roadmap is in [`docs/MODERNIZATION_PLAN.md`](./docs/MODERNIZATION_PLAN.md).

## Repository Health

- CI runs on pushes to `main` and `codex/**`, on pull requests, and on manual dispatch
- Releases are tag-driven through `.github/workflows/release.yml`
- The repo includes issue templates, CODEOWNERS, contribution guidance, and security/support docs
- The current release line is green after `v0.2.5`

## License

This repository is licensed under Apache 2.0. See [LICENSE](./LICENSE).
