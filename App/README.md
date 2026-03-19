# App Packaging Notes

This directory exists to support generation of a real macOS app project from `project.yml`.

## Current Approach

The repository still keeps the source code in Swift package layout, but it now also includes an `XcodeGen` project spec so a maintainer can generate an actual `.xcodeproj` without rebuilding that structure from memory.

The generated project mirrors the package split:

- `ObviewerCore`
- `ObviewerMacApp`
- `Obviewer`

Generated assets:

- `App/Info.plist`
- `Obviewer.xcodeproj`

These are intentionally generated rather than checked in.

## Typical Flow

```bash
brew install xcodegen
export OBVIEWER_CODE_SIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID1234)"
export OBVIEWER_DEVELOPMENT_TEAM="TEAMID1234"
make xcodeproj
make build-app
make package-app
```

The packaging scripts now require code signing and verify that the sandbox entitlements are present in the resulting app bundle before zipping it.
