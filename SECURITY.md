# Security Policy

Obviewer is intended to be a read-only local viewer, so security issues around file access, sandboxing, and unexpected data mutation are especially important.

## Reporting A Vulnerability

Please use GitHub Security Advisories if available for the repository. If private reporting is not available, contact the repository owner directly before opening a public issue.

## Scope

Examples of in-scope concerns:

- Any path that could mutate vault contents
- Sandbox or entitlement misconfiguration
- Security-scoped bookmark behavior that grants broader than read-only access
- Release artifacts missing hardened runtime, sandbox, or read-only entitlement validation
- Path traversal or unsafe file resolution
- Unexpected network access
