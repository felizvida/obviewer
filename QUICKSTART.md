# Quick Start

This is the fastest way to try Obviewer on your Mac.

## One-Command Start

```bash
git clone https://github.com/felizvida/obviewer.git
cd obviewer
make try-local
```

What that does:

- Checks that full Xcode is selected instead of Command Line Tools
- Installs `xcodegen` with Homebrew if it is missing
- Generates `Obviewer.xcodeproj`
- Opens the project in Xcode

## In Xcode

1. Select the `Obviewer` scheme.
2. If Xcode asks about signing, choose your Personal Team under Signing & Capabilities.
3. Press Run.
4. In the app, choose `Open Vault...`.
5. Select your local Obsidian vault folder.

## What You Need

- A Mac
- Full Xcode installed
- Homebrew

If Homebrew is not installed, install it first and then rerun:

```bash
make try-local
```

## If It Stops Early

If `make try-local` tells you that Command Line Tools are selected, run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then rerun:

```bash
make try-local
```

## Manual Fallback

If you want to do the steps yourself:

```bash
brew install xcodegen
make xcodeproj
open Obviewer.xcodeproj
```

Then follow the Xcode steps above.
