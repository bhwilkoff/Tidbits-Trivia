#!/usr/bin/env python3
"""On-device legibility audit: render the corpus's LONGEST prompts and options
on the real Apple TV (TIDBITS_QUESTION hook) and assert the TEXT'S TAIL reaches
the glass — a clipped/truncated prompt loses its ending, and OCR comparing the
row's real text against what rendered is the only honest check
(the static audit can say "131 prompts are over 220 chars"; it cannot say
whether any of them overflows).

Usage: python3 tools/atv_prompt_audit.py [--top 12]
Renders each candidate solo (STEPS=0 parks on it), OCRs one settled frame,
and grades: prompt tail on glass, every option's head on glass.
"""
import json, re, sqlite3, subprocess, sys, time
from pathlib import Path

PYATV = str(Path.home() / ".pyatv-venv/bin/atvremote")
PYATV_ARGS = ["--id", "7A:3F:0C:4E:20:1E", "--protocol", "companion"]

TOP = next((int(a.split("=",1)[1]) for a in sys.argv if a.startswith("--top=")), 12)
DEVICE = "C3FBA9DE-4A60-555B-A65F-80D6809A275B"
BUNDLE = "com.learningischange.tidbitstrivia"
DD = "/Applications/Xcode-beta.app/Contents/Developer"
OUTDIR = Path(f"build/qa/atv-{time.strftime('%F')}/prompt-audit-{int(time.time())}")
OUTDIR.mkdir(parents=True, exist_ok=True)


def sh(cmd, timeout=90):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def candidates():
    db = sqlite3.connect("TidbitsTrivia/Resources/corpus.sqlite")
    rows = db.execute(
        "select id, prompt, option0, option1, option2, option3 from questions").fetchall()
    by_prompt = sorted(rows, key=lambda r: -len(r[1]))[:TOP // 2]
    by_option = sorted(rows, key=lambda r: -max(len(r[i] or "") for i in (2, 3, 4, 5)))[:TOP // 2]
    seen, out = set(), []
    for r in by_prompt + by_option:
        if r[0] not in seen:
            seen.add(r[0])
            out.append(r)
    return out


def ocr_text(png):
    r = sh(["/tmp/tbocr", str(png)], timeout=120)
    try:
        d = json.loads(r.stdout.splitlines()[0])
        return " ".join(t["text"] for t in d["allText"])
    except Exception:
        return ""


def wake_tv():
    """Same verified-wake as atv_run: launches are DENIED while the TV dozes."""
    for _ in range(3):
        r = sh([PYATV] + PYATV_ARGS + ["power_state"], timeout=40)
        if "PowerState.On" in r.stdout:
            return
        sh([PYATV] + PYATV_ARGS + ["turn_on"], timeout=40)
        time.sleep(5)


def main():
    wake_tv()
    rows = candidates()
    print(f"[prompt-audit] {len(rows)} longest-text rows -> {OUTDIR}")
    fails = []
    for i, (qid, prompt, *opts) in enumerate(rows):
        env = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_NO_GAMECENTER": "1",
               "TIDBITS_AUTOPLAY": "classic:mixed",   # launches the game the
               "TIDBITS_QUESTION": qid,               # forced row rides in
               "TIDBITS_AUTOPILOT": "1", "TIDBITS_AUTOPILOT_STEPS": "0"}
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
                print(f"  [FAIL] {qid} launch failed", flush=True)
                continue
        time.sleep(9)
        png = OUTDIR / f"{i:02d}-{qid.replace(':', '_').replace('/', '_')[:60]}.png"
        try:
            sh(["env", f"DEVELOPER_DIR={DD}", "xcrun", "devicectl", "device",
                "capture", "screenshot", "--device", DEVICE,
                "--destination", str(png)], timeout=30)
        except subprocess.TimeoutExpired:
            fails.append((qid, "capture timeout"))
            continue
        glass = norm(ocr_text(png))
        problems = []
        # The prompt's TAIL is the truncation tell (OCR loses ~nothing on 4K).
        tail = norm(prompt)[-24:]
        if tail and tail not in glass:
            problems.append(f"prompt tail missing ({prompt[-30:]!r})")
        for oi, opt in enumerate(opts):
            if not opt:
                continue
            head = norm(opt)[:18]
            if head and head not in glass:
                problems.append(f"option{oi} head missing ({opt[:24]!r})")
        verdict = "OK" if not problems else "; ".join(problems)
        print(f"  [{'PASS' if not problems else 'FAIL'}] {qid} "
              f"(prompt {len(prompt)}ch) {verdict}", flush=True)
        if problems:
            fails.append((qid, verdict))
    (OUTDIR / "report.json").write_text(json.dumps(
        {"checked": len(rows), "fails": fails}, indent=1))
    print(f"\n{len(fails)}/{len(rows)} problem rows -> {OUTDIR}/report.json")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
