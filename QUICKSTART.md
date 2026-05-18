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
4. In the app, choose `Open`.
5. Pick a single `.md` file, a Markdown folder, your real Obsidian vault, or `build/SampleVault`.

Single-file mode is document-only: it reads the selected `.md` file but does not watch or index sibling images, PDFs, or other assets. If relative local assets matter, open the containing folder with the Markdown profile.

## Launch Profiles

Obviewer can start directly in a specific reading profile:

```bash
swift run Obviewer --markdown /absolute/path/to/Note.md
swift run Obviewer --obsidian /absolute/path/to/ObsidianVault
```

Use `--markdown` for a single Markdown file or a plain Markdown folder. Use `--obsidian` for a vault when you want Obsidian-style links, embeds, tags, and graph behavior. For relative local assets, prefer `--markdown /path/to/folder` over opening only one file.

If you are launching a built `.app`, the in-app `Open` button or Finder `Open With` is the most reliable path because macOS grants the read-only sandbox permission. Absolute-path switches are still useful for local development and profile testing, but a fully sandboxed signed app may require user-selected access:

```bash
open /Applications/Obviewer.app --args --markdown /absolute/path/to/Note.md
open /Applications/Obviewer.app --args --obsidian /absolute/path/to/ObsidianVault
```

## What To Expect

The current app gives you:

- a searchable note library
- a reader-first detail pane
- inline links, images, tables, and callouts
- a note graph workspace
- a read-only loading flow built around user-selected file/folder access and explicit reading profiles

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
