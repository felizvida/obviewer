# Quick Start

This is the fastest way to try Obviewer on a Mac with full Xcode installed.

## Fastest Path

```bash
git clone https://github.com/felizvida/obviewer.git
cd obviewer
make try-local
```

That command:

- verifies that full Xcode is selected instead of Command Line Tools
- installs `xcodegen` with Homebrew if needed
- generates `Obviewer.xcodeproj`
- opens the project in Xcode

## Optional Demo Vault

If you want a realistic vault without using your own notes, open a second terminal and run:

```bash
make demo-vault
```

That creates `build/SampleVault`, a synthetic Obsidian-style vault with:

- nested folders
- duplicate note names
- images and documents
- tables, callouts, tags, and anchors
- graph-friendly cross-links

## In Xcode

1. Select the `Obviewer` scheme.
2. If Xcode asks for signing, choose your Personal Team under Signing & Capabilities.
3. Press Run.
4. In the app, choose `Open Vault...`.
5. Pick your real Obsidian vault or `build/SampleVault`.

## What To Expect

The current app gives you:

- a searchable note library
- a reader-first detail pane
- inline links, images, tables, and callouts
- a note graph workspace
- a read-only vault loading flow built around user-selected folder access

The current GitHub releases still publish source archives rather than a ready-made signed `.app`, so local Xcode run is the easiest way to try the app today.

## Requirements

- a Mac
- full Xcode
- Homebrew

## If `make try-local` Stops Early

If the script says Command Line Tools are selected, run the `xcode-select` command it prints and then retry:

```bash
make try-local
```

If the script says no full Xcode app could be found, install Xcode from the App Store, open it once, and rerun the same command.

## Manual Path

If you want to do the steps yourself:

```bash
brew install xcodegen
make xcodeproj
open Obviewer.xcodeproj
```

Then follow the Xcode steps above.

If you pull new changes later, rerun `make xcodeproj` before reopening Xcode so the generated project picks up any added or moved source files.
