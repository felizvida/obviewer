#!/usr/bin/env bash
set -euo pipefail

if [ ! -d "Obviewer.xcodeproj" ]; then
  "$(dirname "$0")/generate_xcode_project.sh"
fi

if [ -z "${OBVIEWER_CODE_SIGN_IDENTITY:-}" ]; then
  echo "OBVIEWER_CODE_SIGN_IDENTITY is required for a release-safe app build." >&2
  echo "Use a Developer ID identity, or \"-\" for an ad-hoc signed build (no Apple account needed)." >&2
  echo "Refusing to package an unsigned app because App Sandbox entitlements must be embedded in the signature." >&2
  exit 1
fi

xcodebuild_args=(
  -project Obviewer.xcodeproj
  -scheme Obviewer
  -configuration Release
  -derivedDataPath build
  CODE_SIGN_STYLE=Manual
  ENABLE_HARDENED_RUNTIME=YES
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  "CODE_SIGN_IDENTITY=${OBVIEWER_CODE_SIGN_IDENTITY}"
  build
)

if [ "${OBVIEWER_CODE_SIGN_IDENTITY}" = "-" ]; then
  # Ad-hoc: the signature still embeds the sandbox entitlements, so macOS keeps
  # enforcing read-only access. No team, no timestamp server.
  xcodebuild_args+=("DEVELOPMENT_TEAM=" "OTHER_CODE_SIGN_FLAGS=--timestamp=none")
elif [ -n "${OBVIEWER_DEVELOPMENT_TEAM:-}" ]; then
  xcodebuild_args+=("DEVELOPMENT_TEAM=${OBVIEWER_DEVELOPMENT_TEAM}")
fi

if [ -n "${OBVIEWER_RELEASE_VERSION:-}" ]; then
  # CFBundleShortVersionString must be numeric (x.y.z); drop a pre-release suffix like "-beta.1".
  marketing_version="${OBVIEWER_RELEASE_VERSION#v}"
  xcodebuild_args+=("MARKETING_VERSION=${marketing_version%%-*}")
fi

if [ -n "${OBVIEWER_BUILD_NUMBER:-}" ]; then
  xcodebuild_args+=("CURRENT_PROJECT_VERSION=${OBVIEWER_BUILD_NUMBER}")
elif [ -n "${GITHUB_RUN_NUMBER:-}" ]; then
  xcodebuild_args+=("CURRENT_PROJECT_VERSION=${GITHUB_RUN_NUMBER}")
fi

xcodebuild "${xcodebuild_args[@]}"
