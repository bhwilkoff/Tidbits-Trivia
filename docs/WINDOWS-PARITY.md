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
- [~] 0.7 Design tokens — brand-coral accent set (#FF5C35); full palette dictionaries + 6-level ramp pending
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
- [x] 1.5 `PlayerRecord` set (GameRecord/AnswerDetail/MissedFact/CalibrationTally/DailyStreak) — JSON-backed (SQLite swap possible later)
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
- [x] 1.21 `GameSettings` KV (JSON-backed) + RecordsStore.ResetAll
- [ ] 1.20 `DailyLog` (per-day results, first-completion-wins)
- [x] golden-vector contract test harness (§8.7) — daily parity GREEN vs Apple/Kotlin/JS

## Slice 2 — Consumer vertical
- [x] 2.1 `GameEngine` (all 18 modes, phases, clocks, host-paced, all submit paths) — end-to-end tests GREEN
- [x] 2.3 `ProgressStats`/DomainProgress/Badges (ProgressMath levels + wedges + LevelableBadge/BadgeMath) — pure port
- [ ] 2.4 `BotOpponent`
- [~] 2.5 Play/Home surface — Quick Play hero + Daily + category picker + mode grid (all MCQ modes reachable); Surprise/Night/Online-MP pending
- [~] 2.6 Customize — category picker + mode grid on Home; mode multiselect (mix) + saved presets pending
- [~] 2.7 Game surface — MCQ playing/reveal/finished LIVE + headless-PNG verified; specialty-mode surfaces pending
- [~] 2.8 Per-mode answer surfaces — ALL non-picture shapes built + PNG-verified + play-through tests GREEN: numeric slider (Closest Call), free-text (Name It), Stake (chip budget + dimmed MCQ until committed), In Order (▲/▼ reorder), Match Up (tap key→value chip), Name as Many (type-against-clock, chips fill). Sweep/Ladder/OddOneOut/ThisOrThat ride MCQ. Fixed a latent bug: the answer surface was rebuilt on every 100ms Remaining tick (would drop typing / interrupt a slider drag) — now rebuilds only on phase/question/reorder change (regression test). Only Picture ID pending (rides image pipeline 2.9)
- [ ] 2.9 Image pipeline (decoded cache + capped HttpClient, sRGB)
- [x] 2.10 Results recap — coral scorecard (headline/score/mode·category) + stat row (correct/accuracy/best-streak) + spoiler-free grid + "Tidbits to remember" missed-fact cards + Play Again (hidden for Daily) + Done; PNG-verified
- [x] 2.11 Emoji-grid share — `ShareText` (Core, byte-faithful web twin: 🟢🔴⚫️ grid + ▰▱ meter + streak/best-run fallback + play link) → clipboard (Windows native idiom); 3 golden tests GREEN
- [ ] 2.12 Four content states on every list/grid
- [~] 2.13 Records dashboard (R-REC-1) — streak+lifetime card, recent 3 + See-all, per-domain knowledge bars, review count; PNG-verified. Drill-ins/calibration/badges/pie pending
- [ ] 2.14 Records drill-ins (game recap, domain, bests)
- [ ] 2.15 Topic Levels + Pie + calibration + badges + avatar re-roll
- [ ] 2.16 Records sign-in banner
- [x] 2.17 Create — topic → corpus retrieval + diversify → play the set (live-gen fallback stubbed); PNG-verified
- [ ] 2.18 Create saved sets
- [x] 2.19 Settings page — review toggle + reset seen/records + about/version; PNG-verified
- [ ] 2.20 Trivia Night (solo)
- [ ] 2.21 Versus CPU / Online-MP picker
- [ ] 2.22 Spaced re-asking + day-streak surfacing
- [ ] 2.23 Daily play-once lock + archive
- [ ] 2.24 Async friend duels (DuelStore + inbox)
- [ ] 2.25 Leaderboard read (season/venue board + friends filter + titles)

## Slice 3 — Live networking Core ★
- [x] 1.18 ★ `FirebaseRTDB` (REST + SSE, anon auth, room codes) — LIVE smoke GREEN vs real project (anon→put→get→delete); offline unit tests GREEN. DPAPI token encryption = follow-up 1.22
- [x] 1.16 ★ `PlayerProfile`/PlayerIdentity contract + helpers (accountKey SHA256, venueKey, season, avatarHue djb2, Elo, streak, merge, LeaderboardRow) — 7 golden tests GREEN
- [ ] 1.17 `PlayerIdentityStore` (portable identity façade)
- [x] 3.1 ★ `LiveRoom` wire types (Meta/Pub/Numeric/Team/Answer/Phase) — keys match web twin, null-omitted; wire tests GREEN
- [x] 3.3 `LiveScoring` (per-shape authoritative scoring: MCQ/numeric/ordering/matching/type/enumerate) — 6 tests GREEN
- [x] 3.2 `LiveHostNet` (open room + publish + setState/setScore + host-plays + self-reconnecting SSE roster/scores/answers, lock-guarded) — builds
- [x] 3.4 `LivePlayerClient` (join, typed submits, SSE watch pub/meta/score, coplayers) — LIVE END-TO-END host↔join↔score GREEN
- [ ] 3.5 LAN Night stack (optional; RTDB-only acceptable)

## Slice 4 — Host cockpit + projector MVP
- [ ] 3.6 `LiveEvent`/`LiveRound`/`LiveEventStore` model
- [ ] 3.7 Builder shell (two-pane)
- [ ] 3.8 Fill a round 3 ways (corpus/AI/hand)
- [ ] 3.13 Solo preview (no records)
- [~] 3.14 host session — LiveNightHost (authoritative model + currentPub builder, all shapes) done for Trivia Night; full Tidbits Live cockpit features pending
- [~] 3.15 Cockpit UI — code/roster header + question + options + standings + reveal/next/lock/end; LIVE PNG vs real room. Projector + polish pending
- [x] 3.16 Reveal-on-command + auto-score (LiveNightHost.Reveal→AutoScore, speed bonus)
- [ ] 3.17 Show-nav (reveal/next/skip/prev/jump/hold)
- [ ] 3.18 Manual score override
- [x] 3.19 Networked join strip (QR + code + tidbitstrivia.com/live) — QRCoder pure-C# PNG; LIVE cockpit PNG shows scannable QR
- [x] 3.36 Projector window (chromeless WindowDecorations.None, 2nd-monitor via Screens API, hot-plug re-place on Screens.Changed) — 'Show on projector' in cockpit
- [x] 3.37 Projector states (lobby QR / question+options / reveal answer / final standings) + Viewbox scale-to-fit text — LIVE PNG verified
- [ ] 3.38 Reveal choreography
- [ ] 3.39 Animated climbing leaderboard (unified phone+paper)
- [ ] 3.40 Round-intro cards
- [ ] 3.41 Winner celebration
- [ ] 3.42 Big-screen chrome (format/difficulty/countdown/QR/story)
- [ ] 3.44 Printable/PDF fallback
- [x] 3.45 Networked Trivia-Night host from Windows (LiveNightHost: openRoom/start/reveal+auto-score/next/end) — LIVE cockpit PNG vs real room

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

**Progress:** Slices 0–1 foundation, the Live networking Core (Slice 3), and a
cockpit/projector MVP (Slice 4) are largely done. Consumer vertical (Slice 2) is
filling in: game loop now ends in a full results recap + spoiler-free share
(2.10/2.11). Next Slice 2 gaps: per-mode answer surfaces (2.8), image pipeline
(2.9), records drill-ins/badges (2.14/2.15), Trivia Night solo (2.20), daily
lock + archive (2.23).
