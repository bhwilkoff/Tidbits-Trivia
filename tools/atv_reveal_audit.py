#!/usr/bin/env python3
"""Reveal-phase depth probe: drive date-seeded random corpus rows to REVEAL on
the real Apple TV and assert the row's EXPLANATION reaches the glass — the
learn-something-every-round promise, verified where the player sees it.

Usage: python3 tools/atv_reveal_audit.py [--n 6]
"""
import json, random, re, sqlite3, subprocess, sys, time
from pathlib import Path

N = next((int(a.split("=",1)[1]) for a in sys.argv if a.startswith("--n=")), 6)
DEVICE = "C3FBA9DE-4A60-555B-A65F-80D6809A275B"
BUNDLE = "com.learningischange.tidbitstrivia"
DD = "/Applications/Xcode-beta.app/Contents/Developer"
PYATV = str(Path.home() / ".pyatv-venv/bin/atvremote")
PYATV_ARGS = ["--id", "7A:3F:0C:4E:20:1E", "--protocol", "companion"]
OUTDIR = Path(f"build/qa/atv-{time.strftime('%F')}/reveal-audit-{int(time.time())}")
OUTDIR.mkdir(parents=True, exist_ok=True)


def sh(cmd, timeout=90):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def wake_tv():
    for _ in range(3):
        r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=40)
        if "PowerState.On" in r.stdout:
            return
        sh([PYATV] + PYATV_ARGS + ["turn_on"], timeout=40)
        time.sleep(5)


def main():
    db = sqlite3.connect("TidbitsTrivia/Resources/corpus.sqlite")
    rows = db.execute("select id, explanation from questions "
                      "where explanation is not null and length(explanation) > 40").fetchall()
    random.seed(time.strftime("%F"))
    picks = random.sample(rows, N)
    wake_tv()
    fails = []
    for i, (qid, explanation) in enumerate(picks):
        env = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_NO_GAMECENTER": "1",
               "TIDBITS_AUTOPLAY": "classic:mixed", "TIDBITS_QUESTION": qid,
               "TIDBITS_AUTOPILOT": "1", "TIDBITS_AUTOPILOT_CORRECT": "1",
               "TIDBITS_AUTOPILOT_STEPS": "1"}   # one submit -> park on REVEAL
        r = sh(["env", f"DEVELOPER_DIR={DD}", "xcrun", "devicectl", "device",
                "process", "launch", "--terminate-existing", "--device", DEVICE,
                "-e", json.dumps(env), BUNDLE], timeout=60)
        if "Launched application" not in (r.stdout + r.stderr):
            wake_tv()
            r = sh(["env", f"DEVELOPER_DIR={DD}", "xcrun", "devicectl", "device",
                    "process", "launch", "--terminate-existing", "--device", DEVICE,
                    "-e", json.dumps(env), BUNDLE], timeout=60)
            if "Launched application" not in (r.stdout + r.stderr):
                fails.append((qid, "launch failed"))
                continue
        time.sleep(11)   # launch + autopilot's first submit + reveal settle
        png = OUTDIR / f"{i:02d}-{qid.replace(':','_')[:60]}.png"
        try:
            sh(["env", f"DEVELOPER_DIR={DD}", "xcrun", "devicectl", "device",
                "capture", "screenshot", "--device", DEVICE,
                "--destination", str(png)], timeout=30)
        except subprocess.TimeoutExpired:
            fails.append((qid, "capture timeout"))
            continue
        if not png.exists():
            fails.append((qid, "no frame"))
            continue
        rr = sh(["/tmp/tbocr", str(png)], timeout=120)
        try:
            glass = norm(" ".join(t["text"] for t in
                                  json.loads(rr.stdout.splitlines()[0])["allText"]))
        except Exception:
            glass = ""
        tail = norm(explanation)[-20:]
        ok = tail in glass
        print(f"  [{'PASS' if ok else 'FAIL'}] {qid} "
              f"({len(explanation)}ch explanation){'' if ok else ' — tail not on glass'}",
              flush=True)
        if not ok:
            fails.append((qid, f"explanation tail missing ({explanation[-40:]!r})"))
    (OUTDIR / "report.json").write_text(json.dumps({"checked": N, "fails": fails}, indent=1))
    print(f"\n{len(fails)}/{N} problems -> {OUTDIR}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
