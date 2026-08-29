"""Run the real-hardware suite across every reachable device and report one matrix.

This is the entry point an autonomous loop calls. It shells out to the
per-platform runners (tools/atv_run.py, tools/ios_run.py, tools/adb_run.py)
rather than importing them, so one platform's crash or hung device cannot take
the whole sweep down with it.

Two habits are deliberate:

  * REACHABILITY IS PROBED, NOT ASSUMED. A device that is off or unplugged is
    reported as SKIP, never as a pass and never as a failure. Silence about an
    untested platform is how a green board comes to mean nothing.
  * Every run writes its own report.json under build/qa/, and this writes a
    summary.json beside them. Archive Watch's Android and iOS harnesses print
    and exit, so nothing there can be compared across runs — there is no
    baseline and no trend. Ours can be diffed.

Usage:
    python3 tools/qa_suite.py                     # smoke set, every reachable device
    python3 tools/qa_suite.py --devices ipad,pixel
    python3 tools/qa_suite.py --full              # every scenario each runner knows
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import sh   # noqa: E402

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
DEVCTL = "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/devicectl"

# The smoke set is the surfaces every platform shares, so a red cell means the
# SAME feature broke somewhere — that is what makes the matrix readable.
SMOKE = ["home", "records", "create", "settings", "paywall"]

PLATFORMS = {
    "atv":    {"runner": "tools/atv_run.py", "flag": None,
               "smoke": ["home", "records", "settings", "daily", "quickplay-classic"]},
    "ipad":   {"runner": "tools/ios_run.py", "flag": "ipad",  "smoke": SMOKE + ["clubhub"]},
    "iphone": {"runner": "tools/ios_run.py", "flag": "iphone", "smoke": SMOKE + ["clubhub"]},
    "pixel":  {"runner": "tools/adb_run.py", "flag": "pixel", "smoke": SMOKE + ["atlas"]},
    # Fire TV and the Android TV dongle are reachable over adb, but Tidbits has
    # no leanback build — no TV launcher intent, no banner, no leanback feature
    # in AndroidManifest.xml. A harness for them is meaningless until that app
    # exists, so they are absent here rather than permanently red.
}


def reachable(dev):
    """Probe, never assume. Returns (ok, why)."""
    try:
        if dev == "atv":
            r = sh([os.path.expanduser("~/.pyatv-venv/bin/atvremote"),
                    "--id", "7A:3F:0C:4E:20:1E", "--protocol", "companion",
                    "power_state"], timeout=45)
            return ("PowerState" in r.stdout, r.stdout.strip()[:60] or "no response")
        if dev in ("ipad", "iphone"):
            r = sh([DEVCTL, "list", "devices"], timeout=90)
            uuid = {"ipad": "AC5377E9", "iphone": "B4E756E2"}[dev]
            line = next((l for l in r.stdout.splitlines() if uuid in l), "")
            return ("available" in line or "connected" in line, line.strip()[:60] or "not listed")
        if dev == "pixel":
            r = sh([ADB, "devices"], timeout=45)
            return ("3B211JEKB14516" in r.stdout, "adb ok" if "3B211JEKB14516" in r.stdout
                    else "not in adb devices")
    except Exception as e:
        return (False, f"probe failed: {e}")
    return (False, "unknown device")


def run_one(dev, scenario, tag):
    cfg = PLATFORMS[dev]
    cmd = ["python3", cfg["runner"], "--scenario", scenario, "--name", f"{tag}-{scenario}"]
    if cfg["flag"]:
        cmd += ["--device", cfg["flag"]]
    t0 = time.time()
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return {"result": "TIMEOUT", "secs": round(time.time() - t0), "failed": ["timeout"]}
    m = re.search(r"^RESULT: (OK|FAIL)(?: — (.*))?$", out, re.M)
    if not m:
        return {"result": "ERROR", "secs": round(time.time() - t0),
                "failed": [out.strip().splitlines()[-1][:80] if out.strip() else "no output"]}
    return {"result": m.group(1), "secs": round(time.time() - t0),
            "failed": [s.strip() for s in (m.group(2) or "").split(",") if s.strip()]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--devices", help="comma list; default every reachable device")
    ap.add_argument("--full", action="store_true", help="every scenario the runner knows")
    ap.add_argument("--scenarios", help="comma list, overrides the smoke set")
    a = ap.parse_args()

    want = a.devices.split(",") if a.devices else list(PLATFORMS)
    tag = f"suite{int(time.time())}"
    outdir = Path("build/qa") / f"suite-{time.strftime('%Y-%m-%d')}" / tag
    outdir.mkdir(parents=True, exist_ok=True)

    summary = {"started": time.strftime("%Y-%m-%d %H:%M:%S"), "devices": {}}
    for dev in want:
        if dev not in PLATFORMS:
            print(f"[suite] unknown device {dev!r} — skipping")
            continue
        ok, why = reachable(dev)
        if not ok:
            print(f"\n=== {dev}: SKIP ({why}) ===")
            summary["devices"][dev] = {"status": "SKIP", "why": why, "scenarios": {}}
            continue

        if a.scenarios:
            scenarios = a.scenarios.split(",")
        elif a.full:
            r = sh(["python3", PLATFORMS[dev]["runner"], "--list"], timeout=90)
            scenarios = [l.split()[0] for l in r.stdout.splitlines() if l.strip()]
        else:
            scenarios = PLATFORMS[dev]["smoke"]

        print(f"\n=== {dev}: {len(scenarios)} scenarios ===")
        per = {}
        for s in scenarios:
            res = run_one(dev, s, tag)
            per[s] = res
            mark = {"OK": "  ok", "FAIL": "FAIL", "TIMEOUT": "TIME", "ERROR": " ERR"}[res["result"]]
            detail = (" — " + ", ".join(res["failed"])) if res["failed"] else ""
            print(f"  [{mark}] {s:26s} {res['secs']:4d}s{detail}")
        summary["devices"][dev] = {
            "status": "RAN", "scenarios": per,
            "pass": sum(1 for v in per.values() if v["result"] == "OK"),
            "fail": sum(1 for v in per.values() if v["result"] != "OK")}

    (outdir / "summary.json").write_text(json.dumps(summary, indent=2))

    print("\n" + "=" * 58)
    total_f = 0
    for dev, d in summary["devices"].items():
        if d["status"] == "SKIP":
            print(f"  {dev:8s} SKIP  ({d['why']})")
            continue
        total_f += d["fail"]
        bad = [s for s, v in d["scenarios"].items() if v["result"] != "OK"]
        print(f"  {dev:8s} {d['pass']:2d} pass  {d['fail']:2d} fail"
              + (f"   -> {', '.join(bad)}" if bad else ""))
    print("=" * 58)
    print(f"summary: {outdir}/summary.json")
    return 1 if total_f else 0


if __name__ == "__main__":
    sys.exit(main())
