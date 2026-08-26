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
| C5 | Trivia Night: cross-platform player joins + full night | scripted RTDB joiner + REAL Chrome web client | ✅ FULL GAME LOOP 2026-08-25: the shipped web app in a real Chrome instance joined the TV-hosted room via tidbitstrivia.com/#/live/QATV ("YOU'RE IN"), the TV counted it ("1 in the room"), the night started with the SAME question on both screens, Chrome's answer bumped the TV to "1 answered", and the TV's reveal propagated back green to Chrome. Evidence: `chrome-join-host-*`, `chrome-join-now.png`, `chrome-night-started.png`, `chrome-answered.png`, `chrome-reveal.png` + Chrome screenshots. Scripted joiner legs also green (10 runs) |
| C6 | Join a game by code (player side) | web join UI | ✅ 2026-08-25 (the deep link prefilled QATV; team-name + Join flow worked in a real browser — the exact flow a phone player uses) |
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
| E1 | Create renders + generates | `--scenario create`, TIDBITS_AUTOCREATE | ✅ 2026-08-24 (live Wikipedia generation on device for TWO topics — Volcanoes `create-live2-*`, Ancient Egypt `create-egypt-*`; needs TIDBITS_CREATE=1 + AUTOCREATE together on tvOS) |
| E2 | Create → share QR renders | TIDBITS_TV_SHARE=1 | ✅ 2026-08-24 (QR drawn — luma 99.6 — with 'Scan to play on your phone' + the live share URL; `e2-share-qr-*`) |
| E3 | Club paywall (products or honest empty) | `--scenario paywall` | ✅ 2026-08-24 (all 3 real products w/ prices $79.99/$29.99/$3.99 on glass; `paywall-1787603899`) |
| E4 | Club hub + gated features (CLUB=1) | TIDBITS_CLUB_HUB=1 + TIDBITS_CLUB=1 | ✅ hub 2026-08-24 (member state + feature list; `club-hub-*`) |
| E5 | Expeditions (map, stage, certificate) | EXPEDITION hooks | ✅ FULL LIFECYCLE 2026-08-24 — 20th Century: list, map, all 7 stages, completion+certificate (`e5-cert2-*`); Around the World: map + stage-1 pass/unlock too (`exp2-map-*`, `exp2-stage-*`) |
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
| Picture-image liveness, corpus-wide | `tools/audit_picture_images.py` (8 polite chunks) | ✅ COMPLETE 2026-08-24: **5,715/5,715 URLs verified live, 0 unverified** — from 5,721 originals: 6 rows tombstoned via genguard (Commons file gone, no free replacement), 2 repointed to live Commons portraits (Heyer, Selena), every repair shipped in both copies + device-regressed on the final build incl. the Selena repoint rendering a real photo (`imgchunk-0..8.json`, `picture-round-final-*`, `selena-verify-*`) |
| Rolling named-scenario health regression | `roll1-*` re-runs on the current build | ✅ TWENTY-TWO consecutive full laps green (roll2–roll23, ~24+ hours of continuous rotation) — all 12 named scenarios each lap; the CHROME MULTIPLAYER LOOP has passed FIFTEEN times as the lap-closer (pass #14 caught corpus finding F-011 live; pass #15 green on the repaired corpus) (pass #8 took three attempts — the two aborted runs surfaced F-008/F-009/F-010 and verified the F-008 fix; the official run went first-press clean with the QADBG overlay armed) (real browser joins, same question both screens, answer counted, reveal + points back in Chrome; passes #3–#7 also asserted the F-006 invariant). Pass #7 additionally exercised the RECONNECT path: Chrome discarded the background tab mid-night, the reload landed on the prefilled join form (live.js keeps `joined` in memory by design), and ONE tap rejoined straight into the in-progress question with score intact via the persistent anon uid. Enhancement candidate (owner call, not a bug): auto-rejoin on load when sessionStorage says the player was joined |
| Focus-storm walks (Settings + Records, presses incl. select/menu) | pyatv press storms during atv_run | ✅ 2026-08-24: Home, Settings, Records all survive 12-press storms incl. select+menu; menu dismisses correctly everywhere (`home-press-storm-*`, `settings-focus-walk-*`, `records-focus-walk-*`) |
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

- **F-006** (2026-08-25) — CLOSED same day (Core fix, device-verified). *A
  night restarted on the same room code inherited prior answers for matching
  question ids*: Chrome-loop pass #2's freshly started night showed
  "1 answered" on Q1 before any new answer arrived — the previous session's
  answer under the same `live/QATV/answers/{qid}` persisted. **Fix v1
  (server-side clear) is impossible**: RTDB security rules deny the host
  deleting other uids' answer nodes (verified — REST DELETE on
  `answers/` → 401 Permission denied). **Fix v2 (shipped)**: `LiveHostNet`
  captures `sessionStartMS` in `open()` and `applyAnswers` filters out any
  answer with `ts < sessionStartMS` — stale ledger rows can't inflate the
  answered-count or leak into reveal scoring. Device-verified with the stale
  answer deliberately left in RTDB as the fixture: fresh QATV night read
  "Q1/5 • 0 answered", ChromeBot's live answer flipped it to "1 answered",
  reveal scored green. macOS + iOS mirror builds green (shared Core).

- **F-007** (2026-08-25) — CLOSED same day (found BY the Chrome loop, pass
  #6 served it live). *The `num:P2043` river-length template dropped the
  definite article*: "Approximately how long is Nile?" / "is Danube?" /
  "is Po?". The existing `fix_missing_article.py` is deliberately head-noun
  conservative (…River/…Sea only) and could not touch bare river names —
  but the P2043 gate has already proven Q4022 (river), which makes the
  aggressive rule safe. Fixed in BOTH places: `gen_numeric.py` now renders
  river-gated subjects as "the {title}" in prompt + explanation (future
  regenerations), and the new `tools/corpus/fix_river_articles.py` repaired
  the 45 shipped rows (prompts AND explanations — some prompts had been
  articled earlier while their explanations were not). Full
  `resync_corpus.sh`: quality gates pass, planted defects caught, Apple==web
  Daily golden parity PASS, suggested topics playable. Rebuilt + installed;
  glass-verified "how long is the Nile?" on the device (f007-glass run).
  Sibling numeric templates checked: elevation/area/height/weight gates are
  geo/person and already covered by the conservative script's head-noun
  rule; only the river gate had the bare-name class.

- **F-008** (2026-08-25) — CLOSED same day (Core fix, device-verified
  twice). *A reused room code showed the previous session's SCORES in a
  fresh night's standings* (ChromeBot at 7 points during Q1 pre-reveal).
  Unlike `answers/` (whose delete the rules deny — F-006), the host OWNS
  `scores/`, so `LiveHostNet.open()` now deletes `scores/` and zeroes the
  local dict alongside the answers sessionStartMS filter; `teams/` still
  persists deliberately (rejoin keeps the name). Glass-verified on a fresh
  QATV night: STANDINGS rows read 0 with the prior session's points still
  in RTDB history (frames chrome-loop8b-q1b + f009-dbg-reveal). macOS +
  iOS mirror builds green.

- **F-009** (2026-08-25) — OPEN (intermittent), diagnostic now armed.
  Twice during pass #8, the host stopped acting on SELECT at the question
  screen: five companion selects (rc=0) on the visibly focused Reveal, one
  on Lock — no state change — while LEFT/RIGHT moved focus normally (frames
  chrome-loop8-reveal3/focustest/locktest). Same session's select DID start
  the night from the lobby; a device reboot didn't prevent a recurrence,
  then a later scripted run revealed fine on the first press. Both
  `reveal()` and `lock()` guard silently on `stage == .playing` — so the
  question was "press not delivered" vs "action fired but hung": the view
  now has an env-gated on-glass counter (`TIDBITS_QA_OVERLAY=1` → "QADBG
  presses=N stage=… revealed=…") that settles it the next time it happens.
  The armed run showed presses=1 → revealed=1 (path healthy). Loop
  discipline: host the Chrome-loop nights WITH the overlay env; on a stuck
  reveal, read the counter before touching anything. Related known flake:
  the FIRST companion select after idle is often dropped (lobby Start
  regularly needs one retry) — retry once before investigating.

  **F-009 RESOLVED as harness-class (2026-08-25 evening, root cause
  found during probe P1):** a fresh SINGLE-command pyatv Companion
  connection frequently DROPS its press (drop rate grew to 100% within a
  long app session), while a connection that runs a warm-up command first
  delivers reliably — `atvremote … --protocol companion power_state
  select` advanced 30+ presses with only occasional single retries where
  bare `select` had hard-stuck twice (Reveal AND Next). The app's handlers
  are healthy whenever a press is actually delivered (QADBG proved
  delivery↔action 1:1), and real Siri remotes don't use this path — so
  players are unaffected. Ratchet: ALL harness presses now use the warmed
  form. Related device fact: the Apple TV SLEPT mid-night during a ~5-min
  idle gap (long-running interactive probes must keep pressing or re-wake;
  the ~108KB black-frame capture signature also appears when the box
  sleeps).

- **F-010** (2026-08-25) — CLOSED same day (four-platform fix,
  browser+device verified). *A player still connected across a host
  session restart was blocked from answering*: ALL FOUR join clients (web
  `js/live.js`, Apple `LivePlayerClient.swift`, Android `LiveRoom.kt`,
  Windows `LivePlayerClient.cs`) keyed submitted state by qid alone, and
  positional qids (r0q0…) collide across sessions — the client showed
  "Locked in — waiting for the reveal" on the NEW session's Q1 with the OLD
  chosen option highlighted. Fix: `meta.createdAt` is the session identity;
  every client resets `submittedQid`/`chosen` (+ web tally counters) when
  it changes (Android's `LiveMeta` gained the `createdAt` field). Verified
  live on the deployed web app: joined, answered session 1's Q1
  ("1 answered"), host restarted on the same code, the UNTOUCHED tab showed
  the new session's Q1 as answerable and its answer counted ("1 answered"
  frames f010-s1/s2-*). tvOS + Android Kotlin + Windows Core builds green.

- **F-011** (2026-08-25) — CLOSED same day (corpus + generator,
  glass-verified). *A superlative row shipped a factually WRONG answer*:
  "Which one below has the greatest length?" crowned a Tokay gecko (stored
  152 — centimetres — labeled 'm') over a humpback whale (16 m).
  Source audit of the fact table: P2043 outside geography mixes units per
  ENTRY (animal cm/m, car mm, plane ??, asteroid km — all labeled 'm');
  geography lengths are km-coherent. Root cause: `gen_facts2.py`'s
  SUP_KEEP gate map simply had NO P2043 entry, so every category was
  admitted where the sibling families were geography-gated. Fix:
  **348 rows tombstoned + pruned** (science 296, mixed-category 48,
  unknown 4) with the reason recorded in tombstones.json; **268 geography
  rows kept**; the generator gained the missing geography gate; all 14
  sup:P2048 height rows audited value-by-value and coherent (kept). Tail
  fix in the same pass: the surviving reveals printed the km figure as
  "m" ("Malaita … (160 m)") — generator now formats P2043 superlatives as
  km and `fix_sup_length_units.py` repaired the 76 shipped small-value
  rows. Two full resyncs green (quality gates + Apple==web Daily golden),
  sw.js CACHE v61→v62, Pages deploys green, rebuilt + installed, and the
  Malaita row glass-verified reading "(160 km)" (run f011-glass2).

- **F-012** (2026-08-25) — CLOSED same evening (69 rows repaired,
  data-plane verified on all mirrors + the live site). *Picture stems
  asserted the wrong subject class*: probe P1 served "Which war is this?"
  over a portrait of Werner Mölders; the stem-assignment keyed off subject
  CATEGORY (war/business/city), so humans filed there got class stems and
  non-humans got person stems ("Who is this?" over Buckingham Palace, "Can
  you name this person?" over the SR-71). `fix_picture_stem_class.py`
  repairs both directions from the definitive p31 signal — EXACT-token Q5
  (the first audit's substring check matched Q515, city, and flagged 95
  false positives; the token fix cut it to the real 69): 17 humans →
  "Who is this?", 52 non-humans → "Can you identify this?". Resync green,
  CACHE v63, Pages deploy green; the repaired stem confirmed identical in
  assets/, Apple Resources/, Android assets/, AND fetched from the live
  site. (TIDBITS_QUESTION can't target picture.json rows — it resolved the
  classic-corpus Mölders row — so on-glass verification rides the already-
  proven picture-round stem rendering, A2/P1.) Follow-up queued: the
  bizpic distractor pool mixes people and companies in one option set
  (Tim Cook offered PwC/EBay/Jeff Bezos), same type-mixing family as the
  "Japan" film distractor.

- **Probe P1 (2026-08-25 evening) — FULL-NIGHT Chrome playthrough: PASS.**
  Across two sessions (the first died when the Apple TV slept mid-night —
  see F-009 note): round 1 (5 MCQs answered from Chrome, reveals + counts
  correct), round 1→2 transition, round 2 PICTURE ROUND (real images
  render in the web view — album art, portrait, text-diagram), round 2→3
  transition, round 3 CLOSEST WINS (web numeric slider: adjust → Submit →
  locked-in disabled state), and the ENDED screen on BOTH sides (TV:
  "STANDINGS / ChromeBot wins!"; web: "THAT'S A WRAP / Final score" +
  Done). The untouched web client followed the host's session RESTART to
  the new night and to its end — the F-010 fix observed working live.
  Evidence: build/qa/atv-2026-08-25/p1-*.png + p1b-*.png.

- **Probe P2 (2026-08-25 evening) — two simultaneous players: PASS.** A
  browser player (tab) and a scripted RTDB player joined QATV together:
  lobby read "2 in the room"; both answered Q1 ("2 answered"); reveal
  scored them apart and the STANDINGS panel ordered them by score with the
  crown on the leader (1 pt correct browser answer above the 0-pt scripted
  wrong answer; frame p2-reveal.png). Two observations: (a) two TABS in
  one browser share the Firebase anon uid and merge into ONE team — the
  second tab's join renames the team (rejoin-friendly by design; a real
  second player is a different browser/device); (b) a join click issued
  before the page settles is silently lost — the P2 tab-A join needed the
  page to finish loading.

- **Probe P3 (2026-08-25 evening) — reveal stress-run: press-path fully
  characterized.** Post-reboot, warmed presses at ~1.5s spacing delivered
  11 of 12 (QADBG presses=6, position r2q1-revealed after 6 cycles = one
  silent drop, no wedge). Before the reboot the path had degraded to
  TOTAL loss — even warmed presses and focus nudges failed at the lobby —
  confirming delivery decays with cumulative companion connections and a
  device REBOOT is the reset. New device fact: companion HID presses do
  NOT reset the box's sleep timer — it slept mid-press-stream (~108KB
  black frames + PowerState.Off while presses were flowing). Net harness
  doctrine: warmed presses + retry for normal use; reboot when delivery
  degrades; expect sleep during long interactive probes regardless of
  press activity (wake + relaunch recovers).

- **Probe P4 part 1 (2026-08-25 evening) — chron: family audit: 77 rows
  tombstoned.** Re-derived every chron: row's "earliest" claim against the
  CURRENT source dates (P571/P577/P569) with title-collision filtering
  (2,276 rows have colliding or since-pruned titles — unverifiable, kept;
  8,868 verified clean). 77 rows' claims are contradicted by their own
  options' current values — value drift or title-identity drift since
  generation (Killing Eve "earliest" over Teen Wolf, Walmart over Levi
  Strauss, the FICTIONAL Hercule Poirot's 1870 "birth" beating Goethe).
  Per the wrong-answer precedent all 77 tombstoned + pruned; resync green,
  CACHE v64. The 178 ancient-negative-year rows (Athens −7000) inspected
  and legitimate. Remaining P4 legs queued: closest bounds, enumerate
  totals, bizpic mixed-type distractors.

Standing loop prompt: work this playbook top to bottom — highest-risk first
(A-row mechanics, C-row multiplayer), one meaty batch per tick (multiple
scenarios, or one finding root-caused AND fixed AND re-verified). Every tick:
update §2 statuses + §3 log, commit + push. Shared-Core fixes get mirrored
(iOS/macOS build re-verified, PARITY.md updated). Never end a tick early for
context reasons; a tick that found a real bug means the loop continues.
Between-tick state lives HERE, not in session memory.
