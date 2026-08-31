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
                    # Calibrated against a real capture: a fresh profile shows
                    # "Compete against your past self", not the games list the
                    # other platforms' copy uses.
                    {"expect_any": r"Compete against your past self|Your games|"
                                   r"Personal bests|No games yet|DAY STREAK"}),
    "create":      (dict(TIDBITS_TAB="create"),
                    {"expect_any": r"Create|quiz|subject|Generate"}),
    "leaderboard": (dict(TIDBITS_TAB="leaderboard"),
                    {"expect_any": r"Leaderboard|standings|season|venue|rank|No standings"}),
    "live":        (dict(TIDBITS_TAB="live"),
                    {"expect_any": r"Live|Host|room|code|join|SCAN"}),
    # NOTE: Windows reads only TIDBITS_CLUB, TIDBITS_LIVE_CODE,
    # TIDBITS_MARATHON_LEN and the auth vars, plus TIDBITS_TAB as of this change.
    # Apple's TIDBITS_SETTINGS / _PAYWALL / _AUTOPLAY / _LIVE_HOST have no Windows
    # equivalent yet, so scenarios for them are NOT listed here — a scenario whose
    # hook does not exist grades whatever screen happened to be showing, which is
    # how the Mac "leaderboard" tab came to be reported as a defect.
    "club":        (dict(TIDBITS_TAB="play", TIDBITS_CLUB="1"),
                    {"expect_any": r"Play|Quick Play|Club|Trivia"}),
}


def crop_text(doc, rect):
    """Keep only OCR items whose box lies inside the app window.

    The desktop icons live at x < 0.06 and the taskbar at the bottom; the app is a
    centred window. Without this, `no_clipped_text` reported "Roblox Player" — a
    truncated desktop shortcut label — as a Tidbits defect.
    """
    x, y, w, h = rect
    def inside(it):
        cx = it.get("x", 0) + it.get("w", 0) / 2
        # The OCR reports a BOTTOM-LEFT origin (Vision's convention) while
        # GetWindowRect is TOP-LEFT. Without the flip the crop keeps the opposite
        # band of the screen: the desktop's "Recycle Bin", which sits at the TOP of
        # a Windows desktop, comes back at y=0.96, and the app's own chrome was
        # being discarded as "outside the window" while the wallpaper was kept.
        cy = 1.0 - (it.get("y", 0) + it.get("h", 0) / 2)
        return x <= cx <= x + w and y <= cy <= y + h
    out = dict(doc)
    for key in ("allText", "topRegion", "centerRegion", "bottomRegion"):
        if isinstance(doc.get(key), list):
            out[key] = [it for it in doc[key] if isinstance(it, dict) and inside(it)]
    return out


def run(name, outdir, g):
    env, spec = SCENARIOS[name]
    env = dict(env)
    env.setdefault("TIDBITS_SKIP_ONBOARD", "1")

    # Every step here is a scheduled-task round trip of ~35s, so a silent scenario
    # looks exactly like a hung one. It is: a six-scenario sweep spent thirteen
    # minutes saying nothing and I killed it twice believing it was stuck.
    t0 = time.time()
    def step(msg):
        print(f"    {time.time() - t0:5.0f}s  {msg}", flush=True)

    step("launching")
    pid = winbox.launch(env, wait=12)
    if pid is None:
        g.grade(f"{name}.launched", False, "the app exited on launch or never started")
        return

    d = outdir / name
    d.mkdir(parents=True, exist_ok=True)
    # Two frames in ONE round trip: the first paint, then content that arrives over
    # the network. The 6s gap is timed on the box rather than by this loop.
    # Per scenario, not once per sweep: Windows CASCADES each new window, so the app
    # opened at x=0.048 on the first launch and x=0.096 on the next. A rect read once
    # is wrong for every scenario after the first, and cropping to it silently threw
    # away most of the app's text — the first run of this graded "3 OCR lines" on a
    # perfectly readable screen.
    rect = winbox.window_rect()
    step(f"window {tuple(round(v, 3) for v in rect)}" if rect else "window rect UNKNOWN")
    step("capturing 2 frames")
    paths, size = winbox.screenshot_series([d / "0.png", d / "1.png"], gap=6,
                                           prefix=f"shot-{name}")
    shots = [(i, Path(p)) for i, p in enumerate(paths)]
    step(f"captured {len(shots)} frame(s) at {size}")
    winbox.quit_app()

    if not shots:
        g.grade(f"{name}.captured", False, "no screenshot came back from the box")
        return

    texts = ocr(shots)
    if OCR_FAILED in texts:
        g.grade(f"{name}.ocr_available", False, texts[OCR_FAILED][:140])
        return

    if rect:
        texts = {k: crop_text(v, rect) for k, v in texts.items()}
    else:
        g.grade(f"{name}.window_located", False,
                "could not read the window rect; the assertions below cover the WHOLE "
                "desktop, the owner's icons and taskbar included")

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

    # A locked box cannot be photographed, and unlocking needs a password this
    # tooling must never handle. Say so up front rather than failing scenario by
    # scenario with the same message.
    if winbox.HOST:
        winbox.keep_awake()
        if winbox.session_locked():
            g.grade("box_unlocked", False,
                    "console session is LOCKED — unlock the machine; the harness "
                    "keeps it awake once it starts unlocked, but cannot unlock it")
            return g.finish()

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
