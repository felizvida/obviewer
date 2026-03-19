#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

AUTO_INSTALL_TOOLS=0
SKIP_OPEN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-tools)
      AUTO_INSTALL_TOOLS=1
      shift
      ;;
    --skip-open)
      SKIP_OPEN=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--install-tools] [--skip-open]" >&2
      exit 1
      ;;
  esac
done

print_next_steps() {
  cat <<'EOF'

Next steps in Xcode:
1. Select the `Obviewer` scheme.
2. If Xcode asks about signing, pick your Personal Team under Signing & Capabilities.
3. Press Run.
4. In the app, choose `Open Vault...` and point it at your local Obsidian vault.
EOF
}

ensure_full_xcode() {
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"

  if [[ -z "$developer_dir" ]]; then
    echo "Xcode developer tools are not configured." >&2
    echo "Install full Xcode, then run:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
  fi

  if [[ "$developer_dir" == "/Library/Developer/CommandLineTools" ]]; then
    if [[ -d /Applications/Xcode.app ]]; then
      echo "Full Xcode is installed but Command Line Tools are currently selected." >&2
      echo "Run this once, then rerun \`make try-local\`:" >&2
      echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    else
      echo "Full Xcode is required to run the app locally." >&2
      echo "Install Xcode from the App Store, then run:" >&2
      echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    fi
    exit 1
  fi
}

ensure_xcodegen() {
  if command -v xcodegen >/dev/null 2>&1; then
    return
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "xcodegen is required but Homebrew is not installed." >&2
    echo "Install Homebrew, then run:" >&2
    echo "  brew install xcodegen" >&2
    exit 1
  fi

  if [[ "$AUTO_INSTALL_TOOLS" -eq 1 ]]; then
    echo "Installing xcodegen with Homebrew..."
    brew install xcodegen
    return
  fi

  echo "xcodegen is required to generate the local app project." >&2
  echo "Run one of these:" >&2
  echo "  brew install xcodegen" >&2
  echo "  ./scripts/try_local.sh --install-tools" >&2
  exit 1
}

ensure_full_xcode
ensure_xcodegen

./scripts/generate_xcode_project.sh

if [[ "$SKIP_OPEN" -eq 1 ]]; then
  echo "Generated Obviewer.xcodeproj"
  print_next_steps
  exit 0
fi

if command -v xed >/dev/null 2>&1; then
  xed Obviewer.xcodeproj
else
  open Obviewer.xcodeproj
fi

print_next_steps
