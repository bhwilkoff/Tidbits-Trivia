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
    # The PROJECTOR — what the pub's big screen shows. Every other scenario
    # photographs the host's laptop; this is the only view of the room's screen,
    # and until now the harness CLOSED it to stop it covering the shell.
    "liveprojector": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST"),
                      {"projector": True,
                       # The room needs ALL THREE at once: which round it is, the
                       # question, and the code to join. Any one of them missing is a
                       # broken night, so this cannot be an `expect_any`.
                       "expect_all": [r"ROUND \d", r"QATEST", r"Answer on your phones"],
                       # A truncated question is unreadable to the room. The prompt
                       # was rendering on one line and ending in an ellipsis.
                       "expect_none": r"\u2026|\.\.\."}),
    # The projector's OTHER states. Each is a different layout and none had ever
    # been photographed; the truncation bug lived in the only state that had.
    "projreveal": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST",
                        TIDBITS_LIVE_STATE="reveal"),
                   {"last_frame_only": True, "projector": True, "expect_none": r"\u2026|\.\.\.",
                    # The room still needs the round line and the code AFTER the
                    # reveal — this is when the tally and explanation appear and
                    # push everything else off.
                    "expect_all": [r"ROUND \d", r"QATEST"]}),
    "projbreak": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST",
                       TIDBITS_LIVE_STATE="break"),
                  {"last_frame_only": True, "projector": True, "expect_none": r"\u2026|\.\.\.",
                   "expect_all": [r"Back in a moment"]}),
    # G2: the scores the host reads out between rounds.
    "projscores": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST",
                        TIDBITS_LIVE_STATE="scores"),
                   {"last_frame_only": True, "projector": True,
                    "expect_none": r"\u2026|\.\.\.",
                    "expect_all": [r"SCORES AFTER ROUND \d"]}),
    "projstandings": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST",
                           TIDBITS_LIVE_STATE="standings"),
                      {"last_frame_only": True, "projector": True, "expect_none": r"\u2026|\.\.\.",
                       # This scenario ends a night with NO teams, which is exactly
                       # the case that rendered a blank wall. The guidance line is
                       # what proves the empty state is on screen.
                       "expect_all": [r"FINAL STANDINGS", r"No teams to rank"]}),
    # G5: the pick-a-category GRID — the slide the room reads to choose the next
    # cell. It needs BOTH hooks: LIVE_BOARD=1 puts a board round in the event at
    # all, and LIVE_STATE=board holds the projector on the grid. With only the
    # second, `currentRoundBoard` is nil and the ordinary question slide renders —
    # the scenario would photograph the wrong screen and still pass.
    #
    # The assertion is the POINTS, not the word "board": a grid that drew its
    # headers but no cells is a board the room cannot pick from.
    "projboard": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST",
                       TIDBITS_LIVE_BOARD="1", TIDBITS_LIVE_STATE="board"),
                  {"last_frame_only": True, "projector": True,
                   "expect_none": r"\u2026|\.\.\.",
                   # "25 left" is the assertion that a 5x5 board is COMPLETE. The
                   # first version asked only for "points on the board" and passed
                   # over a grid with five holes in it — the corpus held every cell,
                   # but the builder was handed a ~10-question category pool and
                   # could not fill five tiers from it. An assertion that cannot
                   # fire is not an assertion.
                   "expect_all": [r"PICK A CATEGORY|PICKS", r"100", r"500",
                                  r"25 left", r"7,500 points on the board"]}),
    # G5: the HOST's copy of the grid, on the laptop — the same two hooks as
    # projboard but photographing the cockpit instead of the projector. The room
    # calls a cell out loud and the host taps it here, so if this panel is missing
    # the board round cannot be played at all.
    "hostboard": (dict(TIDBITS_LIVE_HOST="1", TIDBITS_LIVE_CODE="QATEST",
                       TIDBITS_LIVE_BOARD="1", TIDBITS_LIVE_STATE="board"),
                  {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                   # "Back to the board" proves the transport switched verbs for a
                   # board round; "Pick a category" proves the picker rendered.
                   "expect_all": [r"Pick a category|picks", r"points on the board",
                                  r"Waiting for the room to pick|Board clear"],
                   # While the board is up NOBODY has picked a cell, so a live
                   # question and a Reveal button must not be on the cockpit at all.
                   # The first version of this panel showed both, which invites the
                   # host to reveal a question the room was never asked.
                   "expect_none": r"Reveal answer|Lock answers"}),
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


def capture(path, tries=20, projector=False):
    return macapp.capture(_PID, path, tries=tries, projector=projector) if _PID else False


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
        if capture(p, projector=spec.get("projector", False)):
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
