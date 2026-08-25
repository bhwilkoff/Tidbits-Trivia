# RESUME: the tvOS QA loop (written for post-compaction pickup, 2026-08-25 ~09:00)

**The standing task**: the owner asked for an autonomous loop (ScheduleWakeup,
**300s cadence — never lengthen without the owner**) that systematically tests
every Apple TV feature on the REAL paired device, does LARGE work per tick
(never a 20-second check-and-wait), fixes what it finds, and keeps improving
the harness. `docs/TVOS-TEST-PLAYBOOK.md` is the single source of truth —
campaign summary at top, §2 inventory, §2b depth audits, §3 findings log.

## Current state (exact)

- **Campaign COMPLETE + depth audits COMPLETE** — every A–F row device-verified
  or honestly dispositioned; 5,715/5,715 picture-image URLs live; 200-game
  round-quality sweep clean; all details in the playbook.
- **Rolling-health mode**: **NINETEEN consecutive full 12-scenario laps green**
  (roll2–roll20). **Lap 21 is next, starting at `home`**
  (`--name roll11-<s>`; the newest `rollN-*` dir in `build/qa/atv-<date>/`
  marks rotation position). Rotation order: home, quickplay-classic,
  picture-round, daily, night-host, night-join-crossplatform, versus-ace
  (env form: `--env TIDBITS_VERSUS=ace --env TIDBITS_AUTOPILOT=1 --expect Ace
  --minutes 1.3`), quickmatch, records, settings, create, paywall — then the
  lap-closing **Chrome multiplayer loop** (below), passed 12×. Host the night WITH
  --env TIDBITS_QA_OVERLAY=1 (QADBG counter diagnoses F-009); first select
  after idle often drops — retry once. Open: only F-009 (intermittent,
  QADBG overlay armed). F-010 closed: all four join clients reset answer
  state on a meta.createdAt change — verified live in Chrome.
- Every tick commits + pushes (`git pull --rebase` first — the dailyboard
  cron races).
- **Open findings: NONE.** F-007 closed 2026-08-25 (river articles: generator +
  fix_river_articles.py + full resync + glass-verified "the Nile").
  F-006 closed 2026-08-25: rules deny a host
  deleting other uids' answer nodes (v1 impossible), so `LiveHostNet` now
  filters answers with `ts < sessionStartMS` captured in `open()` —
  device-verified ("0 answered" on a fresh room with a stale ledger row).
- **Owner-only remainder**: live GameKit automatch (needs a second human);
  D5 CloudKit records-sync spot-check (play signed-in on TV, look on iPhone).

## The per-tick loop shape

```bash
python3 tools/atv_run.py --scenario <next> --name rollN-<next>   # grep RESULT
python3 tools/atv_report.py 2026-08-25                           # day table
git fetch -q; git log --oneline HEAD..origin/main | head -2      # new commits?
# + SCRATCHPAD/docs check for owner notes; commit+push if anything changed
```
Green run = ScheduleWakeup noop:false. A FAIL is as likely a harness-expectation
gap as an app bug — **the frames decide** (Read the PNGs / ocr.json in the run
dir) before filing; fix + re-verify on the device before moving on.
Milestone commits at each lap close; findings go in playbook §3 (append-only,
closed only by a green device re-run).

## The Chrome multiplayer loop (each lap's 13th item; passed 2×)

1. Background: `python3 tools/atv_run.py --env TIDBITS_NIGHT_HOST=1 --env
   TIDBITS_LIVE_CODE=QATV --expect "SCAN TO JOIN" --minutes 2.5 --name
   chrome-loopN-host` — wait until its run dir has shot-0001.png.
2. Chrome (ToolSearch-load `mcp__claude-in-chrome__tabs_context_mcp,navigate,
   computer,tabs_close_mcp` if deferred; `tabs_context_mcp createIfEmpty`):
   navigate `tidbitstrivia.com/#/live/QATV` (code prefills), **screenshot
   first and click what you see — the viewport size varies**, type team name
   `ChromeBot`, click Join → screenshot expects **YOU'RE IN**.
3. `TB_EXPECT="-" bash tools/atv_see.sh <png> 200000` + `/tmp/tbocr` →
   **"1 in the room"** on the TV.
4. `~/.pyatv-venv/bin/atvremote --id 7A:3F:0C:4E:20:1E --protocol companion
   select` → TV shows **ROUND 1 + a question**; Chrome screenshot shows the
   **same question**; click an answer → TV shows **"1 answered"** (note F-006:
   a stale prior answer can pre-set this on a reused code); `select` again →
   Chrome shows the **green reveal** (+ points).
5. Close the tab; relaunch the app bare (`--terminate-existing`, env
   `{"TIDBITS_SKIP_ONBOARD":"1","TIDBITS_NO_GAMECENTER":"1"}`) to end hosting;
   record in the playbook rolling row; commit.

## Harness facts a fresh context must not re-learn

- Device: "Ben Bedroom" ATV, devicectl UDID `C3FBA9DE-4A60-555B-A65F-80D6809A275B`,
  pyatv Companion id `7A:3F:0C:4E:20:1E`, venv `~/.pyatv-venv` (**python3.12**;
  pyatv breaks on 3.14), creds `~/.pyatv.conf`.
- Bundle `com.learningischange.tidbitstrivia`; build via `tools/atv_install.sh`
  (needs `-allowProvisioningUpdates`, DEVELOPER_DIR=Xcode-beta); OCR binary:
  `swiftc -O tools/ScreenOCR/main.swift -o /tmp/tbocr` (tmp gets cleared).
- `tools/atv_run.py` has: verified wake (TV dozes → launches denied or land
  BACKGROUNDED — home screen on glass while app_alive passes), foreground
  guard, anti-doze re-wake, capture-timeout tolerance, crash-proof
  report.json, `drop_env` (quickmatch-full drops NO_GAMECENTER), `--luma`
  image gate, `--env K=V` (ONE pair per flag).
- Loose OCR expectations FALSE-PASS on the home screen — expectations must
  match the target surface's own chrome; content-facing regexes word-bounded
  ("error" matched inside "terrorists").
- Background tasks get reaped ~10–15 min: keep every task <8 min, chunk long
  work, durable results per slice in `build/qa/` (never /tmp).
- ~80 captures/day degrades the 4K screenshot daemon → `devicectl device
  reboot` cures it. Two devicectl sessions kill a console stream.
- The full history of fixed findings (F-001..F-005 + the 3-week-red test
  suite) is in playbook §3; the memory `atv-observation-harness` carries the
  standing doctrine. Depth-audit tools: atv_prompt_audit, atv_reveal_audit,
  audit_picture_images (chunked; 429=UNVERIFIED never dead),
  analyze_play_sweep, atv_report.

## If the loop is ever found unarmed

Re-arm immediately: ScheduleWakeup 300s with the rolling-maintenance prompt
(rotation position from the newest rollN-* dir), noop:false. The owner has
twice flagged gaps — the cadence is a commitment.
