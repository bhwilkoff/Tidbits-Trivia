#!/usr/bin/env python3
"""Audit a rendered game screen — the checks that only a picture can answer.

    python3 tools/play/screen_audit.py <shot.png> [--json]

The engine sweep proves the RULES work: the right answer is accepted, the round
ends, the score adds up. It renders nothing, so it is blind to a blank panel, an
option clipped at the screen edge, a reveal that never drew. Those are the
defects that have actually surfaced by looking at screenshots this session —
four separate times — and this is the mechanical version of looking.

What survives is deliberately narrow. Pixel statistics can catch a screen that
did not render; they cannot judge whether a question is any good. That part is
done by READING the sampled frames, which is why the marathon keeps one in sixty
rather than none.

Checks:

  BLANK       the frame is one flat colour below the status bar — a view that
              rendered nothing. (The Windows pass hit exactly this as a blank
              detail pane, and every automated check stayed green.)
  (EDGE-INK was tried and removed. It flagged the launch screen for the device
   BEZEL, and once that was excluded it flagged perfectly good question screens
   for the heavy black borders of the chunky cards, which by design run almost
   to the edge. It cannot tell a card border from clipped text in this app, and
   a check with no signal is worse than no check.)
  (BOTTOM-INK was tried and removed: every screen here is a ScrollView, so
   content reaching the bottom edge is normal and the check flagged a perfectly
   good results screen. A rule that cannot tell overflow from scrolling is a
   rule that gets ignored.)
  LOW-INK     almost nothing drawn at all — a screen that is technically not one
              colour but holds no readable content.

Exits 0 always; the caller decides what to do with the findings.
"""
import argparse
import json
import pathlib
import sys

from PIL import Image

STATUS_BAR = 0.06      # fraction of height that is the OS status bar
HOME_BAR = 0.015       # fraction at the bottom the app must leave clear
# `simctl io screenshot` includes the device bezel and rounded corners on this
# simulator, and reading the very first column as content flagged the launch
# screen for "ink at both edges" — that ink was the phone. The edge band is
# sampled INSIDE the bezel, still well outside the app's own 20pt margin.
BEZEL = 0.030          # fraction of width that is device, not app
MARGIN = 0.018         # width of the band sampled just inside it


def analyse(path):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    top = int(h * STATUS_BAR)
    body = img.crop((0, top, w, h))
    bw, bh = body.size
    small = body.resize((min(bw, 320), min(bh, 700)))
    px = small.load()
    sw, sh = small.size

    colours = {}
    dark = 0
    total = sw * sh
    for y in range(sh):
        for x in range(sw):
            r, g, b = px[x, y]
            key = (r // 24, g // 24, b // 24)
            colours[key] = colours.get(key, 0) + 1
            if r + g + b < 300:
                dark += 1

    dominant = max(colours.values()) / total
    ink = dark / total

    # Ink hard against an edge means clipping, not layout.
    def edge_ink(x0, x1, y0, y1):
        n = c = 0
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b = px[x, y]
                n += 1
                if r + g + b < 300:
                    c += 1
        return c / max(1, n)

    bez = max(1, int(sw * BEZEL))
    m = max(1, int(sw * MARGIN))
    left = edge_ink(bez, bez + m, 0, sh)
    right = edge_ink(sw - bez - m, sw - bez, 0, sh)
    bottom_rows = max(1, int(sh * HOME_BAR))
    bottom = edge_ink(0, sw, sh - bottom_rows, sh)

    flags = []
    if dominant > 0.985:
        flags.append("BLANK")
    elif ink < 0.004:
        flags.append("LOW-INK")
    return {"file": str(path), "dominant": round(dominant, 4), "ink": round(ink, 4),
            "left": round(left, 4), "right": round(right, 4),
            "bottom": round(bottom, 4), "flags": flags}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shots", nargs="+")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    bad = 0
    for s in a.shots:
        p = pathlib.Path(s)
        if not p.exists():
            continue
        try:
            r = analyse(p)
        except Exception as e:                      # a truncated capture
            r = {"file": s, "flags": ["UNREADABLE"], "error": str(e)}
        if r["flags"]:
            bad += 1
        if a.json:
            print(json.dumps(r))
        elif r["flags"]:
            print(f"{','.join(r['flags']):22} {p.name}  "
                  f"dom={r.get('dominant')} ink={r.get('ink')} "
                  f"L={r.get('left')} R={r.get('right')} B={r.get('bottom')}")
    if not a.json:
        print(f"{len(a.shots)} screens, {bad} flagged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
