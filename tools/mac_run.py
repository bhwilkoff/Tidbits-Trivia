"""Real-hardware harness for the macOS app — the 5th platform, and the one with
no coverage at all until now.

The Mac is the only platform where the app is not alone on the display, so the
capture crops to the app's own window via System Events bounds. A full-screen
grab reads the desktop, the menu bar and whatever else is open, and every one of
those strings would count as "text the app put on the glass".

    python3 tools/mac_run.py --only home,records,live
"""
import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import Grader, ocr, qa_dir, sh  # noqa: E402

APP = "/Applications/TidbitsTrivia.app"
BIN = f"{APP}/Contents/MacOS/TidbitsTrivia"
PROC = "TidbitsTrivia"

# The Mac shell is a NavigationSplitView, so the sidebar is on screen for every
# section — which makes the sidebar labels useless as a screen signature. Every
# expect_any below is content from the DETAIL column only.
ANCHOR = r"Tidbits|Quick Play|Records|Create|Leaderboard|Live"

SCENARIOS = {
    "home":    (dict(TIDBITS_TAB="play"),
                {"expect_any": r"Quick Play|Daily|Play a round|Start"}),
    "records":  (dict(TIDBITS_TAB="records"),
                 {"expect_any": r"Your games|Personal bests|No games yet|streak"}),
    "create":   (dict(TIDBITS_TAB="create"),
                 {"expect_any": r"Create|quiz|round|question"}),
    "leaderboard": (dict(TIDBITS_TAB="leaderboard"),
                    {"expect_any": r"Leaderboard|standings|season|venue|rank"}),
    "live":     (dict(TIDBITS_TAB="live"),
                 {"expect_any": r"Live|Host|room|code|join"}),
    "livehost": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST"),
                 {"expect_any": r"QATEST|lobby|players|Start|waiting"}),
}


def quit_app():
    sh(["osascript", "-e", f'tell application "{PROC}" to quit'], timeout=20)
    time.sleep(1)
    sh(["pkill", "-x", PROC], timeout=10)
    time.sleep(1)


def launch(env):
    """Launch with env. `open -a` does NOT forward env to a GUI app, so the
    binary is exec'd directly — which is also what makes the TIDBITS_* hooks
    reachable at all on the Mac."""
    e = " ".join(f"{k}={v}" for k, v in env.items())
    subprocess.Popen(f"{e} '{BIN}' >/dev/null 2>&1 &", shell=True)


def window_bounds():
    """AppleScript is the only bounds source that does not need pyobjc (absent
    on this box). Returns x,y,w,h or None while the window is still drawing."""
    r = sh(["osascript", "-e",
            f'tell application "System Events" to tell process "{PROC}" to '
            'get {position, size} of front window'], timeout=20)
    nums = [int(n) for n in re.findall(r"-?\d+", r.stdout)]
    return tuple(nums[:4]) if len(nums) >= 4 else None


def capture(path, tries=20):
    for _ in range(tries):
        # -R is a SCREEN-region grab, not a window grab: without raising the app
        # first, whatever happens to be in front (a terminal, in the run that
        # caught this) is captured and its text is graded as the app's.
        sh(["osascript", "-e", f'tell application "{PROC}" to activate'], timeout=15)
        time.sleep(0.8)
        b = window_bounds()
        if b and b[2] > 200 and b[3] > 200:
            sh(["screencapture", "-x", "-o", "-R",
                f"{b[0]},{b[1]},{b[2]},{b[3]}", str(path)], timeout=40)
            if Path(path).exists() and Path(path).stat().st_size > 5000:
                return True
        time.sleep(1.5)
    return False


def run(name, outdir):
    env, spec = SCENARIOS[name]
    quit_app()
    launch(env)
    d = outdir / name
    d.mkdir(parents=True, exist_ok=True)
    shots = []
    # Two frames a few seconds apart: the first catches the initial paint, the
    # second catches content that arrives over the network. Grading the union
    # means a slow fetch is not a failure, but a never-arriving one still is.
    for i, wait in enumerate((6, 7)):
        time.sleep(wait)
        p = d / f"{i}.png"
        if capture(p):
            shots.append((wait, p))
    return shots, spec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()

    names = [n for n in (a.only.split(",") if a.only else SCENARIOS) if n in SCENARIOS]
    out = qa_dir("mac", "sweep")
    g = Grader(out, platform="mac", app=APP, scenarios=names)

    if not Path(BIN).exists():
        g.grade("app_installed", False, f"{BIN} missing — nothing to test")
        return g.finish()

    for n in names:
        print(f"\n=== {n} ===")
        shots, spec = run(n, out)
        if not shots:
            g.grade(f"{n}.captured", False, "no window ever appeared")
            continue
        texts = ocr(shots)
        sub = Grader(out, platform="mac")
        sub.grade_glass(shots, texts, spec, ANCHOR)
        for k, v in sub.report["assertions"].items():
            g.grade(f"{n}.{k}", v["pass"], v["evidence"])
    quit_app()
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
