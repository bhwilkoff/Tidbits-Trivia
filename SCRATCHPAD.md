# Project Scratchpad — Tidbits Trivia

> Active snapshot (auto-loaded each session). **For the full state + how to
> build/run/verify each platform + the prioritized backlog, read
> `docs/HANDOFF.md`.** Other refs: `PARITY.md` (feature matrix, source of
> truth), `DECISIONS.md` (the why, 001–025), `docs/QUESTION-QUALITY.md`,
> `docs/ROADMAP.md`, `docs/DATA-CONTRACT.md`. Detailed per-round history is in
> `ARCHIVE.md`.

## Current state (2026-06-24)

**Single biggest open item:** **Trivia Night networked multiplayer (Decision
034)** — ANY Apple device hosts or joins, host-paced, everyone-plays (the TV-only
"Buzz Night" buzzer is **retired/replaced**). Both iOS + tvOS **BUILD SUCCEEDED**,
but the live Bonjour pairing + answer + rejoin only exercise on real devices —
that **2-device hardware test (Ben) is the gate**. **Game Center is code-complete**
(auth/dashboard/access-point/9 achievements/2 leaderboards/Challenges) but needs
**ASC config** — fully specced in `docs/GAME-CENTER-SETUP.md` (owner task; images
in `tools/branding/gamecenter/`). Versions: Apple **1.6.0 (build 47)**; Android
versionName 1.5.1 (verify before next Play upload — recent ships were Apple-only).


- **All four platforms PLAY**, off one shared corpus, all pushed to `main`:
  - **iOS/iPadOS** — full SP (4 modes, 8 categories, learn-reveal), local
    pass-and-play (2–4), records + spaced repetition, create-a-quiz, daily,
    haptics, Settings, onboarding, app icon, Game Center scaffold (no-op until
    entitlement). Verified iPhone 17 Pro sim.
  - **Web** — full SP loop, PWA, network-first corpus, canonical share target.
  - **tvOS** — dark-first focus-correct home + game loop + results. Now
    store-asset-complete: layered App Icon + Top Shelf brand assets ship, target
    re-enabled (universal iOS+tvOS), both slices build clean (2026-06-19).
  - **Android** — full SP loop (home/game/results/records/create), Compose/M3.
- **Corpus**: **~4,500 questions** = summary (describe + cloze) +
  1,144 deep-extraction `fact:*` (Decision 027) + 1,942 Wikidata. **Quality over
  quantity** (Decision 029): summary path reworked into bar-trivia "describe &
  identify" + cloze, gated by a fame floor (intro ≥600 chars) + a richness check
  (≥2 distinguishing tokens) — this deliberately cut summary from 7,834 → 1,657,
  dropping obscure subjects and content-free clues. Old identify/jeopardy/
  categorize shapes deleted. Fact questions mined from FULL articles via
  `wiki_extract.py`; geography stays Wikidata-led. All 4 engines mirror the rework.
  Wikidata source datasets cached in `tools/corpus/cache/` → regen is instant.
  Rebalanced for variety; fixed-stem Wikidata types capped (occClass 733→24).
  **Quality gates (drop-on-fail, enforced in the generator AND the 3 live
  engines):** no answer-leak (robust redaction: leading proper-noun run +
  content title words everywhere; 48%→0%), no foreign-script/math, no oversized
  clue (>320), list/glossary/LaTeX subjects filtered, paren/abbrev-aware
  first-sentence, global cross-category subject dedup. Web logs corpus version.
- **Platform set**: Web + iOS + iPadOS + tvOS + Android (Decisions 020/021).

## Next up (see docs/HANDOFF.md §6 for the full backlog)

Big tracks: online multiplayer (Game Center → Supabase), store submission prep
(iOS + Play), **phone-as-buzzer Phase 1** (foundation landed — needs two-device
pairing test + Buzz Night game-mode wiring), more question types (Q1 This-or-That
real/fake is next corpus-native; then E1 enrichment unlocks 7), adaptive difficulty.
Quick follow-ups: `clean_clue` on explanation text; P31-typed distractors for
the summary path; quality gates 6/7/9; branded iOS launch screen; web
pass-and-play + onboarding parity; Android Room; real share domain.

## Build (quick ref — full recipes in docs/HANDOFF.md §3)

```
# iOS:   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -scheme TidbitsTrivia -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/tidbits-dd
# Android: (cd android; JAVA_HOME=…/Android Studio…/jbr/Contents/Home ./gradlew :app:assembleDebug --no-daemon)
# Web:   python3 -m http.server 8080
# Corpus: cd tools/corpus && python3 generate_corpus.py && python3 wikidata.py && python3 export_json.py  (then sync android asset + rebuild)
```
Screenshot hooks (no-ops in prod): `TIDBITS_AUTOPLAY=mode:category`,
`TIDBITS_AUTOPILOT=1`, `TIDBITS_TAB=…`, `TIDBITS_PARTY=1`, `TIDBITS_ONBOARD=1`,
`TIDBITS_AUTOCREATE="topic"`. Boot ONE sim/emulator at a time.

## Out of scope (intentionally)

| Idea | Why declined | Revisit when |
|---|---|---|
| Cash prizes / wagering for money | HQ Trivia's model is mathematically doomed and off-mission | never |
| Energy / lives / hearts gating | Universal 1-star complaint; contradicts learning mission (Decision 022) | never |
| Real-time-only live game show | Both real-time-only apps (HQ, QuizUp) died; appointment fatigue | a robust async base exists first |
| X/Twitter share target | Explicit product requirement | never |
| Pay-to-restore-streak | Textbook dark pattern (Decision 022) | never |
| Non-MCQ formats (timeline drag, grouping wall) | Need per-client UI; corpus is 4-option-only (Decision 025) | a format earns the custom UI |
| Couch Co-op (thin same-room co-op) | iOS pass-and-play already delivers same-room multiplayer; a *thin* couch mode just duplicates it, and a *valuable* tvOS team mode (team setup + team scoring + focus flows) is a full marquee feature, not thin — and overlaps the deferred Buzz Night, the genuinely differentiated living-room mode. Evaluated 2026-06-20; skipped as not earning its place. | Buzz Night (phone-as-buzzer) ships and a tvOS team-scoreboard shell exists to build on |

## Session log

One-line-per-round; full detail in `ARCHIVE.md`.

- **R1** iOS foundation (Core + iOS UI + corpus + research). **R2** local
  pass-and-play + spaced repetition + haptics + Settings + icon. **R3** emoji
  share + onboarding. **R4** web mirror. **R5** Wikidata moat (10,006).
  **R6** tvOS. **R7** Android (4-platform vision complete). **R8** question
  diversity (5 shapes, no "best described", tell-free distractors, clean clues).
  **R9/9b** Wikidata question-TYPE expansion → 22 types, corpus 11,679; web
  caching fixed (network-first + versioned + SW v2).
- **2026-06-17** — prepped for first compaction: wrote `docs/HANDOFF.md`,
  archived the detailed log here-fileward, tightened this snapshot.
- **2026-06-18** — **deep Wikipedia fact-extraction** (push for better Qs).
  *Found:* summary path only ever parsed short-description + first sentence —
  every summary Q was "name the thing from its definition." *Did:* 3 research
  streams (API surface, QG/distractor literature, stdlib fact-extraction) →
  new vendored skill `wikipedia-fact-extraction` (the proprietary method) →
  new `tools/corpus/wiki_extract.py` (stdlib: infobox depth-scanner →
  protect-then-split segmentation → appositive/relation/date triples →
  coreference-safe stems → infobox-oracle verification → MCQ builder with
  type-matched distractors) → wired into `generate_corpus.py
  --facts-per-category N` (default 0). Verified end-to-end on real articles:
  "Who directed The Godfather? → Coppola" etc., all answers correct,
  distractors type-matched, the contradictory-multi-creator class gated out.
  Decision 027; QUESTION-QUALITY §3rd path; PARITY row. *Then SHIPPED:*
  hardened the extractor v2 (8 cross-domain precision fixes — person-gated
  born/died/nationality, dual-nationality drop, non-noun-type reject,
  nationality-as-creator reject, merged-name reject, album-artist
  misattribution, creators-from-sentence-0-only, infobox-direct facts) and
  regenerated the full corpus **8,630 → 10,776** (7,834 summary + 1,000 fact +
  1,942 wd), 0 errors, exported to `corpus.json` + Android asset, all 1,000 fact
  Qs structurally clean. The earlier summary dip was Wikipedia search variance,
  recovered via deeper search (`--per-category 2600`). *Left:* live engines stay
  summary-based (mirror gates only); ratchet `--facts-per-category` higher
  anytime (warm cache → cheap).
- **2026-06-19** — **bar-trivia question rework** (user: web questions "awkward",
  "what kind of thing is…" / "what subject is this" = nobody asks that; want
  "trivia night" feel). *Found:* summary path shipped obscure subjects + robotic
  framing. *Did:* reworked all 4 engines (generate_corpus.py + engine.js +
  TemplateEngine.swift + Tidbits.kt) → deleted identify/jeopardy/categorize;
  kept **describe** ("This {type} {clue} — who/what is this?", person/thing-aware)
  + **cloze**; added **fame floor** (extract ≥600) + **richness gate** (≥2
  distinguishing tokens, date-parens stripped) + leading-name-anchor reframe.
  Regenerated corpus **10,776 → 4,743** (quality over quantity). Verified: Film &
  TV samples read naturally, all bad patterns 0, iOS+Android BUILD SUCCEEDED.
  Decision 029. *Left:* domain migration done earlier today (Decision 028).
- **2026-06-19** — **tvOS store-asset unblock + parity verify**. *Found:* the
  tvOS code (home + game + results) was complete and focus-correct, but the
  target had been reverted to iOS-only because the tvOS slice had NO layered App
  Icon and NO Top Shelf image → universal archive failed ITMS-90513
  (CFBundleIcons.CFBundlePrimaryIcon + TVTopShelfImage). *Did:* new
  `tools/branding/make_tvos_icon.py` generates the full
  "App Icon & Top Shelf Image.brandassets" tree from the approved mark — landscape
  PARALLAX icon (Back = coral+strewn dots, Front = cream tile + Arial-Black T),
  with BOTH app-icon roles as imagestacks (the 1280×768 App Store role MUST be an
  imagestack too — a flat imageset crashes actool's
  `cloneImageStack:toRepresentMarketingVariant:`), plus Top Shelf 1920×720 +
  Wide 2320×720. Re-enabled tvOS in `project.yml` (supportedDestinations:
  [iOS, tvOS]); SDK-conditional `ASSETCATALOG_COMPILER_APPICON_NAME` (iOS→AppIcon,
  tvOS→brand asset); dropped the manual `TARGETED_DEVICE_FAMILY` so it derives
  from destinations (iOS 1,2 + tvOS 3). *Verified:* actool now injects
  CFBundleIcons + TVTopShelfPrimaryImage/Wide; clean tvOS build SUCCEEDED; iOS
  build (generic dest, no iOS-26 runtime locally) SUCCEEDED with icon + version
  1.0(3) intact; tvOS sim live shots — dark-first home renders + a real Science
  game ("In what year was David Attenborough born?", typed year distractors)
  plays end-to-end off the shared corpus. tvOS is now store-asset-complete; a
  universal archive no longer fails the tvOS slice. *Left:* App Group
  ModelConfiguration on tvOS (currently Caches store — survives launch, purgeable)
  + Records/onboarding browse UI remain ⏳ on tvOS (PARITY unchanged, honest).
- **2026-06-20** — **iOS splash rebuilt** (user: splash should extend the icon —
  dots around the screen, icon centered, not just a T on flat coral). Replaced the
  minimal `UILaunchScreen` dict (color + one centered image only) with a real
  `LaunchScreen.storyboard`: coral view bg + full-bleed `LaunchDots` (transparent,
  aspectFill) + centered `LaunchIcon` tile (exact shipped-icon proportions). New
  `tools/branding/make_launch.py`. Storyboard is iOS-only (tvOS rejects it) →
  `EXCLUDED_SOURCE_FILE_NAMES[sdk=appletv*]`; dangling `UILaunchStoryboardName`
  ignored by tvOS (verified it still launches). Removed unused LaunchLogo. iOS +
  tvOS both build clean. (Couldn't live-capture the iOS splash — no iOS-26 sim
  runtime locally; verified via PIL composite + storyboard compile/link.)
- **2026-06-20** — **game-modes / phone-as-buzzer / bar-trivia research**
  (user: research interaction methods + quiz types + deeply document all bar-trivia
  formats so Tidbits can build learning-first "home versions", solo/same-room/
  virtual). *Did:* 3 parallel research agents (web-sourced) → synthesized
  `docs/GAME-MODES-RESEARCH.md`: Part A (bar/pub + digital formats catalog w/
  innovation hooks), Part B (21 question/interaction types × corpus-fit table),
  Part C (phone-as-buzzer architecture — Apple-native local vs server web-room,
  comparison tables, recommendation), Part D (**Tidbits home versions** — each mode
  run through the learning-orientation 4-question test, grouped solo/same-room/
  async), Part E (one Wikidata enrichment = numeric+image+aliases → unlocks 7
  formats), Part F/G (architecture + build order + decisions to log). Pointer added
  to ROADMAP. **Key calls:** phone-as-buzzer phased (Apple-native local Bonjour/PSK
  MVP → universal web-room on Cloudflare Durable Object; tvOS has no web view so
  host stays native); recommended first modes = **Stake** (adds-only confidence),
  **Couch Co-op** (no-infra same-room), **Predict the Crowd** (needs answer
  telemetry). *Left:* research/proposal only — no modes built yet; awaiting user
  pick of which to ship first (recommend Stake → Couch Co-op).
- **2026-06-20** — **solo backlog + shipped Stake mode (M1)**. *Did:* wrote
  `docs/SOLO-BACKLOG.md` (app-alone game modes M1–M6, question types Q1–Q8,
  functionality F1–F4 + the E1 Wikidata-enrichment unlock, all prioritized w/
  status). Then built **Stake** end-to-end across all 4 engines: an 8-Q round
  where you spend a fixed confidence-chip budget (Sure×2/Likely×3/Hunch×3, sum 8)
  before each answer — commit a chip, then answer; correct = +chip value, wrong =
  +0; **adds-only, never negative** (the fixed budget forces real calibration
  without loss-aversion — faithful to LearnedLeague/Pour House, Decision 022).
  Mirrored: Core `GameMode.swift` (+.stake, `stakeBudget`) + `GameEngine.swift`
  (stakeTiers/currentStake/setStake + adds-only scoring + answer-gating), iOS
  `GamePlayView` (chip selector + reveal +N tag), tvOS `GameView_tvOS` (focusable
  chip row + `.stake` focus case + firstFocus→answers hop), web `store.js`/`app.js`/
  `styles.css`, Android `Tidbits.kt`/`GameState.kt`/`AppRoot.kt`. *Verified:* iOS+tvOS
  BUILD SUCCEEDED, Android BUILD SUCCESSFUL, web JS `node --check` clean; tvOS sim
  live shot shows the chip selector + 30s clock + year distractors working (the
  shared Core engine, which iOS also uses). A diagnostic pass confirmed the engine
  (begin idx=0 budget=30 tiers=3, no spurious submit) — earlier "instant reveal"
  screenshots were stale-framebuffer artifacts, not a bug; DIAG prints removed.
  PARITY row added; SOLO-BACKLOG M1 → ✅. *Left:* F1 calibration readout in Records
  is the queued follow-up; next backlog items E1 (Wikidata enrichment) then
  Q1/M2.
- **2026-06-20** — **M2 Sweep shipped (4 platforms) + phone-as-buzzer Phase-1
  foundation (Bonjour)**. Ben: keep building game modes/question types AND advance
  device-to-device; chose **Apple-native Bonjour** for the buzzer when asked.
  *Did (Sweep, all 4 engines):* new `sweep` mode — 12-Q "set", **+1 per correct**
  (count-scored, no speed/streak), a **persistent fill-grid** (mint hit / coral
  miss, current cell ringed) as the scoreboard, beat-your-own-best via existing
  per-mode best-score, ends on the existing miss-reveal. New teal accent
  (`#13B6C9`) added to all 4 palettes. Core `GameMode`/`GameEngine`, iOS
  `GamePlayView` + tvOS `GameView` grids (Apple auto-lists via `allCases`), web
  `store.js`/`app.js`/`styles.css`, Android `Tidbits.kt`/`GameState.kt`/`AppRoot.kt`
  (+`SweepGrid`). *Verified:* iOS+tvOS+Android BUILD SUCCEEDED, web `node --check`
  clean; **iOS sim live shot** shows the grid filling (Set 1/12, mint+coral cells,
  score=correct-count) — Sweep WORKS, not just compiles. *Did (buzzer foundation,
  Decision 030):* new `Core/Networking/` — `BuzzerProtocol.swift` (pure: Codable
  messages + room-code→TLS-PSK via SHA256 + authoritative `BuzzArbiter` with
  per-seat RTT compensation), `BuzzerTransport.swift` (shared PSK `NWParameters` +
  length-prefixed JSON framing), `BuzzerHost.swift` (`#if os(tvOS)` `NWListener`
  + Bonjour `_tidbits-buzz._tcp`), `BuzzerClient.swift` (`#if os(iOS)` `NWBrowser`/
  `NWConnection`). `Info.plist` gets `NSLocalNetworkUsageDescription` +
  `NSBonjourServices`. *Verified:* the **arbiter+PSK logic offline-proven** by a
  standalone `swiftc` harness (RTT-comp picks the true-first buzzer; first-wins;
  arm/disarm; PSK case-insensitive/distinct/32B; codes avoid ambiguous glyphs);
  both Apple slices **BUILD SUCCEEDED** with the Network code (TLS-PSK
  `__DispatchData` bridge, ciphersuite const, `.service` match all compile).
  *Left (honest):* **NOT two-device-verified** — Bonjour discovery + the iOS
  local-network prompt + the PSK handshake only exercise on real hardware; nothing
  wired into a user-facing flow yet. Next slice: two-device pairing test → wire the
  **Buzz Night** game mode (TV stage/scoreboard, phones buzz, wrong-buzz-opens,
  Learn-the-fact reveal). Versions: Apple 1.0(4), Android v2.
- **2026-06-20** — **backlog blitz (Ben: tackle the whole solo backlog, don't
  wait)**. Shipped, each verified + committed + pushed across platforms:
  **M3 The Pie + M4 Topic Levels** (knowledge cartography — a real 7-wedge pie +
  per-domain XP levels, derived from `GameRecord` history with shared
  `ProgressMath`; iOS/web/Android, tvOS ⏳ no-Records-UI; iOS sim shot verified).
  **F1 Stake calibration** (per-tier Sure/Likely/Hunch hit-rate in Records;
  `CalibrationTally` SwiftData model + localStorage + SharedPreferences; verified
  via the persisted store: Sure 1/2, Likely 0/3, Hunch 1/3 = the 2/8 round; also
  fixed autopilot to complete Stake rounds). **F2 full missed-fact recap** on
  tvOS (focusable ScrollView) + Android (results scroll) — closes the PARITY rows;
  tvOS sim shot verified. **E1 Wikidata enrichment** (the keystone): new
  `tools/corpus/enrich.py` → `assets/enrich.json` (1,591 entities: 1,287 image /
  1,187 numbers / 1,204 aliases) + `gen_picture.py` → `assets/picture.json` (816
  Picture ID Qs); additive, separate from corpus; sampled-correct + an image URL
  resolves 200/jpeg; DATA-CONTRACT updated; 100MB raw cache gitignored. *Left:*
  E1 **consumer UIs** are the next wave — **Picture ID first** (data ready;
  web/Android are JSON-native, iOS/tvOS need a small picture.json loader since
  their corpus is SQLite), then Closest Call (M5 numeric dial) + the other
  E1-gated types; also queued: F3 difficulty, F4 telemetry/Predict-the-Crowd,
  Couch Co-op, Buzz Night game-mode wiring (on the Bonjour foundation), Link Wall.
- **2026-06-20** — **E1 consumer modes shipped** (Ben: keep going on the backlog).
  All 4 platforms, each verified on the iOS sim + 4 builds, versions bumped per
  the new X.Y.Z convention: **Picture ID (Q7)** 1.1.0→… (816 image Qs, AsyncImage/
  img/Coil), **This-or-That / "Which First?" (Q1)** (779 Qs: came-first + bigger
  population/area on the 2-option surface), **population data fix** (enrich.py
  max-claim; Canada 44→40M), and **Closest Call (M5)** 1.1.4 — the **first
  non-MCQ type** (numeric estimation, 1,233 Qs: year/atomic/elevation; slider on
  iOS/web/Android, ±stepper on tvOS since tvOS has no Slider; adds-only proximity;
  Decision 031). Generic per-platform bundled-JSON loader (detects MCQ vs numeric
  by row shape) so each new mode is a one-liner. Also fixed the dark-on-dark
  ChunkyCard tiles (translucent fill bleeding the shadow) + adopted X.Y.Z
  versioning ([[versioning-convention]]). *Left (E1-gated, templated on the above):*
  Odd-one-out (Q3, needs P31/P106 enrichment), Matching (Q5, capital/element
  pairs), Ordering (Q4, year-sort), Type-the-answer (Q6, aliases); non-E1: F3
  difficulty, F4 telemetry/Predict-the-Crowd, Couch Co-op, Buzz Night, Link Wall.
- **2026-06-20** — **legibility fix + Picture ID (first E1 consumer)**. Ben flagged
  dark-on-dark Results tiles. *Found:* structural, not text-color — `ChunkyCard`
  draws a near-black "shadow" rect behind the fill; translucent tint fills
  (`color.opacity(0.18)`) let it bleed through → dark tiles. *Fix:* opaque cream
  base under the fill (one change fixes every tinted tile app-wide); verified on
  sim; memory `[[legibility-check-compositing]]` saved. Then shipped **Picture ID
  (Q7)** on all 4 platforms — the first E1 consumer: a Commons image + "What is
  this?" + the corpus's 4 vetted options (`picture.json`, 816 Qs). New
  `PictureCorpus`/`Pictures` loaders (iOS/tvOS bundle picture.json beside the
  SQLite corpus; web/Android JSON-native), `Question.imageURL`, AsyncImage
  (iOS/tvOS, `.fit`-in-fixed-frame) / `<img>` (web) / Coil (Android, wired into
  build.gradle) each with a load-failure fallback. Needs network (every other
  mode stays offline). iOS sim shot verified a real Commons image renders.
  Versions: Apple 1.0(6), Android v3. *Left:* the remaining E1 types now template
  on Picture ID's bundled-JSON+loader+mode pattern — Closest Call (M5, numeric
  dial), This-or-That (Q1), Odd-one-out (Q3), Matching (Q5), Ordering (Q4),
  Type-the-answer (Q6); plus F3/F4, Couch Co-op, Buzz Night, Link Wall.
- **2026-06-23** — **tvOS parity completion + Trivia Night (the "bar trivia" mode)
  + Buzz Night buzzer**. Ben: finish outstanding tvOS parity/feature work
  (incl. settings/Game Center + iPhone↔TV), AND build a new default mode pulling
  from every question type, hostable on Apple TV or solo/pass-and-play; chose
  **tvOS-parity-first**, **wire the buzzer this session**, **configurable night**.
  Shipped (each verified + pushed): **(1) tvOS Records browse screen**
  (`RecordsView_tvOS` — streak/lifetime/Pie/Topic-Levels/calibration/bests/review,
  focus-scrollable) + **tvOS Settings** (`SettingsView_tvOS`, fixed the
  transparent-bg report) + **Game Center score submission** wired into the shared
  `RecordsStore` path (iOS+tvOS) — closes 5+ ⏳ PARITY cells; sim-verified.
  **(2) Trivia Night** = a client meta-mode (`GameMode.barTrivia` + `NightPlan` +
  `GameEngine.startNight` + `QuestionProvider.nightQuestions`): rounds, each a
  different question TYPE, run through the engine made **shape-driven** (guards +
  timeout dispatch + per-shape clock) so mixed shapes play in one run. Presets
  (Quick/Pub/Works) + category. **All 4 platforms** — iOS/tvOS/web/Android, each
  with a setup UI + round banner + end-of-round beat, **each live-verified**
  (tvOS+web+Android sim/headless shots of a real night; iOS built). Web adds
  shareable `#/night` deep links. **(3) Buzz Night** — wired the Phase-1 Bonjour
  buzzer to a TV-hosted game: `BuzzerHost` gained per-seat scoring +
  wrong-buzz-reopen/lockout; tvOS `BuzzNightView_tvOS` (lobby→buzz loop→standings)
  + iOS `BuzzerJoinView` (join + BUZZ button). Host lobby + in-game UI sim-verified
  (room code, scoreboard); **the live buzz handshake is the only thing left — a
  two-device hardware test for Ben** (Decision 030). Versions → Apple 1.4.0(33),
  Android 1.4.0(28). *Left (next slices):* **pass-and-play team scoring** for the
  night (the "team vs solo" config dimension — solo ships now); the **2-device
  Buzz Night hardware test**; Couch Co-op; Link Wall.
- **2026-06-24** — **Trivia Night playtest hardening + corpus quality + Game
  Center completion.** Continuation of the 06-23 night work, driven by Ben's
  on-device playtest of the TV-hosted buzzer.
  **(1) Buzzer feedback loop (Decision 030 cont.)** — answer-on-device (buzz
  winner answers on their OWN phone, no call-out): `BuzzerHost.broadcastQuestion`
  now ships prompt/options/imageURL; winner gets `isAnswering`, host runs
  `acceptAnswer` / `rejectAnswerAndReopen`. **Device-based rejoin**: `BuzzerClient`
  persists a UUID `deviceID` + last code/name (UserDefaults); `BuzzerHost`
  `seatByDevice` re-seats silently on reconnect (no name re-entry); join code
  stays on the TV for new players; `attemptReconnect` auto-reconnects. **Richer
  feedback**: TV celebrates each buzz/score/miss, every phone sees who buzzed/
  scored/missed + standings (`BuzzerMessage` gained question/answer/result kinds).
  **No-hang**: all-wrong / no-buzz auto-advances; **don't reveal the wrong pick**
  (gives away the answer, esp. 2-option) — 4-option after 3 wrong just moves on,
  2-option hides incorrect options; wording says "Nobody got it right" (not
  "Time's up") when all wrong. **Resume mid-question** works (`replayState`).
  Sim-verified to host UI; **still pending: the 2-device hardware test** (live
  Bonjour pairing/answer/rejoin only exercises on real devices — the gate).
  **(2) Image questions stream** — Picture ID images now reach phones AND the TV
  (`imageURL` plumbed through the buzzer); audited every question TYPE renders in
  TV-hosted night. **(3) Corpus quality** (surgical patches across all 3 artifacts
  — corpus.json / corpus.sqlite / picture.json, source had drifted to ~23.6k so NO
  full regen): composer prompts reworded to "Who composed the score for X" for
  scored media (P31-gated, 965); distractors type-matched via shared specific P31
  (describe/cloze 1,325 + picture.json 3,945) with a `GENERIC_P31` blocklist
  (killed the Arte/Toyota/Ryanair off-type decoys); dropped 543 thin/over-masked
  questions delight couldn't save; **delight pass** (Haiku via Workflow, leak-
  guarded) → **969 rewritten / ~97.6% delightful, 0 answer-in-question leaks**
  (~375 robotic remain, leak-guarded — acceptable floor). **(4) Game Center —
  code-complete** (`GameCenterManager` rewrite): launch auth (presents sign-in
  VC) + access point (hidden in-game) + dashboard + **2 leaderboards**
  (`tidbits.classic.high`, `tidbits.daily.streak`) + **9 achievements** (ids in
  `Achievement` enum; reported from shared `RecordsStore`) + **Challenges** (iOS
  26 listener → launches Classic). **ASC config is the owner task** — fully
  specced field-by-field in `docs/GAME-CENTER-SETUP.md`; **11 brand-matched
  images** (exact app icon, period→mark, 512×512 RGB) in `tools/branding/
  gamecenter/` via `make_leaderboard.py` + `make_achievements.py`. Both iOS+tvOS
  BUILD SUCCEEDED. Versions → Apple **1.5.3 (build 46)**; Android versionName
  **1.5.1** (1.5.2/1.5.3 were Apple-only GC — verify before next Play upload).
  *Left (next slices, unchanged):* **2-device Buzz Night hardware test** (#1);
  **ASC Game Center config** (owner, doc ready); **pass-and-play team scoring**
  for the night; web/Android have no buzzer yet (planned web-room is Phase 2);
  Couch Co-op; Link Wall.
- **2026-06-24** — **Trivia Night → device-agnostic, host-paced local multiplayer
  (Decision 034; supersedes the TV-only buzzer of Decision 030).** Ben: "any device
  could be the host, all other Apple devices join — local multiplayer; redesign the
  host so they can run the game AND play." Chose **host-paced** (host answers, then
  taps Reveal → Next). *State found:* multiplayer was TV-host-only — `BuzzerHost`
  `#if os(tvOS)`, `BuzzerClient` `#if os(iOS)`, race-to-buzz, phones as dumb buzzers.
  *Work done:* **(1) Replaced the whole buzzer stack with a platform-agnostic Core
  layer** (no `#if os` role split): `NightProtocol` (NightMessage: join/welcome/
  roster/night/begin/reveal/answered/finished), `NightTransport` (same Bonjour +
  room-code TLS-PSK, 1 MB frame cap for the night payload), `NightHost` +
  `NightClient` (both compile iOS+tvOS — `NWListener` runs on iOS), and **`LiveNight`**
  — the coordinator that wires the transport to a local `GameEngine`. Deleted the 6
  `Buzzer*` / `BuzzNightView` files; scrubbed "Buzz" everywhere. **(2) Engine made
  host-paceable** (`GameEngine`): `startNight(…, hostPaced:)`, `awaitingReveal` HOLDS
  each reveal behind a "waiting for the host" beat, `onLocalAnswer` reports
  score+correct out, `releaseReveal()` / `goToQuestion()` / `finishExternally()`
  driven by host signals; force-submit-on-reveal so everyone reveals together. Solo
  path untouched (`hostPaced:false`). **(3) Model:** host builds the night once,
  ships plan + full `[Question]` (made `Codable`, incl. `GameMode`/`NightPlan`); every
  device runs its OWN engine + scores itself; host trusts self-reports + aggregates
  standings. **(4) UI** on the universal target: `GamePlayView`/`TVGamePlayView` gained
  an optional `live:` (host Reveal/Next controls + held reveal + live standings;
  joiner waits + follows; nil = solo, unchanged). New `NightLiveContainer` (iOS) +
  `TVNightLiveContainer` (tvOS): join form / lobby (big code) / play / final
  standings. `NightSetupView` gained a Solo/Host toggle; iOS home "Join a Night"
  card; tvOS night hero (Play on TV / Host for others) + header "Join a Night". pbxproj
  surgically updated (removed 6, added 6). **Both iOS + tvOS BUILD SUCCEEDED.**
  Version → Apple **1.6.0 (build 47)**. *State left / gate:* the live Bonjour
  pairing/answer/rejoin is **hardware-only — the 2-device test (Ben) is the gate**
  (same gate as before, new model). web/Android networked = Phase-2 web-room;
  pass-and-play stays their multiplayer. *Left:* team scoring; Couch Co-op; Link Wall.
