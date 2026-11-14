# Handoff

Read this first if you're taking over Obviewer. Last updated November 14, 2026, for version 0.3.0.

## What it is

A read-only macOS reader for Markdown files, Obsidian vaults and DokuWiki folders. It has a SwiftUI shell and an offline WebKit reader, plus a static Quick Look preview. It's used by the maintainer and a few colleagues, and distributed as an ad-hoc signed DMG on GitHub Releases.

## Where things stand

[`STATUS.md`](./STATUS.md) is the ledger of what's verified, limited and unverified. In short: the 0.3.0 feature set works on the maintainer's Apple-silicon Mac (macOS 26), and the automated suites pass (see STATUS for counts). Untested so far: a second-Mac install, accessibility, macOS 14/15, and rendering performance.

## Invariants you must keep

1. **Notes are read-only, enforced by macOS.** Never add a read-write file entitlement. The app's only writes go to its own container and the clipboard. Editing, saving PDFs and sharing are always handed to other apps.
2. **The reader loads nothing remote.** The app holds `network.client` only because WebKit won't start in the sandbox without it. The content rules (which fail closed), the CSP, the navigation policy and DOMPurify carry the guarantee, so keep all four. The Quick Look extension never gets network access.
3. **Nothing institutional gets published.** The publication check (`scripts/publication-check.mjs`) gates CI and releases. Don't write the prohibited terms anywhere in the repository, even to explain the policy.
4. **The renderer bundle matches its source.** Rebuild and commit `Resources/Reader` with every `Renderer/src` change.
5. **The two parsers agree on links.** Extend `Fixtures/notes/expectations.json` when either changes.

## How it fits together

[`ARCHITECTURE.md`](./ARCHITECTURE.md) covers the modules and data flow. [`READER_ARCHITECTURE.md`](./READER_ARCHITECTURE.md) covers the reader and where each safety guarantee is enforced. [`DEVELOPMENT.md`](./DEVELOPMENT.md) covers commands, CI and the release process. [`REDESIGN_PLAN.md`](./REDESIGN_PLAN.md) records why the v0.3 decisions were made.

## Things that can mislead you

- **Green CI doesn't mean the app works.** CI never launches it. WebKit and sandbox behavior only show up in a running build; use [`VERIFICATION.md`](./VERIFICATION.md).
- **`swift run` is not the shipping trust boundary.** The sandbox and entitlements apply only to the signed `.app` built from the Xcode project.
- **Ad-hoc signing has costs:** approval prompts after updates, possibly lost folder access, and managed Macs that refuse the app. A Developer ID would remove them; the notarization path is already in the scripts and workflow.

## Open decisions

- Whether to improve the Slack paste format (Slack flattens nesting and italicizes bold), or document it as is
- Whether to pursue a Developer ID for notarized distribution

The v0.2.8 handoff is in [`history/HANDOFF_v0.2.8.md`](./history/HANDOFF_v0.2.8.md).
