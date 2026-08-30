"""Real-browser harness for the web app — the other platform with no coverage.

Every route is captured at BOTH 375px and 1440px. The project's density rule is
"test at 375px before 1440px", and a desktop-only sweep cannot see the failure
that rule exists to prevent: a layout that is fine wide and clipped narrow. The
clip detector reads the narrow frame, which is where clipping actually happens.

    python3 tools/web_run.py --only daily,live
    python3 tools/web_run.py --base http://localhost:8080     # pre-deploy
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import Grader, ocr, qa_dir, sh  # noqa: E402

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BASE = "https://tidbitstrivia.com"
# Calibrated against a real capture, not assumed: a question view is full-screen
# and carries NO site chrome at all — its frame is "1/7 HISTORY <clue> <options>".
# Anchoring on the wordmark alone called a correctly-rendered Daily "the wrong
# app". The counter is the question view's own signature.
ANCHOR = r"Tidbits|Quick Play|Daily|question|round|play|\d+\s*/\s*\d+"

VIEWPORTS = [("narrow", 375, 812), ("wide", 1440, 900)]

# route -> expect_any. Signatures are content unique to that route: the site
# header is on every page and would match everywhere, which is how a sweep
# reports 15/15 while showing one screen fifteen times.
ROUTES = {
    "home":        ("/", r"Quick Play|Play|Daily|trivia"),
    "daily":       ("/#/daily", r"\d+\s*/\s*\d+|question|Daily"),
    "dailyboard":  ("/#/dailyboard", r"board|today|rank|score|streak"),
    "leaderboard": ("/#/leaderboard", r"Leaderboard|season|venue|rank|standings"),
    "profile":     ("/#/profile", r"Profile|name|stats|sign in|player"),
    "atlas":       ("/#/atlas", r"Atlas|map of what|know"),
    "archive":     ("/#/archive", r"Archive|stor|past"),
    "linkwall":    ("/#/linkwall", r"Link|wall|connect"),
    "expeditions": ("/#/expeditions", r"Expedition|journey|track"),
    "marathon":    ("/#/marathon", r"Marathon|run|long"),
    "duels":       ("/#/duels", r"Duel|challenge|opponent|versus"),
    "club":        ("/#/club", r"Club|member|unlock|plan|subscri"),
    "night":       ("/#/night", r"Night|host|room|code|round"),
    "live":        ("/#/live", r"Live|join|code|room"),
}


def shoot(url, w, h, path, budget=9000):
    sh([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        f"--window-size={w},{h}", f"--virtual-time-budget={budget}",
        f"--screenshot={path}", url], timeout=90)
    return Path(path).exists() and Path(path).stat().st_size > 3000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--base", default=BASE)
    a = ap.parse_args()

    names = [n for n in (a.only.split(",") if a.only else ROUTES) if n in ROUTES]
    out = qa_dir("web", "sweep")
    g = Grader(out, platform="web", base=a.base, routes=names)

    seen = {}
    for n in names:
        path, sig = ROUTES[n]
        print(f"\n=== {n} ({path}) ===")
        d = out / n
        d.mkdir(parents=True, exist_ok=True)
        shots = []
        for label, w, h in VIEWPORTS:
            p = d / f"{label}.png"
            if shoot(a.base + path, w, h, p):
                shots.append((label, p))
            time.sleep(0.5)
        # A cold headless Chrome under load can return a blank first paint before
        # the virtual-time budget expires, which grades as "SCREEN OFF" for a site
        # that is up — measured once on /#/ during a run with three other jobs on
        # the machine. Retry the whole route with a longer budget rather than
        # reporting a live page as dark.
        if shots and max(len(v.get("allText", []))
                         for v in ocr(shots).values()) < 4:
            print("  blank first paint — retrying with a longer budget")
            shots = []
            for label, w, h in VIEWPORTS:
                p = d / f"{label}.png"
                if shoot(a.base + path, w, h, p, budget=20000):
                    shots.append((label, p))
        if not shots:
            g.grade(f"{n}.captured", False, "chrome produced no screenshot")
            continue
        texts = ocr(shots)
        sub = Grader(out, platform="web")
        sub.grade_glass(shots, texts, {"expect_any": sig}, ANCHOR)
        for k, v in sub.report["assertions"].items():
            g.grade(f"{n}.{k}", v["pass"], v["evidence"])
        seen[n] = " ".join(t["text"] for t in
                           texts.get((d / "wide.png").name, {}).get("allText", []))[:150]

    # Distinct routes must show distinct content. Fifteen passing captures of the
    # same screen pass every per-route check ever written.
    dupes = {}
    for n, txt in seen.items():
        if txt and txt in dupes:
            g.grade(f"{n}.distinct_screen", False, f"identical to {dupes[txt]}")
        dupes[txt] = n
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
