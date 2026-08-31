"""Real-hardware harness for the Windows app — the sixth platform on the bench.

Same contract as atv_run / ios_run / adb_run / mac_run: drive the app to a known
surface with an env hook, photograph the glass, OCR it, and grade. Nothing is
believed because the app said so.

Windows-specific realities, learned the same way the others were:

  * The app is SELF-CONTAINED (PublishSingleFile), so the box needs no .NET SDK.
    Publishing happens on the Mac and the output is copied over — the Windows
    machine is a device, not a build server.
  * The capture is the whole desktop. A window-region grab on macOS kept
    photographing whatever was in front of the app, and there is no reason to
    expect Windows to be kinder.
  * A dark or blank frame is reported as a MEASUREMENT (percent black, mean
    luma), never as "the screen was off" — that phrasing cost a lot of wrong
    conclusions on the iPhone.

    python3 tools/win_run.py --only home,records
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import winbox  # noqa: E402
from devharness import (OCR_FAILED, Grader, frame_darkness, ocr,  # noqa: E402
                        qa_dir)

ANCHOR = r"Tidbits|Quick Play|Records|Create|Live|Play"

# TIDBITS_* hooks are the same family Apple and Android use — Tidbits.Core reads
# them from the environment, so one spelling drives every platform.
SCENARIOS = {
    "home":        (dict(TIDBITS_TAB="play"),
                    {"expect_any": r"Quick Play|Daily|Play|Start|Surprise"}),
    "records":     (dict(TIDBITS_TAB="records"),
                    {"expect_any": r"Your games|Personal bests|No games yet|streak|GAMES"}),
    "create":      (dict(TIDBITS_TAB="create"),
                    {"expect_any": r"Create|quiz|subject|Generate"}),
    "leaderboard": (dict(TIDBITS_TAB="leaderboard"),
                    {"expect_any": r"Leaderboard|standings|season|venue|rank|No standings"}),
    "settings":    (dict(TIDBITS_SETTINGS="1"),
                    {"expect_any": r"Settings|Account|Feedback|Gameplay"}),
    "paywall":     (dict(TIDBITS_PAYWALL="1"),
                    {"expect_any": r"Club|Get better|Ranked|member|plan"}),
    "livehost":    (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QWIN"),
                    {"expect_any": r"QWIN|lobby|players|Start|waiting|SCAN"}),
    "classic":     (dict(TIDBITS_AUTOPLAY="classic:mixed", TIDBITS_AUTOPILOT="1",
                         TIDBITS_AUTOPILOT_CORRECT="1"),
                    {"expect_any": r"\?|\d+\s*/\s*\d+|Correct|Nice"}),
}


def run(name, outdir, g):
    env, spec = SCENARIOS[name]
    env = dict(env)
    env.setdefault("TIDBITS_SKIP_ONBOARD", "1")

    pid = winbox.launch(env, wait=12)
    if pid is None:
        g.grade(f"{name}.launched", False, "the app exited on launch or never started")
        return

    d = outdir / name
    d.mkdir(parents=True, exist_ok=True)
    shots = []
    # Two frames: the first paint, then content that arrives over the network.
    for i, extra in enumerate((0, 6)):
        if extra:
            time.sleep(extra)
        p = d / f"{i}.png"
        ok, _ = winbox.screenshot(p, remote_name=f"shot-{name}-{i}.png")
        if ok and p.exists():
            shots.append((i, p))
    winbox.quit_app()

    if not shots:
        g.grade(f"{name}.captured", False, "no screenshot came back from the box")
        return

    texts = ocr(shots)
    if OCR_FAILED in texts:
        g.grade(f"{name}.ocr_available", False, texts[OCR_FAILED][:140])
        return

    lines = max((len(texts.get(p.name, {}).get("allText", [])) for _, p in shots), default=0)
    if lines < 4:
        dk = frame_darkness(shots[-1][1])
        g.grade(f"{name}.readable", False,
                f"{lines} OCR lines; frame is {dk[1]}% black (mean luma {dk[0]})"
                if dk else f"{lines} OCR lines")
        return

    sub = Grader(outdir, platform="windows")
    sub.grade_glass(shots, texts, spec, ANCHOR)
    for k, v in sub.report["assertions"].items():
        g.grade(f"{name}.{k}", v["pass"], v["evidence"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--deploy", action="store_true",
                    help="publish on this Mac and copy to the box first")
    a = ap.parse_args()

    names = [n for n in (a.only.split(",") if a.only else SCENARIOS) if n in SCENARIOS]
    out = qa_dir("windows", "sweep")
    g = Grader(out, platform="windows", host=winbox.HOST or "(unset)", scenarios=names)

    ok, why = winbox.check()
    # Reachability is PROBED, never assumed — an unreachable box must not be
    # able to produce a green board.
    if not g.grade("box_reachable", ok, why):
        return g.finish()

    if a.deploy:
        pub_ok, log = winbox.publish()
        if not g.grade("published", pub_ok, "win-x64 self-contained" if pub_ok else log[-200:]):
            return g.finish()
        dep_ok, err = winbox.deploy()
        if not g.grade("deployed", dep_ok, winbox.REMOTE if dep_ok else err):
            return g.finish()

    for n in names:
        print(f"\n=== {n} ===")
        run(n, out, g)
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
