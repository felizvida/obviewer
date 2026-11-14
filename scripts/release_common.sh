#!/usr/bin/env bash
set -euo pipefail

# Resolved once, when this file is sourced, so later `cd`s can't change it.
OBVIEWER_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

repo_root() {
  printf '%s\n' "$OBVIEWER_REPO_ROOT"
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

is_adhoc_signing() {
  [ "${OBVIEWER_CODE_SIGN_IDENTITY:-}" = "-" ]
}

signing_label() {
  if is_adhoc_signing; then
    printf '%s\n' "adhoc"
  else
    printf '%s\n' "signed"
  fi
}

signed_zip_path() {
  printf '%s\n' "build/$(artifact_basename)-macOS-$(signing_label).zip"
}

signed_dmg_path() {
  printf '%s\n' "build/$(artifact_basename)-macOS-$(signing_label).dmg"
}

notarized_dmg_path() {
  printf '%s\n' "build/$(artifact_basename)-macOS-notarized.dmg"
}

# ---------------------------------------------------------------------------
# Verification helpers.
#
# Rules, because these gates decide what ships:
#   - Every mandatory step checks its own exit status and returns non-zero on
#     failure. Nothing relies on errexit, which bash disables inside `if`, `!`,
#     `&&`, `||` and in functions called from those contexts.
#   - Tool output is captured completely, then matched in-process. No producer is
#     piped into `grep -q`: an early grep exit sends the producer SIGPIPE, which
#     pipefail reports as a failure (or, inverted, masks a match).
#   - A tool that fails is a failed check, never "nothing found".
# Tool paths can be overridden (tests use mocks): CODESIGN, OTOOL, XATTR,
# PLISTBUDDY, PLUTIL, HDIUTIL, MDUTIL, CMP, FIND, GIT.

: "${CODESIGN:=codesign}"
: "${OTOOL:=otool}"
: "${XATTR:=xattr}"
: "${PLISTBUDDY:=/usr/libexec/PlistBuddy}"
: "${PLUTIL:=plutil}"
: "${HDIUTIL:=hdiutil}"
: "${MDUTIL:=mdutil}"
: "${CMP:=cmp}"
: "${FIND:=find}"
: "${GIT:=git}"

APP_ALLOWED_ENTITLEMENTS="com.apple.security.app-sandbox com.apple.security.files.user-selected.read-only com.apple.security.print com.apple.security.network.client"
EXTENSION_ALLOWED_ENTITLEMENTS="com.apple.security.app-sandbox com.apple.security.files.user-selected.read-only"
# Named explicitly for clear errors; the allow-lists above reject these too.
FORBIDDEN_ENTITLEMENTS="com.apple.security.files.user-selected.read-write com.apple.security.files.downloads.read-write com.apple.security.files.all com.apple.security.temporary-exception.files.absolute-path.read-write com.apple.security.temporary-exception.files.home-relative-path.read-write com.apple.security.network.server com.apple.security.get-task-allow com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-dyld-environment-variables com.apple.security.cs.allow-unsigned-executable-memory"

verification_failed() {
  echo "$*" >&2
  return 1
}

require_app_bundle() {
  local app_path="${1:-$(default_app_path)}"
  if [ ! -d "$app_path" ]; then
    verification_failed "Expected app bundle not found at $app_path"
    return 1
  fi
}

# Hardened runtime check: matches "flags=.*runtime" in the CodeDirectory line,
# e.g. "flags=0x10002(adhoc,runtime)", on fully captured codesign output.
has_hardened_runtime() {
  local bundle_path="$1"
  local info
  if ! info="$("$CODESIGN" -dv --verbose=4 "$bundle_path" 2>&1)"; then
    verification_failed "codesign -dv failed for $bundle_path: $info"
    return 1
  fi
  local pattern='flags=0x[0-9a-fA-F]+\([^)]*runtime[^)]*\)'
  if [[ ! "$info" =~ $pattern ]]; then
    verification_failed "Expected hardened runtime flag is missing from $bundle_path."
    return 1
  fi
}

verify_signed_app_bundle() {
  local app_path="${1:-$(default_app_path)}"
  local extension_path="$app_path/Contents/PlugIns/ObviewerQuickLook.appex"

  require_app_bundle "$app_path" || return 1
  if [ ! -d "$extension_path" ]; then
    verification_failed "Quick Look extension not found at $extension_path"
    return 1
  fi

  local output
  if ! output="$("$CODESIGN" --verify --deep --strict "$app_path" 2>&1)"; then
    verification_failed "Strict code signature verification failed for $app_path: $output"
    return 1
  fi
  if ! output="$("$CODESIGN" --verify --strict "$extension_path" 2>&1)"; then
    verification_failed "Strict code signature verification failed for $extension_path: $output"
    return 1
  fi

  has_hardened_runtime "$app_path" || return 1
  has_hardened_runtime "$extension_path" || return 1

  verify_bundle_entitlements "$app_path" "app" "$APP_ALLOWED_ENTITLEMENTS" || return 1
  verify_bundle_entitlements "$extension_path" "Quick Look extension" "$EXTENSION_ALLOWED_ENTITLEMENTS" || return 1

  verify_loadable_without_library_exceptions "$app_path" || return 1
  verify_icon_payload "$app_path" || return 1
  verify_no_detritus "$app_path" || return 1
}

# The shipped icon must be byte-for-byte the committed App/AppIcon.icns, the file
# the publication check inspects rendition by rendition. A compiled asset catalog
# (*.car) is an undocumented container that check can't inspect, so none may ship,
# in the app or in any bundle inside it. OBVIEWER_SOURCE_ICON is a test hook; with
# the default, the icon must also match HEAD (no uncommitted, unscanned edits).
verify_icon_payload() {
  local app_path="$1"
  local shipped_icon="$app_path/Contents/Resources/AppIcon.icns"
  local source_icon="${OBVIEWER_SOURCE_ICON:-}"
  local cars
  if ! cars="$("$FIND" "$app_path" -name '*.car' -print 2>&1)"; then
    verification_failed "Could not search $app_path for compiled asset catalogs: $cars"
    return 1
  fi
  if [ -n "$cars" ]; then
    verification_failed "Compiled asset catalog found; the publication check cannot inspect it. Ship App/AppIcon.icns instead:
$cars"
    return 1
  fi
  if [ -z "$source_icon" ]; then
    source_icon="$(repo_root)/App/AppIcon.icns"
    local status=0
    "$GIT" -C "$(repo_root)" diff --quiet HEAD -- App/AppIcon.icns || status=$?
    case "$status" in
      0) ;;
      1) verification_failed "App/AppIcon.icns has uncommitted changes; package only the committed, scanned icon."; return 1 ;;
      *) verification_failed "Could not confirm App/AppIcon.icns matches HEAD (git exit $status)"; return 1 ;;
    esac
  fi
  if [ ! -f "$source_icon" ] || [ -L "$source_icon" ]; then
    verification_failed "Source icon not found at $source_icon"
    return 1
  fi
  if [ -L "$shipped_icon" ] || [ ! -f "$shipped_icon" ]; then
    verification_failed "App icon not found at $shipped_icon (or it is a link)"
    return 1
  fi
  local compare=0
  "$CMP" -s -- "$source_icon" "$shipped_icon" || compare=$?
  case "$compare" in
    0) ;;
    1) verification_failed "$shipped_icon differs from the committed $source_icon"; return 1 ;;
    *) verification_failed "Could not compare $shipped_icon with $source_icon (cmp exit $compare)"; return 1 ;;
  esac
}

# Signed entitlements must be a valid plist, contain only allowed keys, and grant
# the sandbox and read-only file access. Anything else (read-write files, servers,
# get-task-allow, library-validation exceptions, unknown keys) fails.
verify_bundle_entitlements() {
  local bundle_path="$1"
  local label="$2"
  local allowed="$3"
  local entitlements_path
  local status=0

  entitlements_path="$(mktemp "${TMPDIR:-/tmp}/obviewer-entitlements.XXXXXX")" || return 1
  if ! "$CODESIGN" -d --entitlements :- "$bundle_path" > "$entitlements_path" 2>/dev/null; then
    verification_failed "Could not read the signed entitlements of the $label."
    status=1
  elif ! "$PLUTIL" -lint "$entitlements_path" >/dev/null 2>&1; then
    verification_failed "The signed entitlements of the $label are not a valid property list."
    status=1
  else
    verify_entitlements_file "$entitlements_path" "$label" "$allowed" || status=1
  fi
  rm -f "$entitlements_path"
  return "$status"
}

verify_entitlements_file() {
  local entitlements_path="$1"
  local label="$2"
  local allowed="$3"
  local listing
  local line
  local key
  local found=""
  local top_level_keys=0

  if ! listing="$("$PLISTBUDDY" -c "Print" "$entitlements_path" 2>&1)"; then
    verification_failed "Could not list the entitlements of the $label: $listing"
    return 1
  fi
  # Top-level keys are printed with four spaces of indentation: "    key = value".
  while IFS= read -r line; do
    if [[ "$line" =~ ^\ {4}([A-Za-z0-9._-]+)\ = ]]; then
      key="${BASH_REMATCH[1]}"
      found="$found $key"
      top_level_keys=$((top_level_keys + 1))
      case " $FORBIDDEN_ENTITLEMENTS " in
        *" $key "*)
          verification_failed "Forbidden entitlement $key is present in the signed $label."
          return 1
          ;;
      esac
      case " $allowed " in
        *" $key "*) ;;
        *)
          verification_failed "Entitlement $key is not allowed in the signed $label."
          return 1
          ;;
      esac
    fi
  done <<< "$listing"
  if [ "$top_level_keys" -eq 0 ]; then
    verification_failed "No entitlements were found in the signed $label."
    return 1
  fi

  require_entitlement_true "$entitlements_path" "com.apple.security.app-sandbox" "App Sandbox ($label)" || return 1
  require_entitlement_true "$entitlements_path" "com.apple.security.files.user-selected.read-only" "read-only user-selected file access ($label)" || return 1
}

# Kept for scripts that check a single entitlements file directly.
verify_read_only_entitlements() {
  local entitlements_path="$1"
  local label="$2"
  local network_policy="${3:-no-network}"
  if [ "$network_policy" = "allow-network-client" ]; then
    verify_entitlements_file "$entitlements_path" "$label" "$APP_ALLOWED_ENTITLEMENTS"
  else
    verify_entitlements_file "$entitlements_path" "$label" "$EXTENSION_ALLOWED_ENTITLEMENTS"
  fi
}

require_entitlement_true() {
  local plist_path="$1"
  local key="$2"
  local label="$3"
  local value

  if ! value="$("$PLISTBUDDY" -c "Print :$key" "$plist_path" 2>/dev/null)"; then
    verification_failed "Expected $label entitlement is missing from the signed bundle."
    return 1
  fi
  if [ "$value" != "true" ]; then
    verification_failed "Expected $label entitlement to be true, but found '$value'."
    return 1
  fi
}

# The hardened runtime validates every library a process loads. Ad-hoc signatures
# carry no Team ID, so an ad-hoc app cannot load separately signed frameworks.
# Obviewer links its modules statically; this check keeps it that way: executables
# may depend only on system libraries, and the bundle may not ship frameworks or dylibs.
verify_loadable_without_library_exceptions() {
  local app_path="$1"
  local bundled
  local executable
  local dependencies
  local line
  local library

  if ! bundled="$(find "$app_path" \( -name '*.framework' -o -name '*.dylib' \) -print 2>&1)"; then
    verification_failed "Could not search $app_path for bundled libraries: $bundled"
    return 1
  fi
  if [ -n "$bundled" ]; then
    verification_failed "The app bundle ships frameworks or dylibs, which an ad-hoc signed hardened app cannot load:
$bundled"
    return 1
  fi

  for executable in \
    "$app_path/Contents/MacOS/Obviewer" \
    "$app_path/Contents/PlugIns/ObviewerQuickLook.appex/Contents/MacOS/ObviewerQuickLook"; do
    if [ ! -f "$executable" ]; then
      verification_failed "Expected executable not found: $executable"
      return 1
    fi
    if ! dependencies="$("$OTOOL" -L "$executable" 2>&1)"; then
      verification_failed "otool failed for $executable: $dependencies"
      return 1
    fi
    # Dependency lines are indented; universal binaries add per-architecture header lines.
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]+([^[:space:]]+) ]]; then
        library="${BASH_REMATCH[1]}"
        case "$library" in
          /System/Library/*|/usr/lib/*) ;;
          *)
            verification_failed "Executable $executable depends on a non-system library: $library"
            return 1
            ;;
        esac
      fi
    done <<< "$dependencies"
  done
}

# Strict code signing rejects resource forks and Finder information on bundle files.
verify_no_detritus() {
  local target="$1"
  local attributes
  if ! attributes="$("$XATTR" -lr "$target" 2>&1)"; then
    verification_failed "Could not list extended attributes under $target: $attributes"
    return 1
  fi
  local line
  local offending=""
  while IFS= read -r line; do
    case "$line" in
      *com.apple.FinderInfo*|*com.apple.ResourceFork*) offending="$offending
  $line" ;;
    esac
  done <<< "$attributes"
  if [ -n "$offending" ]; then
    verification_failed "Finder information or resource forks found under $target:$offending"
    return 1
  fi
}

# A release image may contain only these entries at its root. The two hidden ones
# keep the OS from writing Spotlight indexes and file-event logs into the image;
# .fseventsd may hold nothing but its empty no_log marker.
DMG_ALLOWED_ROOT_ENTRIES="Obviewer.app Applications Read_Me_First .fseventsd .metadata_never_index"

verify_volume_layout() {
  local volume="$1"
  local entry
  local name
  local listing
  if ! listing="$(ls -A "$volume" 2>&1)"; then
    verification_failed "Could not list $volume: $listing"
    return 1
  fi
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name="$entry"
    [ "$entry" = "Read Me First - How to Install.md" ] && name="Read_Me_First"
    case " $DMG_ALLOWED_ROOT_ENTRIES " in
      *" $name "*) ;;
      *)
        verification_failed "Unexpected entry in the release image: $entry"
        return 1
        ;;
    esac
  done <<< "$listing"
  if [ -d "$volume/.fseventsd" ]; then
    if ! listing="$(ls -A "$volume/.fseventsd" 2>&1)"; then
      verification_failed "Could not list $volume/.fseventsd: $listing"
      return 1
    fi
    if { [ -n "$listing" ] && [ "$listing" != "no_log" ]; } || [ -s "$volume/.fseventsd/no_log" ]; then
      verification_failed "The release image contains file-event logs (.fseventsd: $(printf '%s' "$listing" | tr '\n' ' '))"
      return 1
    fi
  fi
  if [ -e "$volume/.metadata_never_index" ] && [ -s "$volume/.metadata_never_index" ]; then
    verification_failed "The release image's .metadata_never_index marker is not empty."
    return 1
  fi
}

# Prepares a freshly attached writable staging volume: tells the OS not to write
# Spotlight indexes or file-event logs into it. Call right after attaching.
prepare_staging_volume() {
  local volume="$1"
  : > "$volume/.metadata_never_index" || return 1
  mkdir -p "$volume/.fseventsd" || return 1
  : > "$volume/.fseventsd/no_log" || return 1
  # Not a gate: mdutil may refuse on a -nobrowse volume; the marker file still applies.
  # Only ever pointed at the disposable staging volume, never at a host volume.
  "$MDUTIL" -i off "$volume" >/dev/null 2>&1 || true
}

# Removes OS-generated metadata from the writable staging volume before it is sealed,
# and clears extended attributes from the content we copied in (copy engines and
# volume-discovery services can add Finder information). The sealed image is then
# verified as produced; nothing is ever removed from a release image after the fact.
clean_staging_volume() {
  local volume="$1"
  local entry
  local listing
  if ! listing="$(ls -A "$volume/.fseventsd" 2>&1)"; then
    verification_failed "Could not list $volume/.fseventsd: $listing"
    return 1
  fi
  while IFS= read -r entry; do
    [ -n "$entry" ] && [ "$entry" != "no_log" ] && { rm -rf "$volume/.fseventsd/$entry" || return 1; }
  done <<< "$listing"
  for entry in .Spotlight-V100 .Trashes .TemporaryItems .DocumentRevisions-V100 .DS_Store; do
    rm -rf "${volume:?}/$entry" || return 1
  done
  "$XATTR" -cr "$volume/Obviewer.app" || return 1
  if [ -f "$volume/Read Me First - How to Install.md" ]; then
    "$XATTR" -c "$volume/Read Me First - How to Install.md" || return 1
  fi
}

# Mounts a finished DMG read-only and verifies the app exactly as users will get it.
# The image is detached on every path; any failed check fails the function.
verify_dmg() {
  local dmg_path="$1"
  local mount_point
  local status=0
  local output

  mount_point="$(mktemp -d "${TMPDIR:-/tmp}/obviewer-dmg-verify.XXXXXX")" || return 1
  if ! output="$("$HDIUTIL" attach -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$dmg_path" 2>&1)"; then
    rmdir "$mount_point" 2>/dev/null || true
    verification_failed "Could not mount $dmg_path: $output"
    return 1
  fi

  if ! verify_signed_app_bundle "$mount_point/Obviewer.app"; then
    status=1
  fi
  if [ "$status" -eq 0 ] && [ "$(readlink "$mount_point/Applications" 2>/dev/null || true)" != "/Applications" ]; then
    verification_failed "The DMG is missing its Applications link."
    status=1
  fi
  if [ "$status" -eq 0 ] && is_adhoc_signing && [ ! -f "$mount_point/Read Me First - How to Install.md" ]; then
    verification_failed "The ad-hoc DMG is missing its install guide."
    status=1
  fi
  if [ "$status" -eq 0 ] && ! verify_volume_layout "$mount_point"; then
    status=1
  fi

  if ! output="$("$HDIUTIL" detach "$mount_point" -force 2>&1)"; then
    echo "Warning: could not detach $mount_point: $output" >&2
  fi
  rmdir "$mount_point" 2>/dev/null || true

  if [ "$status" -ne 0 ]; then
    verification_failed "The app inside $dmg_path failed verification."
    return 1
  fi
  echo "Verified mounted DMG: $dmg_path"
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
