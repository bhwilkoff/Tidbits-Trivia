# Tidbits Trivia — Cross-Platform Feature Parity

> **Single source of truth** for what's shipping where. Updated in
> the SAME change set as any user-facing feature.
>
> Companion to `CLAUDE.md` (project context), `SCRATCHPAD.md` (active
> milestone), `DECISIONS.md` (architecture decisions). Per-platform
> design rules live in `DESIGN.md` (iOS), `tvOS-DESIGN.md` (tvOS),
> `WEB-DESIGN.md` (web), `ANDROID-DESIGN.md` (Android) when those
> binding docs exist. The full workflow — including the periodic
> parity audit — is the `cross-platform-parity-discipline` skill.

---

## Legend

- ✅ **Shipped** — live in production on this platform
- 🚧 **In progress** — being built; some parts may already be in main
- ⏳ **Planned** — committed; targeted for an upcoming milestone
- 🔮 **Future** — agreed direction; no timeline yet
- 🚫 **Out of scope** — explicitly not built on this platform (with reason)
- n/a — platform-inapplicable (e.g., lock-screen controls on tvOS)

A ⏳ or 🚫 cell carries its reason in Notes. "Deliberately deferred,
because X" is a healthy cell; a silent blank is drift.

---

## Parity rule

When shipping any user-facing feature:

1. **Confirm the verb is identical across platforms.**
   Find = explore, Profile = identify, etc. Don't let one platform
   own a different verb for the same surface.
2. **Pick the native idiom per platform** — `<dialog showModal>` on
   web, `.sheet` on iOS, focus-driven full-screen on tvOS,
   `ModalBottomSheet` on Android.
3. **Update this table** in the SAME PR. Drift here is what causes
   "the web has X but iOS doesn't" complaints six months later.
4. **Cross-link to the binding design doc** for each platform that
   has one.

---

## 0. Platform set

Web + iOS + iPadOS + tvOS + Android (Decision 020). tvOS earns its place
because living-room trivia is lean-back (Decision 021). iOS is the lead
platform; everything ships there first, then mirrors. A platform not yet
reached is ⏳ with a note, never silence.

## 1. Top-level navigation

| Verb | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Play (home: daily, modes, categories) | ✅ | ✅ | ✅ | ✅ | iOS: bottom Tab. Web: hash-routed tabs + URL state. tvOS: dark-first focus shelf. Android: bottom NavigationBar |
| Records (stats, streak, review) | ✅ | ✅ | ⏳ | ✅ | tvOS persists records (Caches store) but has no browse UI yet; Android via SharedPreferences |
| Create (quiz from any topic) | ✅ | ✅ | 🚫 | ✅ | tvOS: typing a topic on a Siri Remote is hostile — consume shared links instead |

---

## 2. Core gameplay (single-player)

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Classic mode (10 Qs, speed scoring) | ✅ | ✅ | ✅ | ✅ | Same loop on every platform (Swift/JS/Kotlin mirrors) |
| Time Attack (60s) | ✅ | ✅ | ✅ | ✅ | |
| Survival (until one wrong) | ✅ | ✅ | ✅ | ✅ | |
| Stake (confidence allocation) | ✅ | ✅ | ✅ | ✅ | 8-Q round; fixed chip budget (Sure×2/Likely×3/Hunch×3), commit before answering; adds-only, never negative — calibration, not gambling (Decision 022). Solo "home version" of LearnedLeague/Pour House (GAME-MODES-RESEARCH M1) |
| Sweep (fill-the-set, beat-your-best) | ✅ | ✅ | ✅ | ✅ | 12-Q "set"; +1 per correct (count-scored, no speed bonus) with a persistent fill-grid scoreboard (mint hit / coral miss); beat your own best via existing per-mode best-score. Sporcle "sweep the set" home version (SOLO-BACKLOG M2) |
| Picture ID (identify the image) | ✅ | ✅ | ✅ | ✅ | 10-Q mode off the E1 enrichment (`picture.json`, 816 Qs): a Commons image + "What is this?" + the corpus's 4 vetted options. iOS/tvOS AsyncImage, web `<img>`, Android Coil — each with a load-failure fallback (this mode needs the network; all other modes stay offline). SOLO-BACKLOG Q7 |
| Which First? / This-or-That (chronology) | ✅ | ✅ | ✅ | ✅ | 10-Q binary pick off E1 chronology (`thisorthat.json`, 779 Qs): "Which came first?" + "Which has the bigger population/area?" between two same-category entities (verified 0 chronology errors). Renders on the existing 2-option MCQ surface. SOLO-BACKLOG Q1 |
| Closest Call (numeric estimation) | ✅ | ✅ | ✅ | ✅ | 8-Q proximity mode off E1 numbers (`closest.json`, 1,233 Qs: year / atomic number / elevation). Estimate on a slider (iOS/web/Android); tvOS has no Slider so it uses ±coarse/±fine focusable steppers. Adds-only proximity scoring; the first non-MCQ type — earns custom numeric data (Decision 031). SOLO-BACKLOG M5 |
| In Order / Ordering (chronology) | ✅ | ✅ | ✅ | ✅ | 6-Q "arrange earliest→latest" off E1 years (`order.json`, 394 Qs, 4 items each). Uniform ↑/↓ move buttons on every platform (incl. tvOS — no drag). Partial credit by inversion count, adds-only (Decision 031). SOLO-BACKLOG Q4 |
| Match Up / Matching (pairs) | ✅ | ✅ | ✅ | ✅ | 6-Q "link each key to its value" from the corpus's 1:1 Wikidata relations (`match.json`, 136 Qs: country→capital/currency, element→symbol, book→author). Tap key then value to link; partial credit by correct links, adds-only. tvOS = focusable key rows + value chips. SOLO-BACKLOG Q5 |
| Name It / Type-the-answer (free recall) | ✅ | ✅ | ✅ fallback | ✅ | 8-Q free-text recall (`typeanswer.json`, 997 Qs) matched against an accepted set (answer + E1 aliases, diacritic/punct/case/"the"-insensitive). iOS/web/Android = text field; **tvOS** = recall-then-reveal self-mark (text entry is a keyboard wall at ten feet) — graceful per-platform idiom. SOLO-BACKLOG Q6 |
| Odd One Out (which doesn't belong) | ✅ | ✅ | ✅ | ✅ | 8-Q "which doesn't belong?" built from the corpus's country→continent data (`oddoneout.json`, 67 Qs: 3 from one continent + 1 outlier). Plain 4-option MCQ (outlier = answer) — reuses the existing answer surface, zero new UI. SOLO-BACKLOG Q3 |
| Ladder (climb easy→hard) | ✅ | ✅ | ✅ | ✅ | 10-Q MCQ round sorted by the F3 derived difficulty (`difficulty.json` overlay: Wikipedia pageviews → 1..5; popular=easy); harder rungs pay a climb bonus. Client-mode wrapper over the corpus, zero new UI. SOLO-BACKLOG F3 |
| Name as Many / enumeration (Q8) | ✅ | ✅ | ✅ fallback | ✅ | 3-puzzle "name as many X in 60s" round (`enumerate.json`, 11 puzzles / 243 slots: continent→countries + curated planets/elements/oceans/Great Lakes/continents). Type against a live clock; each unique answer (alias-matched via the type-answer normalizer + E1 aliases) fills a chip; +1 each (count-scored). Reveal shows the full set, named vs. missed (testing effect). iOS/web/Android = text field; **tvOS** = recall-self-mark (reveal list + count stepper — keyboard wall at ten feet). Replayable drill: ignores the seen-set. Data curated (historical/defunct states + dupes dropped, PRC→China). SOLO-BACKLOG Q8 |
| Daily Tidbit (deterministic, streak) | ✅ | ✅ | ✅ | ✅ | Same 7 Qs for everyone per day; same FNV-1a/SplitMix64 seed on all platforms |
| 8 categories | ✅ | ✅ | ✅ | ✅ | Mixed/History/Science/Geography/Arts/Film&TV/Music/Sports |
| Countdown clock + speed bonus | ✅ | ✅ | ✅ | ✅ | Per-question or global per mode |
| Streak multiplier | ✅ | ✅ | ✅ | ✅ | Capped at 2× (bounded reward) |
| "Learn the fact" reveal + Wikipedia link | ✅ | ✅ | ✅ | ✅ | The mission-critical screen |
| Post-game missed-fact recap | ✅ | ✅ | ✅ | ✅ | Full "Tidbits to remember" list — every miss + answer + cited fact. tvOS in a focusable ScrollView; Android in the results scroll (SOLO-BACKLOG F2) |
| Four content states (load/empty/error/offline) | ✅ | ✅ | ✅ | ✅ | Web: service-worker offline; native: bundled corpus |
| Emoji-grid result on screen | ✅ | ✅ | ✅ | ✅ | + share intent (Android), ShareLink (iOS), Web Share |

---

## 3. Content pipeline (shared data plane — see docs/DATA-CONTRACT.md)

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Bundled offline corpus (10k, never-repeat) | ✅ JSON→IndexedDB | ✅ SQLite | ✅ SQLite | ✅ JSON (in-memory) | One corpus, per-platform reader; Android bundles assets/corpus.json (Room is a later perf step) |
| Live generation from any Wikipedia topic | ✅ | ✅ | ✅ (fallback) | ✅ | Powers Create + corpus fallback; web hits the API with origin=* (CORS) |
| Template engine + quality gates | ✅ js/engine.js | ✅ Swift | ✅ (shared Core) | ✅ Kotlin | Four mirrors of `tools/corpus/generate_corpus.py` |
| Wikidata structured questions (the moat) | ✅ | ✅ | ✅ | ✅ | ~2,850 verified Qs in the shared corpus (Decision 024); gates 1/2/4/5 by construction |
| Question TYPE variety (29 types) | ✅ | ✅ | ✅ | ✅ | 5 summary shapes + 17 Wikidata + 6 fact types: forward/reverse attribute, superlative, chronology, numeric closest-to, classification, who-directed/wrote/composed, birth/death-year, nationality — all 4-option, rendered via the shared corpus (Decisions 025/027) |
| Deep article fact-extraction (fact:* types) | ✅ | ✅ | ✅ | ✅ | SHIPPED: 1,000 `fact:*` Qs in the shared corpus (6 types: directed/written/composed_by, birth/death_year, nationality) via `tools/corpus/wiki_extract.py` (Decision 027). Build-time only — all 4 read the corpus unchanged |
| Vandalism/NPOV gates 6/7 + human sampling 9 | 🔮 | 🔮 | 🔮 | 🔮 | Next corpus step (e.g. contested continent-of-country cases) |
| E1 Wikidata enrichment (image/numeric/alias) | 🚧 | 🚧 | 🚧 | 🚧 | DATA shipped: `assets/enrich.json` (1,591 entities) + `assets/picture.json` (816 Picture ID Qs) via `tools/corpus/enrich.py`+`gen_picture.py`. Additive, separate from corpus. Consumer modes (Picture ID, Closest Call, …) read it — UI per platform is the next wave (SOLO-BACKLOG E1) |

---

## 3b. Records, sharing, multiplayer

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Personal bests + lifetime stats | ✅ | ✅ | ⏳ | ✅ | SwiftData (Apple); localStorage (web); SharedPreferences (Android) |
| Topic Levels (per-domain XP/level) | ✅ | ✅ | ⏳ | ✅ | QuizUp's best idea: an XP level + bar per knowledge domain, derived from game history (no new persistence). Shared `ProgressMath` (Core) mirrored in store.js/Tidbits.kt. tvOS ⏳ until it gets a Records browse screen (SOLO-BACKLOG M4) |
| The Pie (breadth wedges) | ✅ | ✅ | ⏳ | ✅ | Trivial-Pursuit pie: a wedge per domain earned at a small mastery bar (≥15 correct, ≥60% acc); completes only when all 7 domains filled — fights corpus bias. Same shared derivation (SOLO-BACKLOG M3) |
| Stake calibration readout (F1) | ✅ | ✅ | ⏳ | ✅ | Per-tier hit-rate (Sure/Likely/Hunch) in Records, accumulated across Stake rounds — the self-knowledge mirror. iOS persists via a `CalibrationTally` SwiftData model; web localStorage; Android SharedPreferences. tvOS ⏳ (no Records UI) |
| Answer-distribution telemetry (F4) | ✅ | ✅ | ✅ | ✅ | Local-first **foundation**: privacy-respecting per-option answer counts keyed by question id (`tidbits.answerTelemetry`), written on every game-end via `RecordsStore.recordTelemetry` (iOS/tvOS, UserDefaults) / `Store.recordTelemetry` (web localStorage, Android SharedPreferences). No PII, no network; synthetic-chosenIndex modes (closest/ordering/matching/type) skipped. Invisible infra — the **Predict the Crowd** "X% picked this" reveal stays 🔮 until a backend aggregates these across players (deferred to Ben). SOLO-BACKLOG F4 |
| Daily streak + missed-fact review | ✅ | ✅ | ⏳ | ✅ streak | Spaced re-asking woven into games on web + iOS; Android has streak (review later) |
| Compete vs. your past self | ✅ | ✅ | ⏳ | ✅ | New-best detection on each game |
| Share score (NO X/Twitter) | ✅ Web Share | ✅ ShareLink | ✅ QR | ✅ Intent | Decision 022; web has clipboard fallback |
| Spoiler-free emoji-grid result | ✅ | ✅ | ⏳ | ⏳ | Wordle-style 🟩🟥; the daily share loop (ROADMAP #1) |
| First-run onboarding | ⏳ | ✅ | ⏳ | ⏳ | 3-card play/learn/compete walkthrough |
| Leaderboards | 🔮 Supabase | ⏳ Game Center | ⏳ Game Center | 🔮 Play Games | Apple: GameKit wired, ASC config pending |
| Achievements | 🔮 | ⏳ Game Center | ⏳ Game Center | 🔮 Play Games | |
| Local pass-and-play | 🔮 | ✅ | ⏳ | 🔮 | 2–4 players, shared fair question set, hand-off + scoreboard |
| Spaced re-asking of missed facts | ⏳ | ✅ | ⏳ | ⏳ | Due misses woven into solo games (skips Daily); resolve on correct |
| Haptic feedback | n/a | ✅ | n/a | ⏳ | Correct/wrong/milestone; Settings toggle |
| Settings (haptics, reset, attribution) | ⏳ | ✅ | ⏳ | ⏳ | Toolbar gear → sheet, not a tab |
| Async head-to-head / groups | 🔮 | ⏳ Game Center | ⏳ | 🔮 | Async > real-time for survivability (ROADMAP) |
| Living-room mode (phone-as-buzzer) | 🔮 controller | 🚧 controller | 🚧 host | 🔮 controller | Phase 1 Apple-native (Bonjour + room-code TLS-PSK) FOUNDATION landed: shared `Core/Networking/Buzzer*` (host=tvOS `NWListener`, client=iOS `NWBrowser`); arbiter fairness offline-proven, both slices build clean. NOT yet two-device-verified, not wired to a game mode (Decision 030). Web/Android = Phase 2 web-room (Cloudflare DO). The biggest open market gap (ROADMAP #4) |
| Buzz Night (same-room buzz game) | 🔮 | ⏳ | ⏳ host | 🔮 | Rides the Phase-1 buzzer once paired+verified; TV is stage+scoreboard, phones buzz, wrong buzz opens to others, every Q ends on the Learn-the-fact reveal (GAME-MODES-RESEARCH D2). Web/Android via Phase 2 |
| Cross-platform online | 🔮 | 🔮 | 🔮 | 🔮 | Supabase, after Apple online proves out (Decision 020) |

---

## 4. Authentication + profile

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Sign in with Apple | ✅ | ✅ | ✅ | 🚫 | Apple ecosystem; Android uses Sign in with Google instead |
| Sign in with Google | 🔮 | 🔮 | 🚫 | ✅ | Android Credential Manager one-tap; web GIS when sync ships |
| Email/password | ✅ | ✅ | 🚫 | ✅ | Typing a password with a Siri Remote is hostile — tvOS uses SiwA only |
| Biometric gate for sensitive actions | n/a | ✅ Face ID | n/a | ✅ BiometricPrompt | |
| Account deletion | ✅ | ✅ | ✅ | ✅ | App Store + Play review requirement when sign-in exists |

Sign-in is **optional and gates only sync** — every browse/use verb
works signed-out on every platform (see `per-ecosystem-sync-islands`).

---

## 5. Universal Links / App Links / deep linking

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Universal Links / App Links (HTTPS) | n/a | ⏳ | n/a | ⏳ | `/.well-known/` files; tvOS has no Safari hand-off — custom scheme only |
| Custom scheme | n/a | ⏳ | ⏳ | ⏳ | `appname://` — tvOS needs it for Top Shelf + Siri deep links |
| URL params reflect filter state | ✅ | n/a | n/a | n/a | Web-specific affordance |
| Canonical share URLs (`https://…/item/{id}`) | ✅ renders | ✅ emits | ✅ emits (QR code — a TV can't "send" a link) | ✅ emits | Web is the landing twin for every native share (DEEP_LINKS.md) |

---

## 6. Notifications

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Push notifications | 🚫 | 🔮 APNs | 🚫 | 🔮 FCM | Web push too inconsistent; TV notifications are hostile in a living room |
| Cross-platform dispatcher | n/a | 🔮 | n/a | 🔮 | One Worker, two transports (APNs + FCM) — symmetric payload |
| Notification permission request | n/a | 🔮 | n/a | 🔮 | At opt-in moment, NOT app launch |

---

## 7. Payments / subscription

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| In-app purchase | n/a | 🔮 IAP | 🔮 IAP (same StoreKit) | 🔮 Play Billing | |
| Web subscription | 🔮 | n/a | n/a | n/a | Stripe / Paddle when scoped |
| Cross-platform subscription state sync | 🔮 | 🔮 | 🔮 | 🔮 | Webhooks → `user_subscriptions` table |

---

## 8. Backend services / shared data plane

All clients consume the same backend / published data. List the
canonical services and assets here so references stay aligned.
If the app has a content data plane, the full contract lives in
`docs/DATA-CONTRACT.md` — this table just indexes it.

| Service / asset | Purpose | Where | Consumed by |
|---|---|---|---|
| <!-- e.g. catalog.sqlite.zz | full content DB, query-on-disk | GitHub Release (rolling) | iOS, tvOS, Android download+inflate; web via index --> | | | |

---

## 9. Web-specific affordances

These are web-only by design; other platforms handle the same
need natively.

| Feature | Web | Why |
|---|---|---|
| URL params reflect filter state | ✅ | Shareable deep links; native apps use in-memory state |
| Web Share API + clipboard fallback | ✅ | iOS/Android use the system share sheet; tvOS shows a QR code |
| View Transitions API (cross-view) | ✅ | iOS uses `.navigationTransition(.zoom)`; Android `sharedBounds` |
| Container queries on components | ✅ | Native platforms use size-class branching |
| Installable PWA + offline shell | ✅ | The zero-install reach play; stores cover the rest |

---

## 10. iOS-specific affordances

| Feature | iOS | Why |
|---|---|---|
| Liquid Glass tab bar / toolbar | ✅ | Web uses `backdrop-filter`; Android M3 tonal elevation |
| Live Activities / Dynamic Island | 🔮 | No equivalent elsewhere — accept the asymmetry |
| WidgetKit home-screen widgets | 🔮 | tvOS analog is Top Shelf; Android analog is Glance widgets |
| Hardware-keyboard shortcuts | ✅ | Web n/a (browser conflicts); Android Ctrl+1..5 on tablets |
| Picture-in-Picture + background audio | 🔮 | tvOS PiP exists but TV apps suspend in background |

---

## 11. tvOS-specific affordances

These are ten-foot / lean-back idioms by design. The general rule:
**idle/ambient surfaces belong to lean-back devices** (TV first,
iPad/tablet/desktop second, phones rarely).

| Feature | tvOS | Why |
|---|---|---|
| Top Shelf extension | ⏳ | The marquee surface when your icon is focused on the TV home screen; reads an App Group snapshot the app refreshes via `BGAppRefreshTask` |
| Siri "Up Next" via NSUserActivity | ⏳ | System watchlist integration — tiny code surface |
| App Intents voice launches ("surprise me") | ⏳ | Pairs with any random/serendipity verb |
| Focus-driven UI (no pointer, no touch) | ✅ | The defining constraint — see `tvos-platform-patterns` |
| Idle screensaver / ambient mode | 🔮 | Lean-back idiom; opt-in, never over playback |
| Layered parallax app icon (imagestack) | ⏳ | tvOS icons are layered; see `branding/README.md` |

---

## 12. Android-specific affordances

| Feature | Android | Why |
|---|---|---|
| Predictive back gesture | ⏳ | iOS swipe-back is fixed-animation; Android is user-driven |
| Adaptive icon (foreground / background / monochrome) | ⏳ | iOS uses static; tvOS uses layered imagestack |
| App Shortcuts (long-press app icon) | ⏳ | iOS has AppIntents; tvOS has Top Shelf |
| Material You dynamic color (opt-in) | ⏳ | Other platforms have brand-only theming |
| Google Cast sender | 🔮 | AirPlay analog; needs Cast SDK + device-tested receiver |
| 16 KB page size support | ⏳ | Mandatory for new releases targeting Android 15+ |

---

## Maintenance protocol

When you ship a feature:

1. Find the row in this table. Add new rows under the right section
   if needed.
2. Update each platform's status with one of the legend symbols.
3. Link to the relevant section of the platform's binding design doc.
4. Note any platform-specific deltas in the Notes column.

When a feature ships on one platform but is meaningfully different
elsewhere, add an entry to §9 / §10 / §11 / §12.

When a platform explicitly rejects a feature, add an "Out of scope"
row in the relevant design doc and link from this table.

**Run a parity audit** (the `cross-platform-parity-discipline` skill,
"audit" mode) before any launch wave and roughly once per milestone:
walk the shipped feature list per platform and verify every cell is
honest. Real audits on shipped apps have found both missing rows
(features nobody recorded) AND false cells (a "synced" claim that
never actually synced) — the audit is what keeps this file true.
