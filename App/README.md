# App packaging notes

`project.yml` is the XcodeGen spec for the real macOS app. It generates:

- `Obviewer.xcodeproj`
- `App/Info.plist`
- `Configuration/ObviewerQuickLook-Info.plist`

All three are gitignored. Regenerate them with `make xcodeproj`.

`App/Assets.xcassets` holds the app icon and is tracked. It is drawn by `scripts/generate_app_icon.py` (Pillow only): a page with a purple bookmark and the gold fleur-de-lis that also closes each note in the reader. Rerun the script after changing the drawing.

The generated project contains:

- static libraries: `ObviewerCore`, `ObviewerReaderKit` and `ObviewerMacApp`, linked into each executable (`ObviewerFixtureSupport` only into tests and tools). No frameworks are shipped, because an ad-hoc signed hardened app can't load them.
- the `Obviewer` app, which embeds the `ObviewerQuickLook` app extension. Both bundles carry the `Resources/Reader` folder.
- test bundles: `ObviewerCoreTests`, `ObviewerReaderKitTests`, `ObviewerMacAppTests`

## Builds

```bash
make package-adhoc     # ad-hoc signed Release app + DMG (no Apple account needed)

# Developer ID (signed; notarized when OBVIEWER_NOTARY_KEYCHAIN_PROFILE is set)
export OBVIEWER_CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID1234)"
export OBVIEWER_DEVELOPMENT_TEAM="TEAMID1234"
make package-dmg
```

Every packaging path verifies the app three times: in the staging folder, on the writable image volume before it is sealed, and inside the finished, read-only-mounted DMG. Each time it checks:

- the strict signature
- the hardened runtime flag
- the sandbox and read-only file entitlements, on both the app and the extension
- that no read-write, server-network or debugger (`get-task-allow`) entitlement is present
- that the extension has no network entitlement
- that executables depend only on system libraries, with no bundled frameworks or dylibs
- that no Finder info or resource forks are present

The finished image may contain only the app, the Applications link, the install guide and two empty markers that keep Spotlight indexes and file-event logs out of it.

See [`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md) for the release workflow.
