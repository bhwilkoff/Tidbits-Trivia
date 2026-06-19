#!/usr/bin/env python3
"""White 'T.' launch mark (transparent) for the coral splash — Arial Black,
matching the app icon's T. Supersampled then LANCZOS-downsampled."""
from PIL import Image, ImageDraw, ImageFont
FONT="/System/Library/Fonts/Supplemental/Arial Black.ttf"

def make(px):
    S = px * 4
    im = Image.new("RGBA", (S, S), (0,0,0,0))
    d = ImageDraw.Draw(im)
    # white 'T' (Arial Black), cropped tight, scaled to ~0.52 of canvas height
    tmp = Image.new("RGBA", (S, S), (0,0,0,0)); td = ImageDraw.Draw(tmp)
    f = ImageFont.truetype(FONT, int(0.6*S))
    td.text((S//2, S//2), "T", font=f, fill=(255,255,255,255), anchor="mm")
    g = tmp.crop(tmp.getbbox())
    th = int(0.52*S); sc = th/g.height
    g = g.resize((int(g.width*sc), th), Image.LANCZOS)
    gx, gy = S//2 - g.width//2, S//2 - g.height//2
    im.alpha_composite(g, (gx, gy))
    # white period dot, gapped to the right of the stem near the baseline
    dr = int(0.052*S)
    d.ellipse([S//2+int(0.20*S)-dr, gy+g.height-dr-int(0.02*S),
               S//2+int(0.20*S)+dr, gy+g.height+dr-int(0.02*S)], fill=(255,255,255,255))
    return im.resize((px, px), Image.LANCZOS)

for px in (180, 360, 540):
    make(px).save(f"TidbitsTrivia/Assets.xcassets/LaunchLogo.imageset/logo-{px}.png")
    print("wrote logo", px)
