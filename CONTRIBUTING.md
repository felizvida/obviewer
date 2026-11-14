# Contributing

Thanks for contributing to Obviewer.

## Principles

- **Keep notes read-only.** Never add a read-write file entitlement or any path that writes to user-chosen files. See the entitlements policy in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
- **Keep the reader offline.** No remote loads; keep the content rules, CSP and navigation policy intact.
- **Keep the app light.** Prefer native macOS patterns, and no new runtime dependencies without a strong reason.
- **Follow the publication policy.** Contributions must pass `node scripts/publication-check.mjs --tracked`. CI enforces it.

## Before opening a pull request

1. `swift build && swift test`
2. If you touched `Renderer/`: `cd Renderer && npm ci --ignore-scripts && npm test && npm run build`, and commit the regenerated bundle. `node build.mjs --check` must pass.
3. If you changed how links are recognized: add a case to `Fixtures/notes/expectations.json`.
4. `make publication-check`
5. For UI, WebKit, Finder or Quick Look changes: run the relevant items of [`docs/VERIFICATION.md`](docs/VERIFICATION.md) on a Mac.
6. Describe any entitlement, sandbox or network-related change explicitly in the pull request.

## Pull request expectations

- Keep changes scoped, and explain the user-facing effect.
- Add or update tests when parsing, rendering, vault access or packaging changes.
- Update [`docs/STATUS.md`](docs/STATUS.md) when you change what's verified or limited.
