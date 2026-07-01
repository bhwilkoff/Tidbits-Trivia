# Home Redesign Proposal — "Two taps to trivia"

> **Status:** Proposal (binding-design-doc style). Not yet built.
> **Author:** design-research session, 2026-07-01.
> **Scope:** The Play/Home surface on all four platforms (iOS/iPadOS,
> tvOS, Android, web). No game-loop, corpus, or networking changes.
> **Companion docs:** `CLAUDE.md` (design system), `PARITY.md`
> (feature matrix), `SCRATCHPAD.md` (backlog #4 = unified Trivia Night).
> Follows `mobile-first-density-design` + `native-platform-first` +
> `binding-design-doc-discipline`.

---

## 1. The problem (stated by the product owner)

The current home has **far too much on one screen** and is
**overwhelming to a first-time user**. To start any non-Daily game you
must scroll past four full-width cards, then scan a horizontal rail of
**13 modes**, then scroll a **2-column grid of 8 categories** and tap
one. That's a scan-heavy, scroll-heavy, decision-heavy path before a
single question appears.

Current home stack (verified in `iOS/Views/HomeView.swift` and
`android/.../ui/AppRoot.kt`):

```
Header (TIDBITS + tagline + gear)
Daily card
Trivia Night card         ← has an embedded "Join a night →" button
Pass & Play card
Join a Night card (iOS only; Android folds join into the Night card)
"Pick a mode"     → horizontal scroll of 13 mode chips
"Choose a category" → 2-col grid of 8 category cards  (tap = start)
```

Two failures:

1. **No primary action.** Five cards + two pickers compete; nothing
   says "start here." A first-run user has no obvious front door.
2. **Selection is a scavenger hunt.** Mode and category are two
   separate scrolling regions permanently occupying the home. The
   90%-case player who just wants "a good mix of questions" pays the
   full cost of the power-user surface every visit.

---

## 2. Design rules this proposal leans on (quoted)

From `CLAUDE.md` and the vendored skills — quoted per
`binding-design-doc-discipline` before any new surface is proposed:

- **Density rule** (`CLAUDE.md` → Shared design system):
  *"density comes from removing chrome, not adding decoration. Test
  at 375px before 1440px."* → The redesign **removes** two
  always-open pickers rather than restyling them.
- **Learning mission** (`CLAUDE.md` → Why we build): *"does this
  design invite the user to engage more fully… If a feature makes a
  person more passive, reconsider it."* → Quick Play must not hide
  learning; the "learn the fact" reveal and the mode variety stay
  one tap away, not buried.
- **Native idiom, same verb** (`PARITY.md` → Parity rule): *"Pick the
  native idiom per platform — `<dialog showModal>` on web, `.sheet`
  on iOS, focus-driven full-screen on tvOS, `ModalBottomSheet` on
  Android."* → The customize surface is one **verb** ("Customize a
  game") in four idioms.
- **Native-platform-first**: exhaust platform primitives before
  custom UI. The customize surface uses the OS sheet/dialog; the mode
  selector uses a native segmented/tab primitive where one exists.
- **Six-level type ramp only** (`CLAUDE.md`): *"three weights × two
  sizes = six levels. Refuse a seventh."* → Every new label maps to
  an existing L1–L6 token (mapping table in §6).

### New rule this proposal establishes (needs sign-off)

> **R-HOME-1 — One primary action per platform home.** The home screen
> has exactly ONE visually dominant call-to-action: **Quick Play**.
> Every other path (Daily, Trivia Night, Pass & Play, Customize,
> Create) is visually secondary. Selection surfaces (mode + category)
> are **progressive-disclosure** — never permanently open on the home.
>
> **Why:** the home's job is to get a returning or first-time player
> into a question in ≤2 taps. Competing equal-weight cards + always-on
> pickers defeat that. This rule is what future sessions must not
> "harmonize away" by re-adding a second hero.

---

## 3. Core information architecture

### 3.1 The Quick Play path (the 90% case, 1–2 taps)

A single dominant **Quick Play** hero at the top of the home, below the
wordmark.

- **Tap the hero → a game starts immediately.** No intermediate screen.
- **Smart default resolution** (shared logic, see §7):
  1. **Returning player:** resume the *last mode + category they
     played* (e.g. "Classic · Science"). The hero's subtitle shows it:
     `CLASSIC · SCIENCE` so the player knows what they're about to get
     and it never feels random.
  2. **First run / no history:** **Mixed Bag + Classic** — the
     friendliest, most representative default (all categories, the
     canonical scoring loop).
- **Surprise me** is a small secondary affordance on the hero (a die
  icon / "🎲 Surprise me" text button in the hero's corner): picks a
  random mode + category, so serendipity is opt-in, not the default
  (defaults must feel intentional, per the research — a random default
  reads as "the app doesn't know what I want").

The hero is the ONLY full-bleed, high-saturation element above the
fold — the density rule says brightness/chrome is reserved for the one
thing you want touched (the tvOS "focus does the work" analogue).

### 3.2 Daily Tidbit (habit surface — kept, secondary)

The Daily stays as its own card directly under Quick Play. It's a
*distinct habit* (same 7 Qs for everyone, streak) and shouldn't be
folded into Quick Play. It's visually quieter than the hero (surface
fill + streak chip, not a saturated block). Shows the current streak
inline (`🔥 4`) so it earns its place with live status, not decoration.

### 3.3 Trivia Night — ONE unified entry (backlog #4)

Per `SCRATCHPAD.md` backlog #4 — *"Trivia Night should be a SINGLE
unified entry that lets you host OR join (no separate Host/Join
buttons)."*

Today there are effectively **three** Night entry points on iOS (the
Night card, the embedded "Join a night →" button, and the standalone
"Join a Night" card). **Collapse to one card.** Tapping it opens the
**unified Night sheet**:

```
TRIVIA NIGHT
A night of mixed rounds — every kind of question.

┌───────────────────────────────┐
│  ▶  Start a night   (host/solo)│   ← builds a night, hosts for others
└───────────────────────────────┘         or plays solo on this device
┌───────────────────────────────┐
│  #  Join a night               │   ← reveals a 4-char code field inline
└───────────────────────────────┘
```

One card → one sheet → the two verbs live *inside* it, not on the home.
"Start" flows into the existing preset+category setup (Quick / Pub /
The Works). "Join" reveals the code field inline (no separate screen
until a valid code is entered). This removes the JoinNightCard row and
the embedded button entirely.

### 3.4 The Customize / power-user path (secondary, on demand)

The two always-open pickers (mode rail + category grid) are **removed
from the home** and moved behind a **"Customize a game"** affordance —
a single secondary button/row under the hero. Tapping it opens the
**Customize sheet** (§5). This is where mode + category selection now
lives, plus saved presets and multi-select.

### 3.5 "More ways to play" (collapsed shelf)

Pass & Play and Create are real but not front-page-primary. Group them
into a compact **"More ways to play"** row (two small tiles or a short
list) below Customize — present, scannable, not shouting. Create
already has its own bottom-tab entry, so on Android/iOS it can be a
lighter pointer here.

### 3.6 Resulting home stack

```
Header (wordmark + gear)
▶ QUICK PLAY hero            ← the one primary CTA (+ 🎲 Surprise me)
Daily Tidbit (streak)        ← habit, quiet
Trivia Night (unified)       ← one card → host-or-join sheet
Customize a game →           ← opens mode+category sheet + presets
More ways to play: Pass & Play · Create
```

Six elements, one clearly primary, **zero always-open pickers**, and
the whole thing fits the first screen on a 375px phone with little or
no scroll. That is the density rule applied: we removed two sections
of chrome instead of restyling them.

---

## 4. Phone (compact) wireframe

```
┌─────────────────────────────────────────┐
│ TIDBITS                            ⚙︎    │  L1 wordmark, gear top-right
│ Trivia from the whole of Wikipedia.      │  L5 tagline
│                                          │
│ ┌──────────────────────────────────────┐│
│ │  ▶  QUICK PLAY            🎲 Surprise ││  ← HERO (saturated fill,
│ │     CLASSIC · SCIENCE                 ││    the ONE primary CTA)
│ │     Jump straight into a round        ││  L2 title / L6 tab subtitle
│ └──────────────────────────────────────┘│    tap = start now
│                                          │
│ ┌──────────────────────────────────────┐│
│ │ ☀︎ DAILY TIDBIT              🔥 4    ▸ ││  ← quiet card + live streak
│ │   7 questions. Same set for everyone. ││
│ └──────────────────────────────────────┘│
│                                          │
│ ┌──────────────────────────────────────┐│
│ │ 🎉 TRIVIA NIGHT                     ▸ ││  ← ONE card → host/join sheet
│ │   Host or join a night of mixed rounds││
│ └──────────────────────────────────────┘│
│                                          │
│ ┌──────────────────────────────────────┐│
│ │ ⚙︎ Customize a game                 ▸ ││  ← opens mode+category sheet
│ │   Pick a mode, a category, save a mix ││
│ └──────────────────────────────────────┘│
│                                          │
│ More ways to play                        │  L2 section header
│ ┌───────────────┐  ┌───────────────┐     │
│ │ 👥 Pass & Play│  │ ✨ Create     │     │  ← two small tiles
│ └───────────────┘  └───────────────┘     │
└─────────────────────────────────────────┘
   [ ▶ Play ]   [ ★ Records ]   [ + Create ]   ← existing bottom nav
```

First-run variant: hero subtitle reads `MIXED BAG · CLASSIC` and a
one-line first-run hint sits under the hero ("Tap to play — customize
anytime"). After the first game, the subtitle becomes the last-played
combo.

---

## 5. The Customize sheet (where the two pickers went)

A single **modal sheet** — the native idiom per platform (§8) — opened
from "Customize a game." Medium/half detent, expandable to full.

```
╭──────────────────  Customize a game  ─────────────────╮
│                                                        │
│  MODE                                                  │  L2
│  ┌────────┬────────┬────────┬────────┐   (segmented /  │
│  │Classic │ Time   │Survival│ Stake  │    scrollable   │  ← single-select,
│  ├────────┼────────┼────────┼────────┤    tabs)        │    grouped: the 4
│  │ Sweep  │Picture │Ladder  │ …more  │                 │    "core" modes
│  └────────┴────────┴────────┴────────┘                 │    first, rest under
│                                                        │    "…more"
│  CATEGORY                                               │  L2
│  ( Mixed )  History   Science   Geography               │  ← chips, single-
│   Arts&Lit  Film&TV   Music     Sports                  │    select (or multi,
│                                                        │    see §6)
│                                                        │
│  ★ My presets                                          │  L2 (power users)
│  [ My Mix ]  [ Science Survival ]  [ + Save this ]      │  ← saved combos
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              ▶  Start                              │ │  ← primary
│  └──────────────────────────────────────────────────┘ │
╰────────────────────────────────────────────────────────╯
```

Why a sheet, not the old inline sections:

- **Focus.** The picker is a *task* ("configure a game"), so it earns
  a modal per NN/g bottom-sheet guidance — temporary, contextual,
  dismissable, returns you to a clean home.
- **Native-platform-first.** iOS `.sheet` with `.presentationDetents`,
  Android `ModalBottomSheet`, web `<dialog showModal>`, tvOS
  focus-driven full-screen. No custom drag surface.
- **Both selections in one place, one Start.** Mode and category are
  chosen together and committed with a single explicit **Start** — no
  more "tap a category card = instant start with whatever mode chip
  happened to be selected" (the current hidden-coupling footgun).

Mode grouping: show the **4 core modes** (Classic, Time Attack,
Survival, Stake) as the first row; the other 9 collapse under a "…more"
expander. This keeps the sheet scannable and teaches the hierarchy
(core vs. specialty) without hiding anything.

---

## 6. Power-user affordances

All three are opt-in and invisible to the 90% player:

1. **Remembered last selection.** Persist the last `(mode, category)`
   and surface it as the Quick Play subtitle + pre-select it in the
   Customize sheet. Zero-config personalization — the app quietly
   learns your groove.
2. **Saved presets ("My Mix").** From the Customize sheet, "**+ Save
   this**" stores the current `(mode, category, [categories])` combo
   with an auto/edited name ("Science Survival"). Presets appear as
   one-tap chips in the sheet AND, optionally, the top preset can be
   promoted to a second small tile on the home for the truly frequent
   player. Capped small (say 5) to respect the density rule.
3. **Multi-select category → custom mixed draw.** In the Customize
   sheet, category chips support multi-select. Pick History + Science
   + Geography → the game draws a mix across just those three. "Mixed
   Bag" is simply "all selected." (Multi-select is additive to the
   existing per-category draw; the corpus already tags every question
   with a category, so this is a query filter, not new data.)

These map cleanly to the learning mission: presets and multi-select let
a curious learner *build their own study set* ("just my weak domains"),
which is agency-supporting, not passive.

---

## 7. Type-ramp + density mapping (no seventh level)

Every new label maps to an existing token (`CLAUDE.md` six-level ramp):

| Element | Ramp level | iOS token | Android token | Web class |
|---|---|---|---|---|
| Wordmark "TIDBITS" | L1 page title | `.largeTitle`/rounded black | `displaySmall` | `.view-heading` |
| Section header ("More ways to play", "MODE") | L2 | `.title2` | `headlineSmall` | `.section-header` |
| Card titles ("QUICK PLAY", "DAILY TIDBIT") | L2 | `.title2` | `headlineSmall` | `.section-header` |
| Mode/category chip label, preset name | L3 emphasized body | `.headline` | `titleMedium` | `.body-strong` |
| Card blurb / hero helper line | L5 caption | `.caption` | `labelMedium` | `.caption` |
| Hero subtitle "CLASSIC · SCIENCE", streak "🔥 4" | L6 tabular | `.body.monospacedDigit()` | `bodySmall` tabular | `.tabular` |

**Density check:** the redesign *removes* the 13-chip rail and 8-card
grid from the default view (they move behind one affordance), so the
home has strictly **less** chrome than today while keeping every verb
reachable — the density rule satisfied by subtraction, exactly as
`mobile-first-density-design` prescribes. Test at 375px first.

---

## 8. Per-platform adaptation (same verbs, native idioms)

**Do not screenshot-match across platforms.** Same verbs; each idiom
native.

- **iOS / iPadOS.** Quick Play hero = a prominent `chunkyCard` button
  (existing brand idiom). Customize + Night sheets = `.sheet` with
  `.presentationDetents([.medium, .large])`. Mode selector inside =
  a native `Picker(.segmented)` for the 4 core modes + a "More" row,
  or a wrapped chip grid. On **iPad** (regular width) the Customize
  content can render as a `.popover`/inline sidebar-detail instead of
  a bottom sheet, and the "More ways to play" tiles widen to a row of
  four — size-class driven, never `UIDevice`.
- **tvOS.** No sheets/pointer. The home is a **focus shelf**: Quick
  Play is the hero that claims initial focus **once**
  (`hasClaimedInitialFocus`, per `tvos-platform-patterns`) — pressing
  it starts immediately. "Customize" pushes a focus-driven
  full-screen picker (mode column + category column, `.card` button
  style — never `.plain`). "Surprise me" is a natural remote/App-Intent
  voice verb. Presets render as a focusable row.
- **Android.** Quick Play hero = a filled `ChunkyCard`/Button. Customize
  + Night = `ModalBottomSheet` (M3). Mode selector = M3
  `SingleChoiceSegmentedButtonRow` for the core four + a "More"
  expander; categories = `FilterChip`s (multi-select ready). Presets
  = an `AssistChip` row. Honors `WindowInsets` (edge-to-edge) and
  `currentWindowAdaptiveInfo()` for tablet (medium/expanded → the
  Customize content can be a side pane, not a sheet).
- **Web.** Quick Play = a big primary button; Customize + Night =
  `<dialog showModal>` (native focus trap + ESC). Mode = a segmented
  control (radio group styled) + "more" `<details>`; categories =
  chip checkboxes. **URL-driven state** (web superpower): the Customize
  selection reflects in query params so a configured game is a
  shareable link (`?mode=survival&cat=science`), and `#/night` /
  `#/night/join` remain canonical deep links.

---

## 9. Shared-logic vs per-platform UI

**Shared logic (mirror across Swift Core / store.js / Tidbits.kt —
same behavior, four implementations):**

- **Default resolver:** `resolveQuickPlay() -> (mode, category)` —
  returns last-played if present, else `(Classic, Mixed Bag)`.
- **Last-selection persistence:** write `(mode, category)` on every
  game start (SwiftData/UserDefaults on Apple, localStorage on web,
  SharedPreferences/DataStore on Android). One key, additive.
- **Preset model:** `Preset { name, mode, categories[] }`, list capped
  ~5, CRUD. Same schema all four.
- **Surprise-me RNG** and **multi-category draw filter** (a query
  predicate over the already-category-tagged corpus — no corpus
  change).

**Per-platform UI (native idiom, not shared):** the hero component,
the sheet/dialog/focus-screen presentation, the segmented control, the
chip rows. These diverge by design.

This split is exactly the `per-ecosystem-sync-islands` / Core-vs-UI
discipline: the *decision logic* is shared and identical; the
*presentation* is native.

---

## 10. Migration / rollout (per platform, one change set)

Per the parity rule, ship the redesign as **one wave** so no platform
lags with the old cluttered home. Suggested sequence (iOS is lead per
`PARITY.md §0`):

1. **Shared logic first** (all four in the same PR): default resolver,
   last-selection persistence, preset model + multi-category filter.
   These are pure additions; no user-facing change until the UI lands.
2. **iOS/iPadOS** home refactor: hero + Daily + unified Night + Customize
   sheet + More-ways row. Delete `JoinNightCard` and the embedded
   "Join a night →" button (fold into the unified Night sheet). Verify
   on the sim; keep `DebugHooks.autoplay` working.
3. **Android** mirror in `AppRoot.kt`: replace the mode rail + category
   grid with the Quick Play hero + `ModalBottomSheet` Customize; unify
   the Night card (drop the inline "Join a night →" surface). Verify on
   emulator; the `tidbits://` deep-link inbox already routes daily/
   night/party — no deep-link change needed.
4. **Web** mirror: hero + `<dialog>` Customize + query-param state.
5. **tvOS** mirror: hero focus shelf + full-screen Customize picker;
   respect the initial-focus-once guard.
6. **Update `PARITY.md`** in the same wave — the "Play (home)" row Notes
   get the new IA; add a row for **Quick Play / smart defaults** and
   **Saved presets** so the new affordances are tracked cells, not
   silent additions. Update `SCRATCHPAD.md` backlog #4 → done (unified
   Night) and log the "one primary action" rule (R-HOME-1) in
   `DECISIONS.md` with its **Why** so it isn't re-litigated.

**What does NOT change:** the game loop, results, records, corpus,
networking, Daily determinism, onboarding cards. This is purely the
home surface + a small persistence/preset addition.

**Validation gate:** the redesign is "done" per platform only when the
app is run (sim/emulator/headless) and a first-run user reaches a live
question in ≤2 taps from cold launch, and a returning user's hero shows
their last combo. "Compiles" is not "works."

---

## 11. Open questions for the owner

1. **Promote a preset to the home?** Should the single most-used preset
   get its own small home tile, or stay sheet-only? (Density says
   sheet-only; frequency-of-use says maybe one tile.)
2. **Multi-select categories** — ship in v1 of the redesign, or land the
   single-select simplification first and add multi-select as a fast
   follow? (Recommend: single-select + presets first; multi-select
   next, since it touches the draw query.)
3. **Daily placement** — above or below Quick Play? (Proposed: below —
   Quick Play is the front door; Daily is the habit you already know to
   look for. Streak-chasers will find it instantly regardless.)

---

*Sources consulted for patterns:*
[NN/g — Bottom Sheets](https://www.nngroup.com/articles/bottom-sheet/) ·
[UserOnboard — Sensible Defaults](https://www.useronboard.com/onboarding-ux-patterns/sensible-defaults/) ·
[Apple HIG — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) ·
[VWO — Mobile App Onboarding Guide 2026](https://vwo.com/blog/mobile-app-onboarding-guide/) ·
[Userpilot — Frictionless onboarding / progressive disclosure](https://userpilot.com/blog/mobile-app-onboarding/)
