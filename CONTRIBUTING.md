# Contributing

Thanks for contributing to Obviewer.

## Development Principles

- Preserve the read-only contract for vault access.
- Prefer native macOS patterns over cross-platform abstractions.
- Keep the reading experience elegant, fast, and calm.

## Before Opening A Pull Request

1. Run `swift build`.
2. Run `swift test`.
3. Smoke test with a local Obsidian vault on macOS.
4. Document any sandbox or entitlement changes in the PR.

## Pull Request Expectations

- Keep changes scoped.
- Explain user-facing impact clearly.
- Add or update tests when parsing or vault access behavior changes.
