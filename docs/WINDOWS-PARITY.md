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

## Real-hardware audit (2026-08-31) — a Windows machine joined the bench

The Windows app is now driven on a real Windows 10 Pro box over SSH
(`docs/WINDOWS-DEVBOX-SETUP.md`), not only through headless renders. Iteration
moved there; **`windows-latest` CI is still the gate** (Decision 045 unchanged).

Three parity gaps that every previous audit missed, because each needed either a
real machine or a measurement rather than a checklist:

- **The paywall sold two auto-renewing subscriptions without disclosing renewal**,
  and carried no Terms of Use or Privacy Policy link anywhere in the binary. Store
  Policy 10.8.6 / 10.5.1. Apple's equivalent block exists because of a real 2.1(b)
  rejection. Fixed + gated (`ClubPaywallTests`).
- **The window opened wider than the display.** It asks for 1180x760, the Mac's
  numbers — but AppKit shrinks a window that does not fit and Avalonia does not.
  On a 1366x768 laptop, the most common Windows 10 resolution, the bottom of every
  screen was cut off. Fixed + gated (`WindowFitTest`).
- **Create had no topic suggestions** ("Need a spark?"). An empty topic box is a
  blank-page problem and this is the one screen where the player supplies the
  subject.

Confirmed AT parity by reading both codebases (`tools/mac_win_parity.py`): all 19
game modes, Records (review list, drill-ins, badges, calibration), Settings, the
Live cockpit, the Daily archive, Wikipedia/CC BY-SA attribution.

**Windows hosts Tidbits Live and every platform joins it** — verified on the wire
(RTDB `live/{code}`) and the glass (a screenshot per device): iPad, iPhone, Pixel,
Fire TV, Android TV and web all on the same question. Windows also JOINS a
Mac-hosted room, a direction nothing could previously ask for — every route into
`StartHosting`/join was a Click handler, so `tools/hook_coverage.py` counted 12
surfaces the harness could not reach at all. Now 0.

---

## Status (2026-07-18) — SHIPPED to the Microsoft Store (in certification)

**Windows is a fully supported channel (Decision 046).** First Store submission is
**in certification** — Store ID `9NRKS9LDRCWC`, MSIX v1.6.45, all 7 Partner Center
sections Complete, publishing set to auto-go-live on cert pass. **626 tests green**
on `windows-latest`. The one-time bootstrap is DONE; every future ship is
`gh workflow run windows-store.yml -f submit=true -f commit=true` — see
`WINDOWS-STORE-SUBMISSION.md` (incl. the two solved first-submission blockers:
runFullTrust justification + the Xbox-services "Test" that clears the
access-policies banner).

**208 tests green** on `windows-latest`. The previous status said the remainder
"needs a real Windows box (this dev box is an arm64 Mac)". That framing is
retired: **`windows-latest` IS the Windows box** (Decision 045), and it is now
drivable from the CLI — `gh workflow run windows-repl.yml` → `gh run download`
→ `Read` the PNGs, ~2-4 min. There is no free Windows VM to find; CI is the
answer, permanently.

Closed this pass:

- **0.2 Win32 interop** — `Win32HostInterop`: taskbar progress (ITaskbarList3)
  + global hotkeys (RegisterHotKey). The round-indicator MAPPING is a pure
  function, so the product behaviour is tested off Windows and only the P/Invoke
  is Windows-gated. **Snap Layouts needed no code** — free with the standard
  maximize button, which MainWindow uses.
- **1.22 DPAPI** — the old note ("no durable credentials yet") was **wrong**:
  FirebaseRtdb persists the Firebase *refresh* token, and FileTokenStore wrote it
  in CLEARTEXT. Now DPAPI-protected (CurrentUser + entropy), with legacy
  cleartext migrated and deleted on first read.
- **0.5 deep-link registration** — `tidbitstrivia://` registered via the new
  MSIX package identity. (The https twin is deferred BY SEQUENCE: appUriHandler
  needs a `.well-known` naming the PackageFamilyName, which doesn't exist until
  Partner Center assigns the identity — see WINDOWS-STORE-SUBMISSION §6.)
- **Observability** — input simulation (real clicks/typing drive the app, not
  just render it) + a Windows-captured visual-regression gate. The gate's first
  real run caught a channel-order bug **in the gate itself**.
- **MSIX + Store** — packaging and a CLI submission workflow
  (`windows-store.yml`, `docs/WINDOWS-STORE-SUBMISSION.md`).

Still open, with HONEST reasons:

- **3.34 video picture [~]** — the version-independent pipeline (LibVLC RV32
  frames → `VideoFrameSink` → `VideoSurface`) is BUILT and verified end-to-end
  with synthetic frames, incl. aspect-fit letterboxing. What is NOT yet proven is
  LibVLC actually invoking the callbacks with a real video file; that needs a
  video fixture on Windows CI. The audio of a video already plays (3.32 path).
- **3.5 LAN night** — explicitly optional (RTDB path is acceptable). Not planned.
- **Store bootstrap** — ✅ DONE (2026-07-18). First submission is in certification
  (v1.6.45); Entra app + Manager role + 4 secrets + name reservation + first manual
  submission (age ratings) all complete. Future ships are the §2 CLI command. See
  WINDOWS-STORE-SUBMISSION §0.

---

## Slice 0 — Skeleton & pipeline
- [x] 0.1 FluentAvalonia `NavigationView` shell (Play·Records·Create·Live + Settings)
- [x] 0.6 Headless-PNG harness + `windows-latest` CI (build/snapshot/launch)
- [~] 0.7 Design tokens — brand-coral accent set (#FF5C35); **6-level type ramp SHIPPED** (App.axaml view-heading/section-header/body-strong/body/caption/tabular, adopted across all main views); full light/dark palette dictionaries still pending
- [~] 0.8 Design-token styles — reusable Border.card (chunky card), Button.chunky, Button.compact defined once in App.axaml (WINDOWS-DESIGN §7.1) atop the existing BrandPrimary/BrandAccent tokens + FluentAvalonia coral accent (.accent). Adopted Classes="card" in Records (render-verified identical). Broad adoption across all views is a mechanical follow-up sweep
- [x] 0.2 `Win32HostInterop` seam — taskbar progress (ITaskbarList3) + global hotkeys (RegisterHotKey) behind ONE Windows-guarded helper Core never references; the round-indicator mapping is a pure function (clock outranks team count; expired clock = Error not a misleading full bar; all-answered = the reveal cue; out-of-range clamps) so it is tested off Windows, with the P/Invoke verified on windows-latest. Mica already shipped (0.3). **Snap Layouts need no code** — free with the standard maximize button (MainWindow uses standard decorations); the WM_NCHITTEST fix only matters under custom chrome
- [~] 0.3 Window chrome — Mica backdrop applied (MainWindow TransparencyLevelHint="Mica,AcrylicBlur,None"; the Win11 material, graceful fallback to opaque on Win10/headless). FluentAvalonia's opaque control surfaces keep content readable (avoided the risky global Background=Transparent). Extend-titlebar + theme-follow still pending; Mica visual is windows-latest-CI-verified (headless ignores the hint; 114/114 shell tests still GREEN)
- [~] 0.4 Deep-link inbox + routing — `DeepLink.Parse` maps the custom scheme (tidbitstrivia://live/2NRE, ://daily, ://leaderboard, …) AND the https twin to a nav target (+ sanitized 4-char room code); Program captures a launch URL, MainWindow.Route consumes it on Loaded to select the tab (the inbox pattern — external entry never touches nav directly). Parser + nav-tag unit-tested (12+6 cases). **Quick-Play memory SHIPPED** (GameSettings.LastMode/LastCategoryId; Quick Play replays the last single mode+cat) + **presets SHIPPED** (2.6)
- [~] 0.5 deep-link registration — `tidbitstrivia://` REGISTERED via the MSIX package identity (AppxManifest windows.protocol); parser + inbox already existed (0.4). The **https twin is deferred by sequence, not oversight**: windows.appUriHandler needs /.well-known/windows-app-web-link naming the PackageFamilyName, and the PFN is Name + a hash of the REAL Partner Center Publisher — it does not exist until the Store identity is assigned. A guessed PFN fails silently. See WINDOWS-STORE-SUBMISSION §6

## Slice 1 — Core foundation (`Tidbits.Core`)
- [x] 1.1 `Question` + Closest/Match/Enum/Answered specs
- [x] 1.2 `GameMode` (17 modes + metadata)
- [x] 1.3 `TriviaCategory` (8 categories)
- [x] 1.4 `Player` / Pass & Play — a "Pass & Play" launcher on the Play landing → PartyView: enter 2–4 names, everyone plays the SAME shared question set (drawn once, replayed per player via StartCustom), a "Pass the device to {name}" hand-off between turns, then a ranked scoreboard (winner in coral). Matches don't write records. Setup PNG-verified
- [x] 1.5 `PlayerRecord` set (GameRecord/AnswerDetail/MissedFact/CalibrationTally/DailyStreak) — JSON-backed (SQLite swap possible later)
- [x] 1.6 `NightPlan`/`NightRound`/`NightStartMode` + presets (wire-compat; GameMode→string converter)
- [x] 1.14 ★ `SeededRNG` (splitmix64) + `stableSeed` (FNV-1a64)
- [x] 1.15 ★ `DailyPick` (canonical cross-platform daily)
- [x] 2.2 `Scoring.points` (base 100 + speed + streak ×2 cap)
- [x] 1.7 `CorpusDatabase` — JSON-backed over shared assets/corpus.json (no native dep); all query methods; loads 20,318 verified
- [x] 1.8 `JSONQuestionSource` + `PositionalQuestionParser` (one parser, all 8 shapes)
- [x] 1.9 `QuestionProvider` (router + seen-set + night/mix/daily builders; live-gen stubbed)
- [x] 1.10 `DifficultyOverlay` (difficulty.json → Ladder) + `QuestionSources` loader
- [x] 1.11 `WikipediaClient` — read-only client for the open Wikipedia REST (page/summary) + Action (search) APIs over one capped HttpClient, no key/auth, UA header, concurrent Summaries(titles) dropping failures. Parse/ParseSearch extracted static so decoding is unit-tested offline (summary fields + PageUrl/ImageUrl, search titles, malformed→empty). Foundation for the TemplateEngine (1.12) live-gen port
- [x] 1.12 `TemplateEngine` — faithful port of the ~380-line NLP filter (the moat): describe & cloze shapes, fame-floor + richness gates, type-key/person detection, type-matched distractors, clue cleaning, answer-leak + foreign-script rejection, seeded (splitmix64) determinism. Wired into QuestionProvider.LiveQuestions; offline tests + a naturally-reading sample Q
- [x] 1.13 AI generator (Windows path) — no on-device model, so TemplateEngine IS the generation path (LiveQuestions runs it), matching the Apple fallback
- [x] 1.22 `Keychain` → DPAPI — `DpapiTokenStore` on the existing ITokenStore seam (Core stays OS-agnostic). The prior "no durable credentials yet" note was WRONG: FirebaseRtdb persists the Firebase refresh token and FileTokenStore wrote it as PLAINTEXT to LocalApplicationData — a long-lived credential sufficient to assume a player identity. Now DPAPI CurrentUser + app entropy; legacy cleartext migrated then deleted; undecryptable ciphertext (restored backup/roamed profile) drops and re-auths instead of wedging sign-in. Falls back to the file store off Windows
- [x] 1.23 `Haptics` → no-op stub
- [x] 1.21 `GameSettings` KV (JSON-backed) + RecordsStore.ResetAll
- [x] 1.20 `DailyLog` (per-day results, first-completion-wins; JSON-backed; a replay can't overwrite a day's record) — unit test GREEN
- [x] golden-vector contract test harness (§8.7) — daily parity GREEN vs Apple/Kotlin/JS

## Slice 2 — Consumer vertical
- [x] 2.1 `GameEngine` (all 18 modes, phases, clocks, host-paced, all submit paths) — end-to-end tests GREEN
- [x] 2.3 `ProgressStats`/DomainProgress/Badges (ProgressMath levels + wedges + LevelableBadge/BadgeMath) — pure port
- [x] 2.4 `BotOpponent` — faithful C# twin of js/bots.js (Rookie/Regular/Ace + The House adapting to player accuracy; category skill, difficulty adj, ~5% freeze, log-normal timing, Box–Muller; VsMatch begin/commit/standings, seedable RNG). Seeded tests prove the freeze rate (~5%) + skill (~85% for Ace) + no double-scoring on a repeated reveal
- [~] 2.5 Play/Home surface — Quick Play hero (now replays last mode+cat via GameSettings memory, 0.4) + **Surprise Me (random mode+cat)** + Daily + category picker + mode grid + **Online Quick Match** (2.21b)
- [x] 2.6 Customize — a Customize dialog (multi-mode + category) plays a Custom Mix (engine.StartMix) or saves a named **preset**; PresetsStore (upsert-by-name, cap 5) + a "Your mixes" list on the Play landing. Unit + render verified
- [~] 2.7 Game surface — MCQ playing/reveal/finished LIVE + headless-PNG verified; specialty-mode surfaces pending
- [x] 2.8 Per-mode answer surfaces — ALL shapes built + PNG-verified + play-through tests GREEN: numeric slider (Closest Call), free-text (Name It), Stake (chip budget + dimmed MCQ until committed), In Order (▲/▼ reorder), Match Up (tap key→value chip), Name as Many (type-against-clock, chips fill), Picture ID (image frame over 4 options). Sweep/Ladder/OddOneOut/ThisOrThat ride MCQ. Fixed a latent bug: the answer surface was rebuilt on every 100ms Remaining tick (would drop typing / interrupt a slider drag) — now rebuilds only on phase/question/reorder change (regression test). All 15 consumer modes offered on the Play tab
- [x] 2.9 Image pipeline — `ImageCache` (decoded-Bitmap cache over one capped HttpClient, per-URL inflight dedupe, bounded to 64, null-not-throw on failure); Avalonia's Skia decode is display-ready (no macOS grayscale-white-box trap). Powers Picture ID (loading/unavailable fallback); decode+cache+dedupe tests GREEN. Twin of the macOS ImagePipeline
- [x] 2.10 Results recap — coral scorecard (headline/score/mode·category) + stat row (correct/accuracy/best-streak) + spoiler-free grid + "Tidbits to remember" missed-fact cards + Play Again (hidden for Daily) + Done; PNG-verified
- [x] 2.11 Emoji-grid share — `ShareText` (Core, byte-faithful web twin: 🟢🔴⚫️ grid + ▰▱ meter + streak/best-run fallback + play link) → clipboard (Windows native idiom); 3 golden tests GREEN
- [x] 2.12 Four content states — audited across every data surface: Records ("No games yet" empty), Leaderboard ("Loading standings…" + "No standings yet" + error→empty), Create (now an indeterminate ProgressBar during generation + "No questions found" error + saved-sets hidden when empty), Live saved-events / Daily archive / join wrap all guard empty. Offline: consumer runs off the bundled corpus; Live shows a connection error. Added the missing Create loading indicator this pass
- [~] 2.13 Records dashboard (R-REC-1) — streak+lifetime card, recent 3 + See-all, per-domain knowledge bars, review count; PNG-verified. Drill-ins/calibration/badges/pie pending
- [~] 2.14 Records drill-ins — "See all N games" opens a native FAContentDialog listing every game (header · score · green/red answer-dot strip); tapping a game drills into a per-question recap (dot · prompt · answer) with a back nav. VM exposes full GameDetail/AnswerDot; list + recap PNG-verified. **Domain drill-in SHIPPED** (tap a knowledge bar → a native dialog splitting that domain's per-question history into Missed / Got right, dedup by qid; RecordsViewModel.DomainAnswers over AnswerDetail.CategoryId — web openDomain parity; unit-tested). **Personal-best drill-in SHIPPED** (a 'Personal bests' section: one row per mode played w/ best score + play count, tap → that mode's attempts reusing the See-all list/recap; web openBests parity; unit + render verified). Records drill-ins now COMPLETE
- [~] 2.15 Topic Levels (per-domain XP bars) + **Badges** (levelable milestones via BadgeMath, earned-only, coral tier-number icon per R-ICON-1) + **Stake calibration** (per-tier hit rate) + **The Pie** (7-wedge Trivial-Pursuit breadth circle drawn in Avalonia geometry — each domain's wedge fills in its category color when mastered ≥15 correct/≥60% acc, "N of 7 domains mastered"; test masters Science → wedge fills, PNG) all shipped in the Records dashboard. Avatar re-roll shipped (Settings Profile: hue-colored avatar + Shuffle, on the new PlayerIdentityStore 1.17); liveNights=0 until live-night records are tracked locally
- [x] 2.16 Records profile banner — a card atop Records shows who you're playing as (deterministic hue avatar + "Playing as {name}") and where records live ("saved on this device · edit your profile in Settings"), reading from the PlayerIdentityStore. Honest for Windows: no cross-device account sync yet, so it surfaces identity + device-local storage rather than a fake "sign in". Render test + PNG
- [x] 2.17 Create — topic → corpus retrieval + diversify → play the set (live-gen fallback stubbed); PNG-verified
- [x] 2.18 Create saved sets — `SavedSetsStore` (Core, JSON-backed, newest-first, capped 30, questions serialized intact); after generating, "Save this set" stores it; a "Saved sets" list on the Create landing replays or removes each. Round-trip test + PNG-verified
- [x] 2.19 Settings page — review toggle + reset seen/records + about/version; PNG-verified
- [x] 2.20 Trivia Night (solo) — 3 preset cards (Quick/Pub/The Works) on the Play landing → a self-paced multi-round night off the shape-routing engine; each round opens with a centered interstitial ("ROUND n OF m · title · k questions · Start round"), every shape plays through to the results recap. Full-night play-through test GREEN (all 3 rounds, every question answered). Networked host = Slice 4
- [~] 2.21 Versus CPU — a "Versus CPU" section on the Play landing (Rookie/Regular/Ace/The House, each labeled CPU); starts a Classic match with a live "YOU vs {bot} · CPU" score strip over the game (VersusViewModel drives VsMatch off the engine phases — resolve on each question, commit on reveal), result line on finish, rematch via Play Again. Matches don't write records (parity rule). PNG-verified. **Online Quick Match (real players) SHIPPED** (2.21b): QuickMatchClient over the shared Firebase queue/rooms wire (ETag-CAS claim-or-create, trigger-then-refetch SSE watch, leader publishes the shared set, best score wins) + QuickMatchViewModel state machine + QuickMatchView (searching/playing/result) + a "Quick Match" entry on Play. Wire/claim/result/round-trip/opponent unit-tested; searching screen PNG. **Live 2-player round-trip is 2-device-gated** (needs a second client) like all networked features
- [x] 2.22 Spaced re-asking + day-streak surfacing — due missed facts (RecordsStore.DueReview) woven into MCQ games via engine.Start(review:), opt-out via the Settings toggle, skips Daily + non-MCQ, resolves on a correct answer (end-to-end test). Results recap now surfaces the **day streak** (orange count card + "your best ever!" when Current==Best≥2), read from RecordsStore.Streak after the record write; PNG-verified after a Daily
- [x] 2.23 Daily play-once lock + archive — the Play landing shows today's Daily as a coral hero (play-once; flips to a done card with score once completed) plus a "Previous Tidbits" archive of the last 14 days; unplayed past days are playable via the deterministic day-key seed and never bump the streak (RecordsStore only bumps when day==today). DailyLog records first-completion-wins. PNG-verified
- [x] 2.24 Async friend duels — COMPLETE: DuelStore Core (wire types byte-keyed to js/duels.js, Compact/QuestionsOf, Classify state machine, capped local tracking) + FirebaseRtdb methods (Challenge+invite, Submit own slot, Inbox, Accept, Mine); DuelsUi panel (challenge-a-friend, inbox with Accept, color-coded my-duels with Play); wired from the Leaderboard "⚔ Duels" button over a shared anon-authed GameData.Rtdb — challenge a friend (6-Q set), accept invites, play the frozen set → submit Correct as the score. Offline tests + PNG. Live round-trip 2-device gated like all networked Live features
- [~] 2.25 Leaderboard read — `LeaderboardApi` (Core) reads the STATIC data/leaderboard/ JSON (index → latest season → _overall + per-venue, never RTDB; cache-no-cache); a top-level "Leaderboard" nav item → LeaderboardView renders season overall + each venue (top 25), CHAMPION on #1 and the signed-in player's row highlighted (defendable titles). Empty-state until real live nights end. Parse tests (fake handler) + champion/you PNG. Friends filter needs the friend store (pending)

## Slice 3 — Live networking Core ★
- [x] 1.18 ★ `FirebaseRTDB` (REST + SSE, anon auth, room codes) — LIVE smoke GREEN vs real project (anon→put→get→delete); offline unit tests GREEN. DPAPI token encryption = follow-up 1.22
- [x] 1.16 ★ `PlayerProfile`/PlayerIdentity contract + helpers (accountKey SHA256, venueKey, season, avatarHue djb2, Elo, streak, merge, LeaderboardRow) — 7 golden tests GREEN
- [x] 1.17 `PlayerIdentityStore` — the local portable-identity façade: a persisted profile (display name + deterministic avatar seed), Rename (trim/cap-24) + RerollAvatar; AvatarHue via the shared djb2 PlayerIdentity.AvatarHue. Wired into GameData. Sync/sign-in layer on top later. Unit-tested (rename/reroll/persist/hue)
- [x] 3.1 ★ `LiveRoom` wire types (Meta/Pub/Numeric/Team/Answer/Phase) — keys match web twin, null-omitted; wire tests GREEN
- [x] 3.3 `LiveScoring` (per-shape authoritative scoring: MCQ/numeric/ordering/matching/type/enumerate) — 6 tests GREEN
- [x] 3.2 `LiveHostNet` (open room + publish + setState/setScore + host-plays + self-reconnecting SSE roster/scores/answers, lock-guarded) — builds
- [x] 3.4 `LivePlayerClient` (join, typed submits, SSE watch pub/meta/score, coplayers) — LIVE END-TO-END host↔join↔score GREEN. **Wave A join display added:** a live coral countdown (ticks off Pub.Deadline, turns red ≤5s), and on reveal the correct-answer card + the host's "story behind the answer". VM guard test (null-safe before a question); live values from the SSE pub (gated)
- [ ] 3.5 LAN Night stack (optional; RTDB-only acceptable)

## Slice 4 — Host cockpit + projector MVP
- [x] KB Keyboard cockpit (WINDOWS-DESIGN "keyboard cockpit") — the host runs the show from the keyboard: Space/Enter/→ = Reveal then Next, ← = Back, ↓/S = Skip, L = Lock. Pure CockpitKeymap.Resolve (unit-tested across keys × reveal state); the cockpit tunnels KeyDown so show keys beat button focus
- [x] 3.6 `LiveEvent` + `LiveEventStore` — an authored event = a named list of rounds (reusing NightRound kind+count); JSON-backed store (upsert by id, newest-first, persists); `ToPlan()` converts an event straight to a NightPlan for the host. Convert + store round-trip test
- [x] 3.7 Builder — the Live setup gains a "build a custom event" section: name + add rounds (mode picker × count), a live rounds list (remove each), then Host this event or Save event; saved events list with Host/delete. Single-column (not the Mac two-pane) but fully composes + hosts + persists. Drag-reorder shipped as 3.63; per-round depth/timer/points and per-question overrides shipped as 3.55–3.60 (row closed 2026-09-09; it had read "pending" for weeks after both landed)
- [x] 3.8 Fill a round 3 ways — corpus (Generate from 20k), AI/live (WikipediaClient + TemplateEngine any-topic), hand (CSV import) all in Create
- [x] 3.13 Solo preview — a "Preview solo" button in the event builder plays the composed event through the shared solo-night engine (StartNight, host-paced off) with records:null (no records written), so the host can vet the questions before hosting. Authored-event play-through test GREEN (both rounds run to Finished)
- [~] 3.14 host session — LiveNightHost (authoritative model + currentPub builder, all shapes) done for Trivia Night; setup now exposes host options (category picker, speed-bonus toggle, "I'll play too" + team name — set on the host before Start; PNG-verified). Full authored-event cockpit features pending
- [~] 3.15 Cockpit UI — code/roster header + question + options + standings + reveal/next/lock/end; LIVE PNG vs real room. Projector + polish pending
- [x] 3.16 Reveal-on-command + auto-score (LiveNightHost.Reveal→AutoScore, speed bonus)
- [~] 3.17 Show-nav — reveal/next (existing) + Skip (advance without revealing/scoring) + Back (return to the previous question, unrevealed) added to LiveNightHost + cockpit controls (Back disabled at q1). Jump/hold pending. Guard/wiring tests GREEN; live skip↔back verified in the gated smoke path
- [x] 3.18 Manual score override — per-team −/+ buttons in the cockpit standings (LiveNightHost.AdjustScore → Net.SetScore, clamped ≥0); the team uid rides the button Tag
- [x] 3.19 Networked join strip (QR + code + tidbitstrivia.com/live) — QRCoder pure-C# PNG; LIVE cockpit PNG shows scannable QR
- [x] 3.36 Projector window (chromeless WindowDecorations.None, 2nd-monitor via Screens API, hot-plug re-place on Screens.Changed) — 'Show on projector' in cockpit
- [x] 3.37 Projector states (lobby QR / question+options / reveal answer / final standings) + Viewbox scale-to-fit text — LIVE PNG verified
- [x] 3.38 Reveal choreography — on the big screen, revealing the answer lights the correct option green (bold, dark-on-green) while the rest dim to 40%, so the room instantly reads the answer (LiveHostViewModel.RevealCorrectIndex drives a code-behind-built option list). VM flag tested; visual on windows-latest CI. Projector show-flow now COMPLETE (round-intro + reveal + standings-hold + wager + countdown + winner)
- [x] 3.39 Climbing leaderboard (big-screen standings hold) — a cockpit "Standings on big screen" toggle parks the current ranked standings on the projector between rounds (ModeratedStandings → RankedStandings with 1-based rank + gold leader accent, phone+paper teams unified); the question view yields while held. Hold-toggle + ranked-projection tests
- [x] 3.40 Round-intro moment — the projector shows a brand-colored "NEW ROUND" pill above the round title on the first question of each round (LiveHostViewModel.ShowRoundIntro = first-in-round - [ ] 3.40 Round-intro cards- [ ] 3.40 Round-intro cards not revealed), giving the room a clear round-boundary beat. VM flag tested (off before a live round); big-screen look verified via windows-latest CI launch
- [~] 3.41 Winner celebration — the projector's final-standings screen leads with a green "{winner} wins the night" banner (top of the ordered standings). Confetti/animation polish pending
- [~] 3.42 Big-screen chrome — the projector question screen now shows the round title + "Question X of Y · N players" chrome and a large live coral countdown (ticks off Pub.Deadline via a 1s DispatcherTimer). **Story-on-reveal (the fact behind the answer) + a difficulty band in the chrome SHIPPED** (parity with the join reveal card); live visual rides the gated smoke path
- [x] 3.44 Printable fallback — a "Print" button in the cockpit writes a styled, print-ready HTML standings sheet (LiveExport.StandingsHtml, HTML-escaped) to temp and opens it in the default browser via the OS Launcher (print / save-as-PDF — the $0 path). HTML generator unit-tested (structure + XSS-safe escaping)
- [x] 3.45 Networked Trivia-Night host from Windows (LiveNightHost: openRoom/start/reveal+auto-score/next/end) — LIVE cockpit PNG vs real room

## Slice 5 — Wave A authoring depth
- [x] 3.9 Reorder rounds — each builder round row gets ▲/▼ buttons (disabled at the ends) to move it in the running order (the native Avalonia idiom, matching the In-Order mode); reordering refreshes the balance meter. (Pointer drag-drop deferred; ▲/▼ is the parity verb)
- [x] 3.10 Balance meter — as the host composes a custom event, a live meter shows the question-type mix (a bar per type, width ∝ its share) + a plain-language variety verdict ("One-note — add another type" … "Great variety"). Pure LiveEventBalance.ByType/Verdict; unit-tested. (Category balance n/a — category is set once in Night options)
- [x] 3.11 Per-round wager/timer/speed/host-note — final wager round (builder toggle → ±stake scoring + join stake slider + big-screen FINAL WAGER), per-question timer (3.23), speed-tier (SpeedBonus), AND per-round host notes: an optional note per round in the builder (index-aligned RoundNotes, travels on reorder/delete, persists on the event) shown in the cockpit ONLY (gold note card, never on the projector). Wager + notes round-trip + host-default tests
- [x] 3.12 CSV import — Create gains an "Import CSV" button: native open-file picker → `CsvQuestions.Parse` (RFC-4180-ish: quoted fields, embedded commas, "" escapes; header + malformed rows dropped) → hand-authored MCQs saved as a replayable set (SavedSetsStore). Pure parser unit-tested (quoting + malformed drops)
- [x] 3.20 Live answer distribution/tally — the cockpit options now render a live per-option answer-distribution bar (proportional width + count) that updates as submissions stream in; the correct option tints green on reveal. `LiveNightHost.AnswerDistribution` + a pure `Tally(...)` helper (unit-tested: buckets choices, ignores unanswered/out-of-range)
- [x] 3.23 Live countdown controls — host starts a per-question answer deadline (30s/60s) and extends (+15/+30) or clears it; the deadline rides `Pub.Deadline` so join clients + the projector tick it down. Cockpit shows a live 1s-ticking countdown; the deadline auto-clears on question advance/reveal. Guard test + gated live start/extend/clear verified

## Slice 6 — Wave C submission & scoring
- [x] 3.21 Free-text review + spelling leniency — on reveal of a Name-It round the cockpit lists each team's typed answer with an auto-verdict (✓/✗ via GameEngine.MatchesAccepted, which is case/diacritic/"the"-insensitive); an "Accept" button awards the per-correct points to a borderline spelling the matcher rejected (LiveNightHost.TextReview + AcceptText). Guard + leniency test. **2026-09-09 — a ruling is for the room:** each refused row now carries "Accept" (this team, once — the row then reads "Accepted") and "Accept from everyone" (`LiveNightHost.AcceptTextForAll`: the spelling joins the question's `Accepted` list so every row that typed it turns ✓ and the night's copy carries it; each team the scorer refused for it is paid once, team-deduped like `AutoScore`; `TypedAlike` is the pure mirror of the Swift `typedAlike`, 4 xUnit tests). Hook `TIDBITS_LIVE_ACCEPT_ALL=<text>` (+`_AT`). **Verified on the real box:** four typers of "Keanu Reaves" variants → the wire scores paid exactly the three refused, the review rows read ✓ Accepted
- [x] 3.22 Answer-lock — manual Lock (existing, publishes pub.locked) + **auto-lock at pencils-down**: when the countdown deadline hits 0 the cockpit tick fires Lock (idempotent — Host.Lock no-ops once locked/revealed). A coral LOCKED badge shows the state. Guard test (safe defaults); live path gated
- [x] 3.24 Tie-break engine (brains-only) — the cockpit auto-detects a tie for first (`LiveNightHost.Ties` — shared non-zero top score) and shows a "Break tie" button that opens a picker of the tied leaders; the chosen team gets +1 to take the lead. Pure `Ties(...)` unit-tested (clear leader → none, shared top → both, zero-zero → none). (Numeric closest-wins tie-break rides the existing per-shape scoring)
- [x] 3.25 Team merge — a cockpit "Merge teams" button opens a two-combo FAContentDialog (keep team A · fold team B into it); `LiveNightHost.MergeTeams` combines their scores onto A, zeroes B, and hides B from the big screen. Guard/hide test (same-team + empty-uid no-op, fold hides B)
- [x] 3.26 Name moderation gate — a per-team "Hide" toggle in the cockpit standings hides an offensive networked name from the big screen; the cockpit still shows the real name, the projector renders `ModeratedStandings` ("(hidden)"). LiveNightHost.ToggleHidden/IsHidden/ModeratedStandings; toggle-state test GREEN
- [x] 3.27 Focus/cheat flag — the join client flags a player who switches away from the app while a question is live + unanswered (Window.Deactivated → Client.Blurred → Answer.blurred, already wired in the client). The host cockpit surfaces a coral "N teams left the app this question" line under standings (LiveNightHost.FlaggedCount off AnswersSnapshot). Guard test; live path gated
- [x] 3.28 CSV export — an "Export CSV" cockpit button writes the unified standings (Rank,Team,Score) via the native SaveFilePicker to a `tidbits-standings-{code}.csv`. `LiveExport.StandingsCsv` is pure + quote/comma-escaped (unit test: ranking + escaping + empty→header-only)
- [x] 3.29 In-room paper teams (hybrid) — the host adds a non-networked "paper" team (name dialog) that ranks alongside the phone teams in ONE standings (the hybrid differentiator); scored with the same −/+ override (routed to local paper scores, clamped ≥0). Flows through the cockpit standings, projector, moderation, tie-break, and CSV export. Offline test (add + score + clamp)

## Slice 7 — Wave B AV & show (Windows audio/video backend)
- [x] 3.30 SFX/stinger board — a host sound board on LibVLCSharp (AvPlayer, verified on Windows CI): `SfxBoard` (Core, persisted BYO-clip pads, dedup, cap-24, filename→label) + SfxBoardUi pad grid reachable from the cockpit "🔊 SFX" button; tap a pad → AvPlayer.PlaySfx, "+ Add sound" file-picks audio. Model + label + render tests (PNG). AvPlayer verified on windows-latest CI (168 passed, 0 skipped — LibVLC loads on the x64 ship target)
- [x] 3.31 PA output-device routing — the cockpit "🔊 Audio" panel lists LibVLC output devices (AvPlayer.OutputDevices) in a picker; selecting one routes all channels via AvPlayer.SetOutputDevice. Falls back to "System default" when no extra devices. Rendered in the combined audio panel (PNG)
- [x] 3.32 Audio round (BYO clips) — **now an AUTHORED round, not just an ad-hoc cue.** The builder's "Audio round…" / "Video round…" pick clips and turn each into a "name it" question, storing the path index-aligned with the question (`LiveEvent.RoundClips`). The cockpit shows a Play/Stop row for the clip belonging to the question ON SCREEN, or an explicit "Clip unavailable — re-attach it in the builder" when the file has moved — never a play button that does nothing. A file whose local path cannot be resolved is skipped and reported rather than becoming a silent question. The older ad-hoc "Question clip" cue in the audio panel remains for improvised moments. 8 tests incl. clip/question alignment through edits; on the CI-verified AvPlayer
- [x] 3.33 Looping music beds — "Choose bed" file-picks audio → AvPlayer.PlayBed (input-repeat loop on its own channel, under the SFX + question clip), a Stop button, and a volume slider → AvPlayer.SetBedVolume. In the cockpit audio panel; playback on the CI-verified AvPlayer
- [~] 3.34 Video questions — the bitmap-callback path is BUILT (the VideoView route is abandoned: LibVLCSharp.Avalonia 3.9.4 is compiled against Avalonia 11 and throws MissingMethodException Visual.get_VisualRoot under Avalonia 12). `AvPlayer.SetVideoSink` asks LibVLC for RV32 frames via SetVideoFormatCallbacks/SetVideoCallbacks (signatures read off the assembly by reflection: chroma is a char[4] BUFFER, not a packed uint; cleanup takes ref IntPtr; the delegates are held as fields because LibVLC keeps raw function pointers) → `VideoFrameSink` copies into a WriteableBitmap → `VideoSurface` draws it aspect-FIT (whole frame letterboxed — never the cropped-fill trap). Version-INDEPENDENT (no Avalonia inside LibVLC's path) and headless-verifiable, which VideoView never was. 8 tests drive the pipeline with SYNTHETIC frames — so it is verified on this arm64 Mac, which has no LibVLC native at all — incl. a frame reaching real rendered pixels at exact coral. **Remaining [~]:** LibVLC actually invoking the callbacks against a real video file is unproven; needs a video fixture on Windows CI. A video clip's AUDIO already plays (3.32 path)
- [x] 3.35 Speed-tiered scoring — the fastest three correct answers score +3/+2/+1; extracted the tiering out of AutoScore into pure LiveScoring.SpeedBonuses(fastest-first uids) and unit-tested it (3/2/1, 4th+ none, fewer-than-3, nobody-correct). Gated by the host SpeedBonus toggle
- [x] 3.45 Kahoot `.xlsx` export — `KahootSheet` (Rows/Xlsx, minimal OOXML via ZipArchive) behind Live's Export for Kahoot (.xlsx)…; their caps and allowed times applied and reported; 6 xUnit tests, and the workbook opened by an independent reader (2026-09-07)
- [x] 3.44 SpeedQuizzing folders — `QuickQuestions` (Parse/FromFolder/ClipPaths) behind Live's Import a SpeedQuizzing folder…; filename → question, file → media store, votes skipped by name, order honoured; 3 xUnit tests against the same filenames as the Swift suite (2026-09-07)
- [x] 3.43 GIFT + Aiken — `TextQuestionFormats` (Detect/ParseGift/ParseAiken/ExportGift) behind Create's Import questions… and Live's new Import questions (CSV, GIFT, Aiken)… + Export questions as GIFT…; 4 xUnit tests against the same fixtures as the Swift suite (2026-09-07)
- [x] 3.41 Question library — `LiveLibraryStore` (live-library.json), Save to library per row, Save round to library, From library… picker (FAContentDialog: search + category + Add/remove), Export library as bank package…, a `bank` package imports INTO the library (2026-09-07)
- [x] 3.42 Package pictures reach phones — `MediaPublisher` (SkiaSharp) installed as `LiveMediaStore.DataUrlProvider`; `LiveNightHost` publishes the https twin or a ≤800px JPEG data URL (2026-09-07)
- [x] 3.40 `.tidbits` file association — `uap:FileTypeAssociation` in the MSIX manifest; `Program.LaunchPackage` + `MainWindow` opens Live + `LiveView.ImportFromStream` on load (2026-09-07). Verify the association on windows-latest after the next Store ship (the association is registered by the MSIX, not by a dev run)
- [x] 3.38 The `.tidbits` package — `LivePackage` (System.IO.Compression) + `LiveMediaStore` (LocalAppData); Export package (with media)… / Import event or package… on the Live page; `ImageCache` resolves `tidbits-media:`; 4 xUnit goldens against the shared `tools/live-event/golden.tidbits` (2026-09-07)
- [x] 3.39 Question editor: Picture section (Choose picture… into the store, preview, remove, or URL) + a Clip row (Choose audio… / Choose video… / Remove) that attaches to THIS question via `ClipAt`/`SetClip` keeping `_clips` index-parallel, AND drag-and-drop a picture/audio/video onto a question row (`DragDrop.SetAllowDrop` + Avalonia 12's `DragEventArgs.DataTransfer.TryGetFiles()`; the file's kind decides what it becomes) — LIVE-PACKAGE-FORMAT §8.1, 2026-09-07. The KIND decision is unit-tested on both stacks; the drag GESTURE itself is not simulable headlessly, so exercise it once by hand on a real Windows box
- [x] 3.37 `/live/<code>` deep link — DONE 2026-09-09: `MainWindow.Route` had parsed the code and then only selected the Live nav item, so a Windows player who tapped a shared link landed on the Live tab's form. It now calls `LiveView.JoinFromLink(code)` (joins under the saved name). `TIDBITS_DEEPLINK=<url>` stands in for a protocol launch on the box (`e2e_rename.py windows` launches it). The JOIN A GAME button is second on Play (R-JOIN-1)
- [x] 3.36 Question pictures on the HOST surfaces — **projector DONE 2026-09-09, cockpit DONE the same day (a picture band under the prompt through `ImageCache`, verified on the real box); the Windows host also splits a store-only picture into the Decision 060 room node + a ≤320 px fallback (`LiveMediaStore.PublishPicture` over `MediaPublisher.JpegUnder`), and the Windows JOINER shows pictures for the first time (fallback at once, the node's full version once fetched)** (the picture band in the adaptive slide, via `ImageCache`, so a `tidbits-media:` reference resolves); the COCKPIT still does not show it. — a Kahoot-imported night (LIVE-EVENT-FILE §7) carries `imageURL` on ordinary classic questions; the Mac big screen and cockpit now render it (2026-09-06). Windows opens the file unchanged and publishes `imageURL` to joiners, but its projector and cockpit do not yet show the picture. Route it through `Services.ImageCache` the way `GameView.BuildPicture` does; GIFs should animate

- [x] 3.53 Clips reach the phones (Decision 060) — DONE 2026-09-09: C# `LiveRoom.Media`/`RoomMedia` (byte-keyed to Swift/JS/Kotlin), `LiveHostNet.PublishMedia` (once per room, node before pub), `LiveClipPublisher` (Core), `LiveNightHost.CurrentMedia`/`SyncMedia`/`CueMedia` (after every publish that moves the question; Play cues the phones), the cockpit's "On phones too · 74 KB" line, `LiveMediaCache` + the joiner's offer card in `JoinPlayerView` (LibVLC playback; a video clip draws into a `VideoSurface` in the card). **Windows delta:** no transcoder in the box — an MP3/M4A/AAC or MP4/M4V under 3 MB goes AS IT IS; a WAV/MOV/FLAC or anything over the cap is reported as "Not on phones — attach an MP3 or M4A / MP4 under 3.0 MB" and the PA carries it. Hooks: `TIDBITS_LIVE_HOST_FILE` (import + host a package from launch), `TIDBITS_LIVE_TAPCLIP=1`, `TIDBITS_LIVE_DIAG=1` (launch-hooks.log). **Verified on the real box:** hosted `qa-audio-m4a.tidbits` → `pub.media` = `room:d510…` audio/mp4 74 KB on the wire, the web joiner played it, the cockpit read "On phones too · 74 KB". Found on the way: the `.tidbits` file-association import (8.2) threw `MemoryStream's internal buffer cannot be accessed` on Windows — `GetBuffer()` on a byte[]-backed stream — fixed with `publiclyVisible: true`.

- [x] 3.75 The Windows JOINER answers EVERY format (2026-09-10) — found while photographing 3.74: the joiner drew answer buttons from `Pub.Options` and nothing else, so a Name-It, Closest, Ordering, Matching or Name-as-many question showed a prompt with NO way to answer it (the client's `SubmitText/Number/Order/Pairs/List` had existed unused since the port). `JoinPlayerView` now builds, per format, the macOS `LiveTextAnswer` … `LiveEnumerateAnswer` twins: a text box + Submit (Enter submits), a slider at the midpoint with the unit, an ordered list with ▲/▼ per row + Submit order, a ComboBox per key (Submit matches only when every key is chosen), and an Add row with chips + Done. The panel is rebuilt only when qid/phase/answered/locked change — the client fires Changed on every stream event and a text box rebuilt mid-word lost the typing. Per-question state resets on a new qid. Hook `TIDBITS_LIVE_ANSWER=<text>` + `_AT` types into the SAME box and presses its Submit (Diag line). 6 headless tests (one per format + choice unchanged). **Verified on the real box** (`scratchpad/e2e_wintype.py`): the joiner photographed with the text box, and the wire carried its typed "Keanu Reeves".
- [x] 3.74 The Windows JOINER shows what a question is worth (A2.11, 2026-09-10) — a coral WORTH N PTS chip above the prompt from `Pub.Points` when > 1 (`LivePlayerViewModel.WorthLine/HasWorth`). Verified on the real box as a joiner of a Mac-hosted 3-point round.
- [x] 3.73 A double-points round (macOS-DESIGN A2.11, 2026-09-10) — `LiveEvent.RoundPoints` (index-aligned like `RoundTimers`, 0 = the night's setting; `rounds[i].points` in the file), the builder's round bar gains a Points combo (Night pts / 2 / 3 / 5 / 10) beside the timer (travels with move/delete/duplicate), `LiveNightHost.RoundPointsPerCorrect` and `CurrentPoints` = question override → round → night, the cockpit line "3 pts a question this round", the projector chrome "· 3 pts a question", and `Pub.Points` on the wire. 2 xUnit (resolution order; file round-trip, absent = the night). **Verified on the real box** (`scratchpad/e2e_points.py windows`): `pub.points 3` on the wire and a correct answer paid 3.
- [x] 3.72 A key fixed after reveal re-scores (macOS-DESIGN A3.13, 2026-09-10) — `LiveScoring.KeyDiffers` (the scorer's fields through the wire shape; a prompt/story edit is not a key change; 2 xUnit), `LiveNightHost.ReplaceCurrent` → `Rescore()` when `Revealed`: reverse the answer sheet's paid points per team, drop that record, `AutoScore()` again, and set `RescoreNote` ("Key fixed — re-scored, N teams changed"); `LiveHostNet.SetScore` now updates its local cache before the put so the re-score reads the reversal at once. The cockpit shows the note under the question. Hook `TIDBITS_LIVE_FIX_KEY=<answer>` + `TIDBITS_LIVE_FIX_AT` (reveals if needed, replaces the answer text and accepted list, Diag before/after standings). **Verified on the real box** (`scratchpad/e2e_fixkey.py windows`): Table 1 paid 1 at reveal, then the key fix to "Neo" put Table 1 at 0 and Table 2 at 1 on the wire.
- [x] 3.70 The portable profile FEEDS on Windows (2026-09-10) — three defects under one audit line ("`NightEnded` has no subscribers"): (1) **the account was never bootstrapped at launch** — nothing called `AccountIdentity.Bootstrap()`, so a signed-in player read "Playing on this device only." after every relaunch and no game could reach the profile; `MainWindow.Loaded` now calls it and it raises `ProfileChanged` when it resolves (Settings had read the account first). (2) **No game on Windows had ever written the profile** — `PlayerIdentity.AfterGame` / `AfterLiveNight` (pure ports of Swift `recordGame`/`recordLiveGame`: accuracy nudges the rating, the day advances the streak, a live night grants a freeze, counters sum; 5 xUnit) behind `AccountIdentity.RecordGame`/`RecordLiveGame` (local-first, best-effort `players/{id}` put), wired through two static seams (`GameViewModel.GameRecorded`, `LivePlayerViewModel.NightRecorded`) that `GameData` sets once. (3) **Two identities per device** — `new LivePlayerClient()` / the night host's bare `LiveHostNet` each minted their OWN anonymous uid on the cleartext `FileTokenStore`, so the joiner's standings and the profile lived under different uids; both now take the app's DPAPI-backed `GameData.Rtdb` (`NightHostFactory.Create(…, db:)`). Settings shows `PlayerIdentity.SummaryLine` ("Tidbits Rating 1000 · provisional · 1-day streak · 3 live nights", the Mac's Settings row); the wrap says "Counted toward your streak and Tidbits Rating." **Verified on the real box** (`scratchpad/e2e_profile.py`): the box joined the Mac's night under the SAME uid as its profile, `players/{uid}` read `liveNights`, `streak.current 1`, `freezes` after the wrap, the wrap line and the Settings line photographed. Follow-up: the Settings "Display name" still edits the LOCAL `profile.json`, not the portable profile's `name` (the leaderboard shows "Player 5164" for a Windows player who named themselves) — 3.71.
- [x] 3.71 Settings "Display name" → the portable profile (2026-09-10) — `AccountIdentity.Rename`/`RerollAvatar` (pure `PlayerIdentity.Renamed`/`Reseeded`: trim, cap 24, empty ignored) write `players/{id}`; the local `PlayerIdentityStore` is now a CACHE (`Adopt(name, seed)` on every `ProfileChanged`), so `GameData.PlayerName`, the Records banner, Daily-board and duel submissions all read the portable name offline too. A name typed on this machine before the rule existed is carried up once (`LocalNameHint`) when the portable profile still has its "Player NNNN" default. Hook `TIDBITS_PROFILE_NAME=<name>` (Diag `profile rename: id=… name=… error=…`). 2 xUnit (rename rules; the mirror round-trips through the file). **Verified on the real box** (`scratchpad/e2e_name.py`): the Settings box read the name and `players/{id}.name` on the wire carried it.
- [x] 3.69 Rename a team mid-night (macOS-DESIGN A3.12, 2026-09-09) — `LiveHostNet.Rename(uid, name)` writes `meta/names/{uid}` and a `_names` watch lays the host's name over the joiner's in `JoinedList()`/`Members()` (so the projector, standings, answer sheet and exports all read it); the cockpit's joined row gains a **Rename** button (an `FAContentDialog` with the name). Hook `TIDBITS_LIVE_RENAME=<name>` + `TIDBITS_LIVE_RENAME_AT=<secs>` renames the alphabetically first joined team. Verified on the real box (`scratchpad/e2e_rename.py windows`): the wire carried `meta/names/{uid} = "The Quizzards"` for "Bad Speling" only, and the cockpit shot read the new name.
- [x] 3.68 The night report (macOS-DESIGN A3.11, 2026-09-09) — `LiveNightReport` (Core; `From(answerLog, teams)`, Hardest/Easiest/Rounds/Participation/OverallAccuracy, polls skipped; 2 xUnit), the cockpit's **Night report** command (a dialog: answers right · tables answering · questions, the hardest and easiest with their answers, per-round chips; "Print with the standings"), `LiveExport.StandingsHtml(…, report)` appends the section to the printed standings. Hook `TIDBITS_LIVE_REPORT_AT=<secs>`. **Verified on the real box:** two wire typers, one right — the dialog read 50% answers right · 100% tables answering · 1 question, HARDEST · 50% of 2 got it, the Neo question with its answer.
- [x] 3.67 Polish (2026-09-09): the cockpit's reveal block — the answer line for a non-MCQ (an MCQ's tally lights it), the story, and a "From Wikipedia · <title>" HyperlinkButton to the article — the Mac cockpit had all three, the Windows cockpit only its projector did; and the vote tally is now an MCQ thing on the cockpit AND the projector (`LiveScoring.IsMcq`) — a Name-It's `options` is its accepted list, and both surfaces had drawn it as a one-bar ballot. **Verified on the real box:** the Name-It reveal read "✓ Keanu Reeves", the story, "From Wikipedia · Keanu Reeves" (a link), with the free-text review right under it and no phantom tally bar.
- [x] 3.65 A wager round opens on the standings (A3.9, 2026-09-09) — `LiveHostViewModel.Next` sets `HoldStandings` when Next lands on a wager round's first question; `StandingsHeadline` names the round the scores are AFTER (the previous one at the top of a round; "STANDINGS" before any); the cockpit's wager line says why the standings are up. Hook `TIDBITS_LIVE_NEXT_AT=<secs>`. **Verified on the real box:** Next onto the wager round → the projector held "SCORES AFTER ROUND 1", the wire at r1 with wager:true, the cockpit line "Wager round — the standings are on the big screen so the tables can stake; hide them when they are ready".
- [x] 3.66 The music bed ducks under a clip (A3.10) — `AvPlayer` remembers the bed level, `_clip.Playing` ducks it to a quarter, `EndReached`/`Stopped`/`Paused` restore it (LibVLC's thread; Volume is safe there); the cockpit shows "Music bed ducked under the clip". Hooks `TIDBITS_LIVE_BED=<path>`, `TIDBITS_LIVE_PLAYCLIP_AT=<secs>`. **Verified on the real box** from `launch-hooks.log`: `play bed ok=True` at 35 → `play clip ok=True` → `bed ducked to 8` 80 ms later → `bed restored to 35` when the 6 s m4a ended. (The first two runs quit the app before the clip hook fired — timing, not the feature.)
- [x] 3.64 The poll question (macOS-DESIGN A2.10, 2026-09-09) — `LiveEvent.RoundQuestionPolls` + `QuestionPoll(i,q)`, the file's `rounds[i].questionPolls` both ways, the builder's Timer · points flyout gains "Make this a poll (no right answer)" on choice questions (caption "Poll · the room votes, nobody scores"), `LiveNightHost.CurrentIsPoll` → `Pub.Poll = true`, no `AnswerIndex`/`Answer` on reveal, `AutoScore` skipped (the sheet records the votes, answer "(poll)"), the projector's `RevealCorrectIndex` null so no bar lights, the cockpit's "Poll — the room votes, nobody scores" line, the Windows joiner's "Thanks for voting" line and no right/wrong tint. Round-trip in the overrides test. **Verified on the real box:** hosted the poll night with the projector open — the vote bars (Tacos 2 · Pizza 1) with nothing lit as right, the wire clean, the real web joiner told "Thanks for voting".
- [x] 3.62 The answer sheet (macOS-DESIGN A3.8, 2026-09-09) — `LiveAnswerRecord` (Core; `Submitted(q, a)` for every format) + `LiveExport.AnswersCsv` (long-format, quoted, teams alphabetical; 2 xUnit), `LiveNightHost.AnswerLog` filled in `AutoScore` from what was PAID (`ScoreAnswers(q, answers, paid)` — a score read back after the loop lags the write), the cockpit's **Export answer sheet as CSV** beside the standings export. Hook `TIDBITS_LIVE_EXPORT_ANSWERS=<path>` (5 s after the ACCEPT_ALL ruling). **Verified on the real box:** two wire typers (one right, one wrong) → the sheet read `Table 1,Keanu Reeves,1` and `Table 2,Neo,0`.
- [x] 3.63 Drag-to-reorder rounds (Mac A2.4 parity) — a round header is the drag handle (`DragDrop.DoDragDropAsync` with a `tidbits-round:<i>` text payload; the header's own buttons keep their clicks), a drop on another header calls `MoveRoundTo(from, to)`, which walks `MoveRound` so every parallel list travels; the chevrons stay as the keyboard fallback. Headless: `MoveRoundToForTesting` moves the buzz flag with the round, out-of-range is a no-op. The pointer gesture itself is not driven on the box (no mouse automation on the bench).
- [x] 3.61 The wrap teaches (macOS-DESIGN A3.7, 2026-09-09) — `LiveRecapBook`/`LiveRecapEntry` (Core; `Observe(pub, score)`/`Finish(score)`, nailed = the host's credit; 2 xUnit tests), `LivePlayerClient.Recap` + a STICKY `Ended` (the room is deleted when the host closes the cockpit; `WaitingForStart` no longer reads a torn-down room as a lobby; a post-delete score of 0 is ignored), the join view's wrap: THAT'S A WRAP, Final score, "Tough ones you nailed" with "How did you know that? · Copy" (the clipboard is the Windows idiom — no share sheet), "Tidbits to remember" with the story and a Wikipedia HyperlinkButton. Also fixed here: `ApplyMeta` ignored the `/state` patch (a bare string), so a Windows joiner never learned a night had ended from meta. **Verified on the real box** as a joiner of a Mac-hosted night: the wrap with "Tidbits to remember", photographed after the host tore the room down.
- [x] 3.60 Per-question host note (macOS-DESIGN A2.9, 2026-09-09) — `LiveEvent.RoundQuestionNotes` + `QuestionNote(i,q)`, the file's `rounds[i].questionNotes` both ways, `LiveNightHost.QuestionNotes`/`CurrentQuestionNote`/`SetCurrentNote` (the cockpit's Edit question carries the note too), the editor dialog's "Host note (only you see it)" box (a `noteChanged` callback beside `clipChanged`), the builder caption "💬 <cue>" (keyed by question id), the cockpit's blue 💬 bubble above the prompt, where the round note sits. Round-trip in the overrides test. **Verified on the real box:** the harness night's note showed as "💬 Say KEE-ah-noo. Ask who saw …" under the builder row and as the blue bubble on the cockpit over "Who played Neo in The Matrix?".
- [x] 3.58 Numeric tie-break engine (macOS-DESIGN A3.5, 2026-09-09) — the cockpit's Break tie dialog is now "Closest number" / "Brains-only": the correct number, one guess box per tied team, `LiveNightHost.ClosestWinner` (pure; distance then ordinal name, the Mac's `breakTie` mirrored) → `BreakTieClosest` awards +1. The backlog's ✅ had been false (a pick-the-winner ComboBox only). Hook `TIDBITS_LIVE_TIEBREAK=1` opens it after the ACCEPT_ALL ruling. xUnit: closest wins, exact tie stable, empty → nobody. **Verified on the real box:** two wire typers tied at 3 → the hook opened the dialog: "Closest number" selected, the correct-number box, a guess box for Table 1 and Table 2, Resolve tie / Cancel.
- [x] 3.59 Per-question timer + points (A2.8) — `LiveEvent.RoundQuestionTimers`/`RoundQuestionPoints` (index-aligned per round, 0 = default, additive), `QuestionTimer(i,q)`/`QuestionPoints(i,q)`; the file's `rounds[i].questionTimers`/`questionPoints` (`[int?]`, absent when nothing is set) both ways in `LiveEventFile`; `LiveNightHost.QuestionTimers`/`QuestionPoints` from the factory, `CurrentQuestionTimer` arms the deadline, `CurrentPoints` pays every scoring path (auto-score, accept, accept-from-everyone). Builder: a **Timer · points** flyout per row (15…120 s, 1…10 pts, defaults clear), the row caption "⏱ 45 s · ★ 3 pts", kept by question ID so insert/remove/move need no bookkeeping. Cockpit: "45 s · 3 pts for this one" over the prompt. xUnit round-trip through the file. **Verified on the real box:** a night written by the harness with `questionTimers: [120, null]`, `questionPoints: [3, null]` imported into the builder ("⏱ 120 s · 3 pts" under question 1 only — the star glyph was dropped, Inter has none), hosted → a deadline on the wire for an untimed round, two correct typers paid 3 each.
- [x] 3.56 The builder names what the room has heard (macOS-DESIGN A2.6, 2026-09-09) — `PlayedLog` (Core, JSON at `%LOCALAPPDATA%\TidbitsTrivia\live-played.json`; `Record`/`Entry`/`Ids`/`AskedLine`, capped like the seen set; 2 xUnit tests); `LiveNightHost.Played` is written in `PrepareQuestion` (every question the night SHOWS) and fed to `_provider.MarkSeen` before a sourced draw, so a re-hosted sourced round never re-asks across launches (the provider's own seen set was per launch). Builder: "⟲ Asked today · <night>" under an authored repeat, a **Fresh** button per row (`SwapForFresh`: same kind, not heard, not already in the night, three pulls before giving up by name), the round menu's "Swap the N questions the room has heard" (`RefreshRepeats`). Hooks `TIDBITS_LIVE_IMPORT_FILE` (builder only, rounds open) + `TIDBITS_LIVE_REFRESH=1`. **Verified on the real box:** hosted the QA night, reopened it with the import hook → "⟲ Asked today · Edit & Accept QA" under question 1 only (question 2 was never shown), `live-played.json` written; the refresh swapped it for a fresh Name-It question (Toronto) and left question 2 alone.
- [x] 3.57 A night is a template (A2.7) — the saved-events row gains **Duplicate**, which on a recurring night reads **Clone for next <weekday>** and swaps the heard questions after copying (`LiveEvent.Duplicated`/`CloneName`/`Repeats`).
- [x] 3.55 Edit the question on screen (macOS-DESIGN A3.6, 2026-09-09) — the cockpit's **Edit question** command (primary bar, next to Skip; hidden on a board slide) opens `LiveQuestionEditorDialog` on the night's own copy; `LiveNightHost.ReplaceCurrent` swaps `Questions[Index]` (round index kept), re-deals the ordering/matching shuffles ONLY when that content changed, republishes; `SetCurrentClip` puts an editor clip decision onto the round's clip list and re-offers the media (Decision 060). Hook `TIDBITS_LIVE_EDIT=<prompt>` (+`_AT`). **Verified on the real box:** the prompt changed mid-question on the wire, the web joiner and the cockpit
- [x] 3.54 Projector adapts + full screen (macOS-DESIGN A8.9/A8.10 → WINDOWS-DESIGN 6.3c, 2026-09-09) — DONE: `ProjectorElements` (Core; same ids as the Mac; persisted JSON, `TIDBITS_LIVE_HIDE` for one launch), the cockpit **Screen** command (check items + Show everything + Full screen / Full screen on <display>), `ProjectorWindow.ToggleFullScreen`/`FullScreenOn(Screen)`/F11/double-click; the question screen rebuilt as a 1280x720 canvas with a fit-to-height middle, live vote bars on the options, the team strip as wrapping chips, a horizontal join card WITH a QR (the join code used to be a text strip overlaid top-right), the sponsor line in the flow on every slide. `ProjectorAdaptiveSnapshot` (8 renders) asserts no overlap and no clipped text — it caught `MaxLines` dropping the last line of a question.

## Slice 8 — Waves D + E (venue + moat)
- [x] 3.46 Recurring-series scheduling — an event can repeat weekly (a "Repeats" weekday picker in the builder → LiveEvent.Weekday); the saved-events list shows "Every {day} · next {date}" so a weekly host reuses the template. Pure RecurringSchedule.NextOccurrence/Display (today counts, wraps the week) + IsRecurring/ScheduleLine — unit-tested. Wave D venue business COMPLETE (recurring + sponsor + white-label + lead-capture)
- [x] 3.47 Sponsor kit — an event Sponsor flows to a persistent "Brought to you by {sponsor}" footer on the projector across all phases (LiveEvent.Sponsor → LiveNightHost.Sponsor → VM SponsorLine/HasSponsor). Set in the builder, persists in the saved event; PNG-verified
- [x] 3.48 Lead-capture QR — an event LeadCaptureUrl → a "Join the mailing list" QR on the projector final-standings screen (QrHelper, pure-C#), pointing at the venue's own signup URL (venue keeps its CRM). Builder field, threaded through StartHosting, persists in the saved event; round-trip + VM tests
- [x] 3.49 White-label brand accent — an event BrandHex recolors the projector accents (JOIN NOW / round title / final-standings header) via VM BrandBrush (parses the hex, falls back to brand coral on invalid). Set in the builder, persists; branding test + branded-lobby PNG (blue #0047FF verified)
- [x] 3.50 ★ Standings write (season/venue) — when a live night ends, `LivePlayerClient.RecordStanding` adds the player's score to their cumulative `standings/{season}/{venueKey}/{authUid}` (read-modify-write, keyed by auth uid per the rule), fired once from RecordIfEnded. `StandingWrite` payload (name/score/nights/updatedAt) + the season/venue path pieces are byte-identical to the web/Swift/Kotlin twins — unit-tested (2026-S3 quarter format, path-safe venue key, JSON keys). Completes the moat with the 2.25 read side; the hourly cron aggregates all platforms' writes
- [x] 3.51 Leaderboard read + defendable titles — shipped as 2.25 (LeaderboardApi + a top-level Leaderboard nav → season overall + per-venue, CHAMPION on #1, signed-in player's row highlighted). Now paired with the 3.50 write side = the complete moat
- [x] 3.52 Social graph — `FriendStore` (Core, JSON, dedup-by-uid, private/local) + a "Friends" section leading the Leaderboard (added people ranked by public standing, "—" if unranked) + the join-wrap "Add the people you played with" list (co-players captured at night-end → one-tap Add, flips to "Added ✓"). Store + friends-section + VM add/isFriend tests; PNG

## Owner parity report 2026-07-30 (all four fixed, 1.6.62)
- [x] P.1 **Shell landing was blank** — the detail pane only rendered as a side
  effect of `SelectionChanged`, and FANavigationView settles on the first item
  without raising it, so the whole right-hand side stayed empty until the user
  clicked the sidebar. `MainWindow` now renders the landing surface directly on
  `Loaded`, and only the section-frame fallback needs the view model. Locked in
  by `ShellLandingTest` (asserts `ContentHost.Content` is a `PlayView` with NO
  interaction) — WINDOWS-DESIGN §7.14.
- [x] P.2 **Play home showed 14 Dailies** — every other platform shows today's
  Tidbit plus an archive link. `BuildDaily` now renders TODAY only and puts the
  other 13 days behind "Previous Tidbits" (`DailyArchiveDialog`, sharing one row
  builder in `DailyUi`). Trivia Night + Pass & Play are back above the fold.
- [x] P.3 **Cockpit buttons did not flow** — 13 controls in two non-wrapping
  `StackPanel`s clipped at any non-maximised width. Both groups are `WrapPanel`s
  now; PNG-verified reflowing at 720/1000/1400 — WINDOWS-DESIGN §6.3b.
- [x] P.4 **Projector did not open as a separate window** — it went chromeless
  FULLSCREEN on the primary display when no second monitor existed, burying the
  cockpit with no title bar, no taskbar entry, and no way out. Auto-fullscreen is
  now gated on a real non-primary `Screen`; otherwise it opens as a normal
  decorated, resizable, taskbar-visible window. Esc always leaves fullscreen —
  WINDOWS-DESIGN §6.3a.

## Full macOS→Windows audit 2026-07-30 (playbook: docs/WINDOWS-PARITY-AUDIT.md)
First systematic run of all seven passes. `python3 tools/audit_windows_parity.py`
is the repeatable Pass A.

**Fixed this pass (1.6.63):**
- [x] A.1 **Account deletion** — absent on Windows while iOS/macOS/tvOS/Android
  all ship it (Decision 048). Added `FirebaseRtdb.DeleteAccount()`
  (Identity Toolkit `accounts:delete`) + `AccountIdentity.DeleteAccount()` in the
  SAME node order as Swift (account-keyed → uid-keyed → `emailOwners` LAST →
  credential), plus a Settings section with an `FAContentDialog` confirm that
  reports failure instead of silently leaving the account alive.
- [x] D.1 **Brand CTA broke in dark mode** — `Classes="accent"` fell through to
  FluentAvalonia's derived accent, which LIGHTENS for dark theme: the Quick Play
  hero rendered salmon-with-black-text while the hard-coded coral Daily row right
  beneath it stayed saturated. `Button.accent` now pins the brand token in both
  themes (WINDOWS-DESIGN §5.5).
- [x] D.2 **Accent-on-accent** — fixing D.1 made the Daily hero's "Play today's
  Tidbit" coral-on-coral, i.e. invisible as a button. Inverse treatment (white
  chip, coral label) on coloured surfaces (§5.5).
- [x] G.1 **No app accelerators** — macOS has menu commands; Windows had none.
  Ctrl+N (new game) and Ctrl+, (settings) on `MainWindow`.

**Open, tracked (NOT fixed this pass):**
- [x] A.2 **First-run onboarding** — SHIPPED 1.6.67. `OnboardingDialog` is the
  twin of `OnboardingSheet_macOS`: one compact pass (three numbered points, then
  "Get started"), NOT a multi-page carousel — the Mac shows all three at once and
  a desktop window has the room. Gated on the new `GameSettings.HasOnboarded`,
  written on dismissal by ANY means, so pressing Esc doesn't make it reappear
  next launch. Fired after deep-link routing so a shared link still lands where
  it should. Points use **numbered brand badges, not icon-font glyphs** — Win10
  ships Segoe MDL2 Assets and Win11 Segoe Fluent Icons and the codepoints don't
  all agree, so a glyph that looks right on one renders as tofu on the other.
- [x] A.3a **Printable host materials** — SHIPPED 1.6.65. `LiveExport
  .AnswerSheetHtml` (numbered blank lines per round) + `.QuestionPackHtml`
  (every question with its answer, grouped by round), both HTML → default
  browser → print/save-PDF, the path `StandingsHtml` already used.
  **The two live in DIFFERENT places on Windows than on macOS, on purpose:** a
  saved Windows `LiveEvent` stores only `{kind, count}`, so the answer sheet
  prints from the BUILDER (plan-only, before the night — the contingency hosts
  actually want) while the question pack prints from the COCKPIT, where
  `host.Questions` is the draw the room is really being asked. Printing a pack
  at build time would hand the host a different set of questions.
- [x] A.3b(i) **Video had nowhere to appear** — SHIPPED 1.6.68, and the bigger
  half of this item. Windows already had `AvPlayer.SetVideoSink`,
  `VideoFrameSink` AND `VideoSurface` — but **nothing was wired between them**,
  so a host could play a clip, hear it, and never see a picture on any surface.
  The projector now owns a `VideoSurface` above every other layer (while a clip
  plays it IS the big screen), attaches the sink on load, hides again on
  EndReached/Stopped so the last frame doesn't freeze over the next question, and
  detaches BEFORE disposing (LibVLC writes frames from its own thread). No-ops
  where the natives are absent, which is CI and this Mac.
- [x] A.6 **Per-round timer (Wave A)** — SHIPPED 1.6.69. The builder authors a
  countdown per round (No timer / 30 / 45 / 60 / 90 / 120s) and the host arms it
  automatically as each question comes up.
  **It rides `LiveEvent.RoundTimers`, index-aligned like `RoundNotes` — NOT
  `NightRound`.** `NightRound` is the wire type serialised to every joiner, Apple
  pins its `CodingKeys` to `{kind, count}`, and `tools/night-wire` has golden
  coverage on it; adding a field there would have put a key on the wire for a
  purely host-side authoring concern. macOS makes the same split (its
  `timerSeconds` lives on the Mac-only `LiveRound`, not the shared type).
  Armed on Start and Next but deliberately NOT on GoBack — going back means the
  host is fixing something, and a fresh clock would rush the room mid-correction.
  Tests cover the wire shape staying clean and a legacy saved event with no
  `roundTimers` key still decoding.
- [x] A.3b(ii) **Authoring** a media round in the builder — CLOSED 2026-09-09: the
  shape change this row feared landed with the `.tidbits` package (3.38/3.39):
  `LiveEvent` rounds hold custom questions and per-question clips (`ClipAt`/`SetClip`),
  the question editor attaches audio/video/pictures, and a file dropped on a
  question row becomes its clip. The row had stayed open after the work shipped.
- [x] A.4 Live host: **Remove team** — SHIPPED 1.6.64. `LiveNightHost.RemoveTeam`
  zeroes the score and drops the team from standings/projector/export, matching
  `MergeTeams`' shape: the RTDB node is SHARED with that player's client, so
  deleting it outright would strand them mid-night rather than un-score them.
  Cockpit dialog defaults to Cancel and says plainly that it does not kick them.
  *Resolve tie* was a FALSE gap — Windows does it in one "Break tie" dialog
  rather than macOS's two verbs.
- [x] A.5 Versus **Rematch** — FALSE gap. It rides `GameView`'s "Play again"
  (`player.PlayAgainRequested += () => StartVersus(bot)`). Both now recorded in
  the audit tool's KNOWN_SYNONYMS so they stop being re-flagged.
- [x] E.1 Settings now uses **`FASettingsExpander` rows** (Header + Description +
  Footer control), the Windows 11 Settings idiom, instead of bold `TextBlock`
  headers over `StackPanel`s. Status messages ride `FAInfoBar` rather than
  coloured `TextBlock`s. **Account is `IsExpanded="True"`** on purpose: burying
  sign-in behind a chevron is the same discoverability mistake the iPhone had.
  NOTE the v3 API is FA-prefixed (`FASettingsExpander`/`FASettingsExpanderItem`/
  `FAInfoBar`) — the unprefixed WinUI names do not resolve.
- [x] D.3 **ToggleSwitch washed out in dark mode** — found by giving Settings its
  own both-themes render. Same §5.5 defect as `Button.accent`: a switched-on
  toggle is an accent surface, so FluentAvalonia's derived accent lightened it to
  salmon while every coral beside it stayed saturated. Pinned.
- [x] G.2 **No `AutomationProperties.Name` anywhere** — SHIPPED 1.6.64. Named
  all eight icon-only controls (▲/▼ reorder in the Live builder and the Ordering
  answer shape, ✕ delete on rounds/saved events/saved sets, × on SFX pads).
  `AccessibleNamesTest` is now a source-scan gate: write `Content = "✕"` without
  a name nearby and the build fails. It found two the manual grep missed.
- [x] F.* Window model (projector single/dual monitor, hot-plug, taskbar
  progress) — verified on the REAL Windows box (10.0.0.85) during the 2026-09 Live
  loop: the projector goes full screen and adapts to the switched-on elements
  (`e2e_*` shots in DEVICE-QA-SUITE). Hot-plug re-placement (`Screens.Changed`
  in `ProjectorWindow`) is coded but the bench has one display, so the re-place
  itself is unexercised; the note used to say the whole row was unverifiable.

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
