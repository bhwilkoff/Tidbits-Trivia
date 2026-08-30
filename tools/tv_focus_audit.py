"""Walk every Tidbits surface on a TV and report whether a remote can USE it.

Three things have to be true on a ten-foot screen, and only the first is
usually true by accident:

  1. something HOLDS focus when the surface opens — the MCQ game shipped with
     six focusable nodes and ZERO focused, so CENTER did nothing and the game
     could not be played at all;
  2. the focus is VISIBLE — Compose focuses happily and draws nothing;
  3. CENTER ACTS — the screen changes when you press OK.

This checks 1 and 3 mechanically and measures 2 as a pixel delta between an
unfocused and focused capture, so "the ring is visible" is a number rather than
an opinion. Surfaces are reached by intent extra, never by pressing blind.

    python3 tools/tv_focus_audit.py --device firetv
    python3 tools/tv_focus_audit.py --device androidtv --only settings,paywall
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
from devharness import ocr, qa_dir, sh   # noqa: E402

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
DEVICES = {"firetv": "10.0.0.139:5555", "androidtv": "10.0.0.55:5555"}
PKG = os.environ.get("TIDBITS_ADB_PKG", "com.tidbitstrivia.app.debug")
ACTIVITY = "com.learningischange.tidbitstrivia.MainActivity"

# (name, extras) — extras are (flag, key, value) triples for `am start`.
EXPECT = {'home': 'QUICK PLAY|DAILY TIDBIT', 'records': 'Your games|DAY STREAK|No games yet|Personal bests', 'create': 'Create a quiz|Generate Quiz|Play it as', 'settings': 'Haptics|Gameplay|Review questions|Feedback', 'paywall': 'Get better, not just play more|Ranked Seasons', 'clubHub': 'You.re a member|Link Wall|Club', 'atlas': 'Knowledge Atlas|map of what you actually know', 'linkWall': 'Link Wall|hidden groups', 'expeditions': 'Expedition|campaign', 'storyArchive': 'Story Archive|fact you.ve learned', 'marathonHistory': 'Marathon', 'profile': 'Profile|Player|Rating', 'leaderboard': 'Leaderboard|Season|rank', 'duels': 'Duel', 'online': 'Online|Quick Match|opponent', 'party': 'Pass & Play|Party|players', 'nightSetup': 'Trivia Night|round|preset', 'g-classic': '\\d+\\s*/\\s*\\d+', 'g-closest': '\\d+\\s*/\\s*\\d+', 'g-ordering': '\\d+\\s*/\\s*\\d+', 'g-matching': '\\d+\\s*/\\s*\\d+', 'g-typeAnswer': 'Say your answer out loud|Reveal the answer', 'g-enumerate': '\\d+\\s*/\\s*\\d+', 'g-picture': '\\d+\\s*/\\s*\\d+', 'g-thisOrThat': '\\d+\\s*/\\s*\\d+', 'g-oddOneOut': '\\d+\\s*/\\s*\\d+'}

SURFACES = [
    ("home",            [("ez", "tidbits_skip_onboard", "true")]),
    ("records",         [("es", "tidbits_tab", "records"),
                         ("ei", "tidbits_seed_records", "12")]),
    ("create",          [("es", "tidbits_tab", "create")]),
    ("settings",        [("es", "tidbits_open", "settings")]),
    ("paywall",         [("es", "tidbits_open", "paywall")]),
    ("clubHub",         [("es", "tidbits_open", "clubHub")]),
    ("atlas",           [("es", "tidbits_open", "atlas")]),
    ("linkWall",        [("es", "tidbits_open", "linkWall")]),
    ("expeditions",     [("es", "tidbits_open", "expeditions")]),
    ("storyArchive",    [("es", "tidbits_open", "storyArchive")]),
    ("marathonHistory", [("es", "tidbits_open", "marathonHistory")]),
    ("profile",         [("es", "tidbits_open", "profile")]),
    ("leaderboard",     [("es", "tidbits_open", "leaderboard")]),
    ("duels",           [("es", "tidbits_open", "duels")]),
    ("online",          [("es", "tidbits_open", "online")]),
    ("party",           [("ez", "tidbits_party", "true")]),
    ("nightSetup",      [("ez", "tidbits_night_setup", "true")]),
    # The bespoke game panels — each renders its own controls instead of the
    # MCQ answer list, so each needs its OWN initial-focus requester. This is
    # where the zero-focused bug is expected to survive.
    ("g-classic",       [("es", "tidbits_autoplay", "classic:mixed")]),
    ("g-closest",       [("es", "tidbits_autoplay", "closestCall:mixed")]),
    ("g-ordering",      [("es", "tidbits_autoplay", "ordering:mixed")]),
    ("g-matching",      [("es", "tidbits_autoplay", "matching:mixed")]),
    ("g-typeAnswer",    [("es", "tidbits_autoplay", "typeAnswer:mixed")]),
    ("g-enumerate",     [("es", "tidbits_autoplay", "enumerate:mixed")]),
    ("g-picture",       [("es", "tidbits_autoplay", "pictureId:mixed")]),
    ("g-thisOrThat",    [("es", "tidbits_autoplay", "thisOrThat:mixed")]),
    ("g-oddOneOut",     [("es", "tidbits_autoplay", "oddOneOut:mixed")]),
]


def adbs(dev, *args, timeout=60, binary=False):
    serial = DEVICES.get(dev, dev)
    out = sh([ADB, "devices"], timeout=30).stdout
    if not re.search(rf"^{re.escape(serial)}\s+device", out, re.M):
        sh([ADB, "connect", serial], timeout=30)
    cmd = [ADB, "-s", serial] + list(args)
    if binary:
        return subprocess.run(cmd, capture_output=True, timeout=timeout)
    return sh(cmd, timeout=timeout)


def shot(dev, path):
    r = adbs(dev, "exec-out", "screencap", "-p", timeout=60, binary=True)
    if r.stdout:
        Path(path).write_bytes(r.stdout)
        return True
    return False


def tree(dev):
    """uiautomator dump. Delete first — a failed dump otherwise serves a STALE
    tree from an earlier session. Retry once: it is briefly empty mid-transition."""
    for _ in range(2):
        adbs(dev, "shell", "rm", "-f", "/sdcard/ui.xml")
        adbs(dev, "shell", "uiautomator", "dump", "/sdcard/ui.xml", timeout=60)
        x = adbs(dev, "shell", "cat", "/sdcard/ui.xml", timeout=60).stdout
        if "<node" in x:
            return x
        time.sleep(1.5)
    return ""


def launch(dev, extras):
    adbs(dev, "shell", "am", "force-stop", PKG)
    time.sleep(0.7)
    args = ["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}",
            "--ez", "tidbits_skip_onboard", "true"]
    for flag, k, v in extras:
        args += [f"--{flag}", k, v]
    adbs(dev, *args, timeout=90)


def focused_node(xml):
    """The focused node's raw attributes, or ''."""
    m = re.search(r'<node[^>]*focused="true"[^>]*?>', xml)
    return m.group(0) if m else ""


def focused_bounds(xml):
    n = focused_node(xml)
    m = re.search(r'bounds="([^"]+)"', n)
    return m.group(1) if m else None


def focused_clickable(xml):
    """Can CENTER actually DO something? This is the real requirement, and it
    does not depend on movement. Two earlier rules both produced false alarms:
    a flat pixel-area threshold called a chip row broken, and bounds-equality
    called Records broken because its rows are uniform, so scrolling by one row
    lands focus at an IDENTICAL rect. Whether the focused node is clickable is
    the question that was actually being asked all along."""
    n = focused_node(xml)
    if 'clickable="true"' in n:
        return True
    # A range widget is driven by LEFT/RIGHT, not OK, so "not clickable" does
    # not mean "not usable". Measured on the Closest Call round: the focused
    # node is an android.widget.SeekBar with clickable=false, and five RIGHT
    # presses moved the guess from 1832 to 1837. Verified before excusing.
    return 'android.widget.SeekBar' in n


def px_delta(a, b):
    """How much of the screen changed. The focus ring is a visual claim, so it
    gets measured rather than asserted."""
    try:
        from PIL import Image, ImageChops
        d = ImageChops.difference(Image.open(a).convert("RGB"), Image.open(b).convert("RGB"))
        bb = d.getbbox()
        if not bb:
            return 0
        return (bb[2] - bb[0]) * (bb[3] - bb[1])
    except Exception:
        return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="firetv")
    ap.add_argument("--only", help="comma list of surface names")
    a = ap.parse_args()

    want = set(a.only.split(",")) if a.only else None
    outdir = qa_dir(f"tvaudit-{a.device}", "walk")
    rows, bad = [], []

    for name, extras in SURFACES:
        if want and name not in want:
            continue
        launch(a.device, extras)
        # WAIT FOR THE SCREEN, do not guess a duration. A fixed 7s sleep read
        # the Android TV dongle as "ignores intent extras" across 26 surfaces —
        # it is simply slow (2GB RAM; logcat shows "Skipped 274 frames" and
        # 5s frame times), and the route had not drawn yet. Atlas was Home at
        # 10s and Atlas at 18s on the same launch. Polling makes the walk
        # correct on a fast box and a slow one without a per-device constant.
        exp = EXPECT.get(name)
        p0 = outdir / f"{name}-a.png"
        deadline = time.time() + 40
        text = ""
        while time.time() < deadline:
            time.sleep(2.5)
            if not shot(a.device, p0):
                continue
            for d in ocr([(0, p0)]).values():
                text = " ".join(t["text"] for t in d.get("allText", []))
            if not exp or re.search(exp, text, re.I):
                break
        ok_screen = (not exp) or bool(re.search(exp, text, re.I))
        x = tree(a.device)
        focusable = x.count('focusable="true"')
        focused = x.count('focused="true"')
        # Focus is claimed a few hundred ms after compose settles, and a panel
        # holding a LazyVerticalGrid settles slower than a plain Column — the
        # matching round reported 0 focused on a 7s sample and 1 focused on
        # every sample at 9s. Re-check once before calling it broken, so a slow
        # screen is not recorded as an unusable one.
        if focused == 0:
            time.sleep(3)
            x = tree(a.device)
            focusable = x.count('focusable="true"')
            focused = x.count('focused="true"')
        p1 = outdir / f"{name}-b.png"
        b0 = focused_bounds(x)
        clickable = focused_clickable(x)
        # One D-pad move. The PRIMARY signal is whether the focused element's
        # bounds changed — pixel area was the first cut and it lied twice: a
        # chip row moves focus while changing only ~13k px, which a flat area
        # threshold called broken. Pixels stay on as corroboration.
        adbs(a.device, "shell", "input", "keyevent", "KEYCODE_DPAD_DOWN")
        time.sleep(1.2)
        shot(a.device, p1)
        b1 = focused_bounds(tree(a.device))
        delta = px_delta(p0, p1) if (p0.exists() and p1.exists()) else -1
        moved = bool(b0) and bool(b1) and b0 != b1

        ok_focus = focused >= 1
        # A screen with ONE focusable element has nowhere for D-pad DOWN to go,
        # so zero pixel change is the CORRECT result, not a defect. The first
        # run of this auditor called leaderboard, duels and online broken on
        # exactly that basis — the instrument was wrong, not the app. Only
        # demand movement where there is somewhere to move.
        # Usable = something holds focus AND pressing OK on it does something.
        ok_visible = clickable
        status = "OK" if (ok_focus and ok_visible and ok_screen) else "FAIL"
        if status == "FAIL":
            reason = []
            if not ok_screen:
                reason.append(f"WRONG SCREEN — /{exp}/ not on the glass")
            if not ok_focus:
                reason.append(f"0 focused of {focusable} focusable")
            if not ok_visible:
                reason.append(f"focused node is not clickable — OK does nothing "
                              f"({focusable} focusable, moved={moved})")
            bad.append((name, "; ".join(reason)))
        rows.append({"surface": name, "focusable": focusable, "focused": focused,
                     "clickable": clickable, "moved": moved, "delta": delta,
                     "right_screen": ok_screen, "status": status})
        print(f"  [{status:4s}] {name:16s} focusable={focusable:<3d} focused={focused} "
              f"clickable={str(clickable):5s} screen={str(ok_screen):5s}")

    (outdir / "audit.json").write_text(json.dumps(rows, indent=2))
    print(f"\n  {sum(1 for r in rows if r['status'] == 'OK')}/{len(rows)} surfaces usable by remote")
    for n, why in bad:
        print(f"    FAIL {n}: {why}")
    print(f"  artifacts: {outdir}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
