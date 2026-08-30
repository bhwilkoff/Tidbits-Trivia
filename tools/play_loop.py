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
from devharness import OCR_FAILED, frame_text, ocr, qa_dir, sh  # noqa: E402

LEDGER = Path("build/qa/coverage.json")
DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"
BUNDLE = "com.learningischange.tidbitstrivia"
ADB = str(Path.home() / "Library/Android/sdk/platform-tools/adb")
APKG = "com.tidbitstrivia.app.debug"
ACTIVITY = "com.learningischange.tidbitstrivia.MainActivity"
_DEV_MAC = Path("build/dd-mac/Build/Products/Debug/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia")
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

FEATURES = ["home", "records", "create", "settings", "leaderboard", "clubhub",
            "paywall", "atlas", "profile"]

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
RESULT_RX = (r"Score|SCORE|You got|correct|Correct|Play again|Best|BEST|"
             r"Results|RESULTS|streak|Accuracy|points|POINTS|Done|Finish")
ERROR_RX = r"No questions|Couldn.t load|Something went wrong|failed to|\berror\b"


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
                    "TIDBITS_AUTOPILOT_CORRECT": "1", "TIDBITS_AUTOPILOT_STEPS": "40"}
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
            sh(["pkill", "-x", "TidbitsTrivia"], timeout=10)
            time.sleep(1.5)
            e = " ".join(f"{k}={v}" for k, v in env.items())
            subprocess.Popen(f"{e} '{MACBIN}' >/dev/null 2>&1 &", shell=True)
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
                 "--ez", "tidbits_autopilot_correct", "true",
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
        sh(["osascript", "-e", 'tell application "TidbitsTrivia" to activate'], timeout=15)
        time.sleep(0.6)
        r = sh(["osascript", "-e", 'tell application "System Events" to tell process '
                '"TidbitsTrivia" to get {position, size} of front window'], timeout=20)
        import re as _re
        n = [int(x) for x in _re.findall(r"-?\d+", r.stdout)]
        if len(n) < 4 or n[2] < 200:
            return False
        sh(["screencapture", "-x", "-o", "-R", f"{n[0]},{n[1]},{n[2]},{n[3]}", str(path)],
           timeout=40)
        return Path(path).exists()
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


def run_cell(dev, cell, outdir):
    """Play/open one cell and read the glass. Returns a result dict."""
    import re
    if dev == "atv" and not wake_tv():
        return {"result": "SKIP", "why": "Apple TV would not wake"}
    if not launch(dev, cell):
        return {"result": "FAIL", "why": "launch was refused"}

    d = outdir / dev / cell
    d.mkdir(parents=True, exist_ok=True)
    # Three frames across the round: early (the question), middle, and late
    # (the result). One frame cannot tell "drew a question" from "finished".
    # Time-boxed and long modes cannot reach a result inside ~33s, so watching
    # only that long reported "no result screen" for games that were fine.
    waits = (9, 11, 13, 20, 25) if cell in LONG_MODES else (9, 11, 13)
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
    all_text = " | ".join(frame_text(texts.get(p.name, {})) for _, p in shots)
    lines = max((len(texts.get(p.name, {}).get("allText", [])) for _, p in shots),
                default=0)
    if lines < 4:
        return {"result": "SKIP", "why": f"{lines} OCR lines — screen off/locked"}

    err = re.search(ERROR_RX, all_text, re.I)
    if err:
        return {"result": "FAIL", "why": f"error text: {err.group(0)!r}",
                "evidence": all_text[:200]}

    if cell in MODES:
        played = bool(re.search(QUESTION_RX, all_text))
        finished = bool(re.search(RESULT_RX, all_text))
        if not played:
            return {"result": "FAIL", "why": "never drew a question",
                    "evidence": all_text[:200]}
        return {"result": "OK", "finished": finished, "evidence": all_text[:200]}

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
        for c in MODES + FEATURES:
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
    unfinished = [(p, c) for p, d in led.items() for c, v in d.items()
                  if v.get("result") == "OK" and v.get("finished") is False]
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
        res = run_cell(p, c, out)
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
