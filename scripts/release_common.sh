#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

default_app_path() {
  printf '%s\n' "${OBVIEWER_APP_PATH:-build/Build/Products/Release/Obviewer.app}"
}

artifact_basename() {
  local base="Obviewer"
  if [ -n "${OBVIEWER_RELEASE_VERSION:-}" ]; then
    base="${base}-${OBVIEWER_RELEASE_VERSION}"
  fi
  printf '%s\n' "$base"
}

signed_zip_path() {
  printf '%s\n' "build/$(artifact_basename)-macOS-signed.zip"
}

signed_dmg_path() {
  printf '%s\n' "build/$(artifact_basename)-macOS-signed.dmg"
}

notarized_dmg_path() {
  printf '%s\n' "build/$(artifact_basename)-macOS-notarized.dmg"
}

require_app_bundle() {
  local app_path="${1:-$(default_app_path)}"
  if [ ! -d "$app_path" ]; then
    echo "Expected app bundle not found at $app_path" >&2
    exit 1
  fi
}

verify_signed_app_bundle() {
  local app_path="${1:-$(default_app_path)}"

  require_app_bundle "$app_path"
  codesign --verify --deep --strict "$app_path"

  if ! codesign -d --entitlements :- "$app_path" 2>/dev/null | grep -q "<key>com.apple.security.app-sandbox</key>"; then
    echo "Expected App Sandbox entitlement is missing from the signed app bundle." >&2
    exit 1
  fi

  if ! codesign -d --entitlements :- "$app_path" 2>/dev/null | grep -q "<key>com.apple.security.files.user-selected.read-only</key>"; then
    echo "Expected read-only user-selected file entitlement is missing from the signed app bundle." >&2
    exit 1
  fi
}

require_notary_profile() {
  if [ -z "${OBVIEWER_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    echo "OBVIEWER_NOTARY_KEYCHAIN_PROFILE is required for notarization." >&2
    exit 1
  fi
}

create_sha256_file() {
  local input_path="$1"
  local output_path="$2"
  shasum -a 256 "$input_path" > "$output_path"
}
