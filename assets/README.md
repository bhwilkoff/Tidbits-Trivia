# /assets/ — shared static resources

Single source of truth for static resources consumed by every
platform. Keep the structure consistent so per-platform sync
scripts can copy verbatim.

## Layout

```
assets/
├── data/             JSON catalogs, search indexes, lookup tables
├── images/           Shared bitmaps (PNG / WebP) — branding, splash, hero shots
├── fonts/            Brand fonts (.ttf / .otf) — copied per platform
├── og/               Open Graph + social-preview images
└── README.md         This file
```

## Per-platform sync

| Platform | Sync mechanism | When |
|---|---|---|
| **Web** | Served directly from `/assets/...` via GitHub Pages | Push to `main` |
| **iOS / tvOS (one target)** | Drag the `data/` + `fonts/` folders into the Xcode project; reference via `Bundle.main` | Once at project setup; re-drag when adding new files |
| **Android** | `android/scripts/sync_shared_assets.sh` rsyncs `/assets/` into `android/app/src/main/assets/` | preBuild Gradle task (see android/README.md) |

## The lockstep rule

When you add a file under `/assets/`, ALL platforms see the
same bytes within a single change set. Drift here is a silent bug
class — one platform serves a stale catalog while the others have
the new one, and users get inconsistent data without any error.

Verify before shipping any catalog update:

```sh
# Web (live)
curl -s https://app.example.com/assets/data/catalog.json | md5

# Android (bundled)
unzip -p android/app/build/outputs/apk/debug/app-debug.apk \
  assets/data/catalog.json | md5

# iOS (bundled — after build)
md5 ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug-iphonesimulator/AppName.app/data/catalog.json
```

Matching hashes on every platform = catalog parity. Mismatch = silent ship bug
waiting to bite.

## What does NOT belong here

- **Per-platform image variants** (iOS `@1x/@2x/@3x`, Android `mdpi/hdpi/xhdpi`). Those live in the platform's native asset catalog (`Assets.xcassets`, `res/mipmap-*/`).
- **Generated artifacts** — build the source-of-truth file under `/assets/`, generate variants in CI or a pre-build script.
- **Secrets, API keys, tokens.** Never. Even "public" ones — once a key is bundled, rotating it requires a full release.
- **Large binaries (>5 MB) that change frequently.** They bloat git history and slow every CI clone. Consider a CDN with versioned URLs (R2, Cloudinary, etc.) for those.
