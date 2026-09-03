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
import shutil
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

# G5/file-edge: where the panel-hook scenarios write. Under the QA output dir so a
# run leaves its artifacts beside its screenshots.
# The Mac app is SANDBOXED: it cannot write to a path the harness invents, because
# outside its container only a real panel grant opens a file. So the file-edge
# scenarios pass a BARE FILENAME, the app resolves it inside its own Documents
# directory, and the harness reads it back from the container.
FILEOP_DIR = (Path.home() / "Library/Containers/com.learningischange.tidbitstrivia"
              / "Data/Documents")

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
    # The VIDEO round, built through the REAL picker path and photographed. A
    # video round that renders a black rectangle passes every unit test in the
    # suite — the clip reference, the bookmark and the surface are only provably
    # working when a real file has been through them and the result is on screen.
    #
    # The clip lives in the app container because the sandbox can bookmark that
    # without a panel grant. The OUTSIDE-container grant is a different question
    # and is what TIDBITS_LIVE_AVSELFTEST exists to answer; this does not claim it.
    "videoround": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1",
                        TIDBITS_LIVE_ADDVIDEO="1",
                        TIDBITS_LIVE_CLIPS=str(FILEOP_DIR / "qa-clip.mp4")),
                   {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                    # The round is IN the event and its clip resolved. "Video round"
                    # alone would pass on a round that holds an unplayable
                    # reference, which is the exact bug this is here to catch.
                    "expect_any": r"qa-clip|Video round",
                    "expect_none": r"Could not|unavailable|missing"}),
    # The clip-reference self-test, on the glass. This is the check that CAN fail
    # for the reason that matters: bookmarking a file OUTSIDE the sandbox
    # container, which is what a host's picked clip actually is and what the
    # app-scope entitlement governs. The videoround scenario's clip lives INSIDE
    # the container, which the sandbox grants anyway — it proves the picker path,
    # not the entitlement.
    "avselftest": (dict(TIDBITS_LIVE_AVSELFTEST="1",
                        TIDBITS_LIVE_AVSELFTEST_PATH="/Users/bhwilkoff/Documents/GitHub/Tidbits-Trivia/build/qa/avselftest/outside.m4a"),
                   {"last_frame_only": True,
                    # What this CAN check: the summary rendered and the in-container
                    # bookmark works. What it CANNOT check is the entitlement — a
                    # sandboxed app cannot open a path it was never granted, so the
                    # outside-container line FAILs whether or not the entitlement is
                    # set. Asserting no-FAIL here would be asserting something the
                    # sandbox makes impossible, and the scenario would be red
                    # forever for the wrong reason.
                    "expect_all": [r"BOOKMARK inside container: OK",
                                   r"BOOKMARK outside container"],
                    # This screen prints its verdict as text, so the default
                    # forbid list would flag the self-test's OWN output: it
                    # contains "FAIL", "error -54" and "couldn't be opened" by
                    # design. Dropping \berror\b and couldn.t be is what makes
                    # the guard meaningful here rather than always-red; the
                    # crash-family terms are kept, and they can still fire --
                    # "No questions" is what a broken corpus load looks like on
                    # this window.
                    "forbid": r"No questions|Something went wrong|failed to"}),
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
    # The FILE PANEL EDGE. The behaviour layer (encode/decode/parse) has had good
    # coverage all along; nothing drove button -> panel -> file on disk, which is
    # the half a host actually touches. TIDBITS_LIVE_FILE hands the panel its
    # answer and TIDBITS_LIVE_FILEOP fires the operation on launch.
    #
    # `expect_file` is the real assertion: the on-screen receipt proves the app
    # THINKS it wrote, and a file on disk proves it did.
    "exportevent": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1",
                         TIDBITS_LIVE_FILEOP="exportevent",
                         TIDBITS_LIVE_FILE="qa-event.json"),
                    {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                     "expect_any": r"Exported \d+ rounds",
                     "expect_file": FILEOP_DIR / "qa-event.json"}),
    "exportcsv": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1",
                       TIDBITS_LIVE_FILEOP="exportcsv",
                       TIDBITS_LIVE_FILE="qa-questions.csv"),
                  {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                   "expect_any": r"Exported \d+ questions as CSV",
                   "expect_file": FILEOP_DIR / "qa-questions.csv"}),
    # Import reads the file the export scenario just wrote, so the two together are
    # a genuine round trip THROUGH THE PANELS, not just through the parser.
    "importevent": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1",
                         TIDBITS_LIVE_FILEOP="importevent",
                         TIDBITS_LIVE_FILE="qa-event.json"),
                    {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                     "expect_any": r"Imported \d+ rounds"}),
    # PRINT — the host's Wi-Fi-dies fallback. LivePrintTests already pins that a
    # long pack paginates and that the TEAM sheet does not leak answers, but
    # nothing drove the button. This runs the real render (the only thing skipped
    # is the hand-off to Preview, which would steal the screen mid-capture) and
    # asserts the PDF on disk.
    "printpack": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1",
                       TIDBITS_LIVE_FILEOP="printpack",
                       TIDBITS_LIVE_FILE="qa-pack.pdf"),
                  {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                   "expect_any": r"Printed \d+ pages",
                   "expect_file": FILEOP_DIR / "qa-pack.pdf",
                   # The HOST's pack must carry the answers he reads out.
                   "expect_pdf": r"Answer:"}),
    "printsheet": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1",
                        TIDBITS_LIVE_FILEOP="printsheet",
                        TIDBITS_LIVE_FILE="qa-sheet.pdf"),
                   {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                    "expect_any": r"Printed \d+ pages",
                    "expect_file": FILEOP_DIR / "qa-sheet.pdf",
                    # The TEAM's sheet must carry none of them. This is the one
                    # that matters: a leak here hands the room the answers.
                    "expect_pdf_none": r"Answer:"}),
    "importcsv": (dict(TIDBITS_TAB="live", TIDBITS_LIVE_BUILDER="1",
                       TIDBITS_LIVE_FILEOP="importcsv",
                       TIDBITS_LIVE_FILE="qa-questions.csv"),
                  {"allow_edge": SIDEBAR_FOOTER, "last_frame_only": True,
                   "expect_any": r"Imported \d+ questions from CSV"}),
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
    # An export scenario must not pass on a file a PREVIOUS run left behind.
    if spec.get("expect_file"):
        want = Path(spec["expect_file"])
        want.parent.mkdir(parents=True, exist_ok=True)
        want.unlink(missing_ok=True)
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
        # The file itself, not the app's opinion of it.
        if (want := spec.get("expect_file")) is not None:
            want = Path(want)
            size = want.stat().st_size if want.exists() else 0
            g.grade(f"{n}.file_written", size > 0,
                    f"{want} is {size} bytes" if size else f"{want} was never written")
            # And what is INSIDE it. A printed pack that renders is not the same as
            # one that carries the answers the host reads out — and the team's sheet
            # must carry none. Checked on the PDF a host would actually print, not
            # on the SwiftUI page a unit test builds.
            pat, absent = spec.get("expect_pdf"), spec.get("expect_pdf_none")
            if (pat or absent) and size:
                if not shutil.which("pdftotext"):
                    # A check that cannot see its input must FAIL, not pass quietly.
                    g.grade(f"{n}.pdf_text", False,
                            "pdftotext is not installed — the PDF content was never read")
                else:
                    text = subprocess.run(["pdftotext", str(want), "-"],
                                          capture_output=True, text=True).stdout
                    if pat:
                        hits = len(re.findall(pat, text))
                        g.grade(f"{n}.pdf_text", hits > 0,
                                f"/{pat}/ appears {hits}x in the rendered PDF")
                    if absent:
                        hits = len(re.findall(absent, text))
                        g.grade(f"{n}.pdf_text_none", hits == 0,
                                f"/{absent}/ absent, as required" if not hits
                                else f"/{absent}/ LEAKED into the PDF {hits}x")
    quit_app()
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
