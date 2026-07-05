# Windows Parity Tracker

**Goal:** full parity with the Mac app (all consumer tabs + ALL of
Tidbits Live) in the Avalonia/C# Windows app. Source of the gap list:
the parity audit (2026-07-05). Build order = dependency-correct slices.
`[x]` done · `[~]` partial · `[ ]` not started. Each item cites its Mac
source. "Done" = ported/built + headless-PNG + `windows-latest` CI green.
Determinism-critical items (★) must pass golden vectors vs Apple/Kotlin/JS.

Companion: `WINDOWS-DESIGN.md` (binding spec), `WINDOWS-PLAYBOOK.md`
(pipeline), `PARITY.md` (cross-platform matrix).

---

## Slice 0 — Skeleton & pipeline
- [x] 0.1 FluentAvalonia `NavigationView` shell (Play·Records·Create·Live + Settings)
- [x] 0.6 Headless-PNG harness + `windows-latest` CI (build/snapshot/launch)
- [ ] 0.7 Design tokens as `ThemeVariant` dictionaries (cream `0xFBF3E4` + 7 pops, 6-level ramp)
- [ ] 0.8 `chunkyCard`/`ChunkyButtonStyle`/`CompactButtonStyle` as `ControlTheme`s
- [ ] 0.2 `Win32HostInterop` seam (Mica/DWM, taskbar, hotkeys, snap)
- [ ] 0.3 Window chrome: extend-titlebar + Mica + theme follow
- [ ] 0.4 App-nav store + deep-link inbox + Quick-Play memory + presets
- [ ] 0.5 `tidbitstrivia://` + https deep-link registration (needs package identity)

## Slice 1 — Core foundation (`Tidbits.Core`)
- [x] 1.1 `Question` + Closest/Match/Enum/Answered specs
- [x] 1.2 `GameMode` (17 modes + metadata)
- [x] 1.3 `TriviaCategory` (8 categories)
- [ ] 1.4 `Player` (pass-and-play)
- [ ] 1.5 `PlayerRecord` set (GameRecord/AnswerDetail/MissedFact/CalibrationTally/DailyStreak) → EF Core/SQLite
- [x] 1.6 `NightPlan`/`NightRound`/`NightStartMode` + presets (wire-compat; GameMode→string converter)
- [x] 1.14 ★ `SeededRNG` (splitmix64) + `stableSeed` (FNV-1a64)
- [x] 1.15 ★ `DailyPick` (canonical cross-platform daily)
- [x] 2.2 `Scoring.points` (base 100 + speed + streak ×2 cap)
- [x] 1.7 `CorpusDatabase` — JSON-backed over shared assets/corpus.json (no native dep); all query methods; loads 20,318 verified
- [x] 1.8 `JSONQuestionSource` + `PositionalQuestionParser` (one parser, all 8 shapes)
- [x] 1.9 `QuestionProvider` (router + seen-set + night/mix/daily builders; live-gen stubbed)
- [x] 1.10 `DifficultyOverlay` (difficulty.json → Ladder) + `QuestionSources` loader
- [ ] 1.11 `WikipediaClient` (HttpClient REST)
- [ ] 1.12 `TemplateEngine` (question gen; Regex)
- [ ] 1.13 AI generator → Windows stub (isAvailable=false → TemplateEngine)
- [ ] 1.22 `Keychain` → Credential Manager/DPAPI
- [x] 1.23 `Haptics` → no-op stub
- [ ] 1.21 `GameSettings` KV
- [ ] 1.20 `DailyLog` (per-day results, first-completion-wins)
- [x] golden-vector contract test harness (§8.7) — daily parity GREEN vs Apple/Kotlin/JS

## Slice 2 — Consumer vertical
- [x] 2.1 `GameEngine` (all 18 modes, phases, clocks, host-paced, all submit paths) — end-to-end tests GREEN
- [ ] 2.3 `ProgressStats`/DomainProgress/Badges
- [ ] 2.4 `BotOpponent`
- [~] 2.5 Play surface — Quick Play LIVE (starts a real Classic game); Surprise/Customize/Daily/Night/Online-MP pending
- [ ] 2.6 Customize/Quick Play sheets (mode multiselect, category grid, presets)
- [~] 2.7 Game surface — MCQ playing/reveal/finished LIVE + headless-PNG verified; specialty-mode surfaces pending
- [ ] 2.8 Per-mode answer surfaces (picture/numeric/ordering/matching/type/enumerate/stake/sweep)
- [ ] 2.9 Image pipeline (decoded cache + capped HttpClient, sRGB)
- [ ] 2.10 Results recap (score/accuracy/streak/missed-fact + reflection)
- [ ] 2.11 Emoji-grid share
- [ ] 2.12 Four content states on every list/grid
- [ ] 2.13 Records dashboard (R-REC-1: streak/lifetime/recent-3+See-all/knowledge/calibration/bests/review)
- [ ] 2.14 Records drill-ins (game recap, domain, bests)
- [ ] 2.15 Topic Levels + Pie + calibration + badges + avatar re-roll
- [ ] 2.16 Records sign-in banner
- [ ] 2.17 Create (topic → corpus diversify + live-gen fallback)
- [ ] 2.18 Create saved sets
- [ ] 2.19 Settings page
- [ ] 2.20 Trivia Night (solo)
- [ ] 2.21 Versus CPU / Online-MP picker
- [ ] 2.22 Spaced re-asking + day-streak surfacing
- [ ] 2.23 Daily play-once lock + archive
- [ ] 2.24 Async friend duels (DuelStore + inbox)
- [ ] 2.25 Leaderboard read (season/venue board + friends filter + titles)

## Slice 3 — Live networking Core ★
- [ ] 1.18 ★ `FirebaseRTDB` (REST + SSE, anon auth, room codes)
- [ ] 1.16 ★ `PlayerProfile` wire contract (Rating/Streak/Stats/accountKey/venueKey/season/avatarHue)
- [ ] 1.17 `PlayerIdentityStore` (portable identity façade)
- [ ] 3.1 ★ `LiveRoom` wire types (Meta/Pub/Numeric/Team/Answer/Phase)
- [ ] 3.3 `LiveNightHost.score` (per-shape authoritative scoring)
- [ ] 3.2 `LiveHostNet` (networked host publish + SSE roster)
- [ ] 3.4 `LivePlayerClient` (join a hosted room)
- [ ] 3.5 LAN Night stack (optional; RTDB-only acceptable)

## Slice 4 — Host cockpit + projector MVP
- [ ] 3.6 `LiveEvent`/`LiveRound`/`LiveEventStore` model
- [ ] 3.7 Builder shell (two-pane)
- [ ] 3.8 Fill a round 3 ways (corpus/AI/hand)
- [ ] 3.13 Solo preview (no records)
- [ ] 3.14 `LiveHostSession` (authoritative host model + currentPub)
- [ ] 3.15 Cockpit UI (stage + scoreboard; replaces window)
- [ ] 3.16 Reveal-on-command + auto-score
- [ ] 3.17 Show-nav (reveal/next/skip/prev/jump/hold)
- [ ] 3.18 Manual score override
- [ ] 3.19 Networked join strip (QR + code)
- [ ] 3.36 Projector window (chromeless, 2nd monitor, hot-plug safe)
- [ ] 3.37 Projector states + cross-fades + viewport-fraction text
- [ ] 3.38 Reveal choreography
- [ ] 3.39 Animated climbing leaderboard (unified phone+paper)
- [ ] 3.40 Round-intro cards
- [ ] 3.41 Winner celebration
- [ ] 3.42 Big-screen chrome (format/difficulty/countdown/QR/story)
- [ ] 3.44 Printable/PDF fallback
- [ ] 3.45 Networked Trivia-Night host from Windows

## Slice 5 — Wave A authoring depth
- [ ] 3.9 Drag-to-reorder rounds/questions
- [ ] 3.10 Difficulty/category balance meter
- [ ] 3.11 Per-round timer/wager/speed/host-note
- [ ] 3.12 CSV import
- [ ] 3.20 Live answer distribution/tally
- [ ] 3.23 Live countdown controls (+30/+15/clear)

## Slice 6 — Wave C submission & scoring
- [ ] 3.21 Free-text review + spelling leniency
- [ ] 3.22 Answer-lock (manual + auto-timer)
- [ ] 3.24 Tie-break engine (numeric + brains-only)
- [ ] 3.25 Team merge
- [ ] 3.26 Name/answer moderation gate
- [ ] 3.27 Focus/cheat flag
- [ ] 3.28 CSV export (unified standings)
- [ ] 3.29 In-room paper teams (hybrid)

## Slice 7 — Wave B AV & show (Windows audio/video backend)
- [ ] 3.30 SFX/stinger board (NAudio/CSCore)
- [ ] 3.31 PA output-device routing (WASAPI)
- [ ] 3.32 Audio round (BYO clips)
- [ ] 3.33 Looping music beds
- [ ] 3.34 Video questions (LibVLCSharp/media element)
- [ ] 3.35 Speed-tiered scoring (verify)

## Slice 8 — Waves D + E (venue + moat)
- [ ] 3.46 Recurring-series scheduling
- [ ] 3.47 Sponsor kit (big-screen footer)
- [ ] 3.48 Lead capture QR
- [ ] 3.49 White-label brand accent
- [ ] 3.50 ★ Standings write (season/venue)
- [ ] 3.51 Leaderboard read + defendable titles
- [ ] 3.52 Social graph (add players you played with)

## Deferred (⏳/🔒 — not built on Mac either; carry as honest gaps)
Named show-formats (Jeopardy/Feud/Wheel), multi-venue org hierarchy,
OBS/streaming out, analytics dashboard, venue directory, paywall/pricing.
Apple-only dropped: GameKit/Game Center (→ shared RTDB leaderboard),
Apple Sign In (→ web OAuth or drop), FoundationModels AI (→ TemplateEngine).

---

**Progress:** Slice 0 skeleton + Slice 1 models (1.1–1.3) done. Next:
finish Slice 1 foundation (RNG/DailyPick/Scoring → corpus → persistence →
QuestionProvider + golden test), then Slice 2 consumer vertical.
