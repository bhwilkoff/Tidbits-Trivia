# Project Scratchpad — Tidbits Trivia

> Active snapshot (auto-loaded each session). **For the full state + how to
> build/run/verify each platform + the prioritized backlog, read
> `docs/HANDOFF.md`.** Other refs: `PARITY.md` (feature matrix, source of
> truth), `DECISIONS.md` (the why, 001–025), `docs/QUESTION-QUALITY.md`,
> `docs/ROADMAP.md`, `docs/DATA-CONTRACT.md`. Detailed per-round history is in
> `ARCHIVE.md`.

## Current state (2026-06-20)

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
