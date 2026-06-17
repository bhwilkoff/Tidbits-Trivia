# Quad App Template — Web + iOS/iPadOS + Apple TV + Android with Claude Code

Project template for building **web, iOS/iPadOS, tvOS, and Android
apps in parallel with feature parity** — four native experiences from
one repository. Designed for Claude Code, GitHub Pages, Xcode Cloud,
and Android Studio + GitHub Actions. Skill-aware: the methodology
lives in vendored skills so this template stays lean and travels
complete — clone it and Claude Code knows how to build the way this
template builds, with no `~/.claude/` setup.

The animating principle: **feature parity, not design consistency.**
Web should feel like the web. iOS should feel like iOS. The Apple TV
app should feel like the living room. Android should feel like
Android. The verbs are identical; the idioms aren't.

The second principle: **software with personality, built for people.**
Every methodology skill in this template bakes in a human
orientation — features are tested against whether they deepen
understanding, invite participation, and support human agency before
they're built. The goal of sharing this template is a more connected
ecosystem of personality-filled software, without each builder paying
the up-front cost of setting up AI-assisted development from scratch.

## Track record

This template is the fourth generation of a working lineage — each
predecessor shipped to production and its lessons were folded back in:

- **BOBA Playbook** (iOS App Store + Play internal track + web) —
  origin of the parity matrix, binding design docs, and the
  native-platform-first discipline.
- **Bsky Dreams** (iOS App Store + web) — cross-platform auth,
  deep-link routing lessons.
- **Archive Watch** (tvOS + iOS approved on the App Store, Android
  on Play, web PWA live on a custom domain) — built on the
  TriAppTemplate; contributed everything tvOS, the shared-data-plane
  contract, resilient streaming, per-ecosystem sync, and the store
  submission playbooks now vendored here as skills.

## What's in the template

```
/
├── CLAUDE.md              Project identity + skill-aware standing instructions
├── SCRATCHPAD.md          Active milestone + open questions (lean; archive when full)
├── DECISIONS.md           Decision log — leads with WHY (18 seed decisions)
├── PARITY.md              Cross-platform feature matrix, 4 platforms (single source of truth)
├── DEEP_LINKS.md          The URL contract across all platforms
├── README.md              This file
├── .claude/               Slash commands + session-start hook + vendored skills
├── .github/workflows/     CI for Android (iOS/tvOS use Xcode Cloud; web auto-deploys via Pages)
├── .well-known/           Universal Links + App Links verification files
├── docs/templates/        Seed templates: binding design doc + data-plane contract
│
├── index.html             Web app entry (vanilla HTML/CSS/JS — no build step)
├── css/styles.css         Mobile-first CSS; body flex-column for Safari
├── js/app.js, js/api.js   Web app logic + API abstraction
├── manifest.json          PWA manifest
├── assets/                Shared static assets (consumed by all four platforms)
│
├── apple/                 Swift starter for ONE universal target (iPhone + iPad + Apple TV)
│   ├── README.md          Exact Xcode setup for the universal target
│   ├── App/               Entry point (#if os branches)
│   ├── Core/              Platform-agnostic: models, networking, store
│   ├── iOS/               iPhone/iPad views
│   └── tvOS/              Apple TV views (focus-correct starter)
├── AppVersion.xcconfig    Shared Apple version numbers
├── ci_scripts/            Xcode Cloud build scripts
│
├── android/               Android module (Kotlin + Compose + Material 3 Expressive)
│   ├── gradle/libs.versions.toml         Version catalog (single source of truth)
│   ├── app/                              Composition root
│   ├── scripts/sync_shared_assets.sh     Mirror /assets/ into the AAB
│   └── README.md                         Per-module bootstrap notes
│
└── .gitignore             Build artifacts + secrets across all platforms
```

## Setup — 9 steps

1. **Use as template** on GitHub (or clone + re-init git).
2. **Decide your platform set** and log it as the first project
   decision in DECISIONS.md. All four? tvOS earns its place when the
   content is lean-back (video, music, ambient, photos). A skipped
   platform stays in PARITY.md as a 🚫 column with the reason.
3. **Fill in CLAUDE.md** — project name, what the app does, design
   tokens. Leave the methodology sections; they point at skills.
4. **Fill in SCRATCHPAD.md** — M0/M1 milestones with the
   learning-orientation-design checks.
5. **Create the Xcode project** (one universal target for iPhone +
   iPad + Apple TV — see `apple/README.md` for the full walkthrough):
   - Xcode → File → New → Project → Multiplatform → App
   - Product Name: `AppName` (NO spaces — Xcode Cloud requirement)
   - Save to **repo root** (not a subdirectory)
   - Add tvOS as a supported destination on the same target
   - Move `apple/` Swift files into the Xcode-created group
     (preserving the Core / iOS / tvOS folder split), then delete
     the `apple/` directory
   - Add `AppVersion.xcconfig` to both Debug + Release configs
6. **Bootstrap Android** (in parallel, or whenever you start):
   - Open `android/` in Android Studio
   - Rename `com.example.appname` to your reverse-DNS package
   - Drop secrets into `~/.gradle/gradle.properties`; keystore in
     `~/keystores/` — never in the repo. See `android/README.md`.
7. **Push to GitHub** + enable GitHub Pages (Settings → Pages → main).
   Add a `.nojekyll` file if you serve `/.well-known/` — Jekyll
   silently drops dot-directories.
8. **Set up CI**:
   - Apple — one Xcode Cloud workflow covers iOS + tvOS builds from
     the same target. `.xcodeproj` at root means auto-discovery works.
   - Android — populate the GitHub Secrets listed in
     `.github/workflows/android-build.yml`.
   - Web — GitHub Pages auto-deploys from `main` on every push.
9. **Start building** — Claude Code loads context via the
   session-start hook. Tell it what you want to build; the
   methodology is already in the room.

## How sessions work

- Session-start hook injects CLAUDE.md + current state from
  SCRATCHPAD.md.
- Slash commands: `/status`, `/milestone`, `/decision`, plus the
  bundled KUI commands.
- Vendored skills provide the methodology — see CLAUDE.md
  "How we build" for the trigger table.

## Methodology — skill-aware

This template doesn't repeat methodology in prose; it vendors it as
skills. Invoke them by name when their trigger matches:

**Values + workflow**:
- `learning-orientation-design` — four-question test for new features
- `feature-shipping-discipline` — end-to-end ship sequence
- `binding-design-doc-discipline` — once design docs exist, quote
  the rule before proposing UI work
- `architectural-decision-log` — when adding to `DECISIONS.md`

**Cross-platform method** (the heart of this template — distilled
from shipping the same app on four platforms):
- `cross-platform-parity-discipline` — the PARITY.md workflow:
  same verb / native idiom, same-change-set updates, and the
  periodic parity audit that keeps the matrix honest
- `multiplatform-expansion-method` — how to sequence a multi-platform
  buildout: find the data/UI seam, order platforms by reuse, plan
  the hard ports
- `shared-data-plane-contract` — one published data plane, every
  client a consumer; contract doc, browser CORS/Range realities,
  additive schema evolution, merge-guarded mutations
- `per-ecosystem-sync-islands` — sync each ecosystem on the user's
  OWN cloud (CloudKit / Google Drive App Data); no backend to run
- `resilient-media-streaming` — per-platform patterns for streaming
  from hosts you don't control
- `store-submission-playbook` — App Store + Play Console + tvOS
  submission, end to end, with the gotchas pre-paid

**Cross-platform design principles**:
- `mobile-first-density-design` — density from removing chrome
- `native-platform-first` — exhaust native APIs before custom (the
  single most expensive failure mode across every past project)
- `universal-feature-states` — loading / empty / error / offline

**Platform depth** — each platform gets an umbrella/gotchas skill
distilled from production, plus framework references:
- **iOS**: `ios-production-gotchas` (the cross-cutting lessons from
  three shipped apps — presentation races, dark-mode legibility,
  layout traps, background audio) + 80+ vendored Apple framework
  skills (SwiftUI, SwiftData, networking, Liquid Glass, App Intents,
  WidgetKit, …)
- **tvOS**: `tvos-platform-patterns` — focus engine, ten-foot rules,
  the writable-directory trap, shelf/hero/detail recipes, plus a
  production deep-dive reference (motion values, image pipeline,
  player metadata) to seed a project playbook
- **Android**: `android-production-gotchas` (data-version keying,
  the silent-empty query class, deep-link inbox, the atomic DB swap
  ritual) + the installable Android skill stack — see "Adding the
  Android skill stack" below
- **Web**: `web-platform-patterns` (view system, URL-driven state,
  service-worker discipline, IndexedDB, image fallback chains, CSS
  gotchas, headless verification) + `frontend-design` + `KUI:*`
  design commands
- **Design system depth**: `KUI:<name>` (system, brand, screen,
  review, code, a11y, darkmode, trends, figma)

**App Store / Play Store**: `store-submission-playbook` (process +
gotchas), `app-store-screenshots` (marketing assets),
`app-store-review` (iOS rejection prevention).

## Skills bundled with the template

Skills and slash commands are vendored directly into `.claude/` so
anyone who clones this repo has everything available immediately —
no `~/.claude/` configuration, no marketplace installs, no second
repository to track.

| Source | What | Update path |
|---|---|---|
| `swift-ios-skills` marketplace | 80+ Apple framework skills | refresh from upstream |
| `ui-ux-pro-max-skill` marketplace | `ui-ux-pro-max` design intelligence | refresh from upstream |
| `claude-plugins-official` | `frontend-design` skill | refresh from upstream |
| [ParthJadhav/app-store-screenshots](https://github.com/ParthJadhav/app-store-screenshots) | `app-store-screenshots` | refresh from upstream |
| [BigSiggis/Killer-UI](https://github.com/BigSiggis/Killer-UI) | `killer-ui` skill + `KUI:*` slash commands | refresh from upstream |
| Template maintainer | 21 cross-platform methodology + design + production skills | hand-edited |

**Refreshing marketplace + GitHub-tracked skills**: run
`tools/refresh-skills.sh`. Safe to re-run; reports diffs.

**Adding the Android skill stack** (recommended; not vendored by
default because it would roughly double the .claude size). Use
`tools/install-android-skills.sh`, or install individually:

```sh
# Tier 1 — official
/plugin marketplace add Kotlin/kotlin-agent-skills

# Tier 2 — community
npx skills add chrisbanes/skills
/plugin marketplace add rcosteira79/android-skills
git clone https://github.com/skydoves/android-testing-skills ~/.claude/sources/android-testing-skills
git clone https://github.com/skydoves/compose-performance-skills ~/.claude/sources/compose-performance-skills
npx openskills install drjacky/claude-android-ninja
/plugin marketplace add aldefy/compose-skill

# Re-run refresh to vendor them
./tools/refresh-skills.sh
```

## What this template encodes

**From four platforms' worth of production iteration** (three shipped
app lineages, both app stores):

- **Cross-platform**: parity tracking via a 4-column PARITY.md with
  audit protocol, design-token alignment across CSS / Swift / Kotlin,
  the brand-vs-semantic color split, deep links as a written contract,
  "same verb, native idiom" as the binding rule.
- **Apple universal target**: ONE Xcode target builds iPhone, iPad,
  and Apple TV. Shared `Core/` (models, networking, state, query
  logic) + per-platform view layers behind `#if os` guards. Real
  measurement: ~60–70% of a media app's Swift is platform-agnostic.
  Both platforms share one CloudKit private DB → household sync free.
- **tvOS**: the focus-engine decision tree, ten-foot typography
  (29pt floor), the writable-directory trap (Caches + App Group only
  — simulator won't warn you), hero/shelf/detail recipes, Top Shelf +
  App Intents wiring, layered app icons.
- **Web**: vanilla HTML/CSS/JS, URL-driven state as the web's
  superpower, the canonical-share-URL twin pattern, PWA + service
  worker, Safari compositor pitfalls, MediaSession.
- **Android**: Compose-only, M3 Expressive, edge-to-edge +
  predictive back, Media3 + MediaSession from day one, signing
  hygiene (keystore never in git), manifest deep-link auditing.
- **Production patterns as skills**: shared data plane contract,
  per-ecosystem sync islands (no backend to run), resilient media
  streaming, store submission playbooks with the expensive gotchas
  pre-paid (AASA/assetlinks, Play App Signing fingerprints, layered
  tvOS icons, screenshot automation hooks).

**What the template intentionally doesn't bake in**:

- **Binding design docs** — create per-platform once UI complexity
  warrants (~5 views). Seed from `docs/templates/`.
- **A SwiftData / Room schema** — your app's data model is your own.
- **A pre-baked Compose design system** — `ui/theme/` ships brand-
  token shape, not a component library.
- **Firebase config / keystores / secrets** — per-project, never
  templated, never committed.

## Cross-platform feature parity rule

When shipping any user-facing feature, mirror it on the other
platforms in the same change set where feasible, and update
`PARITY.md`. The rule: **same verb, native idiom**.

| Verb | Web idiom | iOS idiom | tvOS idiom | Android idiom |
|---|---|---|---|---|
| Search | `<input type="search">` + URL params | `Tab(role: .search)` / `.searchable` | `.searchable` (directional keyboard + free Siri dictation) | `SearchBar` family |
| Modal | `<dialog showModal>` | `.sheet` / `.fullScreenCover` | full-screen focus context | `ModalBottomSheet` |
| Drop-down | Popover API | `Menu` | focusable option row | `DropdownMenu` |
| Pull-to-refresh | scroll-snap + custom | `.refreshable` | n/a (auto-refresh on focus return) | `PullToRefreshBox` |
| Cross-view animation | View Transitions API | `.matchedTransitionSource` + `.zoom` | focus-driven crossfade | `SharedTransitionLayout` + `sharedBounds` |
| Filter chips | `<button>` toggling URL params | `FilterToken` / `searchScopes` | focusable chip row | `FilterChip` / `InputChip` |
| Share | Web Share API | ShareLink | QR code on screen | ACTION_SEND |
| Home-screen presence | PWA install | WidgetKit | Top Shelf | Glance widgets + App Shortcuts |
| Voice | n/a | App Intents + Siri | App Intents + Siri | App Actions |

Add a row to PARITY.md for every new user-facing feature.

## Learning orientation

Every feature is evaluated against the four-question test before
implementation. See the `learning-orientation-design` skill:

1. Does it deepen understanding?
2. Does it invite participation?
3. Does it support human agency?
4. Clarity over cleverness?

A "no" to any is a redesign signal at proposal stage, not after
shipping. Applies identically across all four platforms — and it is
the part of this template most worth keeping when you make it yours.
