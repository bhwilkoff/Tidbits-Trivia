# Contributing

This is a quad-platform template — web + iOS/iPadOS + tvOS + Android
in one repo. The contribution rules below keep the platforms in
lockstep.

## The parity rule

Every user-facing change updates **PARITY.md** in the same PR.
- New feature → new row, with `✅` / `🚧` / `⏳` / `🚫` per platform.
- Feature shipped on one platform → either ship the others in the
  same change set OR mark them `⏳` with a target milestone and a
  reason.

Reject PRs that ship a user-facing change without touching PARITY.

## Before opening a PR

| | Web | iOS / tvOS (one target) | Android |
|---|---|---|---|
| Tests pass | `node js/api.test.js` | `⌘U` in Xcode | `./gradlew :app:testDebugUnitTest` |
| Build clean | open in any browser | `xcodebuild build` against BOTH the iOS and tvOS simulator destinations — a shared `Core/` change that breaks the other platform is not done | `./gradlew :app:assembleDebug` |
| Version bumped (if shipping) | n/a — GitHub Pages | `AppVersion.xcconfig` | `app/build.gradle.kts` `versionCode` + `versionName` |
| Docs touched | `WEB-DESIGN.md` if UI/IA changed | `DESIGN.md` / `tvOS-DESIGN.md` if UI/IA changed | `ANDROID-DESIGN.md` if UI/IA changed |
| PARITY.md row | ✅ | ✅ | ✅ |

## Conventions

- **Commit messages quote the user's request verbatim** when
  applicable (see `feature-shipping-discipline` skill).
- **DECISIONS.md leads with WHY, not WHAT** (see
  `architectural-decision-log` skill).
- **No comments unless WHY is non-obvious.** What the code does is
  visible in the code.
- **No emojis in code or commits** unless explicitly requested.
- **Default to skill invocation over re-deriving patterns.** The
  bundled skills in `.claude/skills/` exist because the patterns
  came from real iteration.

## Style

`.editorconfig` enforces indentation across editors. Per-language:

- **JavaScript** — no framework, no build step, no transpile.
  ES2022+ in the browser directly. JSDoc + `// @ts-check`
  comments cover what TypeScript would.
- **Swift** — Apple's API Design Guidelines. 4-space indent.
  Per-platform files end `_iOS.swift` / `_tvOS.swift` and wrap in
  `#if os(...)`; `Core/` files compile for every destination and
  never import per-platform UI.
- **Kotlin** — official Kotlin style (4-space indent). Apply with
  `./gradlew ktlintFormat` once ktlint is added.

## Setting up after clone

```sh
# 1. Web
python3 -m http.server 8080      # http://localhost:8080

# 2. Apple — open Xcode project at root (one target: iPhone/iPad/TV)
open AppName.xcodeproj

# 3. Android — first build downloads SDK + AGP + deps
cd android && ./gradlew :app:assembleDebug
```

If any of those fails on a fresh clone, the template is broken —
that's a P0 fix.

## Reporting issues

When filing an issue, name the platform(s) it affects in the
title (`[ios]`, `[tvos]`, `[web]`, `[android]`, or `[all]`). The
verb/idiom mapping table in README makes it cheap to say "this
is a search bar issue on Find" — use that vocabulary.
