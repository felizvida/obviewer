# Visual Tour

This page is the fastest way to understand how Obviewer feels before you run it yourself.

The screenshots below are generated from the real SwiftUI app against the synthetic showcase vault produced by the repo tooling. They are not hand-made mockups.

## What You Are Looking At

Obviewer is trying to combine four ideas in one product:

- a trustworthy read-only vault browser
- a calmer, more editorial reading experience than raw markdown files
- Obsidian-aware navigation for real local note structures
- a visual system that feels deliberate and macOS-native rather than generic

## Library Overview

![Library overview](./images/visual-tour-library-home.png)

The main window combines a folder-grouped library sidebar with a wide reading surface. The opening note shows the current design language clearly: warm backgrounds, rounded chrome, serif-led note typography, and metadata that stays secondary to the note body.

## Project Reading View

![Project overview note](./images/visual-tour-project-overview.png)

The project note shows the more ambitious reading path: callouts, tables, inline links, attachment links, image embeds, and the right-side contents rail. This is the core reading-room experience the project is aiming to mature.

## Tag-Focused Search

![Tag-focused search](./images/visual-tour-tag-search.png)

Search narrows the sidebar without collapsing the reading flow. In this example, a tag query focuses the library on `#alpha` notes while keeping the selected note open in the detail pane.

## What The Tour Does Not Fully Capture Yet

The current screenshots emphasize the most mature reader-first surfaces. The app also includes:

- a local/global graph workspace
- inline image sizing and lightbox behavior
- generated demo-vault content with duplicate names and attachment-heavy flows

Those areas should be part of future visual refreshes as the product modernizes.

## Why The Screenshots Use A Synthetic Vault

The demo vault is intentional. It gives the project a stable way to validate:

- large folder structures
- duplicate filenames such as `Daily.md` and `Index.md`
- folder-local versus shared attachments
- tables, callouts, tags, anchors, and image embeds
- more realistic note counts than tiny unit-test fixtures

That makes the screenshots useful for both documentation and regression discussion.

## Regenerating The Visuals

If the UI changes, regenerate the screenshots with:

```bash
make docs-screenshots
```

If you also want to browse a persistent sample vault manually, generate one with:

```bash
make demo-vault
```
