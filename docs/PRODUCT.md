# Product Brief

This document explains what the product is supposed to be.

It exists so that future contributors do not have to reverse-engineer product intent from code alone.

## One-Sentence Product Definition

Obviewer is a native macOS reading app for local Obsidian vaults whose central promise is beautiful, trustworthy, read-only access to personal notes.

## Primary User Promise

The user should feel confident about two things:

1. The app will not modify the vault
2. Reading inside the app feels better than reading raw markdown files in a generic tool

If a future decision improves one of those dimensions while damaging the other, preserving trust should win.

## Non-Negotiable Requirement

The only truly critical requirement is:

**The product must be absolutely read-only from the user's perspective and from the operating system's enforcement model.**

This requirement is not optional, and it is not just a preference.

## Product Priorities

The product priorities, in order, are:

1. Trustworthy read-only behavior
2. Excellent reading experience
3. Native macOS quality
4. Useful Obsidian compatibility
5. Performance on real local vaults

## What The Product Is Not Trying To Do

To keep the project coherent, it should not drift toward:

- Editing notes
- Syncing files
- Becoming a task manager
- Becoming a second Obsidian implementation
- Replicating plugin ecosystems
- Maximizing feature breadth at the expense of clarity and design quality

## User Experience Direction

The current visual direction is intentional:

- Warm, paper-like backgrounds rather than flat sterile white
- Serif-forward reading surfaces
- Rounded macOS chrome
- Spacious composition
- Metadata that stays secondary to the note body

The ideal emotional tone is:

- Calm
- Premium
- Trustworthy
- Focused
- Editorial rather than dashboard-like

## Functional Scope

### In Scope

- Selecting a local vault directory
- Persisting access to that vault safely
- Browsing notes
- Searching notes by title, path, tag, and preview text
- Reading markdown notes
- Navigating through linked notes
- Displaying common attachments where appropriate

### Out Of Scope For The Product Identity

- Editing files
- Batch refactoring notes
- Reorganizing folders
- Sync conflict handling
- Remote collaboration features

These could technically be built, but they would pull the product away from its defining idea.

## Reading Experience Standards

A future maintainer should judge new features against these standards:

### Typography

- Text should feel comfortable for long reading sessions
- Hierarchy should be obvious without being noisy
- Serif body typography is a strong default unless a better editorial solution emerges

### Layout

- The interface should prioritize the content column
- Sidebars should help orientation without becoming visually heavy
- Wide screens should still preserve a readable measure

### Interaction

- Interactions should feel native to macOS
- Motion, if added, should feel intentional and quiet
- The reading experience should stay interruption-light

### Visual Restraint

- Avoid trendy but disposable visual gimmicks
- Avoid generic productivity-app blandness
- Aim for a look that feels designed rather than auto-generated

## Product Risks

The main product risks are:

### Risk 1: Weakening the read-only trust story

Even a small write capability undermines the product's defining promise.

### Risk 2: Over-building features before parser fidelity

If notes are rendered incorrectly, the reader experience will feel broken no matter how polished the chrome is.

### Risk 3: Letting the interface drift toward "note management"

The product should remain a reading app first.

### Risk 4: Accepting average UI

The original goal explicitly asked for a fashionable, first-class reading experience. A merely functional interface does not satisfy that goal.

## Success Criteria

The project is moving in the right direction if a new user can:

1. Open a local vault in seconds
2. Trust that nothing will be modified
3. Read notes more comfortably than in Finder, Quick Look, or a generic text editor
4. Navigate common Obsidian note structures without friction

## Product Decisions That Deserve Extra Scrutiny

These decisions should not be made casually:

- Any change that adds broader file permissions
- Any change that enables note mutation
- Any change that trades the native macOS feel for easier cross-platform reuse
- Any change that makes the app feel like a utility shell instead of a premium reader

## Near-Term Product Roadmap

Recommended next product milestones:

1. Establish the real sandboxed app shell
2. Improve markdown and Obsidian fidelity
3. Improve inline navigation and media support
4. Add polish around large-vault browsing and live updates

The app should become trustworthy before it becomes ambitious.
