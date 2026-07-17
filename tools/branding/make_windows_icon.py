#!/usr/bin/env python3
"""MSIX / Store logo assets for the Windows app, from the approved Tidbits mark
(assets/icon.png) — the same source every other platform's icon rides.

MSIX wants a specific named set (Square44x44Logo, Square150x150Logo, Wide310x150,
StoreLogo, SplashScreen). The square tiles are full-bleed, matching the iOS/Android
treatment of the same mark — the source is an opaque coral square, so there is no
alpha to pad with. Only the WIDE tile and splash center the mark on transparency,
because stretching a square mark to 310x150 would distort it.

Also emits the .ico used by the unpackaged .exe (the sideload/dev path).

Usage:  python3 tools/branding/make_windows_icon.py
Output: windows/Tidbits.App/Assets/Windows/*.png  +  Assets/tidbits.ico
"""
import os
from PIL import Image

SRC = "assets/icon.png"
OUT = "windows/Tidbits.App/Assets/Windows"
ICO = "windows/Tidbits.App/Assets/tidbits.ico"

# The MSIX asset set. `scale` targets are what the Store/manifest reference; the
# manifest points at the unscaled name and Windows picks the scale variant.
SQUARE = {
    "Square44x44Logo": 44,
    "Square71x71Logo": 71,
    "Square150x150Logo": 150,
    "Square310x310Logo": 310,
    "StoreLogo": 50,
}
SCALES = [100, 125, 150, 200, 400]


def load():
    im = Image.open(SRC).convert("RGBA")
    if im.size != (1024, 1024):
        raise SystemExit(f"{SRC} is {im.size}; expected 1024x1024")
    return im


def square(im, size):
    return im.resize((size, size), Image.LANCZOS)


def wide(im, w, h):
    """Wide tile = the mark centered on transparent, NOT a stretched square."""
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mark = im.resize((h, h), Image.LANCZOS)
    canvas.paste(mark, ((w - h) // 2, 0), mark)
    return canvas


def splash(im, w, h):
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    side = int(h * 0.6)
    mark = im.resize((side, side), Image.LANCZOS)
    canvas.paste(mark, ((w - side) // 2, (h - side) // 2), mark)
    return canvas


def main():
    im = load()
    os.makedirs(OUT, exist_ok=True)

    for name, base in SQUARE.items():
        for s in SCALES:
            px = max(1, round(base * s / 100))
            square(im, px).save(f"{OUT}/{name}.scale-{s}.png")
        # The unscaled name the manifest references.
        square(im, base).save(f"{OUT}/{name}.png")

    # Target-size assets: the taskbar/Start list icons Windows picks from.
    for px in (16, 24, 32, 48, 256):
        square(im, px).save(f"{OUT}/Square44x44Logo.targetsize-{px}.png")
        # Unplated variants render directly on the taskbar with no plate behind them.
        square(im, px).save(f"{OUT}/Square44x44Logo.targetsize-{px}_altform-unplated.png")

    for s in SCALES:
        wide(im, round(310 * s / 100), round(150 * s / 100)).save(f"{OUT}/Wide310x150Logo.scale-{s}.png")
        splash(im, round(620 * s / 100), round(300 * s / 100)).save(f"{OUT}/SplashScreen.scale-{s}.png")
    wide(im, 310, 150).save(f"{OUT}/Wide310x150Logo.png")
    splash(im, 620, 300).save(f"{OUT}/SplashScreen.png")

    # The .ico for the unpackaged .exe.
    os.makedirs(os.path.dirname(ICO), exist_ok=True)
    im.save(ICO, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    n = len(os.listdir(OUT))
    print(f"wrote {n} MSIX assets to {OUT} and {ICO}")


if __name__ == "__main__":
    main()
