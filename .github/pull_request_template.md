## Summary

- What changes for users?
- Linked issue, if any

## Validation

- [ ] `swift build` and `swift test`
- [ ] Renderer changed? `cd Renderer && npm test && npm run build`, bundle committed, `node build.mjs --check` passes
- [ ] `make publication-check` passes
- [ ] Relevant items of `docs/VERIFICATION.md` checked on a Mac (UI, WebKit, Finder, Quick Look changes)

## Risk notes

- Entitlement, sandbox, network or packaging changes (describe, or write "none")
