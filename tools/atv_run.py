#!/usr/bin/env python3
"""External-observation scenario runner for the paired Apple TV (Tidbits).

Ported from Archive Watch's atv_scenario.py and adapted to trivia: launches the
app with DebugHooks env, screenshots the GLASS on an interval, OCRs every frame
(/tmp/tbocr), optionally sends real remote presses (pyatv Companion), and grades
explicit assertions. The app's own claims are never the evidence for what a
player sees; the screen is.

Usage:
  python3 tools/atv_run.py --list
  python3 tools/atv_run.py --scenario quickplay-classic
  python3 tools/atv_run.py --scenario picture-round --minutes 3
  python3 tools/atv_run.py --env TIDBITS_AUTOPLAY=ladder:science --minutes 2 \
      --expect "LADDER" --name adhoc-ladder

Requires: /tmp/tbocr (swiftc -O tools/ScreenOCR/main.swift -o /tmp/tbocr),
the paired ATV, the app installed (tools/atv_install.sh).
Playbook + findings log: docs/TVOS-TEST-PLAYBOOK.md.
"""
import argparse, json, re, subprocess, sys, time
from pathlib import Path

DEVICE = "C3FBA9DE-4A60-555B-A65F-80D6809A275B"   # Ben Bedroom (devicectl UDID)
BUNDLE = "com.learningischange.tidbitstrivia"
OCR = "/tmp/tbocr"
SHOT_EVERY = 4.0   # 4K captures pressure the device's screenshot daemon;
                   # 2.5s coincided with jetsam events on Archive Watch
PYATV = str(Path.home() / ".pyatv-venv/bin/atvremote")
PYATV_ARGS = ["--id", "7A:3F:0C:4E:20:1E", "--protocol", "companion"]
DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"

BASE_ENV = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_NO_GAMECENTER": "1"}

# Strings that must NEVER appear on the glass in a healthy run. Extend as
# findings land — every user-visible error string the app can render belongs
# here unless a scenario is specifically ABOUT that error.
# Word-bound: bare "Error" matched inside "terrorists" in a question prompt
# and failed a healthy run. Question CONTENT can contain any substring.
FORBID_DEFAULT = r"No questions|Couldn.t load|Something went wrong|failed to|\berror\b|couldn.t be"

# ── Scenario table ─────────────────────────────────────────────────────────────
# expect_any:  regex must match some frame's OCR text (anywhere).
# expect_end:  regex must match one of the LAST 4 frames (final state).
# expect_seq:  list of regexes that must first-match in this order over time.
# forbid:      regex that must match NO frame (default FORBID_DEFAULT + extras).
# min_center_stddev: at least `frames` frames must have centerLuma.stddev >= v
#              (a loaded photo region; a flat/blank image area fails this).
# presses:     [(seconds_after_launch, key), ...] real remote input via pyatv.
SCENARIOS = {
    "home": dict(
        env={}, minutes=0.4,
        expect_any=r"QUICK PLAY", expect_end=r"DAILY TIDBIT|TRIVIA NIGHT",
        note="Home renders: hero, daily, night cards, Records/Settings chrome."),
    "quickplay-classic": dict(
        env={"TIDBITS_AUTOPLAY": "classic:mixed", "TIDBITS_AUTOPILOT": "1",
             "TIDBITS_AUTOPILOT_CORRECT": "1"},
        minutes=1.2,
        expect_any=r"\d+/\d+",
        expect_end=r"ACCURACY|Play Again|FLAWLESS|CORRECT",
        note="A full classic round to the results screen on autopilot."),
    "picture-round": dict(
        # No autopilot: park on the FIRST picture question so every frame
        # samples the image region while the photo should be up.
        env={"TIDBITS_AUTOPLAY": "pictureId:mixed", "TIDBITS_AUTOPILOT": "1",
             "TIDBITS_AUTOPILOT_STEPS": "0"},
        minutes=1.0, min_center_stddev=(28.0, 3),
        expect_any=r".",
        forbid_extra=r"Couldn.t load the image",
        note="Picture ID round: the image region must carry a real photo "
             "(center luminance stddev), not a placeholder or blank."),
    "daily": dict(
        env={"TIDBITS_AUTOPLAY": "daily:mixed", "TIDBITS_AUTOPILOT": "1"},
        # The daily's in-round glass shows neither the word "Daily" nor N/M
        # chrome (caught by a healthy run failing the old regex on 08-25);
        # the results' streak line is the reliable signature.
        minutes=1.2, expect_any=r"day streak|DAILY|Daily",
        expect_end=r"day streak|ACCURACY|Play Again|CORRECT",
        note="Daily Tidbit plays to completion."),
    "versus-cpu": dict(
        # Tight assertions: the first run of this scenario false-passed by
        # matching the word "you" on the HOME screen (the hook wasn't wired on
        # tvOS). The versus HUD's own chrome is the only acceptable evidence.
        env={"TIDBITS_VERSUS": "rookie", "TIDBITS_AUTOPILOT": "1"},
        minutes=2.0,
        expect_any=r"Rookie",
        expect_end=r"You won|takes it|\d+/\d+ correct",
        note="Versus CPU match runs and shows both scores."),
    "records": dict(
        env={"TIDBITS_TAB": "records", "TIDBITS_SEED_RECORDS": "12"},
        minutes=0.5, expect_any=r"Records|Streak|day",
        note="Records dashboard renders with data."),
    "settings": dict(
        env={"TIDBITS_SETTINGS": "1"}, minutes=0.4,
        expect_any=r"Settings|Account|About",
        note="Settings renders; account affordances present."),
    "create": dict(
        env={"TIDBITS_CREATE": "1"}, minutes=0.5,
        expect_any=r"Create|topic|Wikipedia",
        note="Create surface reachable and rendered."),
    "night-host": dict(
        # Tightened after a false pass on the word 'TIDBIT' (home screen):
        # only the lobby's own chrome counts.
        env={"TIDBITS_NIGHT_HOST": "1"}, minutes=1.0,
        expect_any=r"SCAN TO JOIN|TRIVIA NIGHT|in the room",
        forbid_extra=r"QUICK PLAY",
        note="Trivia Night host lobby shows a join code (+ QR)."),
    "night-join-crossplatform": dict(
        # The TV hosts a networked night on a PINNED room code; a scripted
        # cross-platform player (tools/rtdb_join.py — the web app's exact REST
        # path) joins mid-run. The joiner's name on the TV's glass is the
        # end-to-end evidence: host -> Firebase -> client, across platforms.
        env={"TIDBITS_NIGHT_HOST": "1", "TIDBITS_LIVE_CODE": "QATV"},
        minutes=1.6,
        # The pinned QA room accumulates persisted teams (teams/ survives by
        # design), so the count is asserted as ANY number — the join evidence
        # is the sequence lobby -> count -> the night actually STARTING (the
        # owner watched runs that always ended parked at the lobby). Two
        # selects: the first-press drop is a known flake even warmed.
        presses=[(14, "sh:python3 tools/rtdb_join.py --code QATV --name HarnessBot --stay 60 > build/qa/rtdb_join.log 2>&1 &"),
                 (40, "select"), (52, "select")],
        expect_seq=[r"SCAN TO JOIN", r"\d+ in the room", r"ROUND 1/3"],
        forbid_extra=r"QUICK PLAY",
        note="Cross-platform Trivia Night: scripted RTDB player joins the "
             "TV-hosted room, then the night STARTS on the glass."),
    "quickmatch": dict(
        env={"TIDBITS_MULTIPLAYER": "1"}, minutes=1.2,
        expect_any=r"Quick Match|Finding|Searching|opponent",
        forbid_extra=r"QUICK PLAY",   # home-hero text = the sheet never opened
        note="Online multiplayer sheet opens and searches/falls back."),
    "records-drillin": dict(
        # Real remote input: from the seeded Records dashboard, move focus down
        # into the games list and select the top game — the per-answer drill-in
        # must render (R-REC-1's interactive-records rule).
        env={"TIDBITS_TAB": "records", "TIDBITS_SEED_RECORDS": "12"},
        minutes=1.0,
        presses=[(10, "down"), (13, "down"), (16, "select")],
        expect_seq=[r"DAY STREAK", r"Sample question|ACCURACY|answers|CORRECT"],
        note="Records drill-in via real remote presses."),
    "quickmatch-full": dict(
        # Start the search with a real press; a match against the live queue or
        # the bot fallback are BOTH healthy outcomes — the sheet must never
        # just sit there. Drops the NO_GAMECENTER base flag: Quick Match on
        # Apple rides Game Center, and with the flag set the sheet correctly
        # shows its sign-in gate instead (verified 2026-08-24).
        env={"TIDBITS_MULTIPLAYER": "1"}, drop_env=("TIDBITS_NO_GAMECENTER",),
        minutes=1.5,
        # Apple Quick Match rides GameKit: the native matchmaker sheet is the
        # correct surface (Automatch / Invite Friends / Start Game), not the
        # Tidbits-copy search screen the web/Android Firebase queue shows.
        expect_seq=[r"Multiplayer Game|Automatch", r"Start Game|Invite Friends"],
        forbid_extra=r"QUICK PLAY",
        note="Quick Match full flow: press to search, match or bot fallback."),
    "paywall": dict(
        env={"TIDBITS_PAYWALL": "1"}, minutes=0.5,
        expect_any=r"Club|Tidbits Club", forbid_extra=r"\$0|nil",
        note="Club paywall renders plans (or the honest empty state)."),
}

# One scenario per remaining game mode — same shape: autopilot to the results
# screen, question chrome seen, results chrome at the end, no error text.
for _m in ["timeAttack", "survival", "stake", "sweep", "thisOrThat",
           "closestCall", "ordering", "matching", "typeAnswer", "oddOneOut",
           "ladder", "enumerate", "mix"]:
    SCENARIOS[f"mode-{_m}"] = dict(
        env={"TIDBITS_AUTOPLAY": f"{_m}:mixed", "TIDBITS_AUTOPILOT": "1",
             "TIDBITS_AUTOPILOT_CORRECT": "1",
             # Only read for mix: — pins the blend so the run is reproducible.
             "TIDBITS_MIX": "classic,pictureId,closestCall"},
        minutes=1.5,
        expect_any=r"\d+/\d+|SCIENCE|HISTORY|GEOGRAPHY|MIXED|ARTS|MUSIC|SPORTS|SCREEN|BUSINESS",
        expect_end=r"ACCURACY|Play Again|CORRECT|Done|Results",
        note=f"{_m} round to results on autopilot.")
# Survival never ends while every answer is right — the sweep proved 52
# straight correct answers on-device. Answer wrong so the run reaches results.
del SCENARIOS["mode-survival"]["env"]["TIDBITS_AUTOPILOT_CORRECT"]
SCENARIOS["mode-survival"]["minutes"] = 1.0


def sh(cmd, timeout=90, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)


def devicectl(*args, timeout=90):
    return sh(["env", f"DEVELOPER_DIR={DEVELOPER_DIR}", "xcrun", "devicectl"] + list(args),
              timeout=timeout)


def wake_tv():
    """Installs work while the TV sleeps; launches and screenshots do NOT, and
    devicectl has no wake verb. pyatv's Companion protocol does.

    VERIFIED wake: the TV dozes BETWEEN scenarios in a long sweep, and a launch
    landing in that window is denied ("System is asleep - foreground app launch
    forbidden") or comes up backgrounded — the app stays alive while the HOME
    SCREEN owns the glass, which mimics an app bug (F-004 was this). Poll until
    the Companion actually reports On; give up loudly, never silently."""
    for attempt in range(3):
        try:
            r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=40)
            if "PowerState.On" in r.stdout:
                return True
            print("[atv] TV asleep — waking it")
            sh([PYATV] + PYATV_ARGS + ["turn_on"], timeout=40)
            for _ in range(8):
                time.sleep(3)
                r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=40)
                if "PowerState.On" in r.stdout:
                    time.sleep(2)   # let the home screen settle before a launch
                    return True
        except Exception as e:
            print(f"[atv] wake attempt {attempt} failed: {e}")
    print("[atv] WARNING: could not verify the TV awake — launches may background")
    return False


HOME_SCREEN_RX = r"prime video|pluto|fubo|Apple TV\+|Select up for full screen|\d{1,2}:\d{2} [AP]M"


def frame_is_home_screen(png):
    """OCR one frame and report whether the tvOS HOME SCREEN owns the glass —
    the wrong-screen guard from atv_see.sh, inside the runner. A launched-but-
    backgrounded app passes app_alive while every capture shows the system UI."""
    r = sh([OCR, str(png)], timeout=120)
    try:
        d = json.loads(r.stdout.splitlines()[0])
    except Exception:
        return False
    txt = " ".join(t["text"] for t in d.get("allText", []))
    return bool(re.search(HOME_SCREEN_RX, txt, re.I))


def press(key):
    # F-009: a fresh single-command Companion connection frequently DROPS its
    # press; running power_state first on the same connection warms it.
    r = sh([PYATV] + PYATV_ARGS + ["power_state", key], timeout=30)
    if r.returncode != 0:
        print(f"[atv] press {key} failed: {r.stderr.strip()[-120:]}")


def launch(env, drop=()):
    full = {k: v for k, v in BASE_ENV.items() if k not in drop}
    full.update(env)
    r = devicectl("device", "process", "launch", "--terminate-existing",
                  "--device", DEVICE, "-e", json.dumps(full), BUNDLE, timeout=60)
    if "Launched application" not in (r.stdout + r.stderr):
        sys.exit(f"launch failed: {r.stdout[-300:]} {r.stderr[-300:]}")


def app_alive():
    r = devicectl("device", "info", "processes", "--device", DEVICE, timeout=60)
    return "TidbitsTrivia.app/TidbitsTrivia" in r.stdout


def capture_loop(outdir, minutes, presses):
    shots, i = [], 0
    t0 = time.time()
    deadline = t0 + minutes * 60
    pending = sorted(presses or [], key=lambda p: p[0])
    while time.time() < deadline:
        while pending and time.time() - t0 >= pending[0][0]:
            _, key = pending.pop(0)
            if key.startswith("sh:"):
                print(f"[atv] action: {key[3:]}")
                subprocess.Popen(key[3:], shell=True)
            else:
                print(f"[atv] press: {key}")
                press(key)
        p = outdir / f"shot-{i:04d}.png"
        try:
            devicectl("device", "capture", "screenshot",
                      "--device", DEVICE, "--destination", str(p), timeout=30)
        except subprocess.TimeoutExpired:
            # The 4K screenshot daemon hiccups under pressure (Archive Watch's
            # jetsam class). One flaky capture must not kill the scenario —
            # skip the frame, keep the run, say so.
            print(f"[atv] capture {p.name} timed out — skipping frame")
            time.sleep(2)
            continue
        if p.exists():
            shots.append((time.time(), p))
            # The TV dozes during long captures parked on a static screen —
            # late frames go black and the run gets graded on darkness. A tiny
            # PNG is the doze signature: wake it and log the blind window
            # honestly (the frames stay on disk either way).
            if p.stat().st_size < 300_000:
                print(f"[atv] frame {p.name} is {p.stat().st_size}B — TV dozing; waking")
                wake_tv()
        i += 1
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def ocr(shots):
    out = {}
    paths = [str(p) for _, p in shots]
    for chunk in (paths[k:k + 20] for k in range(0, len(paths), 20)):
        r = sh([OCR] + chunk, timeout=600)
        for line in r.stdout.splitlines():
            try:
                d = json.loads(line)
                out[d["file"]] = d
            except json.JSONDecodeError:
                pass
    return out


def frame_text(d):
    return " ".join(t["text"] for t in d.get("allText", []))


def main():
    try:
        _main()
    except SystemExit:
        raise
    except Exception:
        import traceback
        traceback.print_exc()
        # A runner crash must leave a report naming itself — a missing report
        # reads as "interrupted" and hides the crash class entirely.
        try:
            outdir = Path(getattr(_main, "outdir", "build/qa"))
            (outdir / "report.json").write_text(json.dumps(
                {"error": traceback.format_exc().splitlines()[-1]}))
        except Exception:
            pass
        sys.exit(3)


def _main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--minutes", type=float)
    ap.add_argument("--env", action="append", default=[], help="K=V extra env")
    ap.add_argument("--expect", help="ad-hoc expect_any regex")
    ap.add_argument("--luma", help="ad-hoc image gate THRESH:FRAMES (e.g. 28:2)")
    ap.add_argument("--name", default=None)
    ap.add_argument("--outdir", default=None)
    args = ap.parse_args()

    if args.list:
        for k, v in SCENARIOS.items():
            print(f"{k:20s} {v['note']}")
        return

    spec = dict(SCENARIOS.get(args.scenario, {"env": {}, "minutes": 1.0}))
    name = args.name or args.scenario or "adhoc"
    for kv in args.env:
        k, _, v = kv.partition("=")
        spec.setdefault("env", {})[k] = v
    if args.minutes:
        spec["minutes"] = args.minutes
    if args.expect:
        spec["expect_any"] = args.expect
    if args.luma:
        t, n = args.luma.split(":")
        spec["min_center_stddev"] = (float(t), int(n))

    day = time.strftime("%F")
    outdir = Path(args.outdir or f"build/qa/atv-{day}/{name}-{int(time.time())}")
    outdir.mkdir(parents=True, exist_ok=True)
    _main.outdir = outdir
    print(f"[atv] scenario {name} -> {outdir}")

    wake_tv()
    drop = spec.get("drop_env", ())
    launch(spec.get("env", {}), drop)
    time.sleep(6)
    if not app_alive():   # launch-window death retry (Archive Watch: ~2 in 10)
        print("[atv] app died in launch window — one retry")
        wake_tv()
        launch(spec.get("env", {}), drop)
        time.sleep(6)
    # Foreground guard: alive is not frontmost. One probe frame; if the home
    # screen owns the glass, wake + relaunch once before burning the capture.
    probe = outdir / "probe-foreground.png"
    devicectl("device", "capture", "screenshot", "--device", DEVICE,
              "--destination", str(probe), timeout=30)
    if probe.exists() and frame_is_home_screen(probe):
        print("[atv] launched but HOME SCREEN owns the glass — wake + relaunch")
        wake_tv()
        launch(spec.get("env", {}), drop)
        time.sleep(6)

    shots = capture_loop(outdir, spec.get("minutes", 1.0), spec.get("presses"))
    print(f"[atv] {len(shots)} screenshots")
    alive_end = app_alive()
    texts = ocr(shots)

    report = {"scenario": name, "shots": len(shots), "assertions": {}}

    def grade(k, ok, ev):
        report["assertions"][k] = {"pass": bool(ok), "evidence": ev}
        print(f"  [{'PASS' if ok else 'FAIL'}] {k}: {ev}")

    grade("captured_frames", len(shots) >= 3, f"{len(shots)} frames")
    grade("app_alive_to_end", alive_end, "process present at capture end"
          if alive_end else "process GONE at capture end (crash or exit)")

    ordered = [(w, frame_text(texts.get(p.name, {}))) for w, p in shots]
    all_text = " | ".join(t for _, t in ordered)

    if "expect_any" in spec:
        m = re.search(spec["expect_any"], all_text, re.I)
        grade("expect_any", bool(m), f"/{spec['expect_any']}/ "
              + (f"matched {m.group(0)!r}" if m else "matched nothing"))
    if "expect_end" in spec:
        tail = " | ".join(t for _, t in ordered[-4:])
        m = re.search(spec["expect_end"], tail, re.I)
        grade("expect_end", bool(m), f"/{spec['expect_end']}/ in last frames"
              + ("" if m else " — NOT found"))
    for i, rx in enumerate(spec.get("expect_seq", [])):
        hit = next((j for j, (_, t) in enumerate(ordered) if re.search(rx, t, re.I)), None)
        grade(f"seq_{i}_{rx[:18]}", hit is not None,
              f"first match at frame {hit}" if hit is not None else "never matched")
        if hit is not None:
            ordered_tail = ordered[hit:]
            ordered = ordered_tail   # next regex must match at/after this frame

    forbid = FORBID_DEFAULT + ("|" + spec["forbid_extra"] if spec.get("forbid_extra") else "")
    bad = [(p.name, re.search(forbid, frame_text(texts.get(p.name, {})), re.I).group(0))
           for _, p in shots
           if re.search(forbid, frame_text(texts.get(p.name, {})), re.I)]
    grade("no_error_text", not bad,
          "clean" if not bad else f"{len(bad)} frames, e.g. {bad[0]}")

    if "min_center_stddev" in spec:
        thresh, need = spec["min_center_stddev"]
        rich = [p.name for _, p in shots
                if texts.get(p.name, {}).get("centerLuma", {}).get("stddev", 0) >= thresh]
        grade("image_region_loaded", len(rich) >= need,
              f"{len(rich)} frames with center stddev >= {thresh} (need {need})")

    (outdir / "report.json").write_text(json.dumps(report, indent=1))
    (outdir / "ocr.json").write_text(json.dumps(texts, indent=1))
    failed = [k for k, v in report["assertions"].items() if not v["pass"]]
    print(f"\nRESULT: {'OK' if not failed else 'FAIL — ' + ', '.join(failed)}")
    print(f"report: {outdir}/report.json")
    sys.exit(0 if not failed else 1)


if __name__ == "__main__":
    main()
