# Current Status

This document records the current implementation status so a future maintainer can orient quickly without diff archaeology.

## Summary

The repository is in an early but coherent state.

It is best described as:

- A serious prototype scaffold
- A clear product and architecture direction
- Not yet a production-ready app

## Implemented Today

### Application Shell

- SwiftUI app entry point exists
- Core and macOS shell logic are split into separate package targets
- Split-view layout exists
- Toolbar actions exist for opening and reloading a vault
- Empty state and loading state are present

### Vault Access

- Vault selection uses `NSOpenPanel`
- Security-scoped bookmark persistence exists
- Security-scoped access is started when a vault is loaded
- Vault enumeration is read-oriented and centralized

### Note Processing

- Markdown files are discovered
- Supported attachments are indexed
- Notes are parsed into a simple render model
- Search over title, path, tags, and preview text is implemented
- Inline note links and external links are parsed
- GFM-style tables are parsed
- Note headings are collected into a table of contents

### Reading UI

- Large title and metadata header exists
- Paragraph, heading, list, quote, callout, code, divider, and image blocks render
- Tables render in the reader
- Inline links render inside note content
- Linked-note chips are shown for outbound links
- A right-side contents rail exists for long-note navigation

### Tests

- Core parser, normalization, snapshot, and reader tests exist
- `AppModel` orchestration tests exist

### Repository Operations

- GitHub repository exists and is configured
- CI exists
- Tag-driven GitHub release automation exists
- Issue templates and contributor docs exist
- XcodeGen project scaffolding and signing-aware packaging scripts exist

## Partially Implemented

### Obsidian Compatibility

Partially present:

- Wiki links
- Tags
- Callouts
- Standalone image embeds

Missing or incomplete:

- Rich inline formatting
- Full markdown coverage
- Many Obsidian-specific syntaxes

### Read-Only Guarantee

Architecturally present:

- No write API
- Reader-only file path in current code
- Intended sandbox entitlement file exists

Not yet complete:

- A real shipping app target with sandbox configuration has not yet been built in this repository

## Not Implemented Yet

- Full Xcode app project or app target setup
- Notarization
- File watching
- Large-vault performance tuning
- PDF/audio/video rendering
- Nested lists
- Ordered lists
- Task lists
- Footnotes
- Mermaid block previews
- Search ranking sophistication
- Accessibility review
- Screenshot assets
- Formal license selection

## Known Risks

### Risk 1: Toolchain confusion

The repo can appear broken on a machine that only has Command Line Tools active. This is an environment issue that can mask the real health of the codebase.

### Risk 2: Parser fidelity gap

The current parser is intentionally lightweight. Unsupported note constructs may be mistaken for rendering bugs.

### Risk 3: Incomplete shipping container

The current repository expresses the correct sandbox direction, but the final safety story is not complete until the app target itself is configured and tested.

## Recommended Next Milestones

### Milestone 1: Shipping Container

Goal:

- Turn the package scaffold into a real sandboxed macOS app target

Why this first:

- It validates the non-negotiable read-only requirement

### Milestone 2: Parser Fidelity

Goal:

- Improve markdown and Obsidian feature coverage beyond the current inline links and table support

Why next:

- The reading experience is only as good as the content fidelity

### Milestone 3: Reading Navigation

Goal:

- Add richer inline navigation and better handling of large note graphs

Why after parser work:

- Good navigation is much more valuable once content rendering is trustworthy

### Milestone 4: Media And Polish

Goal:

- Add better attachment handling, polish, and release quality

## What A New Maintainer Should Verify First

1. The project builds with full Xcode
2. The app can open a real vault
3. The bookmark restore path behaves correctly after relaunch
4. The entitlements are correctly attached in the eventual app target
5. The parser behaves acceptably on representative vault content

## When To Update This Document

Update this file whenever one of these changes happens:

- The shipping readiness level changes
- A major feature becomes complete
- A major technical risk is removed or discovered
- The next recommended milestone changes
