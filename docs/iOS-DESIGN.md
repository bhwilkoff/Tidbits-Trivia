# Tidbits Trivia — iOS / iPadOS Design (BINDING)

**Binding.** Every new view, tab, sheet, grid, card, route, or toolbar
item in the iPhone/iPad app must trace to a rule in this document. When
something feels overwhelming, squished, or inconsistent, **fix this
document first, then fix the feature.** Proposals (and commits) cite the
rule they implement, e.g. "per iOS-DESIGN §5.3."

Division of labor:
- **This doc** = the binding contract for the iOS/iPadOS surface:
  navigation shell, touch idioms, Home + Records composition, the
  chunky-card system, game-play presentation, state.
- **`docs/tvOS-DESIGN.md` / `WEB-DESIGN.md` / `ANDROID-DESIGN.md` /
  `macOS-DESIGN.md`** = the sibling contracts. The platforms share
  *verbs*, never *idioms* (PARITY "same verb, native idiom"). When a
  rule below deliberately inverts a sibling rule (e.g. §4.1 vs
  tvOS §6.1), that inversion is load-bearing — do not "harmonize" it.
- **`ios-production-gotchas` skill** = the mechanics + failure modes
  this doc does not restate (presentation races, fill-image blowups,
  dark-mode accent trap, size-class adaptivity, simulator verification).
- **`PARITY.md`** = what ships where; updated in the SAME change set.
- **`DECISIONS.md`** = the why behind non-obvious rules.

All iOS UI lives in `TidbitsTrivia/iOS/*.swift` behind `#if os(iOS)`.
Shared logic (models, `AppStore`, the game engine, `RecordsStore`, the
corpus, sync) is consumed from `Core/` verbatim — never duplicated. The
design system itself lives in `Core/Design/Design.swift` and is shared
with every Apple platform.

---

## §1 — Principles (the why)

1.1 **Same verb, native idiom.** The feature set matches the other
platforms; the expression is whatever iOS users already know — tab bar,
sheets with detents, `Menu`, swipe actions, `ShareLink`,
`ContentUnavailableView`. Never invent a custom control where a native
one exists (`native-platform-first`).

1.2 **Touch replaces focus. Density comes from removing chrome.** The
tap is the verb; the card is the chrome. Every divider, badge, tint, and
shadow you remove makes the remaining information read denser
(`mobile-first-density-design`). Design for iPhone portrait first, then
let iPad adapt (§2.2).

1.3 **Learning first.** Every surface should open at least one door to
curiosity, not just report a number. Records exists to let a player
*compete against their past self and revisit what they missed* — not to
tally luggage (CLAUDE.md "Why we build"; `learning-orientation-design`).

1.4 **Lean-in companion.** iOS is where a player customizes, digs into
their history, creates a quiz, and hosts/joins a Trivia Night. The
10-foot lean-back idioms (an ambient wall, an idle attract screen) do
not belong here — that is tvOS.

1.5 **Depth ≤ 2 from any tab root.** Tab → list/detail → drill-in. A
would-be third push must be a **sheet** (the drill-ins in §5) or a
scope, never a third `NavigationLink`. Game play and Settings present
modally and don't count as pushes.

1.6 **One shared data plane.** The phone consumes the same corpus,
editorial config, and CloudKit sync island as every other client. No
iOS-only reads or re-derived flags (`shared-data-plane-contract`).

---

## §2 — Navigation shell (binding)

2.1 **Three content tabs, hard set: Play · Records · Create**
(`ContentView_iOS.swift:12`). The tab bar is reserved for content verbs.
**Settings is NOT a tab** — it lives behind the gear in Home's nav bar
and presents as a `.sheet` (`HomeView.swift:53`, `:97`). Adding a tab
requires amending this rule first.

2.2 **One shell, both form factors.** Root is `TabView(selection:)` with
three `Tab`s, one `NavigationStack` per tab. iPad regular-width adopts
`.tabViewStyle(.sidebarAdaptable)` (adopt when iPad layout work begins —
current build is the plain tab bar). Views adapt via
`@Environment(\.horizontalSizeClass)`, **never `UIDevice` checks**.

2.3 **One `NavigationPath` per tab, owned by `AppStore`**
(`store.playPath` / `recordsPath` / `createPath`). Views never construct
a `NavigationLink(destination:)` to a shared screen; they append to the
active tab's path. A new pushable destination is a `Hashable` route
registered once — never a per-view `navigationDestination`.

2.4 **Deep links and intents land in an inbox.** `onOpenURL` /
GameCenter challenges drop a request that the root drains once
foregrounded (`ContentView_iOS.swift:30`,
`store.drainInbox`). External entry points never mutate the tab
selection directly from outside the view tree.

2.5 **Game play and modes are full-screen covers launched from Home,
not tabs or pushes.** A round takes over via `fullScreenCover(item:)`
(§6). This deliberately inverts tvOS-DESIGN §9 (a mode *replaces the
shell*): on the phone the cover's own close affordance is the exit.

---

## §3 — Surface taxonomy (the only allowed shapes)

Every iOS screen maps to exactly one. A new shape needs a new rule.

3.1 **Tab** — one of the §2.1 verbs. `NavigationStack` + the store path.
3.2 **Card list** — a vertical `VStack`/`ScrollView` of chunky cards
(Home, Records). The canonical Tidbits surface (§7).
3.3 **Grid** — `LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))])`
for mode/category/preset pickers. The 150pt floor keeps every mode and
category name on ONE line (`HomeView.swift:336` — the owner's
"text is bad" wrap bug).
3.4 **Sheet** — transient pickers, forms, and every Records **drill-in**
(§5.4); `presentationDetents` where partial-height helps.
3.5 **Full-screen cover** — game play, and the multiplayer/night
containers, and ONLY those (§6).
3.6 **Card** — the chunky sticker card (§7) for content;
capsule chips for pickers (`ModeChip`, category capsules).

---

## §4 — Touch idiom (binding)

4.1 **`.buttonStyle(.plain)` on cards is CORRECT on iOS.** Every tappable
card wraps `Button { … } label: { card }.buttonStyle(.plain)`. This is
the exact inverse of the tvOS guardrail (tvOS-DESIGN §6.1, where `.plain`
destroys focusability) — there is no focus engine to protect, and
`.plain` keeps the card's fill from being tinted as a system button.
**Never apply the tvOS rule to iOS files or vice versa.**

4.2 **Native controls only.** Empty/error = `ContentUnavailableView`
(`RecordsView.swift:50`). Forms = `Form`/`Section`. Sharing =
`ShareLink`. Facets/sort = a toolbar `Menu`. Every list/grid/sheet
declares loading · loaded · empty · error (`universal-feature-states`).

4.3 **Pickers and drill-ins open as sheets.** The Customize sheet, the
Daily archive, and the three Records drill-ins (Recap / Domain / Best
attempts) are all `.sheet(item:)` bound to an **item, not a Bool**, so
data-dependent content never races (`ios-production-gotchas`).

4.4 **Never a fill-mode image inside `frame(maxWidth: .infinity)`.**
Category art and any hero fill via `.background`/`.overlay` + `.clipped`,
never `scaledToFill` in a flexible frame (the intermittent
layout-blowup; `ios-production-gotchas`).

---

## §5 — Home & Records composition (binding)

### Home (rule R-HOME-1, Decision 036)

5.1 **Home is ONE primary action.** The fixed order is: header →
**Quick Play hero** (the single primary CTA) → the two quiet secondary
actions (Surprise / Customize) → Daily card → Trivia Night card → "More
ways to play" tiles (`HomeView.swift:34-46`). Inserting a section means
amending this rule, not appending. Mode and category pickers live behind
the Customize sheet, never on Home.

5.2 **The hero is exactly one `Button`** (R-HOME-1a) — no embedded
second tap target. Surprise + Customize are two equal-weight secondary
buttons beneath it.

### Records — a dashboard, not a ledger (rule R-REC-1)

5.3 **Records summarizes; it never dumps.** Records is
"compete against your past self," and its job is to let a player **dig
in without being overloaded** (owner directive, 2026-07-03). The tab
shows an at-a-glance summary and **drills into detail via sheets** (§5.4)
— it must never render a full history inline.

The fixed order is: **streak card → lifetime stat row → recent games
(bounded) → Your knowledge (per-domain) → calibration (if any) →
personal bests → facts to review (bounded)**.

5.4 **Progressive disclosure is the core Records rule** (density §5).
Each long list shows a **bounded preview + one "See all" affordance**
that opens the full set in a sheet:

- **Recent games**: show the **3 most recent** as history cards, then a
  "See all N games ›" row opening a full-history sheet. Never
  `records.prefix(40)` inline — that inline dump is the "kitchen sink"
  bug this rule exists to prevent.
- **Personal bests**: one row per mode actually *played* (never per
  `GameMode.allCases`); each opens the Best-attempts sheet.
- **Your knowledge**: the 7 domains are bounded and are the learning
  surface (§1.3) — shown in full; each row drills into a Domain sheet.
- **Facts to review**: cap the inline preview (≤8) with the rest woven
  back into games, not listed.

5.5 **Drill-ins are sheets, never pushes** (§1.5). `GameRecapSheet`,
`DomainDrillSheet`, `BestAttemptsSheet` (`RecordsView.swift:321+`). The
full-history "See all" is likewise a sheet. A row that opens detail
carries a chevron; a row that does nothing carries none (predictable
disclosure, density §5).

5.6 **The full-history sheet is a light list, not a wall of cards.** The
summary uses chunky cards (they earn their weight at 3-5 items); the
"See all" ledger uses a lighter row (divider separation, no per-row hard
shadow) because a scannable list of 40 is not a set of hero cards
(density §1 — repeated identical shadowed boxes tile like luggage).

---

## §6 — Game play (the "player" surface, binding)

6.1 **A round is a `fullScreenCover(item:)`** launched from Home
(`GameContainerView`), applying `.ignoresSafeArea()`. Bind to the
launch *item*, never a Bool — a Bool-gated cover races to a blank first
question (`ios-production-gotchas`).

6.2 **One game engine.** Every mode (all 17 `GameMode` cases) runs the
same `GameEngine` loop; only the win condition, per-question clock, and
scoring shell differ (`GameMode.swift`). A new mode is a new case +
question shape, never a second engine. Multiplayer (Versus, Quick Match,
Trivia Night) reuses the same loop behind its own container.

6.3 **Each question shape has ONE canonical render** shared across
modes — the MCQ card, the stake confidence chips, the closest-call
slider, the ordering/matching boards, the type-answer field. Adding a
shape means adding a render + a `GameMode` case together.

---

## §7 — The chunky card system (binding)

The signature surface is the 90s-Memphis "sticker" card: a thick ink
border + a hard offset shadow (`Design.swift:101` `ChunkyCard`). It is
the one sanctioned custom surface — encapsulated in a single modifier,
not scattered styling.

7.1 **`chunkyCard()` reserves its own BOTTOM shadow gutter.** The
modifier draws a 5pt hard shadow offset by `(+shadowOffset,
+shadowOffset)` and now reserves the **bottom** space that shadow needs,
so vertically-stacked cards never collide (the "claustrophobic /
squished" bug, 2026-07-03). Call sites must NOT hand-add
`.padding(.bottom, shadowOffset)` — it doubles the gutter. The
**trailing** gutter is still reserved per call site
(`.padding(.trailing, Tidbits.Metric.shadowOffset)`) because folding it
into the modifier would misalign horizontal card grids (stat rows, tile
pairs); folding trailing in safely is the remaining ratchet
(a call-site audit + a grid-aware parameter), not yet done.

7.2 **Row cards use `Metric.rowPad` (14); feature cards use 18–20.** The
Home hero/Daily/Night cards breathe at 18–20pt internal padding; list
row cards (history, progress, bests, review) use a single shared row
padding token, never a bare `12`. Content must never butt against the
border.

7.3 **One canonical cell per list** (small multiples, density §3). Every
history row is `GameHistoryRow`; every domain row is `topicRow`; every
answer line is `AnswerRow`. A variant folds back into the canonical cell
with a parameter, never a bespoke second layout.

---

## §8 — Typography & density (binding)

8.1 **Six levels, from `Tidbits.TypeRamp` only** (`Design.swift:44`):
L1 largeTitle · L2 section · L3 emphasized body · L4 body · L5 caption ·
L6 tabular. A raw `font(.system(size:))` outside the ramp is a violation
unless it is a deliberate display number (a hero score, the "TIDBITS"
wordmark) — refactor anything else to a ramp level. **Refuse a seventh
level** (CLAUDE.md density rule).

8.2 **Section headers are L2; captions/blurbs are L5.** One header
pattern everywhere: an L2 title, optional L5 subtitle beneath it (the
Records and Customize sections already follow this).

---

## §9 — Color & materials (binding)

9.1 **The palette is fixed to `Tidbits.Palette`** — a warm cream paper
`bg`, ink text, and the SIX "pops" (coral, blue, yellow, mint, grape,
pink; teal reserved for sweep/mix). The app never invents a seventh hue
(`Design.swift:15`).

9.2 **Brand vs semantic split is absolute.** `coral` = primary CTA;
`blue` = interactive/links; `mint`/`coral` = correct/wrong *content*
meaning. A category's color carries *content* meaning only (which domain)
— never a brand CTA color. Never repurpose correct-green as chrome.

9.3 **Legibility is centralized.** Text/icons over a pop use
`color.legibleForeground`; a pop used as accent text on white uses
`color.legibleAccent` (`Design.swift:70`, `:78`) — yellow and mint fall
back to ink. Never hand-pick a foreground per call site (the dark-on-dark
class of bug; `legibility-check-compositing` memory).

---

## §10 — State, persistence & sync (binding)

10.1 **One read path.** Views read from `AppStore` / `@Query`; nothing
touches SwiftData or URLSession directly. Records queries are `@Query`
over `GameRecord` / `DailyStreak` / `MissedFact` / `CalibrationTally`
(`RecordsView.swift:10`).

10.2 **SwiftData models are shared with the other Apple platforms
verbatim**, in the App Group container, `cloudKitDatabase: .none` with
MANUAL sync on the same CloudKit container. Sign-in is optional and gates
ONLY sync (`per-ecosystem-sync-islands`).

10.3 **No new state without a home** — every persisted value maps to a
model here and, if synced, the sync island.

---

## §11 — Anti-patterns (never)

11.1 A fourth content tab, or Settings as a tab (§2.1). 11.2 A per-view
`navigationDestination` for a shared route (§2.3). 11.3 An inline dump of
a long list on Records instead of preview + "See all" (§5.4) — the
kitchen-sink bug. 11.4 Hand-adding `.padding(.bottom, shadowOffset)` at a
call site — the modifier already reserves the bottom gutter, so this
doubles it (§7.1). 11.5 A row card padded below `Metric.rowPad` (§7.2).
11.6 `fullScreenCover(isPresented:)` around data-dependent game content
(§6.1). 11.7 A second game engine (§6.2). 11.8 A raw `font(.system(size:))`
outside a display number (§8.1). 11.9 A brand color for content meaning
or a category color as chrome (§9.2). 11.10 A `.buttonStyle(.plain)`
rule ported from/into tvOS (§4.1). 11.11 A grid/list/sheet without all
four states (§4.2).

---

## §12 — The tests (run before any surface ships)

12.1 **Competent-designer test** — rebuildable from one paragraph? If
no, strip decoration.
12.2 **Verb test** — what verb does this own? Colliding with a tab's
verb? Structural bug; resolve first.
12.3 **Overload test (Records-specific)** — would a heavy player (100+
games) scroll past more than ~2 screens before every remaining detail is
behind a "See all"? If yes, it violates §5.4.
12.4 **Depth test** — >2 pushes → sheet/scope (§1.5).
12.5 **Parity discipline** — `PARITY.md` updated in the SAME change set;
the proposal quotes this doc's rule numbers. A feature that lands
differently from a sibling must be the native idiom of the same verb —
name the sibling rule it mirrors or inverts.
