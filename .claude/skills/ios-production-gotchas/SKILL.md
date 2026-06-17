---
name: ios-production-gotchas
description: Use when building or debugging iOS/iPadOS SwiftUI features — the cross-cutting production lessons from three shipped App Store apps that no single framework skill covers. Carries the presentation races (fullScreenCover(item:) not isPresented), the matchedTransitionSource-outermost rule, the dark-mode AccentColor legibility trap, fill-mode image layout blowups, background-audio detach/reattach, size-class (never UIDevice) adaptivity, SwiftUI Equatable/render mismatches, and the simulator verification recipes. Triggers on fullScreenCover, sheet race, black screen modal, zoom transition, accent color dark mode, unreadable button, background audio, PiP, AVAudioSession, iPad layout, size class, "works on simulator", Equatable view, navigation transition.
---

# iOS Production Gotchas

The cross-cutting lessons from shipping three iOS apps to the App
Store. The vendored framework skills (swiftui-*, avkit, etc.) carry
API depth; this skill carries the **bugs that cost multi-iteration
debugging sessions** and their one-line fixes — check here FIRST when
a symptom matches.

## Presentation + navigation

- **`fullScreenCover(item:)` / `sheet(item:)` — never
  `isPresented:` + the payload in separate `@State`.** The two-state
  version races: the cover renders before the payload lands → an
  empty/black modal, intermittently. (A real bug chased through
  files, encodings, and URLs before the race was found; `item:` is
  atomic.)
- **`.matchedTransitionSource` must be the OUTERMOST modifier** on
  the source view, and `.navigationTransition(.zoom(...))` used
  exactly as documented. 10+ iterations of layout artifacts
  ("forehead bug") came from modifier-order drift.
- One destination registry (a single shared `navigationDestination`
  modifier all stacks apply), router-owned `NavigationPath` per tab,
  external entry points through an intent inbox — see CLAUDE.md;
  per-view destinations are how "this screen can't push that screen"
  bugs are born.
- Settings is a sheet behind a toolbar gear, not a tab — tab bars
  are for content verbs.

## The dark-mode legibility trap

A single `AccentColor` tuned for light mode (e.g. a deep blue) makes
**bordered buttons, links, and Sign-in buttons unreadable under
forced dark appearance** — and you won't see it because you test in
one appearance. Fixes:

- Give `AccentColor` a **dark-appearance variant** in the asset
  catalog (lighter/brighter twin of the brand accent).
- Use Apple's own button styles for sign-in (white Sign in with
  Apple button on dark) — a custom-styled SiwA button that's
  unreadable means users never sign in, and you'll chase "sync
  doesn't work" instead of the real bug (this happened).
- Audit every `.bordered`/`.borderedProminent` surface in BOTH
  appearances before shipping.

## Layout traps

- **Never put a fill-mode image (`.scaledToFill`) inside
  `frame(maxWidth: .infinity)`** — the frame ADOPTS the image's
  oversized cover dimensions and blows the layout off both screen
  edges, intermittently (depends which artwork variant loads).
  Ambient/hero art goes in `.background` + `.clipped()`, which
  cannot influence layout.
- **Detail heroes FIT, never fill** — an explicit-height
  aspect-fit poster (rounded + shadow) over a blurred ambient
  backdrop beats a fill-crop that beheads the artwork. Request
  larger image variants for the hero only (grid-size elsewhere).
- **Adaptivity via `@Environment(\.horizontalSizeClass)`, never
  `UIDevice` checks**; one `TabView(.sidebarAdaptable)` hierarchy
  serves iPhone + iPad — no parallel `NavigationSplitView` code
  path.

## State + rendering

- **A custom `Equatable` on view-model types must include EVERY
  property that affects rendering.** Excluding "noisy" fields
  (e.g. a node's position) means SwiftUI skips re-renders when only
  that field changes — the state updates, the screen doesn't, and it
  looks like an animation bug. (16 iterations on a graph view before
  instrumentation exposed the state/render mismatch.)
- When repeated fixes don't change a symptom, **instrument before
  iterating** — print the state you believe vs the state that
  renders. The divergence point is the bug (CLAUDE.md debugging
  philosophy; it has paid off every time).
- Auth: Keychain for credentials; silent re-auth on launch and on
  `scenePhase == .active` (the visibilitychange analog) before the
  first authenticated call — not on a timer.

## Media + background

- `AVAudioSession` category `.playback` set before play — without
  it, audio dies on silent-switch/lock and PiP behaves oddly.
- **Background audio**: `audio` in `UIBackgroundModes`, then the
  supported AVKit technique — make the player-VC coordinator an
  `AVPlayerViewControllerDelegate`, **detach `vc.player` on
  `didEnterBackground`** (audio keeps running on the session) and
  **reattach on `willEnterForeground`**. Make it **PiP-aware**: skip
  the detach while PiP owns the video (track PiP via delegate
  callbacks); the PiP restore handler completes `true` when the
  full-screen player stays in the hierarchy.
- PiP: `allowsPictureInPicturePlayback = true`; auto-PiP from inline
  needs `canStartPictureInPictureAutomaticallyFromInline`.
- Create a fresh `AVPlayer` at the resume timecode per presentation
  — don't pass live players between views.
- Streaming from flaky hosts: `resilient-media-streaming`.

## Verification recipes

- Sim screenshots: `xcrun simctl io booted screenshot shot.png`;
  drive the app to a known screen with launch-env hooks
  (`SIMCTL_CHILD_APP_START_ITEM=… xcrun simctl launch …` — Decision
  018); cold start needs ~20–25 s before the shot.
- Boot ONE simulator at a time (parallel boots wedge in "Waiting on
  System App").
- The simulator lies about: filesystem permissions (tvOS), real
  network conditions, background-mode behavior, and CloudKit
  environment — those four classes need a device check before
  "done."
- After touching any shared `Core/` file in the universal target,
  build BOTH destinations (`-destination 'platform=iOS Simulator…'`
  and `platform=tvOS Simulator…`).
- SourceKit phantom "Cannot find X in scope" across files = stale
  index; trust `xcodebuild`. `@Query` macro views can cascade these.
