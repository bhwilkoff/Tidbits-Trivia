---
name: multiplatform-expansion-method
description: Use when planning to add a platform to an existing app (iOS app going to web/Android/tvOS, etc.), sequencing a multi-platform buildout, or scoping how much of an existing codebase a new platform can reuse. Carries the find-the-seam analysis (data plane vs platform layer), platform sequencing by reuse leverage, the hard-ports checklist, per-platform stack table, and when to author design docs and contracts. Triggers on "port to Android", "add a web version", "Apple TV version", multiplatform plan, platform expansion, "how much can we reuse", buildout sequencing.
---

# Multiplatform Expansion Method

How to take an app from one platform to several without rewriting it
several times — distilled from expanding a shipped tvOS app to
iOS/iPadOS, web PWA, and Android inside one month, with all four
reaching their stores.

## Step 1 — Find the seam

Every app separates into two layers. The expansion only rebuilds the
second:

**A. The shared plane** (build once, reuse as-is):
- Published content/data + the pipeline that produces it (see
  `shared-data-plane-contract`)
- Editorial/config JSON
- Deterministic domain logic: schedulers, queue engines, selection
  pools, scoring — anything seeded/pure
- Policy flags baked into the data (visibility, maturity, rights)

**B. The platform layer** (rebuilt natively per platform):
- UI, navigation shell, every view
- The query layer binding (same verbs, native data stack)
- Player/media integration
- Local persistence + platform reach (widgets, voice, deep links)

The contract between them — schemas, asset URLs, query verbs — gets
written down (`docs/DATA-CONTRACT.md`) the moment client #2 exists.
Lock the contract; implement against it independently per platform.

**Reality check from production**: ~60–70% of a media app's Swift was
platform-agnostic. If your analysis says 20%, you probably have UI
logic tangled into the domain layer — untangle first (protocols at
the boundary), then port.

## Step 2 — Sequence by reuse leverage

Order platforms so each phase is the cheapest remaining one and
funds lessons for the next:

| Order | Platform | Why this slot |
|---|---|---|
| 1 | The nearest sibling (tvOS↔iOS via one universal target) | Highest reuse (~60–70%), same toolchain, and ecosystem freebies (one CloudKit DB = household sync free) |
| 2 | The small delta (iPad on the iOS work) | Size-class adaptivity, not a new app |
| 3 | Web (PWA) | Widest reach, zero install, NO review gate — ships continuously; becomes the canonical share-URL target for every native platform |
| 4 | Android | Most new code (full Kotlin rebuild); benefits from every prior phase's design decisions |

Each phase runs: bootstrap → core verbs (browse/view/play) →
personalization → modes/extras → platform reach (widgets, voice,
links). Create the platform's binding design doc once it passes ~5
views.

## Step 3 — Pick the stack per platform (don't re-litigate)

- **Apple**: ONE universal Xcode target (iOS + iPadOS + tvOS),
  `Core/` + per-platform view groups behind `#if os` guards. Swift 6,
  SwiftUI, SwiftData, no third-party packages.
- **Web**: vanilla HTML/CSS/JS, no build step, GitHub Pages,
  URL-driven state, installable PWA. The web app is not a port — URL
  shareability is its superpower.
- **Android**: Kotlin + Compose + M3 Expressive, single-module
  bootstrap, Media3 for playback, Room/SQLite for data, manual or
  Hilt DI.
- **Explicitly rejected** (and why, so it stays rejected): KMP/CMP
  (can't retrofit without rewriting the shipped iOS app; can't render
  Liquid Glass), Flutter/RN (bridge tax on every native API), a
  "responsive web wrapper" per platform (violates feature parity,
  not design consistency).

## Step 4 — Plan the hard ports explicitly

List the features that are NOT a view rewrite and decide each one's
strategy before the wave starts:

- **Deterministic engines** (schedulers, queues): port the LOGIC
  with identical constants/seeds — same hash function, same anchor
  times — then verify cross-platform agreement on a fixed seed.
  Rebuild only the layout natively.
- **Media playback**: each platform binds its native player
  (AVKit / Media3 / `<video>`); resilience strategy per
  `resilient-media-streaming`. Lock-screen/MediaSession integration
  is part of the port, not polish.
- **Sync**: per `per-ecosystem-sync-islands` — decided per ecosystem,
  never a shared custom backend.
- **Lean-back modes** (ambient, screensaver, party): these are
  device-posture idioms, not features to force everywhere — TV
  first, tablet/desktop second, phones rarely. Record the asymmetry
  in PARITY.md.
- **Shaders/visual effects**: per-platform implementations (Metal /
  AGSL / WebGL-CSS) — schedule last, optional.

## Step 5 — Keep the matrix true while you go

`cross-platform-parity-discipline` governs the wave: PARITY.md
updated per change set, deliberate defers carry reasons, and a full
parity audit closes each phase.

## Anti-patterns

- **Making the first platform the canonical UI to reskin.** The
  verbs are canonical; no layout is.
- **Re-implementing the data pipeline per client** "because it's
  just a little filtering." That's parity drift at the data layer —
  see `shared-data-plane-contract`.
- **Porting before untangling.** If domain logic imports UI, the
  port forks it. Protocol-decouple first (a `PlaybackSource`
  protocol in Core, conformed by each app store) — it's a day of
  work that saves a fork per platform.
- **Deferring store plumbing.** Deep-link verification files,
  signing, store listings have multi-day external latencies
  (domain DNS, Play review of the developer account) — start them
  at phase start, not phase end. See `store-submission-playbook`.
