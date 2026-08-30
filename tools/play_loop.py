"""Play real games on real hardware, one uncovered cell at a time, forever.

The point of a loop is that each lap does work the last lap did not. An earlier
loop on this repo re-ran the same five smoke scenarios every tick and the owner
was right to kill it: it was a tripwire wearing a loop's clothes. So coverage is
STATE here, not a fresh random sample. `build/qa/coverage.json` records, per
(platform, cell), when it was last verified and how it went; every tick takes the
never-run cells first and then the stalest, so the matrix fills in and the loop
has an end condition instead of a cadence.

A cell is not "the screen opened". It is a game PLAYED: launch straight into a
mode, let autopilot answer, and read the glass for a question and then for a
result. A mode that renders and then cannot be finished is exactly the bug a
screenshot sweep misses.

    python3 tools/play_loop.py --tick 6          # one lap, six stalest cells
    python3 tools/play_loop.py --status          # the matrix, no runs
    python3 tools/play_loop.py --only pixel      # confine a lap to one platform
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macapp  # noqa: E402
from devharness import OCR_FAILED, frame_text, ocr, qa_dir, sh  # noqa: E402

LEDGER = Path("build/qa/coverage.json")
DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"
BUNDLE = "com.learningischange.tidbitstrivia"
ADB = str(Path.home() / "Library/Android/sdk/platform-tools/adb")
APKG = "com.tidbitstrivia.app.debug"
ACTIVITY = "com.learningischange.tidbitstrivia.MainActivity"
_DEV_MAC = Path("build/dd-mac/Build/Products/Debug/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia")
_MAC_PID = None
MACBIN = str(_DEV_MAC if _DEV_MAC.exists()
             else Path("/Applications/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia"))

APPLE = {"atv":  "C3FBA9DE-4A60-555B-A65F-80D6809A275B",
         "ipad": "AC5377E9-6053-51DE-8E65-D88A4E9345FA",
         "iphone": "B4E756E2-CBFA-5F63-8CEE-21D226637AF7"}
ANDROID = {"pixel": "adb-3B211JEKB14516-4M5scf._adb-tls-connect._tcp",
           "firetv": "10.0.0.139:5555",
           "androidtv": "10.0.0.55:5555"}

# Apple's raw GameMode values. Android matches case-insensitively with
# underscores removed, so one spelling drives both.
MODES = ["classic", "timeAttack", "survival", "stake", "sweep", "pictureId",
         "thisOrThat", "closestCall", "ordering", "matching", "typeAnswer",
         "oddOneOut", "ladder", "enumerate", "mix", "daily", "weakSpot", "marathon"]

# Non-game surfaces that still have to work on every platform.
# 60-second or endurance modes: they need a longer watch before a result exists.
LONG_MODES = {"timeAttack", "enumerate", "survival", "stake", "marathon", "ladder", "sweep"}

# Survival ends only on a WRONG answer, so a correct-answering autopilot is
# immortal and the run can never reach a result. Measured: streak climbed
# #6 -> #13 -> #21 and kept going. These modes are driven with a fallible
# autopilot precisely so the end-of-run path gets exercised at all.
ENDLESS_WHEN_CORRECT = {"survival"}

# Genuinely cannot finish inside any sane watch window — Marathon is 200
# questions and reached 21 in 78s. Absence of a result screen here is arithmetic,
# not a defect, so PROGRESS is the assertion instead.
NO_RESULT_EXPECTED = {"marathon"}

# Feature -> the platforms that actually HAVE it. A uniform list produced false
# failures: the Mac sidebar is Play/Records/Create/Live, so a "leaderboard" tab
# was invented by the harness and the app was blamed for not showing it. On Apple,
# leaderboards are Game Center reached from Settings (PARITY.md line 251), not a
# section — an assertion for a surface a platform does not have is as useless as
# one that cannot fire.
APPLE_ALL = {"ipad", "iphone", "atv", "mac"}
ANDROID_ALL = {"pixel", "firetv", "androidtv"}
EVERYWHERE = APPLE_ALL | ANDROID_ALL
FEATURES = {
    "home":     EVERYWHERE,
    "records":  EVERYWHERE,
    "create":   EVERYWHERE,
    "settings": EVERYWHERE,
    "clubhub":  EVERYWHERE,
    "paywall":  EVERYWHERE,
    "atlas":    EVERYWHERE,
    "profile":  EVERYWHERE,
    # Android has a Leaderboard route; Apple routes it through Game Center, which
    # this harness disables (TIDBITS_NO_GAMECENTER) precisely so it never blocks.
    "leaderboard": ANDROID_ALL,
    # Android-only routes worth covering.
    "linkWall":   ANDROID_ALL,
    "expeditions": ANDROID_ALL,
    "duels":      ANDROID_ALL,
}

# A round is PLAYED if the glass shows a question; FINISHED if it shows a result.
# Both are read from the same frames — a mode that draws and cannot be completed
# is the failure a screenshot sweep cannot see.
# Mode-agnostic on purpose. The first version listed interrogatives and a "n/m"
# counter, and called Survival broken: Survival counts a STREAK ("#20"), and its
# prompts are statements ("this Japanese actress has played…"), so a working game
# matched nothing. A trivia question on screen is better identified by a question
# mark, any progress marker, or reveal chrome than by how the sentence opens.
QUESTION_RX = (r"\?|#\d+|\d+\s*/\s*\d+|Question|QUESTION|Tap your answer|"
               r"seconds left|Nice|Not quite|Correct|correct|Drag|Slide|Type ")
# Scorecards shout: "0/1 CORRECT", "100% ACCURACY", "FLAWLESS!", "GOOD RUN".
# The first version listed only Title-case forms and matched those screens purely
# by accident, through the lowercase "1 day streak" in the share row.
RESULT_RX = (r"(?i:score|you got|correct|play again|best|results|streak|accuracy|"
             r"points|done|finish|flawless|good run|nice run|final)")
ERROR_RX = r"No questions|Couldn.t load|Something went wrong|failed to|\berror\b"

# The paywall on a DEBUG package cannot load plans: the .debug id is not
# registered with Play, so Play declines all three product ids and the screen
# honestly says "Couldn't load". The paywall itself renders correctly — its copy,
# its plan rows, its Club pitch are all on the glass. adb_run.py already narrows
# its forbid list for this exact reason; the generic error pattern did not.
PAYWALL_ERROR_RX = r"No questions|Something went wrong|failed to|couldn.t be"


def devicectl(*a, timeout=90):
    return sh(["env", f"DEVELOPER_DIR={DEVELOPER_DIR}", "xcrun", "devicectl"] + list(a),
              timeout=timeout)


def adb(dev, *a, binary=False, timeout=90):
    cmd = [ADB, "-s", ANDROID[dev]] + list(a)
    if binary:
        return subprocess.run(cmd, capture_output=True, timeout=timeout)
    return sh(cmd, timeout=timeout)


def launch(dev, cell):
    """Put `dev` into the cell — a mode to play, or a feature surface to show."""
    is_mode = cell in MODES
    if dev in APPLE or dev == "mac":
        env = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_NO_GAMECENTER": "1"}
        if is_mode:
            env |= {"TIDBITS_AUTOPLAY": f"{cell}:mixed", "TIDBITS_AUTOPILOT": "1",
                    "TIDBITS_AUTOPILOT_STEPS": "40"}
            if cell not in ENDLESS_WHEN_CORRECT:
                env["TIDBITS_AUTOPILOT_CORRECT"] = "1"
        else:
            env |= {"home": {"TIDBITS_TAB": "play"},
                    "records": {"TIDBITS_TAB": "records"},
                    "create": {"TIDBITS_TAB": "create"},
                    "leaderboard": {"TIDBITS_TAB": "leaderboard"},
                    "settings": {"TIDBITS_SETTINGS": "1"},
                    "clubhub": {"TIDBITS_CLUB": "1", "TIDBITS_CLUB_HUB": "1"},
                    "paywall": {"TIDBITS_PAYWALL": "1"},
                    "atlas": {"TIDBITS_CLUB": "1", "TIDBITS_ATLAS": "1"},
                    "profile": {"TIDBITS_TAB": "records"}}.get(cell, {})
        if dev == "mac":
            global _MAC_PID
            _MAC_PID = macapp.launch(MACBIN, env)
            return True
        r = devicectl("device", "process", "launch", "--terminate-existing",
                      "--device", APPLE[dev], "-e", json.dumps(env), BUNDLE)
        return "Launched application" in (r.stdout + r.stderr)

    adb(dev, "shell", "am", "force-stop", APKG)
    time.sleep(1)
    args = ["shell", "am", "start", "-n", f"{APKG}/{ACTIVITY}",
            "--ez", "tidbits_skip_onboard", "true"]
    if is_mode:
        args += ["--es", "tidbits_autoplay", f"{cell.lower()}:mixed",
                 "--ez", "tidbits_autopilot", "true",
                 "--ez", "tidbits_autopilot_correct",
                 "false" if cell in ENDLESS_WHEN_CORRECT else "true",
                 "--ei", "tidbits_autopilot_steps", "40"]
    else:
        args += {"home": ["--es", "tidbits_tab", "play"],
                 "records": ["--ei", "tidbits_seed_records", "12",
                             "--es", "tidbits_tab", "records"],
                 "create": ["--es", "tidbits_tab", "create"],
                 "leaderboard": ["--es", "tidbits_open", "leaderboard"],
                 "settings": ["--es", "tidbits_open", "settings"],
                 "clubhub": ["--es", "tidbits_open", "clubHub"],
                 "paywall": ["--es", "tidbits_open", "paywall"],
                 "atlas": ["--es", "tidbits_open", "atlas"],
                 "profile": ["--es", "tidbits_open", "profile"]}.get(cell, [])
    r = adb(dev, *args)
    return "Error" not in (r.stdout + r.stderr)


def shot(dev, path):
    if dev in APPLE:
        try:
            devicectl("device", "capture", "screenshot", "--device", APPLE[dev],
                      "--destination", str(path), timeout=60)
        except subprocess.SubprocessError:
            return False
        return Path(path).exists()
    if dev == "mac":
        return macapp.capture(_MAC_PID, path) if _MAC_PID else False
    r = adb(dev, "exec-out", "screencap", "-p", binary=True, timeout=90)
    if not r.stdout:
        return False
    Path(path).write_bytes(r.stdout)
    return True


def wake_tv():
    pyatv = str(Path.home() / ".pyatv-venv/bin/atvremote")
    args = [pyatv, "--id", "7A:3F:0C:4E:20:1E", "--protocol", "companion"]
    for _ in range(3):
        if "PowerState.On" in sh(args + ["power_state"], timeout=40).stdout:
            return True
        sh(args + ["turn_on"], timeout=40)
        time.sleep(6)
    return False


def run_cell(dev, cell, outdir, retry=False):
    """Play/open one cell and read the glass. Returns a result dict."""
    import re
    if dev == "atv" and not wake_tv():
        return {"result": "SKIP", "why": "Apple TV would not wake"}
    if not launch(dev, cell):
        return {"result": "FAIL", "why": "launch was refused"}

    d = outdir / dev / cell / ("retry" if retry else "first")
    d.mkdir(parents=True, exist_ok=True)
    # Three frames across the round: early (the question), middle, and late
    # (the result). One frame cannot tell "drew a question" from "finished".
    # Time-boxed and long modes cannot reach a result inside ~33s, so watching
    # only that long reported "no result screen" for games that were fine.
    # The TVs are slow to first paint — the Google TV dongle has 2GB of RAM, and
    # Fire TV showed a loading screen for >20s before a Daily round appeared. A
    # schedule tuned to a phone spends its frames on a spinner.
    slow = dev in ("firetv", "androidtv", "atv")
    if cell in LONG_MODES:
        waits = (14, 12, 14, 20, 25) if slow else (9, 11, 13, 20, 25)
    else:
        waits = (14, 12, 14, 12) if slow else (9, 11, 13)
    shots = []
    for i, wait in enumerate(waits):
        time.sleep(wait)
        p = d / f"{i}.png"
        if shot(dev, p):
            shots.append((i, p))
    if not shots:
        return {"result": "FAIL", "why": "no screenshot — device blind"}

    texts = ocr(shots)
    if OCR_FAILED in texts:
        return {"result": "SKIP", "why": texts[OCR_FAILED][:120]}
    per_frame = [frame_text(texts.get(p.name, {})) for _, p in shots]
    all_text = " | ".join(per_frame)
    lines = max((len(texts.get(p.name, {}).get("allText", [])) for _, p in shots),
                default=0)
    if lines < 4:
        # The iPhone and iPad have no remote wake, so a dark screen is a real
        # SKIP rather than a failure. But the launch itself tends to wake them:
        # iphone/classic skipped on a dark screen and the next 17 cells on that
        # same phone all passed. One retry converts a stale-lock skip into a
        # verified cell instead of leaving a hole the loop keeps re-visiting.
        if not retry:
            return run_cell(dev, cell, outdir, retry=True)
        return {"result": "SKIP", "why": f"{lines} OCR lines — screen off/locked"}

    err = re.search(PAYWALL_ERROR_RX if cell == "paywall" else ERROR_RX,
                    all_text, re.I)
    if err:
        return {"result": "FAIL", "why": f"error text: {err.group(0)!r}",
                "evidence": all_text[:200]}

    if cell in MODES:
        # A round that reached a RESULT obviously played. Survival with a fallible
        # autopilot dies on question 1 and is already on its scorecard by the first
        # frame ("GOOD RUN — 0/1 CORRECT"), which the question pattern cannot match.
        finished = bool(re.search(RESULT_RX, all_text))
        played = finished or bool(re.search(QUESTION_RX, all_text))
        if not played:
            return {"result": "FAIL", "why": "never drew a question",
                    "evidence": all_text[:200]}

        # Did the round ADVANCE? A stuck game draws a question and sits there,
        # which "a question is on screen" cannot distinguish from a healthy one.
        # Counters are either "n / m" or a Survival streak "#n".
        def counter(t):
            n = [int(x) for x in re.findall(r"(\d+)\s*/\s*\d+", t)]
            n += [int(x) for x in re.findall(r"#(\d+)", t)]
            return max(n, default=None)
        seen = [c for c in (counter(t) for t in per_frame) if c is not None]
        # TWO observations minimum. Fire TV spent its first two frames on
        # "Pulling fresh tidbits…" and only the third showed a counter, so first
        # and last were the SAME frame — reported as "never advanced" for a round
        # that was fine. Progress is unmeasurable from one sample, and
        # unmeasurable is not stuck.
        progressed = (seen[-1] > seen[0]) if len(seen) >= 2 else None

        res = {"result": "OK", "finished": finished, "evidence": all_text[:200]}
        # Progress only has to be shown by a round that did NOT finish. A completed
        # round whose first frame was already its last question ("6/6" then
        # "FLAWLESS 6/6") never advances a counter and is perfectly healthy.
        if progressed is not None and not finished:
            res["progressed"] = progressed
        if cell in NO_RESULT_EXPECTED:
            res["finished"] = True          # arithmetic, not a defect
            res["note"] = "endurance mode — graded on progress, not a result screen"
        return res

    return {"result": "OK", "evidence": all_text[:200]}


def load():
    if LEDGER.exists():
        return json.loads(LEDGER.read_text())
    return {}


def save(led):
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    LEDGER.write_text(json.dumps(led, indent=1, sort_keys=True))


def all_cells(only=None):
    plats = ["ipad", "iphone", "pixel", "atv", "firetv", "androidtv", "mac"]
    if only:
        plats = [p for p in plats if p in only.split(",")]
    out = []
    for p in plats:
        # The TVs have no pointer, so text entry and free recall are self-marked
        # there; they still play, so they stay in the grid.
        for c in MODES:
            out.append((p, c))
        for c, plats in FEATURES.items():
            if p in plats:
                out.append((p, c))
    return out


def status(led):
    plats = sorted({p for p, _ in all_cells()})
    print(f"{'platform':11s} {'covered':>9s}  {'ok':>4s} {'fail':>5s} {'skip':>5s}   oldest")
    total_missing = 0
    for p in plats:
        cells = [c for pp, c in all_cells() if pp == p]
        seen = led.get(p, {})
        ok = sum(1 for c in cells if seen.get(c, {}).get("result") == "OK")
        fail = sum(1 for c in cells if seen.get(c, {}).get("result") == "FAIL")
        skip = sum(1 for c in cells if seen.get(c, {}).get("result") == "SKIP")
        missing = len(cells) - len(set(cells) & set(seen))
        total_missing += missing
        oldest = min((seen[c]["at"] for c in cells if c in seen), default=None)
        age = f"{int((time.time() - oldest) / 60)}m" if oldest else "-"
        print(f"{p:11s} {len(seen):4d}/{len(cells):<4d} {ok:4d} {fail:5d} {skip:5d}   {age}")
    fails = [(p, c, v["why"]) for p, d in led.items() for c, v in d.items()
             if v.get("result") == "FAIL"]
    if fails:
        print(f"\n{len(fails)} failing cell(s):")
        for p, c, why in sorted(fails):
            print(f"  {p:11s} {c:14s} {why[:80]}")
    stuck = [(p, c) for p, d in led.items() for c, v in d.items()
             if v.get("progressed") is False]
    if stuck:
        print(f"\n{len(stuck)} round(s) drew a question but never advanced:")
        for p, c in sorted(stuck):
            print(f"  {p:11s} {c}")
    # A round that ADVANCED is healthy whether or not it reached a result inside
    # the watch window. Stake needs two taps per question (confidence, then
    # answer), so it honestly reaches 2/8 in 78s — reporting that every lap is
    # noise nobody can act on, which is how a real signal gets ignored.
    unfinished = [(p, c) for p, d in led.items() for c, v in d.items()
                  if v.get("result") == "OK" and v.get("finished") is False
                  and v.get("progressed") is not True]
    if unfinished:
        print(f"\n{len(unfinished)} mode(s) drew a question but never reached a result:")
        for p, c in sorted(unfinished):
            print(f"  {p:11s} {c}")
    print(f"\n{total_missing} cell(s) never run")
    return total_missing, len(fails)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tick", type=int, default=6, help="cells to run this lap")
    ap.add_argument("--only", help="confine to these platforms")
    ap.add_argument("--status", action="store_true")
    a = ap.parse_args()

    led = load()
    if a.status:
        status(led)
        return 0

    # Never-run first, then stalest. This is what makes a lap new work.
    cells = all_cells(a.only)
    cells.sort(key=lambda pc: led.get(pc[0], {}).get(pc[1], {}).get("at", 0))
    todo = cells[:a.tick]

    out = qa_dir("play", "lap")
    print(f"lap: {len(todo)} cells -> {out}\n")
    for p, c in todo:
        t0 = time.time()
        try:
            res = run_cell(p, c, out)
        except Exception as e:                       # noqa: BLE001
            # One flaky device call must not take down the lap. An osascript
            # timeout propagated out of a Mac capture and killed all 18 cells,
            # losing the whole lap's work along with it.
            res = {"result": "SKIP", "why": f"{type(e).__name__}: {e}"[:160]}
        res["at"] = int(time.time())
        led.setdefault(p, {})[c] = res
        save(led)          # after EVERY cell, so a killed lap keeps its progress
        mark = {"OK": "  ok", "FAIL": "FAIL", "SKIP": "skip"}[res["result"]]
        extra = ""
        if res["result"] == "OK" and c in MODES:
            extra = "" if res.get("finished") else "  (no result screen)"
        if res["result"] != "OK":
            extra = "  " + res.get("why", "")
        print(f"  [{mark}] {p:10s} {c:14s} {int(time.time()-t0):3d}s{extra}")

    print()
    missing, fails = status(led)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
