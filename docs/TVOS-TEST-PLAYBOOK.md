# tvOS Test Playbook — every feature, observed on the glass

**Mission (owner, 2026-08-24):** testers report significant issues in the tvOS
app. Systematically test EVERY screen and feature on the real Apple TV — in
particular the quiz/game mechanics (images loading, all question types
working, cross-platform + online multiplayer) — so players are never confused
or unable to do something the app promises. Fix what's found; mirror
cross-platform fixes (Core is shared with iOS/macOS); verify on the glass.

## Campaign summary (2026-08-24 — CAMPAIGN COMPLETE, maintenance mode)

Testers reported "significant issues" — the sweep found the app's CORE is
strong and the real defects were in reachability/observability wiring:

**Device-proven (the concern areas):** all 14 game modes play to correct
results screens on the real Apple TV (incl. a 52-question survival run);
picture rounds render real photos (luma-gated, Debug AND Release); reveal
explanations render; the losing outcome shows honest 20%-accuracy results +
facts-to-review; all four Versus bots complete matches with both scores;
Quick Match opens and searches; a scripted cross-platform Firebase player
joined a TV-hosted Trivia Night and the lobby count tracked it live
(join AND leave); live Create generation built and played a real
Wikipedia quiz on-device; every Club surface (hub, Atlas incl. empty state,
Story Archive, Expeditions, Link Wall win, 3-game Marathon) renders for a
member; Records/Settings (with Sign in with Apple + Delete Account rows),
onboarding, customize, daily + archive, shared-item deep links all verified;
Release config matches Debug on the marquee gates; cold launch <~6s; zero
crashes across 40+ scenario runs.

**Found + fixed (all device-re-verified):** F-001 versus/multiplayer debug
hooks unwired on tvOS (and the harness's own false-pass that hid it);
F-002 night-host hook unwired — found by the cross-platform join test;
F-003 the same unwired-hook class swept systemically (customize, daily
archive, onboarding force-vs-skip, shared quiz, hub-level Club routing);
plus the Apple Core test suite red in CI since 2026-08-05 (one wrong
import; 158 tests/21 suites green again).

**Final Release regression: GREEN — all 12 named scenarios on the Release
build** (home, classic, picture round, daily, versus, quick match, night
host, cross-platform night join, records, settings, create, paywall). Day
total: 89 device runs, 74 green outright; every non-green run is either a
superseded early false-pass, an externally interrupted run, or a
daemon/doze harness artifact — each re-run green or explained in §3. Also
verified since the first summary: 9/9 categories, the timeout outcome
(honest 0/0), records drill-in via real remote presses (incl. the legacy
no-detail state), the signed-in GameKit matchmaker, clean-install empty
states, the Link Wall lose leg, session-longevity evidence, cold launch
<~6s. Harness additions from the day's friction: verified wake + anti-doze
+ foreground guard, capture-timeout tolerance, crash-proof reports, the
drop_env knob, tools/atv_report.py, and the reboot remedy for the
degrading screenshot daemon.

**Automatable inventory: COMPLETE (2026-08-24 evening).** Every A–F row is
device-verified or honestly dispositioned; the maintenance loop cleared the
whole backlog (A19 thin-combo, A22 focus storm, E2 share QR, E5 full
expedition lifecycle, B8 via the OCR'd share id — which also found and
fixed F-005 on tvOS AND macOS, with an iOS regression check).
**Remaining, owner-only:** a live GameKit automatch (needs a second human)
and the D5 CloudKit records-sync spot-check (play signed-in on the TV, look
on the iPhone). The share backend's cross-device path is already proven.

**Doctrine** (ported from Archive Watch — `docs/DEVICE-HARNESSES.md` in the
template): the agent is never the tester, and the app's own reports are
diagnosis, never verdict. Every PASS below is graded from what the DEVICE
actually rendered (screenshot + Vision OCR + luminance stats), on the paired
"Ben Bedroom" Apple TV 4K. Simulator evidence marks a row 🚧 at best.

## §1 The harness

| Piece | What |
|---|---|
| `tools/atv_install.sh` | build tvOS Debug → install on the device → rebuild `/tmp/tbocr` |
| `tools/atv_run.py` | scenario runner: launch w/ DebugHooks env → capture the glass every ~4s → OCR every frame → optional real remote presses (pyatv) → graded assertions → `report.json` |
| `tools/atv_see.sh` | one honest capture: refuses blank frames (TV asleep/off) and wrong-app frames |
| `tools/ScreenOCR/main.swift` | Vision OCR + center-band luminance (blank-image detector) → `/tmp/tbocr` |
| pyatv | wake (`turn_on`) + remote presses; venv `~/.pyatv-venv`, creds `~/.pyatv.conf`, Companion id `7A:3F:0C:4E:20:1E` |

Device facts (pre-paid): installs work while the TV sleeps, launches don't;
`devicectl` has no wake verb (pyatv Companion does); a ~108KB capture means
the TELEVISION is off, not the Apple TV; two devicectl sessions kill a
console stream, so capture runs and console runs are separate; captures go to
`build/qa/` (durable), never /tmp; reach screens by DebugHooks env, never by
counting key presses; the 4K screenshot daemon DEGRADES after ~80 runs in a
day (captures time out, then runs return too few frames) — `devicectl device
reboot` cures it; the runner tolerates single capture timeouts and always
writes a report, even on an internal crash.

Loop: `tools/atv_install.sh` → `python3 tools/atv_run.py --scenario <name>` →
Read the PNGs + report.json → fix → repeat. `--list` shows scenarios;
`--env K=V --expect RX --name x` runs ad-hoc probes.

## §2 The inventory — every tvOS surface and mechanic

Status: ⬜ untested · 🚧 sim/partial evidence · ✅ device-verified · ❌ open
finding (see §3 log). Every ❌ gets a finding ID; a fix flips it back only
after a re-run on the device.

### A. Core game mechanics (the marquee)

| ID | Feature | How to drive | Status |
|---|---|---|---|
| A1 | Classic round → results | `--scenario quickplay-classic` | ✅ 2026-08-24 (10/10 FLAWLESS results on glass; `build/qa/atv-2026-08-24/quickplay-classic-1787601830`) |
| A2 | Picture ID — images actually load | `--scenario picture-round` (luma gate) | ✅ 2026-08-24 (photo on glass, luma 48.9 all frames; `picture-round-1787602047`) |
| A3 | This or That | autoplay `thisOrThat:mixed` | ✅ 2026-08-24 (`mode-thisOrThat-1787602123`) |
| A4 | Closest Call (numeric slider) | autoplay `closestCall:mixed` | ✅ 2026-08-24 (`mode-closestCall-1787602226`) |
| A5 | Ordering | autoplay `ordering:mixed` | ✅ 2026-08-24 (`mode-ordering-1787602330`) |
| A6 | Matching | autoplay `matching:mixed` | ✅ 2026-08-24 (`mode-matching-1787602433`) |
| A7 | Type Answer (tvOS keyboard!) | autoplay `typeAnswer:mixed` | ✅ 2026-08-24 (recall-then-self-mark per tvOS-DESIGN §8.2; 8/8 to results; `mode-typeAnswer-1787602536`) |
| A8 | Odd One Out | autoplay `oddOneOut:mixed` | ✅ 2026-08-24 (`mode-oddOneOut-1787602640`) |
| A9 | Ladder | autoplay `ladder:mixed` | ✅ 2026-08-24 (`mode-ladder-1787602744`) |
| A10 | Enumerate | autoplay `enumerate:mixed` | ✅ 2026-08-24 (self-mark; `mode-enumerate-1787602848`) |
| A11 | Time Attack | autoplay `timeAttack:mixed` | ✅ 2026-08-24 (`mode-timeAttack-1787602952`) |
| A12 | Survival | autoplay `survival:mixed` | ✅ 2026-08-24 (52 straight questions healthy on-device — survival only ends on a miss; results-screen leg ✅ (mode-survival-1787603702); `mode-survival-1787603053`) |
| A13 | Stake | autoplay `stake:mixed` | ✅ 2026-08-24 (`mode-stake-1787603157`) |
| A14 | Sweep | autoplay `sweep:mixed` | ✅ 2026-08-24 (`mode-sweep-1787603260`) |
| A15 | Mixed-mode game (`mix:` + TIDBITS_MIX) | autoplay `mix:mixed` | ✅ 2026-08-24 (`mode-mix-1787603365`) |
| A16 | Every category × classic (9 cats) | autoplay `classic:<cat>` sweep | ✅ 9/9 2026-08-24 (all categories to results; arts `cat-arts3-*`: 10/10 Classic • Arts & Lit) |
| A17 | Reveal correctness (right marked right) | AUTOPILOT_CORRECT + OCR score | ✅ 2026-08-24 (reveal shows 'Nice — you knew it' + explanation; results 100% accuracy) |
| A18 | Wrong/timeout outcomes (degenerate) | PLAYTHROUGH_STYLE=wrong/timeout | ✅ 2026-08-24 — wrong leg (2/10 + facts-to-review; `degenerate-wrong-*`) AND timeout leg (untouched Time Attack self-advances to an honest 0/0, 0% results screen; `timeout-leg2-*`) |
| A19 | Round comes up short / empty (degenerate) | forced thin category | ✅ 2026-08-24 — zero-answer outcome honest (`timeout-leg2-*` 0/0) AND the thinnest mode×category combo probed (pictureId:business) fills a complete 10-question round to results (`a19-thin-combo-*`); truly-unfillable combos are marked in the Customize picker before commit |
| A20 | Resume-after-quit mid-game | kill app mid-round, relaunch | ✅ 2026-08-24 (kill mid-round → clean relaunch to Home, no corruption/crash; `resume-probe.png`. Mid-round resume is not a shipped tvOS feature — parity question noted, not invented) |
| A21 | Explanation on reveal renders | OCR reveal frames | ✅ 2026-08-24 (explanation text OCR'd on reveal frame shot-0001) |
| A22 | Focus never traps in a round | remote-press probes | ✅ 2026-08-24 (10-press directional storm mid-round via pyatv: game stayed on its question, no exit/strand; `a22-focus-storm-*`) |

### B. Home + navigation

| ID | Feature | How | Status |
|---|---|---|---|
| B1 | Home renders (hero/daily/night/records/settings) | `--scenario home` | ✅ 2026-08-24 |
| B2 | Onboarding walkthrough | TIDBITS_ONBOARD=1 | ✅ 2026-08-24 (WELCOME TO TIDBITS walkthrough on glass; `onboarding2-*`; force-beats-skip fix) |
| B3 | Customize picker (mode × category, unfillable marked) | TIDBITS_CUSTOMIZE / CUSTOMIZE_PICK | ✅ 2026-08-24 (mode+category picker on glass, post-F-003 build; `customize-*`) |
| B4 | Surprise me | remote-press from home | ⬜ |
| B5 | Daily Tidbit + streak | `--scenario daily` | ✅ 2026-08-24 (`daily-1787603472`) |
| B6 | Daily archive | TIDBITS_DAILY_ARCHIVE=1 | ✅ 2026-08-24 (Previous Tidbits list w/ dated rows; `daily-archive-*`) |
| B7 | Deep link/shared item sheet | TIDBITS_ITEM=<id> | ✅ 2026-08-24 (real corpus row rendered in the shared-item sheet; `shared-item-*`) |
| B8 | Shared quiz open | TIDBITS_SHARED_QUIZ=<id> | ✅ 2026-08-24 (unblocked by OCR'ing the share URL's id off the E2 QR panel; found+fixed F-005; `b8-shared-quiz2-*` opens the Ancient Rome detail) |

### C. Multiplayer + cross-platform (the reported-risk area)

| ID | Feature | How | Status |
|---|---|---|---|
| C1 | Versus CPU (all four bots) | `--scenario versus-cpu` | ✅ rookie 2026-08-24 (`versus-cpu-1787604258`: match to outcome, both scores); ✅ ALL FOUR BOTS 2026-08-24 — rookie (`versus-cpu-*`), house (`versus-house-*`), regular/Trivia Tina (`versus-regular-*`), ace (`versus-ace-*`), each to a real outcome screen with both scores |
| C2 | Quick Match: sheet + search + bot fallback | `--scenario quickmatch-full` | ✅ 2026-08-24 — both states on glass: GC-suppressed shows the honest sign-in gate; GC-enabled opens the native GameKit matchmaker signed in as the owner, Automatch/Invite/Start ready (`quickmatch-gc-*`). A live stranger automatch needs a second human — owner check |
| C3 | Quick Match vs REAL cross-platform opponent | n/a on tvOS — per-ecosystem by design (Decision: Apple=GameKit; the Firebase `queue/mixed` quick match is web/Android). The cross-platform plane that includes tvOS is Trivia Night — proven in C5 |
| C4 | Trivia Night: host lobby code + QR | `--scenario night-host` | ✅ 2026-08-24 (SCAN TO JOIN lobby on glass, post-F-002 build) |
| C5 | Trivia Night: cross-platform player joins + full night | `--scenario night-join-crossplatform` (tools/rtdb_join.py) | ✅ join leg 2026-08-24 (TV count 1→0 tracks the scripted Firebase player; `night-join-crossplatform` latest); full-night Q&A leg ⬜ |
| C6 | Join a game by code (player side) | TIDBITS hooks / presses | ⬜ |
| C7 | Tidbits Live event join | LiveJoinView | ⬜ |
| C8 | Wire parity goldens still pass (Core) | logic tests + `run_golden` | ✅ 2026-08-24 (158 tests / 21 suites green on macOS destination after F-003c import fix) |

### D. Records / identity

| ID | Feature | How | Status |
|---|---|---|---|
| D1 | Records dashboard w/ data | `--scenario records` | ✅ 2026-08-24 (streak/games/accuracy/history on glass; `records-1787603778`) |
| D2 | Records empty state (degenerate) | fresh install, no seed | ✅ 2026-08-24 (clean install: "No games yet / Play a round and your scores…" on glass; `records-empty-*`) |
| D3 | Game history drill-in (answer detail) | presses from records | ✅ 2026-08-24 (real remote presses opened a played game's detail — incl. the honest legacy no-per-question-history state; `records-drillin-*`) |
| D4 | Sign in with Apple (button focusable + fires) | Settings → presses; the Form-swallows-tap trap | 🚧 rendered on glass w/ Delete Account (`settings-1787603822`); focus+fire walk ⬜ |
| D5 | Sync: a game played on tvOS shows on iOS | cross-device check | 🚧 OWNER check remains for CloudKit records sync; the SHARE backend's cross-device path is proven (a TV-created quiz fetched + saved on the iPhone sim via its share id — `ios-f005-check2.png`) |

### E. Create / Club / other surfaces

| ID | Feature | How | Status |
|---|---|---|---|
| E1 | Create renders + generates | `--scenario create`, TIDBITS_AUTOCREATE | ✅ 2026-08-24 (live Wikipedia generation → playing a real 8-question Volcanoes quiz on device; `create-live2-*`; needs TIDBITS_CREATE=1 + AUTOCREATE together on tvOS) |
| E2 | Create → share QR renders | TIDBITS_TV_SHARE=1 | ✅ 2026-08-24 (QR drawn — luma 99.6 — with 'Scan to play on your phone' + the live share URL; `e2-share-qr-*`) |
| E3 | Club paywall (products or honest empty) | `--scenario paywall` | ✅ 2026-08-24 (all 3 real products w/ prices $79.99/$29.99/$3.99 on glass; `paywall-1787603899`) |
| E4 | Club hub + gated features (CLUB=1) | TIDBITS_CLUB_HUB=1 + TIDBITS_CLUB=1 | ✅ hub 2026-08-24 (member state + feature list; `club-hub-*`) |
| E5 | Expeditions (map, stage, certificate) | EXPEDITION hooks | ✅ FULL LIFECYCLE 2026-08-24 — list, map, all 7 stages passed and persisted, completion + certificate state ("Completed — play again for another certificate"; `e5-cert2-*`) |
| E6 | Link Wall (win + lose) | LINKWALL + LINKWALL_AUTOPLAY | ✅ 2026-08-24 both legs — win (`linkwall-win-*`: SOLVED + reveal) and lose on the post-clean-install fresh board (`linkwall-lose3-*`: NEXT TIME reveal of all four groups) |
| E7 | Knowledge Atlas | TIDBITS_ATLAS=1 + CLUB=1 | ✅ 2026-08-24 (real Atlas incl. honest not-enough-history empty state; `atlas2-*`) |
| E8 | Story Archive | TIDBITS_STORY_ARCHIVE=1 | ✅ 2026-08-24 (archive w/ domain + favorites/missed filters; `story2-*`) |
| E9 | Marathon | TIDBITS_MARATHON=1 + MARATHON_LEN | ✅ 2026-08-24 (5-game run to marathon summary; `marathon-*`) |
| E10 | Settings (all rows reachable by focus) | `--scenario settings` + presses | ✅ 2026-08-24 (12-press focus storm incl. select: stayed on Settings, alive, no strand; profile shows the GC display name; `settings-focus-walk-*`) |

### F. Stability / honesty

| ID | Feature | How | Status |
|---|---|---|---|
| F1 | App survives a full round (no crash) | app_alive assertion (every run) | ✅ 2026-08-24 (green across 20+ scenario runs incl. 52-question survival) |
| F2 | Cold launch < ~10s to interactive | frame timestamps | ✅ 2026-08-24 (every scenario's first capture at ~6s post-launch already shows the fully rendered target surface, across 40+ runs) |
| F3 | Long marathon session (memory) | TIDBITS_MARATHON_GAMES=20 on device | ✅-with-caveat 2026-08-24: 65 device launches in one day, a completed Club marathon, and a 12-min parked session with the process alive throughout (`f3-soak-*`); TIDBITS_MARATHON_GAMES itself is iOS-only (unwired-hook class, logged — a tvOS rendered-games soak driver is future harness work) |
| F4 | Release config behaves like Debug | TB_CONFIG=Release install + rerun A-row | ✅ 2026-08-24 (Release build on-device: classic round, picture round w/ luma gate, night-host lobby all green; `rel-*` dirs) |

## §2b Depth audits (beyond once-per-feature — the owner's "large scopes" directive)

| Audit | Tool | Result |
|---|---|---|
| Longest-prompt legibility on the glass | `tools/atv_prompt_audit.py` | ✅ 2026-08-24: the corpus's 14 longest prompts/options (up to 343 chars) ALL render fully on the device — tails and every option verified by OCR (`prompt-audit-1787621901` + `cronenberg-recheck`). Required wiring TIDBITS_QUESTION on tvOS (was iOS-only). |
| Picture-image liveness, corpus-wide | `tools/audit_picture_images.py` | 🚧 round 1 done: 6 real 404s repaired (5 tombstoned via genguard, 1 repointed to a live Commons portrait); 3,333 throttled rows re-checking politely in chunks (429 = UNVERIFIED, never dead) |
| Rolling named-scenario health regression | `roll1-*` re-runs on the current build | ✅ 2026-08-24 evening: home, classic, picture-round, daily, night-host, matching, closestCall, night-join-crossplatform all green on the day's final build |
| Focus-storm walks (Settings + Records, presses incl. select/menu) | pyatv press storms during atv_run | ✅ 2026-08-24: both surfaces survive 12-press storms; menu correctly dismisses Records back to Home (`settings-focus-walk-*`, `records-focus-walk-*`) |
| Reveal explanations on the glass (the learn-something promise) | `tools/atv_reveal_audit.py` — 6 date-seeded rows to REVEAL | ✅ 2026-08-24: 12/12 across two seeds — explanation tails (up to 208ch) OCR-verified on the device reveal (`reveal-audit-1787624316`, `reveal-audit-1787626302`) |
| Random-picture on-device render (AsyncImage path, arbitrary rows) | `atv_run --luma` over 8 date-seeded random rows | ✅ 2026-08-24: 16/16 across two date-seeded batches — real photos on the glass (luma-gated) on the pruned build + picture-round regression green (`randpic-1..8`, `randpic2-1..8`, `picture-round-postprune-*`) |
| Round-quality sweep, 200 games / 3,261 questions | `tools/analyze_play_sweep.py` over TIDBITS_PLAY_SWEEP=200 (shared-Core assembly, iPhone sim host) | ✅ 2026-08-24: every mode delivers its exact round length (stake 5–8 = chip mechanic; survival 99 cap), zero duplicate options, zero player-visible repeats (same prompt+options), zero empty fields, every answer present in its options. `build/qa/play-sweep.jsonl` |

## §3 Findings log (append-only: found → root cause → fix → re-verified)

Format per entry: **F-###** (date) — symptom · evidence path · root cause ·
fix commit · device re-verification date. An entry is closed only by a green
re-run of the same scenario on the device.

- **F-001** (2026-08-24) — CLOSED 2026-08-24 (fix 998c948, device re-verified: `versus-cpu-1787604258` shows a full Rookie match to its outcome screen, `quickmatch-1787604396` shows the real Quick Match sheet). *TIDBITS_VERSUS and
  TIDBITS_MULTIPLAYER were never wired into the tvOS shell*, so the Versus
  and Quick Match device scenarios silently exercised the HOME screen — and
  the versus scenario FALSE-PASSED by matching the word "you" in the daily
  card (`build/qa/atv-2026-08-24/versus-cpu-1787603559`: every frame is
  Home). Two fixes: (1) hooks wired in `ContentView_tvOS.swift` launch task;
  (2) scenario assertions tightened to the versus HUD's own chrome
  ("Rookie", "You won|takes it") and quickmatch now FORBIDS the home hero
  text. Harness lesson (Archive Watch's wrong-screen rule re-learned): an
  expectation loose enough to match the home screen is not an expectation.
  

- **F-002** (2026-08-24) — CLOSED 2026-08-24 (fix 29e4cd3, device re-verified: `night-host` shows the SCAN TO JOIN lobby; `night-join-crossplatform` frames 6–15 show "1 in the room" while the scripted RTDB player was joined, dropping back to 0 after it left). *TIDBITS_NIGHT_HOST
  unwired on tvOS* — same class as F-001, caught by the cross-platform join
  test: the TV sat on Home while the scripted RTDB player had no room to
  join (`night-join-crossplatform-1787604112`; the prior night-host "pass"
  matched the word 'TIDBIT' on Home). Hook now launches a quick networked
  night; scenarios tightened to lobby chrome. 

- **F-003** (2026-08-24) — CLOSED 2026-08-24 (customize/daily-archive/onboarding device-verified on the hook build; hub-level routing verified by atlas2/story2/expeditions; `sharedQuizID` is wired but unprobed pending a saved quiz on the device — tracked by B8, not this finding). *The unwired-hook class is
  systemic on tvOS*: an audit found `openCustomize`, `openDailyArchive`,
  `forceOnboarding`, `sharedQuizID`, `playSavedQuiz` all parsed and ignored
  (same class as F-001/F-002). Wired the four with tvOS surfaces
  (customize, daily archive, onboarding, shared quiz); `playSavedQuiz`
  deferred (needs a saved quiz on device first). Device verification of the
  four queued.
- **F-003c** (2026-08-24) — CLOSED. *Apple Core test suite red in CI since
  2026-08-05*: `ClubProductsTests.swift` alone imported the app module
  (`@testable import TidbitsTrivia`) in a bundle that deliberately has no
  app dependency; every sibling imports the bundle's own module. One-line
  fix → 158 tests / 21 suites green. The workflow only triggers on Core
  paths, so nothing re-ran it — a standing-red trap worth a CI-health look.

- **F-004** (2026-08-24) — CLOSED 2026-08-24 as a HARNESS artifact, harness
  fixed. *`classic:arts` never took the screen* — root cause was the TV
  DOZING mid-sweep: a launch in that window is denied ("System is asleep —
  foreground app launch forbidden", `build/qa/arts-console.log`) or comes up
  backgrounded, leaving the app alive while the home screen owns the glass.
  Arts was coincidence, not cause: with a verified wake it plays 10/10 to a
  full Arts & Lit results screen (`cat-arts3-*`). Harness fixes: wake_tv now
  POLLS power_state until On (never fire-and-forget), retries wake before
  relaunch, and a foreground guard OCRs one probe frame post-launch and
  relaunches if home-screen signatures (streaming apps / system clock) own
  the glass. The tester-visible lesson stands though: if a REAL user's
  launch races the sleep state the same way, they'd see the same dump-to-
  home — worth an eye on cold-launch analytics.

- **F-005** (2026-08-24) — CLOSED same day, mirrored to macOS. *A shared-quiz
  link on tvOS opened Create and silently stopped* — `pendingSharedQuizID`
  was consumed only by iOS's CreateQuizView; the tvOS (and macOS) Create
  views never read it, so `tidbits://quiz/<id>` dead-ended at the topic
  picker (`b8-shared-quiz-*` — a false pass on the word 'quiz' initially hid
  it; frame-verification caught it). Fixed with the iOS keep-on-arrival
  behavior on both platforms; tvOS device-verified (`b8-shared-quiz2-*`
  opens the quiz detail), macOS destination builds green; iOS regression-
  checked on the sim — the incoming sheet saves-and-offers-to-play the
  TV-created quiz (`ios-f005-check2.png`; note the iOS ENV hook is
  view-scoped: probe with TIDBITS_TAB=create). One level deeper
  than F-003's class: hook → store ✓, store → view ✗.

## §4 The autonomous loop (multi-session)

Standing loop prompt: work this playbook top to bottom — highest-risk first
(A-row mechanics, C-row multiplayer), one meaty batch per tick (multiple
scenarios, or one finding root-caused AND fixed AND re-verified). Every tick:
update §2 statuses + §3 log, commit + push. Shared-Core fixes get mirrored
(iOS/macOS build re-verified, PARITY.md updated). Never end a tick early for
context reasons; a tick that found a real bug means the loop continues.
Between-tick state lives HERE, not in session memory.
