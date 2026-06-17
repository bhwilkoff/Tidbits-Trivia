# /branding/ — brand identity source files

Master design files (SVG, Sketch, Figma exports) for everything
that becomes an app icon, splash screen, OG image, or App Store /
Play Store asset. Generate variants from these — never edit a
variant by hand.

**One canonical master.** When the icon changes, DELETE the retired
master from this directory entirely — a stale master sitting next to
the current one WILL get picked up by a future asset-generation pass
(this shipped a wrong icon to a store listing twice on one real
project before the rule existed).

## Layout

```
branding/
├── icon-master.svg            ← 1024×1024 SVG master
├── icon-monochrome.svg        ← single-color silhouette (Android themed icon, iOS dark variant)
├── tvos-icon-layers/          ← 2–3 layer sources for the tvOS parallax imagestack
├── wordmark.svg               ← full lockup
├── og-image-master.svg        ← 1200×630 OG image template
├── app-store-screenshots/     ← per-locale screenshot sources
├── feature-graphic.svg        ← Play Store 1024×500
└── README.md                  ← this file
```

## Generating variants

The [`app-store-screenshots`](https://github.com/ParthJadhav/app-store-screenshots)
skill bundled in `.claude/skills/` covers the App Store side; for
icons the canonical paths are:

| Target | Source | Output | Tool |
|---|---|---|---|
| iOS App Icon (1024×1024) | `icon-master.svg` | `AppIcon.appiconset/Icon-1024.png` | `inkscape` / `rsvg-convert` |
| tvOS layered icon (imagestack) | `tvos-icon-layers/*.svg` | "App Icon & Top Shelf Image" brandassets | render per-layer, see below |
| Android adaptive foreground (108dp) | `icon-master.svg` cropped to 72×72 safe zone | `mipmap-anydpi-v26/ic_launcher_foreground.xml` | hand-edit vector |
| Android themed icon (monochrome) | `icon-monochrome.svg` | `drawable/ic_launcher_monochrome.xml` | same |
| Web favicon set | `icon-master.svg` | `/favicon.ico`, `/icon-192.png`, `/icon-512.png` | realfavicongenerator.net or `sharp-cli` |
| OG image (1200×630) | `og-image-master.svg` | `/assets/og/og-default.png` | `sharp-cli` / Figma export |
| Play feature graphic (1024×500) | `feature-graphic.svg` | `play-store/feature-graphic.png` | Figma export |
| Play icon (512×512) | `icon-master.svg` | `play-store/icon-512.png` | `rsvg-convert` |

## The tvOS layered icon (different rules — read before archiving)

tvOS icons are **parallax imagestacks**, not flat PNGs: 2–3 layers
(back field / middle motif / front subject) that the system
translates independently when the icon is focused. Hard-won rules:

- **Layers are LANDSCAPE**: 400×240 (@1x), 800×480 (@2x) for App
  Icon; 1280×768 for the App Store stack. A square-rendered layer
  fails actool's asset-symbol generation — but **only on a clean
  build** (incremental builds mask it). Verify with a from-scratch
  build before any archive.
- The flat look at rest should match `icon-master.svg`; design the
  layers so the stack at rest = the brand icon.
- A separate flat **Top Shelf image** (1920×720 class) is required
  for the App Store product page even if you ship no Top Shelf
  extension.
- Quick-and-dirty rasterizers (`qlmanage`) render square thumbnails
  — center-crop each layer to 5:3 before import.

## Don't commit binary intermediates

The SVG masters live here; the generated PNGs/WebPs live where each
platform consumes them. Don't pre-render a PNG variant into
`/branding/` — that adds churn and someone will edit the PNG
instead of the source.

## The brand mark pattern

If your app's identity is a compact glyph (mark + wordmark
separation), keep them in separate SVG files. App icon = glyph
only; in-app wordmark view = mark + wordmark; OG image = wordmark +
tagline. Three different uses, three different SVGs, all derived
from the same brand system.
