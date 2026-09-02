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
import macapp  # noqa: E402
from devharness import Grader, ocr, qa_dir, sh  # noqa: E402

# Prefer the locally built app: the harness should grade what is about to ship,
# not the copy in /Applications, which lags. Pointing at /Applications is why a
# keychain-password dialog kept turning up in Mac runs after the fix landed.
_DEV = Path("build/dd-mac/Build/Products/Debug/TidbitsTrivia.app")
APP = str(_DEV if _DEV.exists() else Path("/Applications/TidbitsTrivia.app"))
BIN = f"{APP}/Contents/MacOS/TidbitsTrivia"
PROC = "TidbitsTrivia"

# The Mac shell is a NavigationSplitView, so the sidebar is on screen for every
# section — which makes the sidebar labels useless as a screen signature. Every
# expect_any below is content from the DETAIL column only.
ANCHOR = r"Tidbits|Quick Play|Records|Create|Leaderboard|Live"

# The sidebar footer is flush with the window on EVERY Mac surface; see
# devharness.clipped_lines / the allow_edge note.
SIDEBAR_FOOTER = r"Settings & Account"

SCENARIOS = {
    "home":    (dict(TIDBITS_TAB="play"),
                {"allow_edge": SIDEBAR_FOOTER, "expect_any": r"Quick Play|Daily|Play a round|Start"}),
    "records":  (dict(TIDBITS_TAB="records"),
                 {"allow_edge": SIDEBAR_FOOTER, "expect_any": r"Your games|Personal bests|No games yet|streak"}),
    "create":   (dict(TIDBITS_TAB="create"),
                 {"allow_edge": SIDEBAR_FOOTER, "expect_any": r"Create|quiz|round|question"}),
    "leaderboard": (dict(TIDBITS_TAB="leaderboard"),
                    {"allow_edge": SIDEBAR_FOOTER,
                     # DETAIL-column content only. "Leaderboard" is now a SIDEBAR row, and the
                     # split view shows the sidebar on every section, so matching it
                     # would pass while Play was on screen.
                     "expect_any": r"Resets in|No standings yet|This season"}),
    "live":     (dict(TIDBITS_TAB="live"),
                 {"allow_edge": SIDEBAR_FOOTER, "expect_any": r"Tidbits Live|Event name|Rounds",
                  "expect_none": r"Join a game|Join a night|join one with a code"}),
    # The room CODE, not a generic word. The first version of this accepted
    # "players|waiting|Start", and once the QR panel shipped it passed on the
    # word "Players" in "Players scan, or join at…" — which would still be there
    # if the code never rendered. A host who cannot read the code out has no
    # night, so the code is what the assertion is for.
    "livehost": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST"),
                 {"allow_edge": SIDEBAR_FOOTER, "expect_any": r"QATEST"}),
    # The Live builder with a populated event and its first round expanded, so
    # the per-question list and the Edit affordance are observable at all
    # (macOS-DESIGN §A2.4). Nothing could reach them from a cold launch.
    # The assertion is the per-question "Answer:" summary line, which exists
    # ONLY inside an expanded round's question list. "Rounds" matched the word
    # "rounds" in an events-list subtitle that is on screen whether or not a
    # single question rendered; "Add question" is real but sits below the fold
    # at the default window height, so it asserted the window size, not the list.
    "livebuilder": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1"),
                    {"allow_edge": SIDEBAR_FOOTER, "expect_any": r"Answer:"}),
}


_PID = None


def quit_app():
    macapp.quit_all()


def launch(env):
    """Launch through LaunchServices with the hooks attached (macapp.launch).

    This used to exec the binary directly, believing `open` could not forward
    env. `open --env` can, and exec'ing is worse than merely unnecessary: System
    Events cannot see an unregistered process, so every capture failed."""
    global _PID
    _PID = macapp.launch(APP, env)


def capture(path, tries=20):
    return macapp.capture(_PID, path, tries=tries) if _PID else False


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
            g.grade(f"{n}.captured", False,
                    macapp.why_no_window(_PID) if _PID else "the app was never launched")
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
