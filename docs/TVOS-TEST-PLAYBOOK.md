# tvOS Test Playbook — every feature, observed on the glass

**Mission (owner, 2026-08-24):** testers report significant issues in the tvOS
app. Systematically test EVERY screen and feature on the real Apple TV — in
particular the quiz/game mechanics (images loading, all question types
working, cross-platform + online multiplayer) — so players are never confused
or unable to do something the app promises. Fix what's found; mirror
cross-platform fixes (Core is shared with iOS/macOS); verify on the glass.

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
counting key presses.

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
| A16 | Every category × classic (9 cats) | autoplay `classic:<cat>` sweep | ⬜ |
| A17 | Reveal correctness (right marked right) | AUTOPILOT_CORRECT + OCR score | ✅ 2026-08-24 (reveal shows 'Nice — you knew it' + explanation; results 100% accuracy) |
| A18 | Wrong/timeout outcomes (degenerate) | PLAYTHROUGH_STYLE=wrong/timeout | ⬜ |
| A19 | Round comes up short / empty (degenerate) | forced thin category | ⬜ |
| A20 | Resume-after-quit mid-game | kill app mid-round, relaunch | ⬜ |
| A21 | Explanation on reveal renders | OCR reveal frames | ✅ 2026-08-24 (explanation text OCR'd on reveal frame shot-0001) |
| A22 | Focus never traps in a round | remote-press probes | ⬜ |

### B. Home + navigation

| ID | Feature | How | Status |
|---|---|---|---|
| B1 | Home renders (hero/daily/night/records/settings) | `--scenario home` | ✅ 2026-08-24 |
| B2 | Onboarding walkthrough | TIDBITS_ONBOARD=1 | ⬜ |
| B3 | Customize picker (mode × category, unfillable marked) | TIDBITS_CUSTOMIZE / CUSTOMIZE_PICK | ⬜ |
| B4 | Surprise me | remote-press from home | ⬜ |
| B5 | Daily Tidbit + streak | `--scenario daily` | ✅ 2026-08-24 (`daily-1787603472`) |
| B6 | Daily archive | TIDBITS_DAILY_ARCHIVE=1 | ⬜ |
| B7 | Deep link/shared item sheet | TIDBITS_ITEM=<id> | ⬜ |
| B8 | Shared quiz open | TIDBITS_SHARED_QUIZ=<id> | ⬜ |

### C. Multiplayer + cross-platform (the reported-risk area)

| ID | Feature | How | Status |
|---|---|---|---|
| C1 | Versus CPU (all four bots) | `--scenario versus-cpu` | ✅ rookie 2026-08-24 (`versus-cpu-1787604258`: match to outcome, both scores); house/regular/ace ⬜ |
| C2 | Quick Match: sheet + search + bot fallback | `--scenario quickmatch` | 🚧 sheet opens on device (`quickmatch-1787604396`); full match flow ⬜ |
| C3 | Quick Match vs REAL cross-platform opponent | web client joins `queue/mixed` (script TBD) | ⬜ |
| C4 | Trivia Night: host lobby code + QR | `--scenario night-host` | ✅ 2026-08-24 (SCAN TO JOIN lobby on glass, post-F-002 build) |
| C5 | Trivia Night: cross-platform player joins + full night | `--scenario night-join-crossplatform` (tools/rtdb_join.py) | ✅ join leg 2026-08-24 (TV count 1→0 tracks the scripted Firebase player; `night-join-crossplatform` latest); full-night Q&A leg ⬜ |
| C6 | Join a game by code (player side) | TIDBITS hooks / presses | ⬜ |
| C7 | Tidbits Live event join | LiveJoinView | ⬜ |
| C8 | Wire parity goldens still pass (Core) | logic tests + `run_golden` | ⬜ |

### D. Records / identity

| ID | Feature | How | Status |
|---|---|---|---|
| D1 | Records dashboard w/ data | `--scenario records` | ✅ 2026-08-24 (streak/games/accuracy/history on glass; `records-1787603778`) |
| D2 | Records empty state (degenerate) | fresh install, no seed | ⬜ |
| D3 | Game history drill-in (answer detail) | presses from records | ⬜ |
| D4 | Sign in with Apple (button focusable + fires) | Settings → presses; the Form-swallows-tap trap | 🚧 rendered on glass w/ Delete Account (`settings-1787603822`); focus+fire walk ⬜ |
| D5 | Sync: a game played on tvOS shows on iOS | cross-device check | ⬜ |

### E. Create / Club / other surfaces

| ID | Feature | How | Status |
|---|---|---|---|
| E1 | Create renders + generates | `--scenario create`, TIDBITS_AUTOCREATE | 🚧 picker renders (`create-1787603857`); live generation ⬜ |
| E2 | Create → share QR renders | TIDBITS_TV_SHARE=1 | ⬜ |
| E3 | Club paywall (products or honest empty) | `--scenario paywall` | ✅ 2026-08-24 (all 3 real products w/ prices $79.99/$29.99/$3.99 on glass; `paywall-1787603899`) |
| E4 | Club hub + gated features (CLUB=1) | TIDBITS_CLUB_HUB=1 + TIDBITS_CLUB=1 | ⬜ |
| E5 | Expeditions (map, stage, certificate) | EXPEDITION hooks | ⬜ |
| E6 | Link Wall (win + lose) | LINKWALL + LINKWALL_AUTOPLAY | ⬜ |
| E7 | Knowledge Atlas | TIDBITS_ATLAS=1 + CLUB=1 | ⬜ |
| E8 | Story Archive | TIDBITS_STORY_ARCHIVE=1 | ⬜ |
| E9 | Marathon | TIDBITS_MARATHON=1 + MARATHON_LEN | ⬜ |
| E10 | Settings (all rows reachable by focus) | `--scenario settings` + presses | 🚧 renders w/ profile+account rows (`settings-1787603822`); focus walk ⬜ |

### F. Stability / honesty

| ID | Feature | How | Status |
|---|---|---|---|
| F1 | App survives a full round (no crash) | app_alive assertion (every run) | ✅ 2026-08-24 (green across 20+ scenario runs incl. 52-question survival) |
| F2 | Cold launch < ~10s to interactive | frame timestamps | ⬜ |
| F3 | Long marathon session (memory) | TIDBITS_MARATHON_GAMES=20 on device | ⬜ |
| F4 | Release config behaves like Debug | TB_CONFIG=Release install + rerun A-row | ⬜ |

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

## §4 The autonomous loop (multi-session)

Standing loop prompt: work this playbook top to bottom — highest-risk first
(A-row mechanics, C-row multiplayer), one meaty batch per tick (multiple
scenarios, or one finding root-caused AND fixed AND re-verified). Every tick:
update §2 statuses + §3 log, commit + push. Shared-Core fixes get mirrored
(iOS/macOS build re-verified, PARITY.md updated). Never end a tick early for
context reasons; a tick that found a real bug means the loop continues.
Between-tick state lives HERE, not in session memory.
