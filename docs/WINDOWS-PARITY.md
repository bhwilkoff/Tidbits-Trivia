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
- [~] 0.3 Window chrome — Mica backdrop applied (MainWindow TransparencyLevelHint="Mica,AcrylicBlur,None"; the Win11 material, graceful fallback to opaque on Win10/headless). FluentAvalonia's opaque control surfaces keep content readable (avoided the risky global Background=Transparent). Extend-titlebar + theme-follow still pending; Mica visual is windows-latest-CI-verified (headless ignores the hint; 114/114 shell tests still GREEN)
- [~] 0.4 Deep-link inbox + routing — `DeepLink.Parse` maps the custom scheme (tidbitstrivia://live/2NRE, ://daily, ://leaderboard, …) AND the https twin to a nav target (+ sanitized 4-char room code); Program captures a launch URL, MainWindow.Route consumes it on Loaded to select the tab (the inbox pattern — external entry never touches nav directly). Parser + nav-tag unit-tested (12+6 cases). Quick-Play memory / presets still pending
- [ ] 0.5 `tidbitstrivia://` + https deep-link registration (needs package identity)

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
- [ ] 1.22 `Keychain` → Credential Manager/DPAPI
- [x] 1.23 `Haptics` → no-op stub
- [x] 1.21 `GameSettings` KV (JSON-backed) + RecordsStore.ResetAll
- [x] 1.20 `DailyLog` (per-day results, first-completion-wins; JSON-backed; a replay can't overwrite a day's record) — unit test GREEN
- [x] golden-vector contract test harness (§8.7) — daily parity GREEN vs Apple/Kotlin/JS

## Slice 2 — Consumer vertical
- [x] 2.1 `GameEngine` (all 18 modes, phases, clocks, host-paced, all submit paths) — end-to-end tests GREEN
- [x] 2.3 `ProgressStats`/DomainProgress/Badges (ProgressMath levels + wedges + LevelableBadge/BadgeMath) — pure port
- [x] 2.4 `BotOpponent` — faithful C# twin of js/bots.js (Rookie/Regular/Ace + The House adapting to player accuracy; category skill, difficulty adj, ~5% freeze, log-normal timing, Box–Muller; VsMatch begin/commit/standings, seedable RNG). Seeded tests prove the freeze rate (~5%) + skill (~85% for Ace) + no double-scoring on a repeated reveal
- [~] 2.5 Play/Home surface — Quick Play hero + Daily + category picker + mode grid (all MCQ modes reachable); Surprise/Night/Online-MP pending
- [~] 2.6 Customize — category picker + mode grid on Home; mode multiselect (mix) + saved presets pending
- [~] 2.7 Game surface — MCQ playing/reveal/finished LIVE + headless-PNG verified; specialty-mode surfaces pending
- [x] 2.8 Per-mode answer surfaces — ALL shapes built + PNG-verified + play-through tests GREEN: numeric slider (Closest Call), free-text (Name It), Stake (chip budget + dimmed MCQ until committed), In Order (▲/▼ reorder), Match Up (tap key→value chip), Name as Many (type-against-clock, chips fill), Picture ID (image frame over 4 options). Sweep/Ladder/OddOneOut/ThisOrThat ride MCQ. Fixed a latent bug: the answer surface was rebuilt on every 100ms Remaining tick (would drop typing / interrupt a slider drag) — now rebuilds only on phase/question/reorder change (regression test). All 15 consumer modes offered on the Play tab
- [x] 2.9 Image pipeline — `ImageCache` (decoded-Bitmap cache over one capped HttpClient, per-URL inflight dedupe, bounded to 64, null-not-throw on failure); Avalonia's Skia decode is display-ready (no macOS grayscale-white-box trap). Powers Picture ID (loading/unavailable fallback); decode+cache+dedupe tests GREEN. Twin of the macOS ImagePipeline
- [x] 2.10 Results recap — coral scorecard (headline/score/mode·category) + stat row (correct/accuracy/best-streak) + spoiler-free grid + "Tidbits to remember" missed-fact cards + Play Again (hidden for Daily) + Done; PNG-verified
- [x] 2.11 Emoji-grid share — `ShareText` (Core, byte-faithful web twin: 🟢🔴⚫️ grid + ▰▱ meter + streak/best-run fallback + play link) → clipboard (Windows native idiom); 3 golden tests GREEN
- [x] 2.12 Four content states — audited across every data surface: Records ("No games yet" empty), Leaderboard ("Loading standings…" + "No standings yet" + error→empty), Create (now an indeterminate ProgressBar during generation + "No questions found" error + saved-sets hidden when empty), Live saved-events / Daily archive / join wrap all guard empty. Offline: consumer runs off the bundled corpus; Live shows a connection error. Added the missing Create loading indicator this pass
- [~] 2.13 Records dashboard (R-REC-1) — streak+lifetime card, recent 3 + See-all, per-domain knowledge bars, review count; PNG-verified. Drill-ins/calibration/badges/pie pending
- [~] 2.14 Records drill-ins — "See all N games" opens a native FAContentDialog listing every game (header · score · green/red answer-dot strip); tapping a game drills into a per-question recap (dot · prompt · answer) with a back nav. VM exposes full GameDetail/AnswerDot; list + recap PNG-verified. Domain / personal-best drill-ins pending
- [~] 2.15 Topic Levels (per-domain XP bars) + **Badges** (levelable milestones via BadgeMath, earned-only, coral tier-number icon per R-ICON-1) + **Stake calibration** (per-tier hit rate) + **The Pie** (7-wedge Trivial-Pursuit breadth circle drawn in Avalonia geometry — each domain's wedge fills in its category color when mastered ≥15 correct/≥60% acc, "N of 7 domains mastered"; test masters Science → wedge fills, PNG) all shipped in the Records dashboard. Avatar re-roll shipped (Settings Profile: hue-colored avatar + Shuffle, on the new PlayerIdentityStore 1.17); liveNights=0 until live-night records are tracked locally
- [x] 2.16 Records profile banner — a card atop Records shows who you're playing as (deterministic hue avatar + "Playing as {name}") and where records live ("saved on this device · edit your profile in Settings"), reading from the PlayerIdentityStore. Honest for Windows: no cross-device account sync yet, so it surfaces identity + device-local storage rather than a fake "sign in". Render test + PNG
- [x] 2.17 Create — topic → corpus retrieval + diversify → play the set (live-gen fallback stubbed); PNG-verified
- [x] 2.18 Create saved sets — `SavedSetsStore` (Core, JSON-backed, newest-first, capped 30, questions serialized intact); after generating, "Save this set" stores it; a "Saved sets" list on the Create landing replays or removes each. Round-trip test + PNG-verified
- [x] 2.19 Settings page — review toggle + reset seen/records + about/version; PNG-verified
- [x] 2.20 Trivia Night (solo) — 3 preset cards (Quick/Pub/The Works) on the Play landing → a self-paced multi-round night off the shape-routing engine; each round opens with a centered interstitial ("ROUND n OF m · title · k questions · Start round"), every shape plays through to the results recap. Full-night play-through test GREEN (all 3 rounds, every question answered). Networked host = Slice 4
- [~] 2.21 Versus CPU — a "Versus CPU" section on the Play landing (Rookie/Regular/Ace/The House, each labeled CPU); starts a Classic match with a live "YOU vs {bot} · CPU" score strip over the game (VersusViewModel drives VsMatch off the engine phases — resolve on each question, commit on reveal), result line on finish, rematch via Play Again. Matches don't write records (parity rule). PNG-verified. Online Quick Match (real players) still pending
- [x] 2.22 Spaced re-asking + day-streak surfacing — due missed facts (RecordsStore.DueReview) woven into MCQ games via engine.Start(review:), opt-out via the Settings toggle, skips Daily + non-MCQ, resolves on a correct answer (end-to-end test). Results recap now surfaces the **day streak** (orange count card + "your best ever!" when Current==Best≥2), read from RecordsStore.Streak after the record write; PNG-verified after a Daily
- [x] 2.23 Daily play-once lock + archive — the Play landing shows today's Daily as a coral hero (play-once; flips to a done card with score once completed) plus a "Previous Tidbits" archive of the last 14 days; unplayed past days are playable via the deterministic day-key seed and never bump the streak (RecordsStore only bumps when day==today). DailyLog records first-completion-wins. PNG-verified
- [~] 2.24 Async friend duels — `DuelStore` (Core) COMPLETE: wire types byte-keyed to js/duels.js (DuelQuestion p/o/c/e, DuelPlayer, Duel, DuelInvite), pure logic (Compact/QuestionsOf round-trip, Classify outcome state machine YourTurn/WaitingOnThem/Won/Lost/Tie, newest-first capped local id tracking), and the networked methods over FirebaseRtdb (Challenge+invite, Submit own slot, Inbox, Accept, Mine). 8 offline tests. Serverless duels/{id}+duelInbox contract. Remaining: the inbox/challenge/play/results UI
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
- [~] 3.7 Builder — the Live setup gains a "build a custom event" section: name + add rounds (mode picker × count), a live rounds list (remove each), then Host this event or Save event; saved events list with Host/delete. Single-column (not the Mac two-pane) but fully composes + hosts + persists. Drag-reorder / per-round depth pending
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
- [~] 3.42 Big-screen chrome — the projector question screen now shows the round title + "Question X of Y · N players" chrome and a large live coral countdown (ticks off Pub.Deadline via a 1s DispatcherTimer). Format/difficulty labels + story on reveal pending
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
- [x] 3.21 Free-text review + spelling leniency — on reveal of a Name-It round the cockpit lists each team's typed answer with an auto-verdict (✓/✗ via GameEngine.MatchesAccepted, which is case/diacritic/"the"-insensitive); an "Accept" button awards the per-correct points to a borderline spelling the matcher rejected (LiveNightHost.TextReview + AcceptText). Guard + leniency test
- [x] 3.22 Answer-lock — manual Lock (existing, publishes pub.locked) + **auto-lock at pencils-down**: when the countdown deadline hits 0 the cockpit tick fires Lock (idempotent — Host.Lock no-ops once locked/revealed). A coral LOCKED badge shows the state. Guard test (safe defaults); live path gated
- [x] 3.24 Tie-break engine (brains-only) — the cockpit auto-detects a tie for first (`LiveNightHost.Ties` — shared non-zero top score) and shows a "Break tie" button that opens a picker of the tied leaders; the chosen team gets +1 to take the lead. Pure `Ties(...)` unit-tested (clear leader → none, shared top → both, zero-zero → none). (Numeric closest-wins tie-break rides the existing per-shape scoring)
- [x] 3.25 Team merge — a cockpit "Merge teams" button opens a two-combo FAContentDialog (keep team A · fold team B into it); `LiveNightHost.MergeTeams` combines their scores onto A, zeroes B, and hides B from the big screen. Guard/hide test (same-team + empty-uid no-op, fold hides B)
- [x] 3.26 Name moderation gate — a per-team "Hide" toggle in the cockpit standings hides an offensive networked name from the big screen; the cockpit still shows the real name, the projector renders `ModeratedStandings` ("(hidden)"). LiveNightHost.ToggleHidden/IsHidden/ModeratedStandings; toggle-state test GREEN
- [x] 3.27 Focus/cheat flag — the join client flags a player who switches away from the app while a question is live + unanswered (Window.Deactivated → Client.Blurred → Answer.blurred, already wired in the client). The host cockpit surfaces a coral "N teams left the app this question" line under standings (LiveNightHost.FlaggedCount off AnswersSnapshot). Guard test; live path gated
- [x] 3.28 CSV export — an "Export CSV" cockpit button writes the unified standings (Rank,Team,Score) via the native SaveFilePicker to a `tidbits-standings-{code}.csv`. `LiveExport.StandingsCsv` is pure + quote/comma-escaped (unit test: ranking + escaping + empty→header-only)
- [x] 3.29 In-room paper teams (hybrid) — the host adds a non-networked "paper" team (name dialog) that ranks alongside the phone teams in ONE standings (the hybrid differentiator); scored with the same −/+ override (routed to local paper scores, clamped ≥0). Flows through the cockpit standings, projector, moderation, tie-break, and CSV export. Offline test (add + score + clamp)

## Slice 7 — Wave B AV & show (Windows audio/video backend)
- [ ] 3.30 SFX/stinger board (NAudio/CSCore)
- [ ] 3.31 PA output-device routing (WASAPI)
- [ ] 3.32 Audio round (BYO clips)
- [ ] 3.33 Looping music beds
- [ ] 3.34 Video questions (LibVLCSharp/media element)
- [x] 3.35 Speed-tiered scoring — the fastest three correct answers score +3/+2/+1; extracted the tiering out of AutoScore into pure LiveScoring.SpeedBonuses(fastest-first uids) and unit-tested it (3/2/1, 4th+ none, fewer-than-3, nobody-correct). Gated by the host SpeedBonus toggle

## Slice 8 — Waves D + E (venue + moat)
- [x] 3.46 Recurring-series scheduling — an event can repeat weekly (a "Repeats" weekday picker in the builder → LiveEvent.Weekday); the saved-events list shows "Every {day} · next {date}" so a weekly host reuses the template. Pure RecurringSchedule.NextOccurrence/Display (today counts, wraps the week) + IsRecurring/ScheduleLine — unit-tested. Wave D venue business COMPLETE (recurring + sponsor + white-label + lead-capture)
- [x] 3.47 Sponsor kit — an event Sponsor flows to a persistent "Brought to you by {sponsor}" footer on the projector across all phases (LiveEvent.Sponsor → LiveNightHost.Sponsor → VM SponsorLine/HasSponsor). Set in the builder, persists in the saved event; PNG-verified
- [x] 3.48 Lead-capture QR — an event LeadCaptureUrl → a "Join the mailing list" QR on the projector final-standings screen (QrHelper, pure-C#), pointing at the venue's own signup URL (venue keeps its CRM). Builder field, threaded through StartHosting, persists in the saved event; round-trip + VM tests
- [x] 3.49 White-label brand accent — an event BrandHex recolors the projector accents (JOIN NOW / round title / final-standings header) via VM BrandBrush (parses the hex, falls back to brand coral on invalid). Set in the builder, persists; branding test + branded-lobby PNG (blue #0047FF verified)
- [x] 3.50 ★ Standings write (season/venue) — when a live night ends, `LivePlayerClient.RecordStanding` adds the player's score to their cumulative `standings/{season}/{venueKey}/{authUid}` (read-modify-write, keyed by auth uid per the rule), fired once from RecordIfEnded. `StandingWrite` payload (name/score/nights/updatedAt) + the season/venue path pieces are byte-identical to the web/Swift/Kotlin twins — unit-tested (2026-S3 quarter format, path-safe venue key, JSON keys). Completes the moat with the 2.25 read side; the hourly cron aggregates all platforms' writes
- [x] 3.51 Leaderboard read + defendable titles — shipped as 2.25 (LeaderboardApi + a top-level Leaderboard nav → season overall + per-venue, CHAMPION on #1, signed-in player's row highlighted). Now paired with the 3.50 write side = the complete moat
- [x] 3.52 Social graph — `FriendStore` (Core, JSON, dedup-by-uid, private/local) + a "Friends" section leading the Leaderboard (added people ranked by public standing, "—" if unranked) + the join-wrap "Add the people you played with" list (co-players captured at night-end → one-tap Add, flips to "Added ✓"). Store + friends-section + VM add/isFriend tests; PNG

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
