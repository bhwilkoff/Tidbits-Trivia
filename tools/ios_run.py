"""Drive a REAL iPhone/iPad and grade Tidbits from the glass.

The tvOS sibling of this file is tools/atv_run.py, and the doctrine is the same:
the app's own claims are never the evidence for what a player sees; the screen
is. What differs is the plumbing.

  * There is NO remote wake on iOS. devicectl cannot wake a locked device and
    there is no Companion protocol to borrow. The arrangement is physical:
    passcode OFF, Auto-Lock NEVER, device on a charger. A black capture is a
    LOCKED SCREEN, not a failed launch, so this runner refuses to grade a run it
    could not see (`screen_awake`) instead of reporting a confident nonsense.
  * There is no press verb either, so scenarios reach their surface through the
    DebugHooks env spine (TIDBITS_TAB=play|records|create, TIDBITS_SETTINGS=1,
    …) or a deep link via --payload-url. Never by pressing blind.
  * iOS captures are small enough that a byte-size doze heuristic (the tvOS
    300KB rule) does not transfer. Blindness is judged on OCR line count
    instead, which is resolution independent.

Usage:
    python3 tools/ios_run.py --list
    python3 tools/ios_run.py --device ipad --scenario home
    python3 tools/ios_run.py --device iphone --env TIDBITS_TAB=records \
        --expect "Records|Streak" --name adhoc
"""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

# Physical devices, by friendly name. `devicectl list devices` prints these
# UUIDs; they are stable per device-pairing, not per build.
DEVICES = {
    "ipad":   "AC5377E9-6053-51DE-8E65-D88A4E9345FA",   # iPad Pro 12.9 (5th gen)
    "iphone": "B4E756E2-CBFA-5F63-8CEE-21D226637AF7",   # iPhone 12
}
BUNDLE = "com.learningischange.tidbitstrivia"
PROCESS_MATCH = "TidbitsTrivia.app/TidbitsTrivia"
OCR = "/tmp/tbocr"
DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"
SHOT_EVERY = 3.0

BASE_ENV = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_NO_GAMECENTER": "1"}

# A frame carrying fewer than this many OCR lines is treated as unreadable. A
# locked/asleep iPad yields zero; a real Tidbits screen yields many.
MIN_LINES_READABLE = 4

FORBID_DEFAULT = (r"No questions|Couldn.t load|Something went wrong|"
                  r"failed to|\berror\b|couldn.t be")

# Chrome that proves OUR app owns the glass rather than Springboard. A readable
# frame of the WRONG app survives every other check and then answers questions
# about a screen we are not testing.
APP_ANCHOR_RX = r"Play|Records|Create|Tidbits|Quick Play|Daily"

# expect_any regexes are calibrated against real captures on the iPad Pro 12.9,
# never guessed — an assertion written from imagination fails on correct pixels
# and teaches the loop to be ignored.
SCENARIOS = {
    "home":     {"env": {"TIDBITS_TAB": "play"},    "minutes": 0.6,
                 "expect_any": r"DAILY TIDBIT|TRIVIA NIGHT|Surprise me"},
    "records":  {"env": {"TIDBITS_TAB": "records"}, "minutes": 0.6,
                 "expect_any": r"Your games|DAY STREAK|Personal bests"},
    "create":   {"env": {"TIDBITS_TAB": "create"},  "minutes": 0.6,
                 "expect_any": r"Generate Quiz|Your quizzes|Need a spark"},
    "settings": {"env": {"TIDBITS_SETTINGS": "1"},  "minutes": 0.6,
                 "expect_any": r"Sign in with Apple|Account|Feedback"},
    "paywall":  {"env": {"TIDBITS_PAYWALL": "1"},   "minutes": 0.7,
                 "expect_any": r"Get better, not just play more|Ranked Seasons"},
    "clubhub":  {"env": {"TIDBITS_CLUB": "1", "TIDBITS_CLUB_HUB": "1"}, "minutes": 0.7,
                 "expect_any": r"You.re a member|Link Wall"},
}


def sh(cmd, timeout=90, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)


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


# Archive Watch uses 0.010 here; that constant does NOT transfer. Measured on
# the iPad Pro 12.9 Records tab, Tidbits' own left margin puts body text at
# x=0.0116 and bold section headers at x=0.0099 (Vision's box hugs the ink, so
# heavier type starts marginally further left). A 0.010 threshold called three
# correctly-rendered headings clipped on every frame. 0.005 keeps a 2x margin
# below the real gutter, so only text actually running off the edge trips it.
CLIP_X = 0.005


def clipped_lines(d):
    """Lines whose box starts at the very left edge — text the layout could not
    fit. Big display type is excluded by height: a hero numeral legitimately
    spans the frame, chrome type never starts at the gutter."""
    return [t for t in d.get("allText", [])
            if t.get("x", 1.0) <= CLIP_X and t.get("h", 1.0) <= 0.030]


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
    outdir = Path("build/qa") / f"ios-{time.strftime('%Y-%m-%d')}" / f"{name}-{int(time.time())}"
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"[ios] {name} on {a.device} -> {outdir}")

    launch(device, spec["env"], a.url)
    time.sleep(6)   # let the first real frame render before the first capture
    shots = capture_loop(device, outdir, spec.get("minutes", 0.6))
    alive_end = app_alive(device)
    texts = ocr(shots)

    report = {"device": a.device, "scenario": name, "env": spec["env"],
              "shots": len(shots), "assertions": {}}
    failures = []

    def grade(key, ok, evidence):
        report["assertions"][key] = {"pass": bool(ok), "evidence": evidence}
        print(f"  [{'PASS' if ok else 'FAIL'}] {key}: {evidence}")
        if not ok:
            failures.append(key)

    grade("captured_frames", len(shots) >= 3, f"{len(shots)} frames")

    # The blind check comes FIRST and gates everything that reads the glass: a
    # null result from a blind instrument is indistinguishable from a real
    # absence, so an unreadable run must not be graded at all.
    line_counts = [len(texts.get(p.name, {}).get("allText", [])) for _, p in shots]
    best = max(line_counts, default=0)
    readable = best >= MIN_LINES_READABLE
    grade("screen_awake", readable,
          f"best frame had {best} OCR lines"
          + ("" if readable else " — SCREEN OFF/LOCKED. Set passcode off, "
                                "Auto-Lock Never, and leave the device on a charger."))

    grade("app_alive_to_end", alive_end,
          "process present at capture end" if alive_end
          else "process GONE at capture end (crash or exit)")

    if readable:
        all_text = " | ".join(frame_text(texts.get(p.name, {})) for _, p in shots)

        grade("app_owns_glass", bool(re.search(APP_ANCHOR_RX, all_text, re.I)),
              "Tidbits chrome on the glass" if re.search(APP_ANCHOR_RX, all_text, re.I)
              else "readable frames, but no Tidbits chrome — wrong app/screen")

        if "expect_any" in spec:
            m = re.search(spec["expect_any"], all_text, re.I)
            grade("expect_any", bool(m), f"/{spec['expect_any']}/ "
                  + (f"matched {m.group(0)!r}" if m else "matched nothing"))

        bad = re.search(spec.get("forbid", FORBID_DEFAULT), all_text, re.I)
        grade("no_error_text", not bad,
              "clean" if not bad else f"found {bad.group(0)!r}")

        clipped = {p.name: [t["text"] for t in clipped_lines(texts.get(p.name, {}))]
                   for _, p in shots}
        clipped = {k: v for k, v in clipped.items() if v}
        grade("no_clipped_text", not clipped,
              "no left-edge clipping" if not clipped else f"clipped: {clipped}")

    report["result"] = "OK" if not failures else "FAIL"
    (outdir / "report.json").write_text(json.dumps(report, indent=2))
    print(f"\nRESULT: {'OK' if not failures else 'FAIL — ' + ', '.join(failures)}")
    print(f"report: {outdir}/report.json")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
