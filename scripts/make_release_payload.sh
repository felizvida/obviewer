#!/usr/bin/env bash
# Builds the exact files for a GitHub release, locally, and checks them. It never
# uploads anything: it ends by printing the upload command for the maintainer to run
# after the maintainer's own pre-publication guard has passed the same files.
#
# Usage: scripts/make_release_payload.sh <tag> <build-number>
#   e.g. scripts/make_release_payload.sh v0.3.0-beta.2 8
#
# Run it in a clean checkout whose HEAD is the commit the tag points at (or will point
# at). Output: dist/<tag>/ holding the ad-hoc DMG, its SHA-256 file, the install guide
# copy, and the source archives with their SHA-256 file; the same set the release
# workflow used to upload.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TAG="${1:-}"
BUILD_NUMBER="${2:-}"
if [ -z "$TAG" ] || [ -z "$BUILD_NUMBER" ]; then
  echo "Usage: $0 <tag> <build-number>" >&2
  exit 2
fi
# Strict, anchored: v<major>.<minor>.<patch> with an optional dot-separated label of
# letters and digits. No slashes, dots-only segments or other characters, because the
# tag becomes part of output paths.
TAG_PATTERN='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$'
if ! [[ "$TAG" =~ $TAG_PATTERN ]]; then
  echo "Tag must look like v<x.y.z> or v<x.y.z>-<label> (letters, digits, dots): $TAG" >&2
  exit 2
fi
if ! [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo "Build number must be a positive integer without leading zeros: $BUILD_NUMBER" >&2
  exit 2
fi

# Same gates as the release workflow, before anything is built.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Tracked files have uncommitted changes; build releases from a clean checkout." >&2
  exit 1
fi
BASE_VERSION="${TAG#v}"
BASE_VERSION="${BASE_VERSION%%-*}"
PROJECT_VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -n 1 | tr -d '"')"
if [ "$BASE_VERSION" != "$PROJECT_VERSION" ]; then
  echo "Tag $TAG (version $BASE_VERSION) does not match MARKETING_VERSION $PROJECT_VERSION in project.yml." >&2
  exit 1
fi
NOTES="docs/RELEASE_NOTES_${TAG}.md"
if [ ! -s "$NOTES" ]; then
  echo "Reviewed release notes are required at $NOTES." >&2
  exit 1
fi
CHANNEL="$(sed -n 's/^<!-- release-channel: *\([a-z]*\) *-->$/\1/p' "$NOTES" | head -n 1)"
case "$CHANNEL" in
  prerelease) PRERELEASE_FLAG="--prerelease" ;;
  stable) PRERELEASE_FLAG="" ;;
  *) echo "$NOTES must declare <!-- release-channel: prerelease --> or <!-- release-channel: stable -->." >&2; exit 1 ;;
esac
case "$TAG" in
  *-*) [ "$CHANNEL" = "prerelease" ] || { echo "Tag $TAG looks like a pre-release, but the notes declare a stable release." >&2; exit 1; } ;;
esac
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]; then
    echo "Tag $TAG exists but does not point at HEAD." >&2
    exit 1
  fi
fi

node scripts/publication-check.mjs --tracked
node scripts/publication-check.mjs "$NOTES"

OUT="dist/$TAG"
if [ -e "$OUT" ] || [ -L "$OUT" ]; then
  echo "$OUT already exists; move it aside first (this script never overwrites a payload)." >&2
  exit 1
fi
if [ -L dist ] || { [ -e dist ] && [ ! -d dist ]; }; then
  echo "dist must be a real directory, not a link or a file." >&2
  exit 1
fi
mkdir -p dist
mkdir "$OUT"
COMMIT="$(git rev-parse HEAD)"

git archive --format=tar.gz --output="$OUT/obviewer-$TAG-source.tar.gz" "$COMMIT"
git archive --format=zip --output="$OUT/obviewer-$TAG-source.zip" "$COMMIT"
(cd "$OUT" && shasum -a 256 "obviewer-$TAG-source.tar.gz" "obviewer-$TAG-source.zip" > "obviewer-$TAG-sha256.txt")

./scripts/generate_xcode_project.sh
OBVIEWER_CODE_SIGN_IDENTITY="-" \
OBVIEWER_RELEASE_VERSION="$TAG" \
OBVIEWER_BUILD_NUMBER="$BUILD_NUMBER" \
  ./scripts/package_release_dmg.sh
cp "build/Obviewer-$TAG-macOS-adhoc.dmg" "$OUT/"
cp docs/INSTALL.md "$OUT/INSTALL-$TAG.md"
(cd "$OUT" && shasum -a 256 "Obviewer-$TAG-macOS-adhoc.dmg" > "obviewer-$TAG-dmg-sha256.txt")

# Every file that will be uploaded, with the DMG mounted read-only and scanned file by file.
node scripts/publication-check.mjs "$OUT" "$NOTES"

echo
echo "Release payload for $TAG (commit $COMMIT, build $BUILD_NUMBER) is in $OUT:"
(cd "$OUT" && ls -l && shasum -a 256 ./*)
echo
echo "Nothing has been uploaded. After the maintainer's pre-publication guard passes these"
echo "exact files, the notes, the tag and the history, push the commit and the tag, then run:"
echo
echo "  gh release create $TAG $OUT/* --notes-file $NOTES --title \"Obviewer $TAG\" --verify-tag ${PRERELEASE_FLAG}"
