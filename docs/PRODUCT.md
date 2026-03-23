# Product Brief

This document captures the product intent so future contributors do not need to reverse-engineer it from code alone.

## One-Sentence Product Definition

Obviewer is a native macOS reading app for local Obsidian vaults whose defining promise is trustworthy, beautiful, read-only access to personal notes.

## Primary User Promise

The user should feel confident about two things:

1. the app will not modify the vault
2. reading in the app feels better than reading raw markdown in generic tools

If a future change improves one dimension while damaging the other, protecting trust should win.

## Non-Negotiable Requirement

The only truly critical requirement is:

**The product must be read-only from the user's perspective and from the operating system's enforcement model.**

This is not optional and not just a UI preference.

## Product Priorities

In order:

1. trustworthy read-only behavior
2. excellent reading experience
3. native macOS quality
4. strong Obsidian compatibility for common note shapes
5. good performance on real local vaults

## What The Product Is Not Trying To Do

To stay coherent, the product should not drift into:

- editing notes
- sync or collaboration
- task management
- plugin ecosystem emulation
- broad file-management behavior
- feature sprawl that weakens trust or design quality

## Current Product Pillars

### Reader-First Experience

The reader is the center of gravity. The note body should always feel more important than the surrounding chrome.

### Trustworthy Local Access

The app should feel safe to point at a personal vault because it is local-only and read-only by design.

### Obsidian-Aware Navigation

Wiki links, tags, tables, callouts, attachments, and graph relationships matter because real Obsidian vaults rely on them.

### Calm Native Design

The app should feel editorial, warm, and intentionally macOS-native rather than generic utility software.

## User Experience Direction

The current direction is intentional:

- warm paper-like backgrounds instead of flat white
- serif-forward reading surfaces
- rounded native chrome
- spacious composition
- metadata that stays secondary to the body

The emotional tone should be:

- calm
- premium
- trustworthy
- focused
- editorial rather than dashboard-like

## Functional Scope

### In Scope

- selecting a local vault directory
- reopening the last vault safely
- browsing notes and folders
- searching by title, path, tags, and preview text
- reading markdown notes with common Obsidian constructs
- navigating linked notes and graph relationships
- viewing common attachments and images where appropriate

### Out Of Scope For The Product Identity

- editing files
- batch refactoring notes
- reorganizing folders
- remote sync
- collaboration features

Those could be built technically, but they would pull the product away from its core idea.

## Reading Experience Standards

Future contributors should judge changes against these standards.

### Typography

- text should feel good during long reading sessions
- hierarchy should be legible without noise
- serif body typography remains a strong default unless a better editorial direction clearly wins

### Layout

- the content column should stay primary
- sidebars should orient, not dominate
- wide screens should still preserve a readable measure

### Interaction

- interactions should feel native to macOS
- motion should be quiet and purposeful
- the experience should stay interruption-light

### Visual Restraint

- avoid disposable visual gimmicks
- avoid generic productivity-app blandness
- aim for a look that feels authored rather than auto-generated

## Product Risks

### Risk 1: weakening the read-only trust story

Even a small write capability undermines the product's defining promise.

### Risk 2: outrunning parser fidelity

If the notes render incorrectly, chrome polish will not save the experience.

### Risk 3: letting navigation become management

The product should remain a reading app first, even when graph and search become richer.

### Risk 4: accepting average UI

The original goal called for a first-class, fashionable reading experience. Merely functional UI is not enough.

## Success Criteria

The product is moving in the right direction if a new user can:

1. open a local vault quickly
2. trust that nothing will be modified
3. read notes more comfortably than in Finder, Quick Look, or a generic text editor
4. follow common Obsidian structures without friction
5. understand note relationships through search, links, and graph views

## Decisions That Deserve Extra Scrutiny

These choices should not be made casually:

- any broader file permissions
- any feature that enables note mutation
- any change that weakens the native macOS feel
- any change that makes the app feel like a utility shell instead of a premium reader
- any parser shortcut that would make real vaults look untrustworthy

## Near-Term Product Roadmap

The next product milestones should be:

1. ship the production distribution path without weakening the sandbox model
2. improve markdown and Obsidian fidelity
3. improve performance and live refresh on real vaults
4. deepen graph, media, accessibility, and polish

The detailed plan lives in [`MODERNIZATION_PLAN.md`](./MODERNIZATION_PLAN.md).
