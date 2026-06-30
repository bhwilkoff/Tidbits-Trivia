#!/usr/bin/env python3
"""Tidbits Google Play feature graphic (1024x500). Neo-brutalist brand: cream paper, thick ink
borders, hard offset shadows, color pops. Rendered at 2x then downscaled for clean edges."""
import math, sys
from PIL import Image, ImageDraw, ImageFont

S = 2
W, H = 1024 * S, 500 * S

CREAM   = (251, 243, 228)
CREAM_D = (243, 231, 206)
INK     = (26, 23, 20)
INKSOFT = (107, 97, 87)
CORAL   = (255, 92, 92)
BLUE    = (45, 91, 255)
YELLOW  = (255, 201, 60)
MINT    = (47, 203, 138)
GRAPE   = (139, 92, 246)
WHITE   = (255, 255, 255)

ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"
def font(size, weight="Black"):
    f = ImageFont.truetype(ROUNDED, size * S)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f

img = Image.new("RGB", (W, H), CREAM)
d = ImageDraw.Draw(img, "RGBA")

# --- subtle scattered sparkle dots in the cream ---
import itertools
spots = [(70,60),(150,420),(470,80),(360,300),(540,440),(620,150),(930,70),(990,300),(880,440),(760,60)]
for (x,y) in spots:
    x*=S; y*=S; r=5*S
    d.ellipse([x-r,y-r,x+r,y+r], fill=(26,23,20,28))

def rrect(draw, box, r, fill=None, outline=None, width=0):
    draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)

def card_tile(w, h, r, fill, border=6, shadow=11, glyph=None, gfont=None, gcolor=INK):
    """RGBA tile: hard offset shadow + bordered rounded card + optional centered glyph."""
    w*=S; h*=S; r*=S; border*=S; shadow*=S
    pad = shadow + border + 8*S
    tw, th = w + pad*2, h + pad*2
    t = Image.new("RGBA", (tw, th), (0,0,0,0))
    td = ImageDraw.Draw(t)
    rrect(td, [pad+shadow, pad+shadow, pad+shadow+w, pad+shadow+h], r, fill=INK)      # shadow
    rrect(td, [pad, pad, pad+w, pad+h], r, fill=fill, outline=INK, width=border)      # card
    if glyph:
        bb = td.textbbox((0,0), glyph, font=gfont)
        gw, gh = bb[2]-bb[0], bb[3]-bb[1]
        td.text((pad + (w-gw)/2 - bb[0], pad + (h-gh)/2 - bb[1]), glyph, font=gfont, fill=gcolor)
    return t

def paste_rot(base, tile, center, angle):
    r = tile.rotate(angle, expand=True, resample=Image.BICUBIC)
    base.alpha_composite(r, (int(center[0]*S - r.width/2), int(center[1]*S - r.height/2)))

def circle_badge(base, center, radius, fill, border=6, shadow=9, glyph_poly=None):
    cx, cy, rad = center[0]*S, center[1]*S, radius*S
    b, sh = border*S, shadow*S
    bd = ImageDraw.Draw(base, "RGBA")
    bd.ellipse([cx-rad+sh, cy-rad+sh, cx+rad+sh, cy+rad+sh], fill=INK+(255,))          # shadow
    bd.ellipse([cx-rad, cy-rad, cx+rad, cy+rad], fill=fill+(255,), outline=INK, width=b)
    if glyph_poly:
        bd.polygon([(cx+px*rad, cy+py*rad) for (px,py) in glyph_poly], fill=WHITE+(255,))

def star(n=5, inner=0.42, rot=-90):
    pts=[]
    for i in range(n*2):
        ang=math.radians(rot + i*180/n)
        rr = 0.74 if i%2==0 else 0.74*inner
        pts.append((math.cos(ang)*rr, math.sin(ang)*rr))
    return pts

def sparkle():  # 4-point concave sparkle
    a=0.72; c=0.14
    return [(0,-a),(c,-c),(a,0),(c,c),(0,a),(-c,c),(-a,0),(-c,-c)]

base = img.convert("RGBA")

# --- right-side motif cluster ---
qfont = font(150, "Heavy")
yellow_card = card_tile(210, 210, 40, YELLOW, glyph="?", gfont=qfont, gcolor=INK)
paste_rot(base, yellow_card, (820, 248), -8)
circle_badge(base, (946, 130), 60, MINT, glyph_poly=star())
circle_badge(base, (700, 372), 54, BLUE, glyph_poly=sparkle())
circle_badge(base, (922, 392), 28, CORAL)

img = base.convert("RGB")
d = ImageDraw.Draw(img, "RGBA")

# --- wordmark + tagline (left) ---
wm = font(150, "Black")
d.text((64*S, 150*S), "TIDBITS", font=wm, fill=INK, anchor="lm")
# coral accent rule under the wordmark
rrect(d, [66*S, 232*S, 360*S, 248*S], 8*S, fill=CORAL)
tag = font(33, "Semibold")
d.text((66*S, 300*S), "Trivia from the whole of Wikipedia.", font=tag, fill=INKSOFT, anchor="lm")
sub = font(26, "Bold")
d.text((66*S, 350*S), "11,000+ real questions.", font=sub, fill=INK, anchor="lm")


out = sys.argv[1] if len(sys.argv) > 1 else "feature.png"
img.resize((1024, 500), Image.LANCZOS).save(out)
print("wrote", out)
