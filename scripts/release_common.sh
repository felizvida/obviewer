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
  local entitlements_path

  require_app_bundle "$app_path"
  codesign --verify --deep --strict "$app_path"

  if ! codesign -dv --verbose=4 "$app_path" 2>&1 | grep -Eq "flags=.*runtime"; then
    echo "Expected hardened runtime flag is missing from the signed app bundle." >&2
    exit 1
  fi

  entitlements_path="$(mktemp "${TMPDIR:-/tmp}/obviewer-entitlements.XXXXXX.plist")"
  codesign -d --entitlements :- "$app_path" > "$entitlements_path" 2>/dev/null

  require_entitlement_true "$entitlements_path" "com.apple.security.app-sandbox" "App Sandbox"
  require_entitlement_true "$entitlements_path" "com.apple.security.files.user-selected.read-only" "read-only user-selected file access"

  if /usr/libexec/PlistBuddy -c "Print :com.apple.security.files.user-selected.read-write" "$entitlements_path" >/dev/null 2>&1; then
    echo "Forbidden read-write user-selected file entitlement is present in the signed app bundle." >&2
    rm -f "$entitlements_path"
    exit 1
  fi

  rm -f "$entitlements_path"
}

require_entitlement_true() {
  local plist_path="$1"
  local key="$2"
  local label="$3"
  local value

  if ! value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null); then
    echo "Expected $label entitlement is missing from the signed app bundle." >&2
    exit 1
  fi

  if [ "$value" != "true" ]; then
    echo "Expected $label entitlement to be true, but found '$value'." >&2
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
