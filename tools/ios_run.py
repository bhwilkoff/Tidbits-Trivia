"""Drive a REAL iPhone/iPad and grade Tidbits from the glass.

The tvOS sibling is tools/atv_run.py and the Android one is tools/adb_run.py;
the shared grading spine is tools/devharness.py. The doctrine is the same
everywhere — the app's own claims are never the evidence for what a player
sees; the screen is. What differs is the plumbing:

  * There is NO remote wake on iOS. devicectl cannot wake a locked device and
    there is no Companion protocol to borrow. The arrangement is physical:
    passcode OFF, Auto-Lock NEVER, device on a charger. A black capture is a
    LOCKED SCREEN, not a failed launch, so this runner refuses to grade a run
    it could not see rather than reporting confident nonsense.
  * There is no press verb either, so scenarios reach their surface through the
    DebugHooks env spine (TIDBITS_TAB=play|records|create, TIDBITS_SETTINGS=1,
    …) or a deep link via --payload-url. Never by pressing blind.

Usage:
    python3 tools/ios_run.py --list
    python3 tools/ios_run.py --device ipad --scenario home
    python3 tools/ios_run.py --device iphone --env TIDBITS_TAB=records \
        --expect "Records|Streak" --name adhoc
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import Grader, ocr, qa_dir, sh   # noqa: E402

# Physical devices, by friendly name. `devicectl list devices` prints these
# UUIDs; they are stable per pairing, not per build.
DEVICES = {
    "ipad":   "AC5377E9-6053-51DE-8E65-D88A4E9345FA",   # iPad Pro 12.9 (5th gen)
    "iphone": "B4E756E2-CBFA-5F63-8CEE-21D226637AF7",   # iPhone 12
}
BUNDLE = "com.learningischange.tidbitstrivia"
PROCESS_MATCH = "TidbitsTrivia.app/TidbitsTrivia"
DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"
SHOT_EVERY = 3.0

BASE_ENV = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_NO_GAMECENTER": "1"}

# Chrome that proves OUR app owns the glass rather than Springboard.
APP_ANCHOR_RX = r"Play|Records|Create|Tidbits|Quick Play|Daily"

# expect_any regexes are calibrated against real captures on the iPad Pro 12.9,
# never guessed — an assertion written from imagination fails on correct pixels
# and teaches the loop to be ignored.
SCENARIOS = {
    "home":     {"env": {"TIDBITS_TAB": "play"},    "minutes": 0.6,
                 "expect_any": r"DAILY TIDBIT|TRIVIA NIGHT|Surprise me"},
    "records":  {"env": {"TIDBITS_TAB": "records"}, "minutes": 0.6,
                 "expect_any": r"Your games|DAY STREAK|Personal bests|No games yet"},
    "create":   {"env": {"TIDBITS_TAB": "create"},  "minutes": 0.6,
                 "expect_any": r"Generate Quiz|Your quizzes|Need a spark"},
    "settings": {"env": {"TIDBITS_SETTINGS": "1"},  "minutes": 0.6,
                 "expect_any": r"Sign in with Apple|Account|Feedback"},
    "paywall":  {"env": {"TIDBITS_PAYWALL": "1"},   "minutes": 0.7,
                 "expect_any": r"Get better, not just play more|Ranked Seasons"},
    "clubhub":  {"env": {"TIDBITS_CLUB": "1", "TIDBITS_CLUB_HUB": "1"}, "minutes": 0.7,
                 "expect_any": r"You.re a member|Link Wall"},
}


def devicectl(*args, timeout=90):
    return sh(["env", f"DEVELOPER_DIR={DEVELOPER_DIR}", "xcrun", "devicectl"] + list(args),
              timeout=timeout)


def launch(device, env, url=None):
    full = dict(BASE_ENV)
    full.update(env or {})
    args = ["device", "process", "launch", "--terminate-existing",
            "--device", device, "-e", json.dumps(full)]
    if url:
        args += ["--payload-url", url]
    args.append(BUNDLE)
    r = devicectl(*args, timeout=90)
    if "Launched application" not in (r.stdout + r.stderr):
        sys.exit(f"launch failed: {r.stdout[-300:]} {r.stderr[-300:]}")


def app_alive(device):
    r = devicectl("device", "info", "processes", "--device", device, timeout=90)
    return PROCESS_MATCH in r.stdout


def capture_loop(device, outdir, minutes):
    shots, i = [], 0
    deadline = time.time() + minutes * 60
    while time.time() < deadline:
        p = outdir / f"shot-{i:04d}.png"
        try:
            devicectl("device", "capture", "screenshot",
                      "--device", device, "--destination", str(p), timeout=45)
        except subprocess.TimeoutExpired:
            # One flaky capture must not kill the scenario — skip the frame,
            # keep the run, say so.
            print(f"[ios] capture {p.name} timed out — skipping frame")
            time.sleep(2)
            continue
        if p.exists():
            shots.append((time.time(), p))
        i += 1
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="ipad", help="ipad|iphone or a raw UUID")
    ap.add_argument("--scenario")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--minutes", type=float)
    ap.add_argument("--env", action="append", default=[], help="K=V extra env")
    ap.add_argument("--url", help="deep link, e.g. tidbits://daily")
    ap.add_argument("--expect", help="ad-hoc expect_any regex")
    ap.add_argument("--name")
    a = ap.parse_args()

    if a.list:
        for k, v in SCENARIOS.items():
            print(f"  {k:10s} {v['env']}")
        return 0

    spec = dict(SCENARIOS.get(a.scenario, {"env": {}, "minutes": 0.6}))
    spec["env"] = dict(spec.get("env", {}))
    for kv in a.env:
        k, _, v = kv.partition("=")
        spec["env"][k] = v
    if a.expect:
        spec["expect_any"] = a.expect
    if a.minutes:
        spec["minutes"] = a.minutes

    device = DEVICES.get(a.device, a.device)
    name = a.name or a.scenario or "adhoc"
    outdir = qa_dir("ios", name)
    print(f"[ios] {name} on {a.device} -> {outdir}")

    launch(device, spec["env"], a.url)
    time.sleep(6)   # let the first real frame render before the first capture
    shots = capture_loop(device, outdir, spec.get("minutes", 0.6))
    alive_end = app_alive(device)
    texts = ocr(shots)

    g = Grader(outdir, device=a.device, scenario=name, env=spec["env"],
               shots=len(shots))
    g.grade("captured_frames", len(shots) >= 3, f"{len(shots)} frames")
    g.grade("app_alive_to_end", alive_end, "process present at capture end"
            if alive_end else "process GONE at capture end (crash or exit)")
    g.grade_glass(shots, texts, spec, APP_ANCHOR_RX)
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
