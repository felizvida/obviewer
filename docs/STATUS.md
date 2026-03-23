# Current Status

This document records the implementation baseline so a future maintainer can orient quickly without diff archaeology.

## Summary

The repository is best described as:

- a working prototype with real product behavior
- a healthy codebase for continued iteration
- not yet a finished shipping app

The project has moved past "scaffold only" status. It is now strong enough for real product work, but it still needs distribution, fidelity, performance, and accessibility modernization.

## Implemented Today

### Application Shell

- SwiftUI app entry point exists
- core and macOS shell logic are split into separate targets
- split-view library and reader workspace exists
- graph workspace exists
- toolbar and command actions exist for opening and reloading a vault
- empty, loading, and error states exist

### Vault Access

- vault selection uses `NSOpenPanel`
- security-scoped bookmark persistence exists
- security-scoped access is started and swapped through dedicated services
- vault enumeration is centralized and read-oriented
- live loading progress is surfaced to the UI

### Note Processing

- markdown files are discovered
- supported attachments are indexed
- notes are parsed into a render model with inline runs
- search over title, path, tags, and preview text is implemented
- note links, attachment links, and heading anchors are classified
- relative note and attachment resolution is source-aware
- headings are collected into a table of contents
- a note graph is derived from outbound links

### Reading UI

- metadata header exists
- paragraph, heading, list, quote, callout, code, divider, and image blocks render
- inline images render with sizing hints
- tables render in the reader
- inline note and attachment links render inside note content
- linked-note navigation exists
- a right-side contents rail exists for long notes
- local image lightbox behavior exists

### Graph UI

- local and global graph views exist
- graph inspector exists
- search-aware graph filtering exists
- folder grouping contributes to visual identity

### Quality Tooling

- synthetic demo vault generation exists
- documentation screenshot generation exists
- core and app-model regression tests exist
- view-support tests exist

### Repository Operations

- GitHub repository is configured
- CI is green on `macos-14` and `macos-15`
- tag-driven GitHub release automation exists
- issue templates and contributor docs exist
- XcodeGen project generation exists
- signing-aware packaging scripts exist
- Apache 2.0 licensing is in place

## Partially Implemented

### Obsidian Compatibility

Present:

- wiki links
- tags
- tables
- callouts
- headings and anchors
- image embeds and size hints

Still incomplete:

- full CommonMark coverage
- ordered lists and nested list fidelity
- task lists
- footnotes
- Mermaid
- math
- embedded PDF/audio/video rendering
- richer frontmatter semantics

### Read-Only Guarantee

Architecturally present:

- no write API
- reader-only file access path
- read-only entitlement baseline exists
- unsigned release packaging is blocked

Still incomplete:

- no published signed/notarized app artifact yet
- no end-user distribution path that fully demonstrates the trust story

### Distribution

Present:

- source releases
- signing-aware build scripts
- XcodeGen app-project generation
- notarization-ready DMG packaging scripts
- release workflow hooks for signed/notarized DMG publishing when secrets are configured

Still incomplete:

- production Apple signing secrets configured in GitHub
- first published notarized GitHub `.dmg`
- Mac App Store path
- auto-update channel

### Performance

Present:

- acceptable behavior on the synthetic demo vault
- loading progress visibility

Still incomplete:

- incremental indexing
- file watching
- large-vault profiling
- caching and smarter search ranking

## Not Implemented Yet

- notarized `.app` or `.dmg` release artifacts
- App Store distribution
- live vault refresh
- large-vault performance instrumentation
- UI snapshot testing
- accessibility audit and VoiceOver tuning
- PDF/audio/video reader surfaces
- Mermaid rendering or preview
- crash/reporting or telemetry strategy
- in-app onboarding for first-run distribution builds

## Known Risks

### Risk 1: Parser fidelity gap

The parser is increasingly capable, but still incomplete enough that unsupported syntax can look like a rendering bug.

### Risk 2: Distribution gap

The repo is release-automated, but the published artifact is still source-only. That keeps the strongest user-facing trust story incomplete.

### Risk 3: Performance ceiling

The current full-reload indexing model will eventually limit very large vaults and richer graph interactions.

### Risk 4: UI verification gap

Most confidence comes from core and orchestration tests, not visual regression or accessibility validation.

## Recommended Next Milestones

### Milestone 1: Shipping Distribution

Goal:

- publish a signed, notarized macOS app distribution without broadening file permissions

Why first:

- it completes the trust story for real users

### Milestone 2: Content Fidelity

Goal:

- improve markdown and Obsidian support enough that real vaults render predictably

Why next:

- reader quality depends on faithful content rendering

### Milestone 3: Scale And Live Refresh

Goal:

- improve indexing, caching, and change observation for larger vaults

### Milestone 4: Polish And Accessibility

Goal:

- refine graph UX, media handling, visual consistency, and accessibility

The detailed execution plan is in [`MODERNIZATION_PLAN.md`](./MODERNIZATION_PLAN.md).

## What A New Maintainer Should Verify First

1. the project builds and tests with full Xcode
2. the app can open a real vault and the synthetic demo vault
3. bookmark restore works after relaunch
4. the entitlement baseline stays read-only
5. current docs still match the real release and runtime behavior

## When To Update This Document

Update this file whenever:

- shipping readiness changes
- a major feature becomes solid
- a major risk is removed or discovered
- the recommended modernization sequence changes
