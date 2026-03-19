#!/usr/bin/env bash
set -euo pipefail

"$(dirname "$0")/build_app.sh"

APP_PATH="build/Build/Products/Release/Obviewer.app"
ZIP_PATH="build/Obviewer-macOS-signed.zip"

if [ ! -d "$APP_PATH" ]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_PATH"

if ! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "<key>com.apple.security.app-sandbox</key>"; then
  echo "Expected App Sandbox entitlement is missing from the signed app bundle." >&2
  exit 1
fi

if ! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "<key>com.apple.security.files.user-selected.read-only</key>"; then
  echo "Expected read-only user-selected file entitlement is missing from the signed app bundle." >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created $ZIP_PATH"
