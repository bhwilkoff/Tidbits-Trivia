---
name: universal-feature-states
description: Use when designing any list, grid, search, sheet, or feature with content that loads. Every such surface must define behavior for FOUR states beyond happy path — loading, empty, error, offline. Plus understand the distinction between EmptyState (structural), ErrorBanner (attention), HintBanner (first-run tip), and Walkthrough (multi-step tutorial). Triggers on empty state, loading state, error handling, offline support, ContentUnavailableView, "what happens if no data?"
---

# Universal Feature States

## The rule

Every list, grid, search, sheet, or feature with content that loads must define behavior for **four states beyond happy path**:

1. **Loading** — content is being fetched
2. **Empty** — no content exists
3. **Error** — fetch failed
4. **Offline** — network unavailable

And five teaching surfaces that occupy distinct roles in the UI:

- **EmptyState** — structural ("no content here yet")
- **ErrorBanner** — attention ("something went wrong")
- **OfflinePill** — status ("you're offline")
- **HintBanner** — first-run tip ("did you know?")
- **Walkthrough** — multi-step tutorial ("here's how this feature works")

If any one isn't defined, the feature WILL ship a hole.

## When to invoke

- Designing a new list, grid, feed, search, or data-loading surface
- Reviewing a "what happens when there's no data?" question
- Choosing between a hint banner and a walkthrough
- Adding teaching/onboarding to an existing surface
- Reviewing error handling on a write action

## The four data states

### Loading

`ProgressView` only for operations **>300ms**. Below that, the spinner appears and disappears so fast it reads as a flash, which is jankier than no spinner.

For initial list/grid loads, use **skeleton rows** matching the shape of real rows (3-5 placeholder cells). Skeleton means:

- Same outer dimensions as real rows
- Greyed-out / shimmering rectangles where text + images will be
- NOT a full-screen spinner — content loads IN PLACE, layout doesn't jump

The principle: loading should preserve the eventual layout, so when content arrives the user's eye doesn't have to re-locate.

### Empty

`ContentUnavailableView` (iOS) or `<div class="empty-state">` (web) with:

- **Brand-voice copy** — not "No items." but something that fits the tone (BOBA's would be *"No decks yet — start with a template."*)
- **A productive next-action** — empty state isn't an end; it's an invitation. Provide a button or call-to-action that lets the user get unstuck.

Example (iOS):

```swift
ContentUnavailableView {
    Label("No decks yet", systemImage: "rectangle.stack")
} description: {
    Text("Start with a template or build from scratch.")
} actions: {
    Button("Browse Templates") { ... }
}
```

The "actions" slot is where most empty states fail — they describe the absence without offering the user a path forward.

### Error

`ContentUnavailableView` with the SAME shape as empty, but with:

- **Clear error message** that distinguishes user-fixable (network, auth) from system errors
- **Retry button** for transient errors
- **For write actions** (not load actions), error surfaces above the action as a `BOBAErrorBanner` — orange-bordered inline banner that doesn't interrupt nav. The action stays available to retry.

The principle: a failed write should let the user retry without losing their input. A failed load should let them retry without losing their place.

### Offline

Degraded, not blocked. Cached data continues to work; cloud writes disable with inline tooltips.

UI surfaces:
- **OfflinePill** — subtle status indicator in the top-trailing nav (iOS) or mobile header (web)
- **Inline disabled buttons** — when an action requires cloud, disable it and surface "Sign in / connect to save" inline
- **Cached read paths must work** — search the catalog, browse owned items, etc. operate against local data

The principle: offline is a degraded mode of the same app, not a separate failure mode. Don't show "no internet" splash screens.

## The five teaching surfaces

These often get conflated. They serve distinct purposes:

### 1. EmptyState — "There's nothing here yet"

Structural. The view has no content to show. Always paired with a next-action. Cannot be dismissed (it's not a notification — it's the state of the view).

### 2. ErrorBanner — "Something went wrong"

Attention. The user's action failed and they need to know. Distinct from EmptyState because it interrupts a flow rather than describing a state. Always paired with retry. Usually inline near the action.

### 3. OfflinePill — "You're in degraded mode"

Status. Persistent while the condition is true (offline, syncing, paused). Subtle, not attention-grabbing. Top-trailing nav slot.

### 4. HintBanner — "Did you know X?"

First-run tip. One-shot per user per device. Dismissible permanently. Used for non-obvious behavior the design itself can't carry (a bonus play ceiling, a swipe-down gesture, a power user shortcut).

iOS pattern (BOBA's `HintsManager`):
- `@Observable` HintsManager backed by UserDefaults tracks dismissed IDs
- `HintBanner(id:title:message:)` renders nothing if dismissed OR global toggle off
- Tapping X dismisses permanently
- Settings has master toggle + "Reset hints" button

### 5. Walkthrough — "Here's how this feature works"

Multi-step tutorial. Anchored on real UI (not a slide deck). Fires on first visit to a major feature.

Rules:
- **≤5 steps, ≤12 words/step** — if you need more, refactor the feature
- **Anchor-based, not modal** — highlight real UI with a ring; copy floats in a glass tooltip
- **Skip + Done always visible** — tap outside to advance; tap anchor to complete the demonstrated action
- **Voice: second person, action-oriented** — *"Tap a card to add it to your deck."* not *"In this view, users can build decks by..."*
- **Re-launchable** — every walkthrough re-triggers from a "?" overflow Menu so returning users can re-learn

### Decision tree — which teaching surface

| Use case | Component |
|---|---|
| Screen has no content yet | **EmptyState** |
| User action failed | **ErrorBanner** |
| Network/sync status | **OfflinePill** |
| Non-obvious tip on known surface | **HintBanner** |
| First-time feature discovery | **Walkthrough** |

**Anti-pattern**: using a Walkthrough to explain self-explanatory UI. If your UI needs a walkthrough to be understood, the UI is the problem — fix the UI, not the walkthrough.

## Implementation pattern

For every new feature, your state-definitions checklist:

- [ ] **Loading**: skeleton or spinner with 300ms threshold
- [ ] **Empty**: `ContentUnavailableView` / `.empty-state` with brand-voice copy + next-action
- [ ] **Error (read)**: `ContentUnavailableView` w/ retry
- [ ] **Error (write)**: inline ErrorBanner above the action w/ retry
- [ ] **Offline**: cached read paths work; writes disable with inline tooltip
- [ ] **Hint (if applicable)**: dismissible HintBanner for one tip
- [ ] **Walkthrough (if new pattern)**: anchored ≤5 steps, fires once

Don't ship without each box checked. The cost of missing one is a user hitting a hole and either being confused or losing data.

## Anti-patterns

### ❌ Per-tab empty/error styling

Every tab inventing its own empty state shape. Use canonical `BOBAEmptyState`, `BOBAErrorBanner` components everywhere. Inconsistency is the #1 source of "feels janky" feedback.

### ❌ "No items" as the empty copy

Generic, doesn't invite action. Always write brand-voice empty copy.

### ❌ Full-screen spinner on every load

Layout jumps when content arrives. Use in-place skeletons.

### ❌ Modal slide-deck onboarding

Explicitly rejected pattern. Walkthroughs are anchored on real UI, not stylized slides. Users learn by seeing the real product, not an abstracted preview.

### ❌ Hidden offline behavior

If the user can hit a button that silently fails because they're offline, that's a broken UX. Either disable the button OR queue the write for later sync with a visible status pill.

### ❌ Cascading hints / walkthroughs

Multiple teaching surfaces on the same first visit. Each fires on its own first use; never bundle. The user is overwhelmed by the second tip.

## Real-world examples

- BOBA Playbook DESIGN.md §6.7 (Universal states) — `BOBAEmptyState`, `BOBAErrorBanner`, `BOBAOfflinePill`, `BOBAHintBanner`, `BOBAWalkthrough` are canonical primitives
- Apple HIG — `ContentUnavailableView` patterns
- Material 3 (`m3.material.io`) — error / empty / loading state guidance

## See also

- [[mobile-first-density-design]] — empty/error states must obey density rules too
- [[binding-design-doc-discipline]] — projects typically have a §6.7-style "Universal states" rule that this skill operationalizes
- [[native-platform-first]] — `ContentUnavailableView` is a native iOS primitive; `<dialog>` is native web
