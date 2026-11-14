# Security Policy

Obviewer is a read-only viewer, so problems with file access, sandboxing, content isolation and unexpected network or data flow matter most.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting (Security › Report a vulnerability) for this repository. If that isn't available, contact the repository owner privately before opening a public issue.

## Security model (summary)

- **Files:** App Sandbox with `files.user-selected.read-only` as the only file permission, so macOS rejects writes to notes. The app writes only to its own container and the clipboard.
- **Network:** the app holds `network.client` because WebKit requires it to start in the sandbox. Obviewer makes no requests itself, and the reader blocks non-local loads with content rules (failing closed), a strict CSP and a navigation policy. The Quick Look extension has no network permission. `network.server` is never granted.
- **Note content:** HTML in notes is sanitized with DOMPurify, scripts can't run (CSP), and page messages to Swift are limited to read-only events.
- **Handoffs:** Edit in…, opening attachments and share services run in other apps. Obviewer confirms attachments and app links, and refuses to open apps, installers or scripts.

Details: [`docs/READER_ARCHITECTURE.md`](docs/READER_ARCHITECTURE.md).

## In scope

- Any path that could modify or delete files in a user's notes
- Sandbox, entitlement or signing misconfiguration, including a debugger entitlement in release builds
- Security-scoped bookmarks granting more than read-only access
- Remote content loading or other unexpected network activity from the reader
- Script execution or escaping the sanitizer through note content
- Path traversal through the `obviewer-asset://` scheme
- Release artifacts that skip the documented signature, entitlement or publication checks
