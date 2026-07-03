#!/usr/bin/env python3
"""macOS app icon set for Tidbits.

The iOS icon (icon-1024.png) is full-bleed — iOS masks it into the squircle.
macOS does NOT mask app icons, so a full-bleed square looks non-native in the
Dock. This reshapes the SAME art into the macOS icon grid: an 824x824 rounded
rectangle centered on a transparent 1024 canvas (100px padding each side,
185.4px corner radius — Apple's macOS Big Sur grid), then emits every size the
AppIcon set needs and rewrites Contents.json's `mac` idiom entries.

Run from repo root:  python3 tools/branding/make_macos_icon.py
"""
import os, sys, json
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from make_icon import render          # full-bleed RGBA art at size S
from PIL import Image, ImageDraw

SS = 4                                  # supersample factor for crisp edges
ICONSET = "TidbitsTrivia/Assets.xcassets/AppIcon.appiconset"

# macOS Big Sur icon grid on a 1024 canvas: 824 body, 100 inset, 185.4 radius.
def shaped_1024():
    C = 1024 * SS
    body = int(824 * SS)
    inset = int(100 * SS)
    radius = int(round(185.4 * SS))
    art = render(C).convert("RGBA").resize((body, body), Image.LANCZOS)
    mask = Image.new("L", (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, body - 1, body - 1], radius=radius, fill=255)
    canvas = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    canvas.paste(art, (inset, inset), mask)
    return canvas.resize((1024, 1024), Image.LANCZOS)

base = shaped_1024()

# (px, filename) — one file per AppIcon slot.
outputs = [
    (16,  "mac-16.png"),   (32,   "mac-16@2x.png"),
    (32,  "mac-32.png"),   (64,   "mac-32@2x.png"),
    (128, "mac-128.png"),  (256,  "mac-128@2x.png"),
    (256, "mac-256.png"),  (512,  "mac-256@2x.png"),
    (512, "mac-512.png"),  (1024, "mac-512@2x.png"),
]
for px, name in outputs:
    base.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name))
    print("wrote", name, f"({px}px)")

# Rewrite Contents.json: keep the iOS full-bleed entry, (re)write the mac slots.
mac = [
    ("16x16", "1x", "mac-16.png"),   ("16x16", "2x", "mac-16@2x.png"),
    ("32x32", "1x", "mac-32.png"),   ("32x32", "2x", "mac-32@2x.png"),
    ("128x128", "1x", "mac-128.png"), ("128x128", "2x", "mac-128@2x.png"),
    ("256x256", "1x", "mac-256.png"), ("256x256", "2x", "mac-256@2x.png"),
    ("512x512", "1x", "mac-512.png"), ("512x512", "2x", "mac-512@2x.png"),
]
images = [{
    "filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
}]
for size, scale, fn in mac:
    images.append({"filename": fn, "idiom": "mac", "scale": scale, "size": size})

contents = {"images": images, "info": {"author": "xcode", "version": 1}}
with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)
    f.write("\n")
print("wrote Contents.json (iOS full-bleed + 10 mac slots)")
