#!/usr/bin/env python3
"""Android TV launch banner + TV launcher icon, from the approved Tidbits mark.

Google rejected versionCode 93 under TV-BN with "Your icon does not fill the
entire icon space". The banner it saw was 320x180 but its ARTWORK filled only
79.7% of the width and 57.8% of the height — 38px of dead cream top and bottom —
so on the Google TV apps row it read as a small logo floating in a flat field
while every neighbouring tile was edge-to-edge art. Same story for the icon: the
adaptive foreground occupies 62% of its canvas, which is correct on a phone
(that is the mask safe zone) and reads as "doesn't fill" on a TV that draws the
icon without the adaptive viewport.

So this generates TV-ONLY assets and leaves the phone icon alone:

  drawable-xhdpi/tv_banner.png            320x180, artwork to all four edges
  mipmap-television-*/ic_launcher.png     512x512, tile at 0.70 of the frame
  branding/play-tv-banner-1280x720.png    the Play listing TV banner

The `television` UI-mode qualifier outranks density and version in resource
resolution, so a TV picks up these bitmaps while every phone keeps the adaptive
icon in mipmap-anydpi-v26.

    python3 tools/branding/make_tv_assets.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

CORAL = (255, 116, 111, 255)
CREAM = (252, 245, 233, 255)
INK = (35, 30, 26, 255)
YELLOW = (255, 201, 60, 255)
BLUE = (45, 91, 255, 255)
GREEN = (47, 203, 138, 255)
GRAPE = (139, 92, 246, 255)
PINK = (255, 93, 162, 255)

FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_TAG = "/System/Library/Fonts/Supplemental/Arial.ttf"
RES = "android/app/src/main/res"
SS = 4  # supersample, then LANCZOS down


def circ(d, cx, cy, r, **k):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], **k)


def T_glyph(S, color, target_h_frac):
    tmp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(tmp)
    f = ImageFont.truetype(FONT, int(0.55 * S))
    td.text((S // 2, S // 2), "T", font=f, fill=color, anchor="mm")
    g = tmp.crop(tmp.getbbox())
    th = int(target_h_frac * S)
    sc = th / g.height
    return g.resize((max(1, int(g.width * sc)), th), Image.LANCZOS)


def tile(size, frac):
    """The cream 'T.' tile on transparent, `frac` of a `size` square."""
    S = size
    k = frac / 0.59  # the phone icon's tile fraction, which set these ratios
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    m = (1 - frac) / 2 * S
    bw = 0.040 * S * k
    so = 0.026 * S * k
    box = [m, m, S - m, S - m]
    tr = 0.255 * (S - 2 * m)
    d.rounded_rectangle([box[0] + so, box[1] + so, box[2] + so, box[3] + so], radius=tr, fill=INK)
    d.rounded_rectangle(box, radius=tr, fill=INK)
    d.rounded_rectangle([m + bw, m + bw, S - m - bw, S - m - bw], radius=tr - bw * 0.55, fill=CREAM)
    g = T_glyph(S, INK, 0.345 * k)
    cx, cy = S / 2, S / 2
    gx, gy = int(cx - g.width / 2), int(cy - g.height / 2 - 0.012 * S)
    im.alpha_composite(g, (gx, gy))
    dr = 0.030 * S * k
    circ(d, cx + 0.125 * S * k, gy + g.height - dr * 0.6, dr, fill=CORAL)
    return im


def confetti(im, spec):
    """Dots placed in FRACTIONS of the frame; several deliberately bleed off an
    edge, which is what turns a flat background into artwork that fills."""
    d = ImageDraw.Draw(im)
    W, H = im.size
    for fx, fy, fr, kind, col in spec:
        cx, cy, r = fx * W, fy * H, fr * H
        if kind == "ring":
            circ(d, cx, cy, r, outline=col, width=max(1, int(0.018 * H)))
        else:
            circ(d, cx, cy, r, fill=col)


BANNER_CONFETTI = [
    (0.028, 0.120, 0.078, "fill", YELLOW),
    (0.086, 0.030, 0.036, "fill", PINK),
    (0.022, 0.885, 0.066, "ring", GRAPE),
    (0.078, 0.968, 0.030, "fill", GREEN),
    (0.585, 0.055, 0.034, "fill", BLUE),
    (0.665, 0.958, 0.042, "fill", GREEN),
    (0.968, 0.120, 0.060, "fill", BLUE),
    (0.918, 0.415, 0.026, "fill", GRAPE),
    (0.978, 0.780, 0.072, "fill", YELLOW),
    (0.880, 0.945, 0.032, "ring", PINK),
]

ICON_CONFETTI = [
    (0.140, 0.150, 0.057, "fill", YELLOW), (0.205, 0.112, 0.028, "fill", PINK),
    (0.858, 0.138, 0.042, "fill", BLUE), (0.915, 0.405, 0.022, "fill", GRAPE),
    (0.138, 0.842, 0.051, "ring", GRAPE), (0.205, 0.882, 0.019, "fill", GREEN),
    (0.862, 0.836, 0.053, "fill", GREEN),
]


def fit(font_path, text, max_w, max_h):
    """Largest size that fits BOTH bounds. The first cut of this banner hard-coded
    a point size and rendered a wordmark reading "TIDE" — the frame ran out before
    the word did, and nothing in the pipeline could have noticed."""
    lo, hi, best = 8, int(max_h * 3), None
    while lo <= hi:
        mid = (lo + hi) // 2
        f = ImageFont.truetype(font_path, mid)
        l, t, r, b = f.getbbox(text)
        if (r - l) <= max_w and (b - t) <= max_h:
            best, lo = f, mid + 1
        else:
            hi = mid - 1
    return best or ImageFont.truetype(font_path, 8)


def banner(w, h):
    """Full-bleed: the app's own coral field with confetti bleeding off every
    edge, the cream tile at the left, the name in ink beside it. Ink on coral is
    6.5:1; cream on coral is 2.3:1, which is not a ten-foot pair."""
    W, H = w * SS, h * SS
    im = Image.new("RGBA", (W, H), CORAL)
    confetti(im, BANNER_CONFETTI)
    d = ImageDraw.Draw(im)

    pad = 0.075 * H
    t = int(H - 2 * pad)
    im.alpha_composite(tile(t, 0.94), (int(pad * 1.2), int(pad)))

    x = pad * 1.2 + t + 0.045 * W
    avail = W - x - 0.045 * W
    d.text((x, H * 0.425), "TIDBITS", font=fit(FONT, "TIDBITS", avail, 0.32 * H),
           fill=INK, anchor="lm")
    d.text((x + 0.004 * W, H * 0.715), "Trivia", font=fit(FONT_TAG, "Trivia", avail, 0.135 * H),
           fill=INK, anchor="lm")
    return im.resize((w, h), Image.LANCZOS).convert("RGB")


def tv_icon(size):
    """Full-bleed coral + a tile at 0.70 of the frame. 0.70 with the mark's own
    corner radius keeps the corners inside a circular mask while filling far more
    of the square than the phone icon's 0.59 safe-zone tile."""
    S = size * SS
    im = Image.new("RGBA", (S, S), CORAL)
    confetti(im, ICON_CONFETTI)
    im.alpha_composite(tile(S, 0.70))
    return im.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    out = f"{RES}/drawable-xhdpi"
    os.makedirs(out, exist_ok=True)
    banner(320, 180).save(f"{out}/tv_banner.png")
    print("wrote", f"{out}/tv_banner.png")

    # xhdpi is what Google names for 1080p TVs; xxhdpi covers 4k panels that
    # report a higher density rather than scaling the xhdpi bitmap up.
    for bucket in ("xhdpi", "xxhdpi"):
        d = f"{RES}/mipmap-television-{bucket}"
        os.makedirs(d, exist_ok=True)
        ic = tv_icon(512)
        ic.save(f"{d}/ic_launcher.png")
        ic.save(f"{d}/ic_launcher_round.png")
        print("wrote", d)

    os.makedirs("branding", exist_ok=True)
    banner(1280, 720).save("branding/play-tv-banner-1280x720.png")
    print("wrote branding/play-tv-banner-1280x720.png")
