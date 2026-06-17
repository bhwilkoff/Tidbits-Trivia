---
name: android-production-gotchas
description: Use when building or debugging the Android (Kotlin + Compose + M3) app — the cross-cutting production lessons from shipping a Compose app to Google Play that the framework docs don't carry. Covers data-layer invalidation keying (dbVersion on every produceState), BundledSQLiteDriver for guaranteed FTS5, the staged atomic DB swap ritual, the contradictory-WHERE silent-empty bug class, sealed-Route navigation with a deep-link inbox, icon parity mapping (SF Symbols → Material), Media3 queue flags, and emulator verification recipes. Triggers on Compose, Room, SQLite Android, FTS5, produceState, LaunchedEffect key, sealed route, BackHandler, deep link Android, emulator, assembleDebug, Media3 queue, "screen shows zero items", "empty grid", Play build.
---

# Android Production Gotchas

Cross-cutting lessons from shipping a Kotlin + Compose + Material 3
app to Google Play in parallel with iOS/tvOS/web siblings. The
Android skill stack (install via `tools/install-android-skills.sh`)
carries framework depth; this skill carries the **bugs and rituals
that cost real sessions** on a production parity build.

## Data layer

- **Key every screen's query on a data version.** Screens holding
  query results key their `produceState`/`LaunchedEffect` on a
  `dbVersion` counter (and a `userState.changes` counter where user
  records matter) that bumps on every data swap or filter change.
  Without it, the seed→full-database swap (or a settings toggle)
  silently doesn't propagate — screens show stale data until
  recreated.
- **BundledSQLiteDriver, not framework SQLite**, when you need FTS5
  or schema guarantees — the OS-provided SQLite version varies by
  device/API level; the bundled driver makes search work everywhere.
- **The staged atomic swap ritual** for downloaded databases:
  ETag-conditional GET → stream-inflate (`Inflater(nowrap = true)`
  for raw DEFLATE, 64 KB chunks) to a STAGING file → size floor →
  open-probe a known row → atomic rename → store ETag → bump
  `dbVersion`. Any failure keeps the cached DB; the bundled seed is
  the floor state.
- **Decode only the rows a screen shows** — query on disk; never
  materialize a large catalog into memory.
- One read path: a single `CatalogDatabase`/repository layer owns
  ALL data SQL and applies the universal filter clauses (visibility,
  maturity) in ONE place. Screens never touch SQLite, OkHttp, or
  asset files directly.

## The contradictory-WHERE bug class

A query builder that unconditionally excludes a type AND a filter
that requires that same type compose into `WHERE type != 'x' AND
type = 'x'` → **0 rows, no error**. On a real app this made an
entire category invisible on two platforms for weeks (the
count-gate then hid the dead tile, masking it further).

Defenses: when a filter explicitly requests an excluded-by-default
type, the request wins (an explicit branch); **verify category
counts with direct SQL** against the live DB whenever a surface
looks inexplicably empty; treat "shows zero items" as a query bug
until proven otherwise.

## Navigation + entry points

- v1: **manual DI (`AppContainer` in `Application`) + a sealed
  `Route` back stack + `BackHandler`** — Hilt/Navigation3 arrive
  when module count or route complexity demands them, not before.
- Every pushable destination is a case of the sealed `Route`,
  handled in one `AppRoot` — never per-screen ad-hoc overlays.
- **Deep links land in a pending-inbox** (`DeepLinks.pendingItem`),
  parsed in `MainActivity` (`onCreate` + `onNewIntent`), consumed
  ONCE by `AppRoot` — never push routes from outside the
  composition.
- **Audit the manifest against every URL the app emits.** A share
  link or App Link path not declared in an intent-filter fails
  silently for external opens while in-app navigation works. Route
  every declared path to the RIGHT screen — a `/series/{slug}` link
  landing on a generic detail screen reads as "broken app." Test:
  `adb shell am start -a android.intent.action.VIEW -d <url>`.
- Tab taps clear the back stack; system back pops it.

## Parity-port specifics

- **Icon parity = Material twins, not copied glyphs.** Map each SF
  Symbol to its closest Material Symbols equivalent
  (theater/mood/bolt/nightlight/landscape/science/brush/newspaper…)
  — same meaning, native family.
- Deterministic shared logic (schedulers, shuffles) ports with
  identical constants — same hash (FNV-1a), same mixer (SplitMix64),
  same local-time anchors — then verify agreement with the other
  platforms on a fixed seed.
- Proportional/timeline layouts (EPG-style) = Compose custom
  `Layout` placing children by minute-offset × px-per-minute, with
  `stickyHeader` for the ruler — don't fake it with weighted rows.
- Media3 queue playback: per-item position persistence; queue
  playback that shouldn't pollute resume state carries an explicit
  `persistProgress=false`-style flag on the play spec.
- Lock-screen/media-key controls = Media3 `MediaSession` from day
  one (a parity row, not polish).

## Theme + surfaces

- Brand theme default; **dynamic color is opt-in, never the
  default** when the product has a strong canvas (a cinema app is
  not a settings app).
- M3 typography styles only, six hierarchy levels, refuse a seventh.
- Tiles: image + two text lines, nothing else; stable `key`s on
  every Lazy container; explicit empty-state sentences
  (`universal-feature-states`).

## Verification recipes

- `./gradlew :app:assembleDebug` is the gate; emulator-verify
  user-facing claims (a green build is not a working feature).
- Boot ONE emulator at a time, and never alongside an iOS simulator
  — parallel boots wedge both.
- Screenshots: SystemUI demo mode for a clean status bar; drive
  screens via deep links (`adb shell am start -d appname://…`);
  screenshot IDs must come from LIVE data, not stale seeds.
- Release signing: keystore in `~/keystores/`, creds in
  `~/.gradle/gradle.properties`, NEVER in git; verify the AAB's
  signer fingerprint against assetlinks before upload. Play-specific
  process in `store-submission-playbook`.
- `versionName` stays in lockstep with the iOS marketing version;
  bump `versionCode` every ship.
