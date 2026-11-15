# Documentation

Start with the [`README`](../README.md). Then read in this order:

1. [`INSTALL.md`](./INSTALL.md): installing and using the release build
2. [`STATUS.md`](./STATUS.md): what's verified, what's limited, what hasn't been checked yet
3. [`HANDOFF.md`](./HANDOFF.md): the invariants and traps, for anyone taking over
4. [`PRODUCT.md`](./PRODUCT.md): who it's for and what's in and out of scope
5. [`ARCHITECTURE.md`](./ARCHITECTURE.md): modules and data flow
6. [`READER_ARCHITECTURE.md`](./READER_ARCHITECTURE.md): the WebKit reader and where each safety guarantee is enforced
7. [`DEVELOPMENT.md`](./DEVELOPMENT.md): building, testing, CI, the publication policy and releases
8. [`VERIFICATION.md`](./VERIFICATION.md): the manual checklist for a build on a real Mac
9. [`history/REDESIGN_PLAN_v0.3.md`](./history/REDESIGN_PLAN_v0.3.md): why the v0.3 decisions were made

Also: [`../QUICKSTART.md`](../QUICKSTART.md) to run from source, and [`../CHANGELOG.md`](../CHANGELOG.md) for release history.

## Quick facts

| | |
| --- | --- |
| Version | 0.3.0, pre-release `v0.3.0-beta.1` |
| Platform | macOS 26 or later, Apple silicon (from the release after beta.2); verified on macOS 26 |
| Languages | Swift (SwiftUI, AppKit, WebKit, JavaScriptCore); JavaScript for the renderer |
| Distribution | Ad-hoc signed DMG on GitHub Releases (not notarized) |
| Permissions | App: sandbox, read-only user-selected files, print, outgoing network (for WebKit). Quick Look: sandbox, read-only user-selected files. |

## History

[`history/`](./history/) holds the v0.2.8-era status, handoff, product notes, architecture, development guide, roadmap and visual tour. They're kept for context and aren't maintained. In [`images/`](./images/), `reader.png` shows the current reader (a Debug build of the v0.3.0-beta.2 redesign, demo content; macOS's screen-sharing indicator was painted out of the window corner). The historical visual tour loads its v0.2.8 screenshots from the `v0.3.0-beta.1` tag.
