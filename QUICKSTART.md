# Quick Start

**To use Obviewer,** install the release build: see [`docs/INSTALL.md`](./docs/INSTALL.md). This page is for running it from source.

## Fastest path

You need a Mac with macOS 14 or later, full Xcode 15 or later, and Homebrew.

```bash
git clone https://github.com/felizvida/obviewer.git
cd obviewer
make try-local
```

`make try-local` checks that full Xcode (not just the Command Line Tools) is selected, installs XcodeGen if it's missing, generates `Obviewer.xcodeproj` and opens it. Then:

1. Select the **Obviewer** scheme.
2. If Xcode asks for signing, choose your Personal Team, or "Sign to Run Locally", under Signing & Capabilities.
3. Run (⌘R).
4. In the app, choose **Open File or Folder** and pick a `.md` file, a Markdown folder, an Obsidian vault, a DokuWiki folder, or the test notes in `Fixtures/notes/`.

You don't need Node to run the app: the reader bundle is committed under `Sources/ObviewerReaderKit/Resources/Reader/`.

## Sample data

- `Fixtures/notes/` holds small notes that exercise the renderer: Obsidian syntax, a GitHub README, tricky emphasis, hostile HTML, and a DokuWiki tree.
- `make demo-vault` generates `build/SampleVault`, a synthetic Obsidian vault with nested folders, images, callouts, tags and many cross-links.

## Single files

Opening one `.md` file shows that note and refreshes it when the file changes. Images or notes stored next to it need read-only access to the folder: use the banner's **Allow Access…** button, or open the folder itself.

## Launch options (development)

```bash
swift run Obviewer --markdown /absolute/path/to/Note.md
swift run Obviewer --obsidian /absolute/path/to/Vault
swift run Obviewer --dokuwiki /absolute/path/to/dokuwiki
```

These override the detected flavor. A sandboxed, signed app only gets access to paths the user chose, so for a built `.app` prefer the Open command, Finder, or `open -a Obviewer <path>`.

## If something goes wrong

- **"Command Line Tools are selected":** run the `xcode-select` command the script prints, then rerun `make try-local`.
- **After pulling changes:** rerun `make xcodeproj`. The project is generated, so new files appear only after regenerating.
- **Blank reader:** choose Help › Copy Reader Diagnostics and include the text in an issue.
