#!/usr/bin/env python3
"""Generate the white 'T.' launch mark (transparent) for the coral splash.
Supersampled 4x then downsampled (LANCZOS) for smooth anti-aliased edges."""
from PIL import Image, ImageDraw

def draw_T(S):
    """Draw a clean, CONNECTED white 'T.' on a transparent SxS canvas."""
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    W = (255, 255, 255, 255)
    cx = S / 2
    bar_w, bar_h = 0.66 * S, 0.155 * S
    stem_w = 0.175 * S
    top = 0.215 * S
    bottom = 0.74 * S
    r_bar = bar_h / 2
    r_stem = stem_w / 2
    # Top bar (rounded ends)
    d.rounded_rectangle([cx - bar_w/2, top, cx + bar_w/2, top + bar_h], radius=r_bar, fill=W)
    # Vertical stem — starts INSIDE the bar (overlap) so the T is fully connected
    d.rounded_rectangle([cx - stem_w/2, top + bar_h*0.15, cx + stem_w/2, bottom], radius=r_stem, fill=W)
    # The '.' — a small dot to the lower-right (the Tidbits wordmark period)
    dot_r = 0.052 * S
    dcx, dcy = cx + stem_w/2 + dot_r*2.0, bottom - dot_r
    d.ellipse([dcx - dot_r, dcy - dot_r, dcx + dot_r, dcy + dot_r], fill=W)
    return im

SS = 4
for px in (180, 360, 540):
    big = draw_T(px * SS)
    small = big.resize((px, px), Image.LANCZOS)
    small.save(f"TidbitsTrivia/Assets.xcassets/LaunchLogo.imageset/logo-{px}.png")
    print(f"wrote logo-{px}.png")
