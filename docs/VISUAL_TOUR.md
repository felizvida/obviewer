# Visual Tour

This page is the fastest way to understand what Obviewer is trying to feel like before you run the app yourself.

The screenshots on this page are generated from the current SwiftUI app against the synthetic showcase vault created by the repository tooling. They are not hand-made mockups.

## What You Are Looking At

Obviewer is trying to combine three ideas in one surface:

- A trustworthy read-only vault browser
- A calmer, more editorial reading experience than raw markdown files
- Obsidian-aware navigation for real local note structures

## Library Overview

![Library overview](./images/visual-tour-library-home.png)

The main window combines a folder-grouped library sidebar with a wide reading surface. The home note shows the current design language clearly: warm backgrounds, rounded chrome, serif-led note typography, and metadata that stays secondary to the note body.

## Project Reading View

![Project overview note](./images/visual-tour-project-overview.png)

A project note demonstrates the richer Obsidian-aware rendering path: callouts, tables, inline links, attachment links, image embeds, and the right-side contents rail for long-form reading. This is the core “reading room” experience the product is aiming for.

## Tag-Focused Search

![Tag-focused search](./images/visual-tour-tag-search.png)

Search narrows the sidebar without collapsing the reading flow. In this example, a tag query focuses the library on `#alpha` notes while keeping the selected note open in the detail pane.

## Why The Screenshots Use A Synthetic Vault

The demo vault is intentional. It gives the project a stable way to validate:

- Large folder structures
- Duplicate filenames like `Daily.md` and `Index.md`
- Folder-local versus shared attachments
- Tables, callouts, tags, anchors, and image embeds
- A more realistic note count than tiny unit-test fixtures

That makes the screenshots useful for both documentation and regression checking.

## Regenerating The Visuals

If the UI changes, regenerate the screenshots with:

```bash
make docs-screenshots
```

If you also want to browse a persistent sample vault manually, generate one with:

```bash
make demo-vault
```
