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
>
> **Last audit: 2026-06-30 (Android ↔ Apple, code-verified).** Found 4
> false cells (§3b emoji grid, §4 entire auth section, §5 share URLs,
> §12 adaptive icon) and confirmed the real Android-behind-iOS gaps
> (onboarding, full Settings + attribution, haptics, pass-and-play).
> Core gameplay is at genuine parity. Corrections applied below.

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
| Play vs CPU (online-multiplayer v0, Decision 038) | ✅ | ✅ | ✅ | ✅ | **2026-07-02:** the home "Online Multiplayer" surface is live — one sheet/panel (Quick Match marked coming-soon = the v1 slot) + four CPU opponents (The House adapts to the player's recent accuracy; Rookie/Regular/Ace). Believable-bot spec mirrored 3× (`BotOpponent.swift`/`Bots.kt`/`js/bots.js`): category-varying skill, log-normal timing, ~5% freeze; same Scoring as the player. **Every bot is visibly labeled CPU.** Live strip + per-reveal outcome + final standings; iOS + Android live-verified, tvOS build-verified (GC interstitial blocks the headless sim), web syntax-checked. Matches don't write records (same as pass-and-play) |
| Online Quick Match (real players) | 🚫 | 🚧 | 🚧 | 🚫 | **Decision 039 (owner): native platform multiplayer only — GameKit; no third-party backend.** iOS + tvOS BUILT 2026-07-02: `GKMatchmakerViewController` (invites/automatch 2–4) → `GameKitTransport` behind the `NightPeerLink` seam → the SAME LiveNight machinery, leader-elected + auto-paced. **Gate: 2-device Game Center hardware test** (sims can't). Web/Android 🚫 = Google killed PGS multiplayer (2020) and the owner ruled out backends — they keep Play vs CPU + local night, Quick Match row stays coming-soon |
| Play (home) — Quick Play + progressive disclosure | ✅ | ✅ | ✅ | ✅ | **Redesigned 2026-07-01 (rule R-HOME-1, Decision 035), revised same day (Decision 036 / R-HOME-1a):** ONE single-action Quick Play hero; **Surprise + Customize are a quiet secondary pair under it** (no button-in-button); prominent Daily; unified Trivia Night; **home tile = Online Multiplayer placeholder** (Create lives in its tab). Native idiom per platform (iOS `.sheet`, Android `ModalBottomSheet`, web `<dialog>`, tvOS focus picker + chip row). **R-ICON-1: platform icon systems only (SF Symbols / Material Symbols / inline SVG) — no emoji chrome** |
| Quick Play + saved presets (power-user) | ✅ | ✅ | ✅ | ✅ | Last-(mode,category) resolves the Quick Play default; saveable presets; Surprise = random. Customize sheet self-explains modes (selected mode's blurb line); sentence-case labels everywhere. tvOS: category-select starts the game (documented ten-foot inversion, Decision 036) and has no presets (⏳ low-value on TV) |
| Records (stats, streak, review) | ✅ | ✅ | ✅ | ✅ | **Redesigned 2026-07-01 (Task 8):** removed the confusing domains Pie; per-domain rows explain the level ("N more to Level X"); spelled-out labels ("Accuracy"/"Correct", "Level"). Achievement taxonomy authored in `docs/achievements.json` (GC + Play creation via API is owner-blocked). Android via SharedPreferences |
| Create (quiz from any topic) | ✅ | ✅ | 🚫 | ✅ | **Corpus-grounded 2026-07-01 (Task 7):** retrieves REAL vetted corpus questions matching the topic (no hallucination), falls back to live generation only when thin. tvOS: typing on a Siri Remote is hostile — n/a |

---

## 2. Core gameplay (single-player)

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| **Trivia Night** (configurable "bar trivia" night) | ✅ | ✅ | ✅ | ✅ | The new flagship default mode, on **all four platforms**: a host-configured night of themed **rounds**, each round drawing one question TYPE — so one night pulls from EVERY question type (general MCQ → picture → which-first → closest → ordering → matching → name-it → odd-one-out → name-as-many). Presets (Quick / Pub / The Works) + category (iOS also per-round counts). A client meta-mode over the shape-routing engine (no corpus change — Decisions 025/031). Round banners + end-of-round beats + the shared missed-fact recap. **iOS** home card → `NightSetupView` → `NightContainerView`. **tvOS** home hero → ten-foot `NightSetupView_tvOS` → `TVNightContainer`. **web** coral banner → native `<dialog>` setup → the shared game loop, plus shareable `#/night`·`#/night/quick`·`#/night/works` deep links. **Android** coral home card → `NightSetupScreen` → `Route.Game(BAR_TRIVIA, nightRounds=…)`. Solo everywhere; **Apple devices also host/join a networked night** (any device hosts, Decision 033 — see §3b "Trivia Night — networked"); web/Android networked play is the queued Phase-2 follow-up |
| Classic mode (10 Qs, speed scoring) | ✅ | ✅ | ✅ | ✅ | Same loop on every platform (Swift/JS/Kotlin mirrors) |
| Time Attack (60s) | ✅ | ✅ | ✅ | ✅ | |
| Survival (until one wrong) | ✅ | ✅ | ✅ | ✅ | |
| Stake (confidence allocation) | ✅ | ✅ | ✅ | ✅ | 8-Q round; fixed chip budget (Sure×2/Likely×3/Hunch×3), commit before answering; adds-only, never negative — calibration, not gambling (Decision 022). Solo "home version" of LearnedLeague/Pour House (GAME-MODES-RESEARCH M1) |
| Sweep (fill-the-set, beat-your-best) | ✅ | ✅ | ✅ | ✅ | 12-Q "set"; +1 per correct (count-scored, no speed bonus) with a persistent fill-grid scoreboard (mint hit / coral miss); beat your own best via existing per-mode best-score. Sporcle "sweep the set" home version (SOLO-BACKLOG M2) |
| Picture ID (identify the image) | ✅ | ✅ | ✅ | ✅ | 10-Q mode off the E1 enrichment (`picture.json`, 4,813 Qs): a Commons image + a **type-aware, varied stem** + the corpus's 4 vetted options. `gen_picture.py:picture_stem()` classifies each subject from its one-line description and asks the RIGHT question — a person gets "Who is this Finnish ski jumper?", a place "What city is this?", an event "Name this siege." — rotating across ~4 phrasings (1,954 distinct stems; bare "What is this?" down from 100% to 10%, kept only for genuinely typeless subjects). Stem lives in the data, so all four platforms inherit it with no client change. Occupation now wins over embedded work/place nouns ("video game designer" → a person, not "What video game is this?"), and both explanation formats (describe + cloze) are parsed. Two corpus-wide cleanups ride along (`recategorize_and_clean.py`, all modes benefit): **category repair** of 740 miscategorized people (athletes filed under Film & TV → Sports, etc., only when the description doesn't support the current category) and **option-disambiguator stripping** of 2,718 rows (a distractor like "John Thomson (photographer)" beside bare names was a giveaway; collision cases like "Russo-Ukrainian war (2022–present)" keep their qualifier). iOS/tvOS AsyncImage, web `<img>`, Android Coil — each with a load-failure fallback (this mode needs the network; all other modes stay offline). SOLO-BACKLOG Q7 |
| Which First? / This-or-That (chronology) | ✅ | ✅ | ✅ | ✅ | 10-Q binary pick off E1 chronology (`thisorthat.json`, 779 Qs): "Which came first?" + "Which has the bigger population/area?" between two same-category entities (verified 0 chronology errors). Renders on the existing 2-option MCQ surface. SOLO-BACKLOG Q1 |
| Closest Call (numeric estimation) | ✅ | ✅ | ✅ | ✅ | 8-Q proximity mode off E1 numbers (`closest.json`, 1,233 Qs: year / atomic number / elevation). Estimate on a slider (iOS/web/Android); tvOS has no Slider so it uses ±coarse/±fine focusable steppers. Adds-only proximity scoring; the first non-MCQ type — earns custom numeric data (Decision 031). SOLO-BACKLOG M5 |
| In Order / Ordering (chronology) | ✅ | ✅ | ✅ | ✅ | 6-Q "arrange earliest→latest" off E1 years (`order.json`, 394 Qs, 4 items each). Uniform ↑/↓ move buttons on every platform (incl. tvOS — no drag). Partial credit by inversion count, adds-only (Decision 031). SOLO-BACKLOG Q4 |
| Match Up / Matching (pairs) | ✅ | ✅ | ✅ | ✅ | 6-Q "link each key to its value" from the corpus's 1:1 Wikidata relations (`match.json`, 136 Qs: country→capital/currency, element→symbol, book→author). Tap key then value to link; partial credit by correct links, adds-only. tvOS = focusable key rows + value chips. SOLO-BACKLOG Q5 |
| Name It / Type-the-answer (free recall) | ✅ | ✅ | ✅ fallback | ✅ | 8-Q free-text recall (`typeanswer.json`, 997 Qs) matched against an accepted set (answer + E1 aliases, diacritic/punct/case/"the"-insensitive). iOS/web/Android = text field; **tvOS** = recall-then-reveal self-mark (text entry is a keyboard wall at ten feet) — graceful per-platform idiom. SOLO-BACKLOG Q6 |
| Odd One Out (which doesn't belong) | ✅ | ✅ | ✅ | ✅ | 8-Q "which doesn't belong?" built from the corpus's country→continent data (`oddoneout.json`, 67 Qs: 3 from one continent + 1 outlier). Plain 4-option MCQ (outlier = answer) — reuses the existing answer surface, zero new UI. SOLO-BACKLOG Q3 |
| Ladder (climb easy→hard) | ✅ | ✅ | ✅ | ✅ | 10-Q MCQ round sorted by the F3 derived difficulty (`difficulty.json` overlay: Wikipedia pageviews → 1..5; popular=easy); harder rungs pay a climb bonus. Client-mode wrapper over the corpus, zero new UI. SOLO-BACKLOG F3 |
| Name as Many / enumeration (Q8) | ✅ | ✅ | ✅ fallback | ✅ | 3-puzzle "name as many X in 60s" round (`enumerate.json`, 11 puzzles / 243 slots: continent→countries + curated planets/elements/oceans/Great Lakes/continents). Type against a live clock; each unique answer (alias-matched via the type-answer normalizer + E1 aliases) fills a chip; +1 each (count-scored). Reveal shows the full set, named vs. missed (testing effect). iOS/web/Android = text field; **tvOS** = recall-self-mark (reveal list + count stepper — keyboard wall at ten feet). Replayable drill: ignores the seen-set. Data curated (historical/defunct states + dupes dropped, PRC→China). SOLO-BACKLOG Q8 |
| Daily Tidbit (deterministic, streak) | ✅ | ✅ | ✅ | ✅ | **2026-07-01 audit: the old "same seed on all platforms" note was silently false** — three different seed strings/hashes/pools/shuffles meant every platform picked a DIFFERENT daily (owner caught it). Now: one canonical hash-rank pick (Decision 037, `DailyPick.swift`/`pickDailyIds`/`pickDaily`), golden-proven identical on all three stacks via `tools/daily-parity/run.sh` (which also flushed out Kotlin's signed-byte FNV divergence on non-ASCII ids) |
| Daily play-once + Previous Tidbits archive (R-DAILY-1) | ✅ | ✅ | ✅ | ✅ | **2026-07-01 (Decision 036):** today's Daily locks after completion (card flips to done-state with score; no Play Again on results); archive lists last 30 days — unplayed past days playable via the deterministic day-key seed; past plays never bump the streak. Per-day results: UserDefaults (Apple) / SharedPreferences (Android) / localStorage (web) |
| 8 categories | ✅ | ✅ | ✅ | ✅ | Mixed/History/Science/Geography/Arts/Film&TV/Music/Sports |
| Countdown clock + speed bonus | ✅ | ✅ | ✅ | ✅ | Per-question or global per mode |
| Streak multiplier | ✅ | ✅ | ✅ | ✅ | Capped at 2× (bounded reward) |
| "Learn the fact" reveal + Wikipedia link | ✅ | ✅ | ✅ | ✅ | The mission-critical screen. **2026-07-01 audit: the Android cell was silently false** — its reveal lacked the correct/lightbulb status icon and the "Read <title> on Wikipedia" source link both iOS + web had. Fixed same day: Material `Verified`/`Lightbulb` badge, richer explanation type, `SportsScore` round-complete icon (was a 🏁 emoji), and the source link via `LocalUriHandler` — emulator-verified opening Chrome |
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
| Personal bests + lifetime stats | ✅ | ✅ | ✅ | ✅ | SwiftData (Apple); localStorage (web); SharedPreferences (Android). tvOS shown in `RecordsView_tvOS` |
| Topic Levels (per-domain XP/level) | ✅ | ✅ | ✅ | ✅ | QuizUp's best idea: an XP level + bar per knowledge domain, derived from game history (no new persistence). Shared `ProgressMath` (Core) mirrored in store.js/Tidbits.kt and now rendered on tvOS (SOLO-BACKLOG M4) |
| The Pie (breadth wedges) | ✅ | ✅ | ✅ | ✅ | Trivial-Pursuit pie: a wedge per domain earned at a small mastery bar (≥15 correct, ≥60% acc); completes only when all 7 domains filled — fights corpus bias. Same shared derivation; tvOS Canvas pie in `RecordsView_tvOS` (SOLO-BACKLOG M3) |
| Stake calibration readout (F1) | ✅ | ✅ | ✅ | ✅ | Per-tier hit-rate (Sure/Likely/Hunch) in Records, accumulated across Stake rounds — the self-knowledge mirror. iOS persists via a `CalibrationTally` SwiftData model; web localStorage; Android SharedPreferences; tvOS reads the same model in `RecordsView_tvOS` |
| Answer-distribution telemetry (F4) | ✅ | ✅ | ✅ | ✅ | Local-first **foundation**: privacy-respecting per-option answer counts keyed by question id (`tidbits.answerTelemetry`), written on every game-end via `RecordsStore.recordTelemetry` (iOS/tvOS, UserDefaults) / `Store.recordTelemetry` (web localStorage, Android SharedPreferences). No PII, no network; synthetic-chosenIndex modes (closest/ordering/matching/type) skipped. Invisible infra — the **Predict the Crowd** "X% picked this" reveal stays 🔮 until a backend aggregates these across players (deferred to Ben). SOLO-BACKLOG F4 |
| Daily streak + missed-fact review | ✅ | ✅ | ✅ | ✅ | Streak on all 4; spaced re-asking of missed questions now woven into games on all 4 (Android by question-id via `Corpus.byId`), each with an opt-out toggle |
| Compete vs. your past self | ✅ | ✅ | ✅ | ✅ | New-best detection on each game; tvOS surfaces personal bests in `RecordsView_tvOS` |
| Share score (NO X/Twitter) | ✅ Web Share | ✅ ShareLink | ✅ QR | ✅ Intent | Decision 022; web has clipboard fallback |
| Spoiler-free emoji-grid result | ✅ | ✅ | ✅ | ✅ | Wordle-style 🟩🟥; the daily share loop (ROADMAP #1). tvOS renders it on `TVResultsView`. **Audit 2026-06-30: Android shipped it** — `ResultsScreen` renders 🟩🟥⬛ and shares it (was falsely ⏳) |
| First-run onboarding | ⏳ | ✅ | ⏳ | ✅ | 3-card play/learn/compete walkthrough. **Android shipped 2026-06-30** (`OnboardingScreen`, emulator-verified: 🧠 All-of-Wikipedia / 💡 Learn-every-round / 🎉 Solo-or-together) |
| Leaderboards | 🔮 Supabase | 🚧 Game Center | 🚧 Game Center | 🔮 Play Games | Apple **code complete**: auth (now presents the sign-in sheet) + score submission on game-end (classic high + daily streak) + the dashboard (Settings → "Leaderboards & Achievements") + access point. No-op until authenticated; the only thing left is **creating the leaderboards in App Store Connect** with the matching IDs (`docs/GAME-CENTER-SETUP.md`) |
| Achievements | 🔮 | 🚧 Game Center | 🚧 Game Center | 🔮 Play Games | Apple **code complete**: **9** achievements reported from the shared `RecordsStore` (first game / flawless / centurion / 7- & 30-day streak / full pie / Stake sharpshooter / explorer / scholar), partial-progress where it makes sense. Pending **ASC achievement creation** with matching IDs (`docs/GAME-CENTER-SETUP.md`) |
| Challenges (friend score/achievement) | 🔮 | 🚧 Game Center | 🚧 Game Center | 🔮 | iOS-26 async friend challenges — **code complete** (challenge listener registered; "Play" launches Classic). Rides the leaderboards/achievements; enable "challengeable" per board in ASC. Fits async-first (Decision 023), no backend. **Activities deliberately skipped** (would fork the Bonjour/Supabase multiplayer story; Apple-only) |
| Local pass-and-play | 🔮 | ✅ | ⏳ | ✅ | 2–4 players, shared fair question set, hand-off + scoreboard. **Android shipped 2026-06-30** (`PartyContainer`, emulator-verified: setup → handoff → turns → ranked scoreboard + share) |
| Spaced re-asking of missed facts | ✅ | ✅ | ✅ | ✅ | Due misses woven into corpus-MCQ games (skips Daily + non-MCQ modes); resolve on correct. **Opt-out toggle** ("Review questions") on every platform: iOS/tvOS via `GameSettings.reviewKey` @AppStorage (both now in their Settings screen), web + Android via a Records→Settings switch. Default ON |
| Haptic feedback | n/a | ✅ | n/a | ✅ | Correct/wrong; Settings toggle. **Android shipped 2026-06-30** (`GameHaptics` via `View.performHapticFeedback` CONFIRM/REJECT, honors the Settings toggle) |
| Settings (haptics, reset, attribution) | ◑ | ✅ | ✅ | ✅ | iOS + tvOS: full Settings (review toggle / reset seen / reset all records / Game Center status / attribution; haptics is n/a on tvOS). tvOS reached from the home header. **Android shipped full Settings 2026-06-30** (`SettingsScreen` via Home gear: haptics + review toggles, Material You toggle, reset seen, reset all records, version, Wikipedia CC BY-SA attribution — emulator-verified). web: "Review questions" toggle so far (Records→Settings); reset/about still pending there |
| Async head-to-head / groups | 🔮 | ⏳ Game Center | ⏳ | 🔮 | Async > real-time for survivability (ROADMAP) |
| Trivia Night — networked (any device hosts/joins) | 🔮 | 🚧 host+join | 🚧 host+join | 🚧 host+join | **Device-agnostic, cross-platform local multiplayer (Decision 033 — supersedes the TV-only buzzer of Decision 030).** ANY Apple device (iPhone, iPad, Apple TV) can **host** a Trivia Night or **join** one — there is no special "TV host" and no "Buzz Night" (the name is retired). The model is **host-paced, everyone-plays**: the host builds the night once and ships the night to every device (`NightHost`/`NightClient`/`LiveNight`) over the **cross-platform v2 transport** — DNS-SD discovery (Bonjour ↔ Android NsdManager) + plain TCP + app-layer **AES-GCM** keyed by the room code (`docs/CROSS-PLATFORM-MULTIPLAYER.md`). Apple migrated OFF TLS-PSK (Android's stack can't speak the GCM-PSK suite) but **keeps `includePeerToPeer` so Apple↔Apple still pairs over AWDL with no router — no degradation**; the `.night` ships canonical `WireQuestion`s so a Swift host renders on a Kotlin joiner. Each device runs its own engine over the identical list and **scores itself locally** (host trusts self-reports — friendly living-room game, no server). Everyone answers on their OWN screen (no race-to-buzz); the **host plays too** and taps **Reveal → Next** to pace it. The engine is `hostPaced`: it HOLDS each reveal behind a "waiting for the host" beat (so no one sees the answer early), then everyone reveals together and sees the **live standings** (leader crowned). Every question shape works (not just MCQ — the whole night). Device-based silent rejoin (stable per-device id → same seat + score) and mid-night catch-up (host replays the night + current question). **iOS/iPadOS**: home "Trivia Night" (Solo / Host toggle in `NightSetupView`) + "Join a Night" card → `NightLiveContainer`. **tvOS**: night hero (Play on this TV / Host for others) + header "Join a Night" → `TVNightLiveContainer` (big join code on the screen, host plays with the remote). **Android** (2026-06-30): home "Trivia Night" → Host / Play-solo, "Join a night" → `NightJoinScreen` → `NightContainer` (lobby + room code, host-paced live game, standings). Emulator-verified: host lobby (code), round banners, host-paced "waiting for the host" lock, Reveal/Next controls. **All three stacks BUILD SUCCEEDED** (iOS/tvOS via Xcode-beta, Android via Gradle). The live pairing/answer/rejoin is **hardware-only — a cross-platform (and same-platform) 2-device test is the gate** (Ben; emulators/simulators can't mDNS-peer). Wi-Fi Aware (no router) + BLE (no Wi-Fi) are queued transport adapters; GitHub-gist = the Phase-2 remote path. Web = Phase 2. ROADMAP #4 |
| Cross-platform online | 🔮 | 🔮 | 🔮 | 🔮 | Supabase, after Apple online proves out (Decision 020) |

---

## 4. Authentication + profile

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
> **Audit 2026-06-30: this entire section was fictional.** A code grep
> found NO auth/account/biometric/sync on web, iOS, tvOS, OR Android —
> no `ASAuthorization`/SiwA, no Credential Manager, no CloudKit, no
> Face ID / BiometricPrompt, no account or deletion path anywhere. The
> only "identity" that exists is Game Center (`GKLocalPlayer`, Apple).
> Cells corrected to 🔮. This is a whole-app future subsystem, not an
> Android-specific gap.

| Sign in with Apple | 🔮 | 🔮 | 🔮 | 🚫 | Not built on any platform (no SiwA code). Gates only sync, also unbuilt. Android would use Google instead |
| Sign in with Google | 🔮 | 🔮 | 🚫 | 🔮 | Was falsely ✅ on Android — no Credential Manager code exists. Future, when sync ships |
| Email/password | 🔮 | 🔮 | 🚫 | 🔮 | No auth backend yet. tvOS would stay SiwA-only (password entry on a remote is hostile) |
| Biometric gate for sensitive actions | n/a | 🔮 | n/a | 🔮 | Was falsely ✅ — no Face ID / BiometricPrompt code on either platform. Nothing sensitive to gate until accounts exist |
| Account deletion | 🔮 | 🔮 | 🔮 | 🔮 | Store-review requirement that activates **only once sign-in exists**; no account system today |

Sign-in is **optional and would gate only sync** — every browse/use verb
works signed-out on every platform (see `per-ecosystem-sync-islands`).
None of it is built yet on any platform.

---

## 5. Universal Links / App Links / deep linking

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Universal Links / App Links (HTTPS) | n/a | ⏳ | n/a | 🚧 | `/.well-known/` files; tvOS has no Safari hand-off — custom scheme only. **Android 2026-06-30**: intent-filter (`autoVerify`, tidbitstrivia.com) + `.well-known/assetlinks.json` shipped; autoVerify is **OWNER-blocked** until the Play App Signing SHA-256 is added to assetlinks (Play Console → App integrity) — until then HTTPS links open via chooser |
| Custom scheme | n/a | ✅ | ⏳ | ✅ | `tidbits://` — **Android shipped 2026-06-30** (manifest BROWSABLE filter + `MainActivity.routeFor` → AppRoot inbox; emulator-verified `tidbits://party` + `tidbits://settings`). iOS handler exists in `.onOpenURL`. tvOS needs it for Top Shelf + Siri deep links |
| URL params reflect filter state | ✅ | n/a | n/a | n/a | Web-specific affordance |
| Canonical share URLs (`https://…/item/{id}`) | ✅ renders | ⏳ emits | ⏳ | ✅ emits | **Audit 2026-06-30:** iOS `ResultsView` ShareLink + tvOS still text-only (no URL). **Android now emits `https://tidbitstrivia.com`** in the score + pass-and-play share (a canonical landing twin); per-`item/{id}` deep-share is the next step. iOS should match. Web renders item URLs as the landing twin (DEEP_LINKS.md) |

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
| Predictive back gesture | ✅ | **Shipped 2026-06-30** — `android:enableOnBackInvokedCallback="true"`; Compose `BackHandler` drives the back stack. iOS swipe-back is fixed-animation; Android is user-driven |
| Adaptive icon (foreground / background / monochrome) | ✅ | **Shipped** (audit 2026-06-30) — `mipmap-anydpi-v26` adaptive icon WITH a monochrome layer (themed-icon ready). iOS uses static; tvOS uses layered imagestack |
| App Shortcuts (long-press app icon) | ✅ | **Shipped 2026-06-30** — static `shortcuts.xml` (Daily / Trivia Night / Pass & Play) firing `tidbits://` deep links. iOS has AppIntents; tvOS has Top Shelf |
| Material You dynamic color (opt-in) | ✅ | **Shipped 2026-06-30** — Settings → "Use system colors" toggle drives `AppTheme(dynamicColor)` (Android 12+). Brand theme default. Other platforms have brand-only theming |
| Google Cast sender | 🔮 | AirPlay analog; needs Cast SDK + device-tested receiver |
| 16 KB page size support | ✅ | Satisfied by AGP 9.2 + `targetSdk = 36` (16 KB-aligned native libs by default). Mandatory for new releases targeting Android 15+ |

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
