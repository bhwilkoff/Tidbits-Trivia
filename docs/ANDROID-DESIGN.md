# Tidbits Trivia — Android Design (BINDING)

**Binding.** Quote the rule number before proposing any new screen,
route, sheet, card, or data path in the Android app (`android/`). If no
rule fits, propose a NEW rule first. Companion to `PARITY.md`, the
sibling design docs, and `android-production-gotchas` (the mechanics this
doc does not restate). The platforms share *verbs*, never *idioms*; when
a rule below inverts an iOS/tvOS rule, that is the Material idiom of the
same verb.

All UI is Compose under
`android/app/src/main/java/com/learningischange/tidbitstrivia/`. The two
load-bearing files are `ui/AppRoot.kt` (shell + nearly every screen) and
`data/Tidbits.kt` (domain model + `Store`).

## §1 Principles

- **§1.1 Android feels like Material.** The feature set matches the other
  platforms; the expression is Material 3 — `NavigationBar`,
  `FilterChip`, `ModalBottomSheet`, `Switch`. Never port iOS/tvOS chrome;
  never hand-roll where an M3 component exists (`native-platform-first`).
- **§1.2 Compose-only, single Activity, edge-to-edge.** One
  `MainActivity` → `setContent { AppTheme { AppRoot() } }`
  (`MainActivity.kt:18`). No Fragments, no XML beyond the splash theme.
  `minSdk 29`.
- **§1.3 State stays on the device.** Records/streaks/presets persist via
  `Store` over SharedPreferences; the corpus is bundled JSON loaded into
  memory (`data/Tidbits.kt`). *(Current architecture, stated honestly:
  no Room/FTS5, no ViewModel/UiState/Event, no Hilt — screens hold state
  inline with `mutableStateOf`. The `dbVersion`/`produceState`
  invalidation discipline from `android-production-gotchas` does not
  apply here because there is no SQLite read layer. If a Room catalog
  ever lands, that discipline becomes binding — amend this rule then.)*
- **§1.4 Mobile-first density.** Density from removing chrome
  (`mobile-first-density-design`). Fixed phone shell today; adaptive
  (tablet/foldable) layout is a future wave, not silent.
- **§1.5 Learning first.** Records lets a player revisit misses and beat
  their past self — a door to curiosity, not a dump (CLAUDE.md "Why we
  build").

## §2 Navigation shell

- **§2.1 Three content tabs, hard set: Play · Records · Create** via an
  M3 `NavigationBar` (`AppRoot.kt:174`), shown only on the three tab
  routes. Settings is NOT a tab — it is behind the gear in Home's top bar
  (`Route.Settings`). A new tab requires amending this rule.
- **§2.2 One sealed `Route` back stack.** Navigation is a
  `mutableStateListOf<Route>` (`AppRoot.kt:78`); every destination is a
  `Route` case dispatched in one `when (current)` (`:122`). New
  destinations extend `Route` — never an ad-hoc overlay. *(Jetpack
  Navigation / `NavigationSuiteScaffold` arrive only when route
  complexity or adaptive layout demands them — propose the rule change
  first.)*
- **§2.3 System back pops the stack** (`BackHandler`, `:116`); a tab tap
  clears the stack to that root (`:120`). A live Night tears down its
  session before popping (`:155`).
- **§2.4 Deep links land in an inbox.** `MainActivity.routeFor()` maps
  `tidbits://…` / `https://tidbitstrivia.com/…` to a token that
  `AppRoot`'s `LaunchedEffect(deepLink)` consumes once (`:103-114`). New
  entry points extend this inbox, never push routes from outside the
  composition. **Every deep-link host/path you emit must be declared in
  the manifest intent-filter** or external opens fail silently; App Links
  need the Play App Signing SHA-256 in `assetlinks.json`
  (`store-submission-playbook`).

## §3 Surfaces

- **§3.1 Home** = "TIDBITS" wordmark + settings icon → Quick Play hero
  (coral, one action, R-HOME-1) → Surprise/Customize pair → **Join a game
  card** (teal, R-JOIN-1 — the second thing on Home; opens `NightJoin`,
  and a `/live/{code}` App Link opens it with the code remembered) →
  Daily card (yellow, play-once → archive) → Trivia Night card → "More
  ways to play" tiles (Pass & Play, Online Multiplayer) (`AppRoot.kt`).
  Pickers live in the `CustomizeSheet` `ModalBottomSheet`, never on Home.
- **§3.2 Records** = the dashboard (§5). **A summary, never a full
  ledger.**
- **§3.3 Create** = topic field → generated quiz (`:1186`).
- **§3.4 Game** = `GameScreen` phase machine on `GameState.phase`
  (`:560`); one `PlayingScreen` for every mode, with a mode-specific
  input panel.
- **§3.5 Card list** = a vertical `Column` of `ChunkyCard`s — the
  canonical content surface.
- **§3.6 Sheet** = `ModalBottomSheet` for pickers and every Records
  drill-in (`RecapDialog`, `DomainDrillDialog`, `BestAttemptsDialog`).

## §4 The chunky card — binding

`ChunkyCard` (`AppRoot.kt:1227`) = a `Surface` with an 18dp rounded shape
+ a 2.5dp `Ink` border.

- **§4.1 Ship the hard offset shadow (gap).** iOS/web draw the 90s
  sticker's hard 5px offset shadow; **Android renders only the border
  half** (`:1229`). Add the offset-shadow layer (a `Canvas`/`drawBehind`
  offset rounded rect in `Ink`) so the Android card matches the sibling
  surface, then reserve its gutter (§4.2).
- **§4.2 Stacked cards carry a consistent gutter.** Card lists separate
  items with a fixed `Arrangement.spacedBy` / `Modifier.padding` — no
  list is exempt (the flush-stack "squished" bug the iOS/web docs also
  forbid). Once the offset shadow exists (§4.1), the gutter must clear it.
- **§4.3 One canonical cell per list** (`GameHistoryRow`, `TopicRow`,
  answer rows) with generous, consistent internal padding — content never
  butts the border. Stable `key`s on every `LazyColumn`/`LazyGrid`.

## §5 Records — a dashboard, not a ledger (rule R-REC-1)

Mirrors iOS-DESIGN §5.3–5.6 as the Material idiom. **`RecordsScreen`
(`AppRoot.kt:963`) currently dumps `records.take(40)` inline plus every
domain and every scored mode — the same kitchen-sink bug as iOS. This
rule is the fix.**

- **§5.1 Records summarizes and drills in; it never dumps.** Detail lives
  behind `ModalBottomSheet` drill-ins (`:1097`, `:1114`, `:1130`).
- **§5.2 Fixed order:** streak → lifetime stat row → recent games
  (bounded) → "Your knowledge" → calibration (if any) → personal bests →
  facts to review (bounded).
- **§5.3 Progressive disclosure is the core rule:** each long list is a
  **bounded preview + a "See all" affordance** opening the full set in a
  sheet:
  - **Recent games**: the **3 most recent**, then "See all N games"
    opening the full history — never `records.take(40)` inline.
  - **Personal bests**: one row per mode actually played.
  - **Your knowledge**: 7 domains in full (bounded, the learning
    surface).
  - **Facts to review**: cap the preview (≤8).
- **§5.4 The full-history sheet is a light list** (divider rows, no
  per-row hard shadow), not 40 stacked cards.

## §6 Theme

- **§6.1 Brand theme by default; dynamic color is OFF by default,
  opt-in via Settings** (`Theme.kt:31`; only Android 12+ and only when
  the user enables it). The brand cream/ink identity is the product.
- **§6.2 Tokens in `ui/theme/`**: `Color.kt` (coral `#FF5C5C` primary,
  blue `#2D5BFF`, grape `#8B5CF6`, the `Pops` category ramp, cream/ink),
  `Theme.kt`, `Type.kt` — in lockstep with the Apple `Design.swift`
  palette. Never a seventh hue.
- **§6.3 Brand vs semantic split is absolute.** Primary/secondary =
  chrome/CTA; `Pops` category accents = content meaning only;
  `AppSemantics` Success/Warning/Error = status only. `onAccent()` /
  `accentText()` (`Theme.kt:84`) keep text legible on bright fills.
- **§6.4 M3 typography styles only, six levels** (`Type.kt`
  displaySmall → bodySmall, mapped to M3 slots); refuse a seventh
  (CLAUDE.md density rule). **Wire the brand font (gap):** `Type.kt:16`
  still uses `FontFamily.Default` with a FILL-IN TODO — Android does not
  yet match the iOS rounded typeface. Ship the brand font so the type
  ramp reads as one system across platforms.
- **§6.5 M3, not M3 Expressive (current).** Standard `MaterialTheme`.
  Adopting M3 Expressive is a deliberate future decision, not a drift.

## §7 Out of scope on Android v1 (intentional — next wave)

Adaptive tablet/foldable layout (`NavigationSuiteScaffold` +
`currentWindowAdaptiveInfo`); Glance widgets + App Shortcuts; M3
Expressive adoption. Each ships later with a reason — never partially,
never silently.

## §8 Parity discipline

- **§8.1** Update `PARITY.md` in the same change set as any user-facing
  feature; proposals/commits quote these rule numbers.
- **§8.2** A feature that lands differently from a sibling is the native
  *Material* idiom of the same verb — name the rule it mirrors or
  inverts. **Emulator-verify a release build before "done"**
  (`android-production-gotchas`).
