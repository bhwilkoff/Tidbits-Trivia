"""Drive a REAL Android device (Pixel 8a today; Fire TV / Android TV when a
leanback build exists) and grade Tidbits from the glass.

The adb-specific hazards below each cost Archive Watch a failed run, and are
reproduced here rather than rediscovered:

  * CONNECT BEFORE EVERY COMMAND. A network device's TLS debugging port rotates
    after sleep, and the connection drops between commands. Every call goes
    through `adbs()`, which resolves the serial first.
  * A dump must DELETE the target file first — a failed `uiautomator dump`
    otherwise serves a STALE tree from some earlier session, which reads as our
    app showing another app's UI.
  * Retry a tree dump once: it is briefly empty during transitions.
  * `input tap` is INERT on the TV profile (motion events are not part of the
    focus grammar); it works on the phone profile. Scenarios here reach their
    surface by intent extra regardless — never by pressing blind.
  * On Fire OS `monkey` reports success but never foregrounds. Use `am start -n`.

Usage:
    python3 tools/adb_run.py --list
    python3 tools/adb_run.py --device pixel --scenario home
    python3 tools/adb_run.py --device pixel --extra tidbits_open=settings \
        --expect "Account|Feedback" --name adhoc
"""
import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import (Grader, ocr, qa_dir, sh)   # noqa: E402

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")

# Friendly name -> how to reach it. An mdns name is stable across port rotation;
# a bare host:port is not, which is why `connect()` re-resolves every time.
DEVICES = {
    "pixel":     {"serial": "adb-3B211JEKB14516-4M5scf._adb-tls-connect._tcp",
                  "profile": "phone"},
    "firetv":    {"serial": "10.0.0.139:5555", "profile": "tv"},
    "androidtv": {"serial": "10.0.0.55:5555",  "profile": "tv"},
}

# The DEBUG package, deliberately. ScreenshotHooks.apply() opens with
# `if (!BuildConfig.DEBUG) return`, so against the release build every intent
# extra is silently ignored and every scenario lands on Home — six of them did,
# and all six PASSED, because a readable frame of the wrong screen satisfies
# every check that is not looking for the RIGHT screen. Override with
# TIDBITS_ADB_PKG only if you know the hooks are not needed.
PKG = os.environ.get("TIDBITS_ADB_PKG", "com.tidbitstrivia.app.debug")
ACTIVITY = "com.learningischange.tidbitstrivia.MainActivity"
SHOT_EVERY = 3.0

# Applied to every launch unless a scenario overrides them.
BASE_EXTRAS = {"tidbits_skip_onboard": ("ez", "true")}

APP_ANCHOR_RX = r"Play|Records|Create|Tidbits|Quick Play|Daily"

# tidbits_tab: play|records|create.  tidbits_open: clubHub|paywall|atlas|
# linkWall|expeditions|storyArchive|marathonHistory|settings|profile|
# leaderboard|duels|online  (AppRoot.kt ignores an unknown value rather than
# crashing a sweep, so a typo here shows up as "wrong screen", not a crash).
# expect_any is calibrated against a real Pixel 8a capture, never guessed, and
# tolerates the legitimate EMPTY state where one exists: a fresh debug install
# has no history, so Records correctly reads "No games yet" and an assertion
# that only knows the populated shape would fail on a healthy screen.
SCENARIOS = {
    "home":     {"extras": {"tidbits_tab": ("es", "play")},    "minutes": 0.6,
                 "expect_any": r"DAILY TIDBIT|QUICK PLAY|Surprise me"},
    "records":  {"extras": {"tidbits_tab": ("es", "records")}, "minutes": 0.6,
                 "expect_any": r"No games yet|Your games|DAY STREAK|Personal bests"},
    "create":   {"extras": {"tidbits_tab": ("es", "create")},  "minutes": 0.6,
                 "expect_any": r"Create a quiz|Generate Quiz|Play it as"},
    "settings": {"extras": {"tidbits_open": ("es", "settings")}, "minutes": 0.6,
                 "expect_any": r"Haptics|Gameplay|Review questions|Feedback"},
    # The debug package is not Play-registered, so queryProductDetailsAsync
    # returns nothing and the sheet correctly says "Couldn't load plans" — the
    # iPad shows no such failure, which is how this was told apart from a real
    # regression. The check is NARROWED, not disabled: any other error string
    # still fails, and PRICES on Android can only be verified on a Play-signed
    # internal-track build, never here.
    "paywall":  {"extras": {"tidbits_open": ("es", "paywall")},  "minutes": 0.7,
                 "expect_any": r"Get better, not just play more|Ranked Seasons",
                 "forbid": (r"No questions|Something went wrong|failed to|"
                            r"\berror\b|couldn.t be")},
    "atlas":    {"extras": {"tidbits_open": ("es", "atlas")},    "minutes": 0.7,
                 "expect_any": r"A map of what you actually know|by\s+domain"},
}


def connect(dev):
    """Resolve a live serial, re-connecting if the port rotated. Returns the
    serial adb will accept right now."""
    serial = DEVICES[dev]["serial"] if dev in DEVICES else dev
    out = sh([ADB, "devices"], timeout=30).stdout
    if re.search(rf"^{re.escape(serial)}\s+device", out, re.M):
        return serial
    sh([ADB, "connect", serial], timeout=30)
    return serial


def adbs(dev, *args, timeout=60, binary=False):
    serial = connect(dev)
    cmd = [ADB, "-s", serial] + list(args)
    if binary:
        return subprocess.run(cmd, capture_output=True, timeout=timeout)
    return sh(cmd, timeout=timeout)


def wake(dev):
    """Wake and unlock. `stayon` keeps the screen up for the rest of the run so
    a long capture does not go dark halfway and get graded on blackness."""
    adbs(dev, "shell", "svc", "power", "stayon", "true")
    adbs(dev, "shell", "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1.2)
    adbs(dev, "shell", "wm", "dismiss-keyguard")
    time.sleep(1.0)


def launch(dev, extras, deep_link=None):
    full = dict(BASE_EXTRAS)
    full.update(extras or {})
    adbs(dev, "shell", "am", "force-stop", PKG)
    time.sleep(0.8)
    if deep_link:
        args = ["shell", "am", "start", "-a", "android.intent.action.VIEW",
                "-d", deep_link, PKG]
    else:
        args = ["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}"]
    for k, (kind, v) in full.items():
        args += [f"--{kind}", k, v]
    r = adbs(dev, *args, timeout=90)
    if "Error" in (r.stdout + r.stderr) or "Exception" in (r.stdout + r.stderr):
        sys.exit(f"launch failed: {r.stdout[-300:]} {r.stderr[-300:]}")


def app_alive(dev):
    r = adbs(dev, "shell", "pidof", PKG, timeout=45)
    return bool(r.stdout.strip())


def capture_loop(dev, outdir, minutes):
    shots, i = [], 0
    deadline = time.time() + minutes * 60
    while time.time() < deadline:
        p = outdir / f"shot-{i:04d}.png"
        try:
            r = adbs(dev, "exec-out", "screencap", "-p", timeout=60, binary=True)
            if r.stdout:
                p.write_bytes(r.stdout)
        except subprocess.TimeoutExpired:
            print(f"[adb] capture {p.name} timed out — skipping frame")
            time.sleep(2)
            continue
        if p.exists() and p.stat().st_size > 0:
            shots.append((time.time(), p))
        i += 1
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def logcat_errors(dev):
    """Crash-adjacent lines from OUR pid only. A stack trace explains a dead app
    that the glass can only report as 'gone'."""
    pid = adbs(dev, "shell", "pidof", PKG, timeout=45).stdout.strip().split(" ")[0]
    if not pid:
        return ""
    r = adbs(dev, "shell", "logcat", "-d", f"--pid={pid}", "-t", "200", timeout=60)
    return "\n".join(l for l in r.stdout.splitlines()
                     if re.search(r"\bE/|FATAL|Exception", l))[-2000:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="pixel", help="pixel|firetv|androidtv or a serial")
    ap.add_argument("--scenario")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--minutes", type=float)
    ap.add_argument("--extra", action="append", default=[],
                    help="k=v (string extra) — use k:ez=true for a boolean")
    ap.add_argument("--link", help="deep link, e.g. tidbits://daily")
    ap.add_argument("--expect", help="ad-hoc expect_any regex")
    ap.add_argument("--name")
    a = ap.parse_args()

    if a.list:
        for k, v in SCENARIOS.items():
            print(f"  {k:10s} {v['extras']}")
        return 0

    spec = dict(SCENARIOS.get(a.scenario, {"extras": {}, "minutes": 0.6}))
    spec["extras"] = dict(spec.get("extras", {}))
    for kv in a.extra:
        k, _, v = kv.partition("=")
        kind = "es"
        if ":" in k:
            k, _, kind = k.partition(":")
        spec["extras"][k] = (kind, v)
    if a.expect:
        spec["expect_any"] = a.expect
    if a.minutes:
        spec["minutes"] = a.minutes

    name = a.name or a.scenario or "adhoc"
    outdir = qa_dir(f"adb-{a.device}", name)
    print(f"[adb] {name} on {a.device} -> {outdir}")

    wake(a.device)
    launch(a.device, spec["extras"], a.link)
    time.sleep(5)   # let the first real frame render before the first capture
    shots = capture_loop(a.device, outdir, spec.get("minutes", 0.6))
    alive_end = app_alive(a.device)
    texts = ocr(shots)

    g = Grader(outdir, device=a.device, scenario=name,
               extras={k: v[1] for k, v in spec["extras"].items()}, shots=len(shots))
    g.grade("captured_frames", len(shots) >= 3, f"{len(shots)} frames")
    g.grade("app_alive_to_end", alive_end, "process present at capture end"
            if alive_end else "process GONE at capture end (crash or exit)")
    if not alive_end:
        err = logcat_errors(a.device)
        if err:
            (outdir / "logcat-errors.txt").write_text(err)
            print(f"[adb] wrote logcat-errors.txt ({len(err)} bytes)")
    g.grade_glass(shots, texts, spec, APP_ANCHOR_RX)
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
