# [APP NAME] — Architecture & Technology Decisions

Entries capture the *why* behind choices — not the *what* (the code
already shows that). Each entry should answer: **"what would the next
developer get wrong if they didn't know this?"** Lead with the rule,
follow with `**Why:**` and `**How to apply:**`. Append-only.

Invoke the `architectural-decision-log` skill when adding a new entry.

---

## 001 — Vanilla HTML/CSS/JS for Web

*Date: YYYY-MM-DD*

No framework, no build step. GitHub Pages serves static files
directly. Framework abstractions cost more than they save at this
scale; adding one would require a build pipeline, a CI step, and a
mental model every future contributor has to carry.

**Why**: reach for complexity only when simplicity has actually
failed, not when it might someday fail. The 2026 web platform
(View Transitions, Container Queries, Popover API, `<dialog>`, CSS
Nesting, `:has()`) is mature enough that the framework value-add
shrinks every year.

**How to apply**: revisit if component count exceeds ~20 OR a
feature genuinely needs reactive state across many components.
Until then, plain DOM + ES2022 + Supabase SDK via CDN.

---

## 002 — Xcode Project at Repository Root

*Date: YYYY-MM-DD*

`.xcodeproj` lives at repo root, no subdirectory, no spaces in
project name.

**Why**: Xcode Cloud requires `.xcodeproj` at the repo root for
auto-discovery. Spaces in paths cause shell-script and CI issues.
Past projects that nested under two levels with spaces lost hours
debugging "Project does not exist at root."

**How to apply**: when creating the Xcode project, save to repo
root. Product name has no spaces. Move scaffolded `apple/` source
files into the Xcode-created group (preserving the Core / iOS /
tvOS split — see Decision 013), then delete the `apple/` directory.

---

## 003 — Shared Apple Version Config via xcconfig

*Date: YYYY-MM-DD*

`AppVersion.xcconfig` at repo root defines `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`. All Apple targets (the universal app +
any extensions) reference it.

**Why**: editing version numbers via Xcode's identity panel creates
per-target overrides in `project.pbxproj` that shadow the xcconfig,
causing targets to drift silently.

**How to apply**: ALWAYS edit `AppVersion.xcconfig` directly. Never
use Xcode UI for version numbers. Bump on every ship as part of the
`feature-shipping-discipline` 7-step sequence.

---

## 004 — SwiftUI + @Observable + SwiftData (Apple) — iOS 26 / tvOS 26 baseline

*Date: YYYY-MM-DD*

SwiftUI for all UI. `@Observable` for state. SwiftData for local
persistence (on tvOS: with the App Group container per Decision
017). UIKit only where SwiftUI lacks a native equivalent.
**`IPHONEOS_DEPLOYMENT_TARGET = 26.0` / `TVOS_DEPLOYMENT_TARGET =
26.0`** as the floor.

**Why**: iOS 26's user base passes 90% by 2026; optimizing for
back-compat costs feature velocity AND prevents using Liquid Glass,
native `Tab(role: .search)`, `scrollEdgeEffectStyle`,
`.matchedTransitionSource`, etc. The DESIGN.md anti-patterns
(custom drawers, custom scroll-edge fades, hand-rolled focus
animations) all came from reaching for custom when native iOS 26
shipped the thing.

**How to apply**: write iOS 26 native APIs directly without
`@available(iOS X, *)` guards. When extending an existing file
with old guards, remove them. When adding new code, never write
iOS 17 / 18 workarounds. For framework-level depth, invoke
`all-ios-skills:<name>` rather than re-deriving.

---

## 005 — Cross-Platform Feature Parity

*Date: YYYY-MM-DD*

Every platform in the project's platform set (web, iOS/iPadOS, tvOS,
Android — decided in M0, see Decision 014) implements the same core
feature set. Platform-specific implementation is acceptable (Keychain
vs Tink-encrypted DataStore vs localStorage); platform-exclusive
features are the exception, not the rule.

**Why**: users expect the same capabilities regardless of platform.
Implementation details can differ to leverage each platform's
strengths. The animating principle is **feature parity, not design
consistency** — web should feel like the web, iOS like iOS, the TV
app like the living room, Android like Android.

**How to apply**: track parity in `PARITY.md` (single source of
truth). When adding to one platform, mirror to the others in
the same change set where feasible, and update PARITY.md row(s).
Reject PRs that ship a feature without updating PARITY.md. Run the
periodic parity audit (`cross-platform-parity-discipline` skill)
before launch waves.

---

## 006 — Kotlin + Jetpack Compose for Android (NOT KMP / CMP / Flutter / RN)

*Date: YYYY-MM-DD*

Native Kotlin + Compose for the Android client. Separate codebase
from iOS Swift/SwiftUI; same monorepo (`/android/`).

**Why**: KMP works best when both platforms start together — most
new projects can't retrofit it without rewriting iOS. CMP can't
render Liquid Glass natively, which kills it for any iOS-26-shaped
design. Flutter / RN add runtime + bridge overhead for every native
API (CameraX, ML Kit, Credential Manager, biometrics) — strictly
worse than native Android for an Android-only client.

**How to apply**: structure the domain layer as pure Kotlin (no
Android imports) inside `:core:domain` so a future KMP `:shared`
module is the upgrade path if/when needed. Don't preemptively
optimize for that path; keep the door open.

---

## 007 — Material 3 + M3 Expressive; brand theme default, dynamic color opt-in

*Date: YYYY-MM-DD*

Android ships a fixed brand theme by default — NOT Material You
dynamic color. User can opt into "Use system colors" in Settings,
which flips to `dynamicDarkColorScheme(context)` on Android 12+
and overrides `primary` only (semantic / element colors never
change).

**Why**: content semantics (status pills, weapon colors,
designation badges) need stable colors; wallpaper-derived `primary`
fighting brand `#FF5C35` reads muddy. Same rule as
iOS: element / semantic on content, brand on chrome.

**How to apply**: in `ui/theme/Color.kt`, keep brand tokens at the
top and semantic tokens in a separate `AppSemantics` object. Theme
overrides only `colorScheme` brand slots — never the semantic
object.

---

## 008 — Android: Compose-only, no XML / AppCompat / ActionBar

*Date: YYYY-MM-DD*

Compose for every screen. `ComponentActivity` (never
`AppCompatActivity`). No XML layouts. No AppCompat. No
`setSupportActionBar()`. M3 SearchBar / ModalBottomSheet /
NavigationSuiteScaffold / SharedTransitionLayout cover the
component catalog.

**Why**: Compose has been Google's recommended UI toolkit since
2021; all new M3 Expressive components ship Compose-first. Mixing
in XML / AppCompat doubles the maintenance surface and forces every
new screen to choose between paradigms. The single-paradigm
discipline keeps reviews tight.

**How to apply**: any time you're about to write a custom
Composable, first check whether M3 / M3 Expressive ships a
component that does 80%. If yes, use it and accept the spec. Same
"native first" failure mode as iOS — reaching for custom when the
platform already shipped the thing.

---

## 009 — Android: edge-to-edge + predictive back are non-negotiable

*Date: YYYY-MM-DD*

`enableEdgeToEdge()` called in every Activity. `Scaffold` /
`safeContentPadding()` / `systemBarsPadding()` for inset handling.
M3 components animate during predictive-back drag without `BackHandler`
intervention — only override `BackHandler` for unsaved-changes
confirmations.

**Why**: Android 16 (`targetSdk >= 36`) ignores
`windowOptOutEdgeToEdgeEnforcement`. Predictive back is the default
in Android 15 and non-opt-out at `targetSdk >= 36`. Fighting either
is fighting the platform.

**How to apply**: never call `WindowCompat.setDecorFitsSystemWindows(window, true)`.
Never lock orientation at >600dp width. Test every screen with
predictive-back drag (3-finger swipe in Android Studio's emulator)
before merging.

---

## 010 — Universal Links / App Links: `/.well-known/` is the contract

*Date: YYYY-MM-DD*

iOS `apple-app-site-association` (no extension) AND Android
`assetlinks.json` BOTH live in `/.well-known/` at the domain root.
Both are JSON. Coexist without conflict.

**Why**: this is the single most-frequently-blown piece of cross-
platform setup. Symptoms (disambiguation chooser on Android; URL
falls back to Safari on iOS) look like the OS is broken; the
actual bug is always the verification file missing, malformed, or
excluded from the static-site build (Jekyll excludes dotdirs by
default).

**How to apply**: see `/.well-known/README.md` for the exact JSON
shapes. Add the file paths to Jekyll's `_config.yml` `include:`
list. For Android, include BOTH the upload-key fingerprint AND the
Play App Signing fingerprint — internal-testing AABs are
upload-signed; production installs are Play-signed.

---

## 011 — Refresh JWT before every Worker / Storage / Edge Function call

*Date: YYYY-MM-DD*

Both iOS and Android wrap their HTTP clients in an interceptor that
calls `refreshIfNeeded()` before forwarding the request. The auth
SDK's auto-refresh only covers its own internal HTTP path; external
endpoints (Cloudflare Workers, Supabase Storage, custom Edge
Functions) bypass it.

**Why**: the silent failure mode is a 401 (or, worse, a 400 with
"exp claim" in the body) on a Worker call that looks like a generic
backend bug. The wasted-debugging cost compounds — every team that
ships this hits it once.

**How to apply**: iOS — `SupabaseClient.refreshIfNeeded()` extension
called at the top of every Worker / Storage method. Android — install
a `SupabaseAuthInterceptor` on the OkHttpClient that's shared
between Coil + Ktor + Supabase. Web — `js/api.js` checks token
expiry before every cross-origin request.

---

## 012 — Brand vs Semantic color split is binding on all platforms

*Date: YYYY-MM-DD*

Two distinct token systems. **Brand** colors (primary / accent /
background / surface) for UI chrome only. **Semantic** colors
(success / warning / error + domain-specific) for content meaning
only. Never use a brand color for content meaning; never use a
semantic color for chrome.

**Why**: tokens drift when one developer uses `--color-primary` to
mean "this is the primary action" and another uses it to mean
"this state is active." Splitting brand from semantic at the token
layer makes drift impossible — the names don't overlap.

**How to apply**: web `:root` separates `--brand-*` from
`--semantic-*`. iOS `Design.swift` has separate `BobaBrand` and
`BobaSemantics` enums. Android `Color.kt` keeps brand tokens at
file scope and semantic tokens inside `object AppSemantics`. Theme
overrides only brand; dynamic color (Material You) opt-in only
affects brand.

---

## 013 — One universal Apple target serves iPhone, iPad, and Apple TV

*Date: YYYY-MM-DD*

iOS, iPadOS, and tvOS ship from a SINGLE Xcode app target. Shared
logic lives in a `Core/` group (models, networking, state, query
layers, playback/queue logic, sync); per-platform UI lives in `iOS/`
and `tvOS/` groups behind `#if os(iOS)` / `#if os(tvOS)` guards.
`Core/` never imports per-platform UI — when Core logic needs app
state, Core defines a protocol and the app store conforms to it.

**Why**: measured in production (Archive Watch): ~60–70% of a media
app's Swift is platform-agnostic. Separate targets (or separate
projects) turn that overlap into copy-drift — the duplicated files
each grow their own bug fixes. The universal target also gives both
platforms the same bundle-adjacent benefits for free: one CloudKit
container (an iPhone and an Apple TV signed into the same iCloud
account sync without extra work), one version number, one Xcode
Cloud workflow. The conversion of a tvOS-only project to universal
was done mid-App-Review without regressing the in-review build —
the `#if os` seam is that clean.

**How to apply**: see `apple/README.md` for the exact setup. New
shared logic goes in `Core/` FIRST; only drop to a platform group
when the code genuinely touches platform UI. A deliberate
per-platform copy (rare) carries a "don't let these drift" comment
and is recorded as unification debt. After touching any `Core/`
file, build BOTH the iOS and tvOS destinations before declaring
done.

---

## 014 — The platform set is a decision, not a default

*Date: YYYY-MM-DD*

In M0, decide which of the four platforms (web, iOS/iPadOS, tvOS,
Android) this app ships on, and record it here with reasons. A
skipped platform stays in PARITY.md as a 🚫 column with the reason —
never silently deleted.

**Why**: tvOS earns its place when the content is lean-back — video,
music, ambient surfaces, photo-driven experiences. It is the wrong
platform for lean-in apps (text entry, productivity, anything
keyboard-shaped: typing on a Siri Remote is hostile). Carrying a
platform that doesn't fit costs every future feature a parity cell;
dropping one silently makes the matrix lie.

**How to apply**: replace this entry's placeholder with the actual
decision ("This app ships on web + iOS + Android; tvOS skipped
because …"). If the set changes later, append a superseding entry.

---

## 015 — Per-ecosystem sync on the user's OWN cloud; no backend to run

*Date: YYYY-MM-DD*

User state (favorites, progress, preferences) syncs per ecosystem,
each through the user's own free cloud: **CloudKit private database**
for Apple devices (iPhone ↔ iPad ↔ Apple TV), **Google Drive App
Data folder** for Android + Web. No cross-ecosystem sync, no
separately-run sync backend. Sign-in is OPTIONAL and gates ONLY
sync — every browse/use verb works signed-out, offline-first, on
every platform.

**Why**: a custom sync backend is a server to provision, pay for,
secure, and operate forever — for data that platform vendors already
host free in the user's own account. CloudKit's private DB and
Drive's App Data folder are exact analogs (hidden, per-app,
user-owned). The privacy story is also strictly better: the
developer never sees the data. Production-verified across
Apple TV ↔ iPhone households.

**How to apply**: see the `per-ecosystem-sync-islands` skill for the
full pattern — including the CloudKit trap that cost a real project
weeks (never `CKQuery` by recordName; use fixed-ID records fetched
directly), tombstones + last-writer-wins merge, and the rule that
sync status must be user-visible (a "Last sync / Sync Now" row),
never silent.

---

## 016 — Shared data plane: published once, every client a consumer

*Date: YYYY-MM-DD*

If multiple clients consume the same content/data (a catalog, feed,
or corpus), it is compiled by ONE pipeline into ONE published
artifact set, and every client is a consumer only. No client
re-implements pipeline logic, re-derives content flags, or re-hosts
the data. The contract (schemas, asset URLs, query verbs, refresh
protocol) lives in `docs/DATA-CONTRACT.md`, authored the moment the
second client exists.

**Why**: per-client data logic is parity drift at the data layer —
four implementations of "what is visible" diverge silently and the
bugs are invisible until a user compares two devices. Baking flags
(visibility, maturity, rights) into the published artifact at build
time means every client filters with a `WHERE` clause and inherits
policy fixes for free.

**How to apply**: see the `shared-data-plane-contract` skill — it
carries the publishing patterns (Releases vs Pages vs git), the
verified browser CORS/Range matrix, ETag-conditional refresh,
additive schema evolution, and the merge-guard rule (a rebuild may
never replace the accumulated artifact; mutations are additive and
reversible).

---

## 017 — tvOS persistence: Caches + App Group only

*Date: YYYY-MM-DD*

On tvOS, the app writes ONLY to `Library/Caches`, `tmp`, and an App
Group container. Anything that must survive (user state, snapshots
shared with a Top Shelf extension) lives in the App Group; anything
re-fetchable lives in Caches. SwiftData/Core Data containers are
built with an explicit App Group `ModelConfiguration`, with a
fallback chain down to in-memory so the app always launches.

**Why**: tvOS apps cannot write to Application Support or Documents
— but the SIMULATOR allows it, so the bug passes every simulator
test and crashes only on real hardware (`NSCocoaErrorDomain 513`,
EPERM). SwiftData's default store location is Application Support,
so the default `.modelContainer(for:)` crashes on a real Apple TV.
Found the hard way on a first device install.

**How to apply**: never `FileManager.url(for:
.applicationSupportDirectory, …, create: true)` on tvOS. Never
`try!` a file/directory creation. Treat Caches as purgeable. The
`tvos-platform-patterns` skill has the full container-fallback
recipe.

---

## 018 — Debug/state env hooks ship in the app, as production no-ops

*Date: YYYY-MM-DD*

The app honors environment-variable hooks — `APP_START_TAB`,
`APP_START_ITEM`, `APP_DIAG=1`, `APP_AUTOPLAY=1` — that drive it to
a known screen/state at launch or enable structured diagnostic
logging. All are no-ops in production builds.

**Why**: two recurring needs share one mechanism. (1) Store
screenshots: `SIMCTL_CHILD_APP_START_ITEM=… simctl launch` opens
exactly the screen to capture, per locale, scriptable. (2) Debugging
behavior you can't attach to (a TV across the room, playback
stalls): env-gated diagnostics turn on without a code change and
cost nothing when off. Re-deriving either ad hoc wastes a session
each time.

**How to apply**: wire hooks in the root view once per platform
(launch-env on iOS/tvOS; `adb shell am start` extras on Android;
query params on web — which already has them for free). Screenshot
IDs/state must come from LIVE data, not stale seeds. Remove one-off
diagnostics after a fix; keep env-gated ones.

---

<!-- Add new entries below this line. Lead with the rule. Number
     sequentially. Don't rewrite existing entries — append a new
     one that supersedes or amends. -->

## 019 — Two question pipelines, ONE template engine; the validation layer is the product

**Decision**: Questions come from two sources — a pre-baked offline corpus
(`tools/corpus/generate_corpus.py` → bundled `corpus.sqlite`) and live
runtime generation (`Core/Engine/TemplateEngine.swift` from the Wikipedia
API) — but both run the **same template shapes and the same quality gates**.
Neither client re-implements the pipeline.

**Why**: For a Wikipedia-sourced app the open API is a firehose of
true-but-misleading facts; the moat is the FILTER, not the fetch (market
research; Wikitrivia's entire bug list is a free QA report). Pre-baking gives
offline play, speed, never-repeat, and insulation from mid-game vandalism;
live gives infinite topics and "create a quiz." If the two pipelines drift,
the corpus and the live path produce different-quality questions and the gate
rules rot.

**How to apply**: when you change a gate or template, change it in BOTH
`TemplateEngine.swift` and `generate_corpus.py` in the same commit, and
regenerate the corpus. The gate rulebook is `docs/QUESTION-QUALITY.md` —
quote the rule number you're touching. The Wikidata SPARQL validation layer
(gates 2/4/5/6/7) is the top corpus priority; until it lands, the engine
enforces the cheap gates (1/3/8 + answer-leak redaction) and a popularity
proxy.

---

## 020 — Online is Game Center for Apple now; Supabase cross-platform later

**Decision**: iOS/tvOS online multiplayer, leaderboards, and achievements
ride **Game Center**. Web/Android online and true cross-platform matchmaking
are deferred to a **Supabase** layer later. Single-player, records, and
sharing need no backend and ship first.

**Why**: Game Center gives free, trusted matchmaking + identity + leaderboards
across the Apple ecosystem with no server to run — the fastest credible path
to "online" on the lead platform. Standing up real-time cross-platform infra
in v1 would blow the budget for a feature most players won't touch on day one;
research shows async > real-time for survivability anyway.

**How to apply**: gate all GameKit behind `GameCenterManager` (every method a
no-op until authenticated, so the SP build runs with no provisioning profile).
Leaderboard IDs live in one enum and must match App Store Connect. When
cross-platform online is scoped, the Supabase schema mirrors the
already-shipped record/score shapes — additive, not a rewrite.

---

## 021 — tvOS earns its place: living-room trivia is lean-back

**Decision**: Tidbits ships on tvOS. The platform set is Web + iOS + iPadOS +
tvOS + Android (amends the M0 set under Decision 014).

**Why**: Decision 014 says tvOS earns its place only when content is
lean-back. Group/party trivia on the big screen is exactly that — and market
research found **tvOS-first living-room trivia with zero-install
phone-as-buzzer is essentially uncontested** (TV-brand incumbents abandoned
local play; Jackbox is comedy-party, not knowledge trivia). It's the single
biggest open gap, so tvOS is a strategic bet, not a checkbox.

**How to apply**: tvOS is a Phase 2 milestone (the universal target already
compiles for it via a placeholder). Read `tvos-platform-patterns` before any
tvOS UI. Create+type-a-topic is 🚫 on tvOS (Siri Remote typing is hostile);
tvOS consumes shared links and hosts living-room games instead.

---

## 022 — No dark patterns: no energy, no cash prizes, no pay-to-restore, no X/Twitter

**Decision**: Tidbits will never ship energy/lives gating, cash-prize
economics, paywalls on previously-free features, pay-to-restore-streak,
manufactured near-misses/FOMO, or compulsion-loop variable rewards. Sharing
never targets X/Twitter. Streaks have forgiveness; the wrong-answer screen
teaches, never shames.

**Why**: Every one of these is a documented 1-star driver and the market's
*universal* complaint (HQ's doomed prizes, Duolingo's 2025 energy revolt,
Sporcle/Trivia Crack paywall backlash). A clean, fair, ad-light reputation is
itself a differentiator — and these mechanics directly violate the
learning-orientation mandate (the tell of a dark pattern: removing it would
help the user). The X/Twitter exclusion is an explicit product requirement.

**How to apply**: every engagement mechanic passes the learning-orientation
four-question test AND the "would removing it help the user?" check before it
ships. Monetization, when it comes, is convenience/cosmetic — never
content-gating.

---

## 023 — Multiplayer build order is async-first; same-room == remote

**Decision**: Build multiplayer in this order: local pass-and-play → Game
Center async head-to-head & groups → tvOS living-room (phone-as-buzzer) →
cross-platform online (Supabase). Same-room and remote use the SAME mechanic.

**Why**: The two real-time-only apps researched (HQ, QuizUp) died;
async/league apps (Trivia Crack, LearnedLeague) survived — real-time is the
most fun and the most economically punishing. Jackbox's lesson is that one
room-code mechanic serving both in-person and remote beats two code paths.

**How to apply**: the per-player loop is already `GameEngine`; multiplayer
wraps an array of engines or drives a shared one over the network — never a
parallel loop. A zero-install short room code (web controller) is the join
target for living-room mode, not a player-side app install.

---

## 024 — The quality moat is Wikidata SPARQL, deriving answers structurally

**Decision**: High-confidence questions come from `tools/corpus/wikidata.py`,
which builds questions from **Wikidata SPARQL** over bounded, recognizable
domains (capitals P36, currency P38, continent P30, UNESCO-site country P17,
element symbol/atomic-number P246/P1086, Best-Picture director P57,
prize-winning book author P50). The answer is derived **structurally** from a
typed triple, and distractors are typed siblings pulled from the SAME query.
These coexist in `corpus.sqlite` with the summary-based questions under
`template_id` `wd:*`.

**Why**: For a Wikipedia-sourced app the moat is the FILTER, not the fetch
(Decision 019). Summary-text questions are good but can be ambiguous; a
structured triple makes the question verifiable by construction —
QUESTION-QUALITY gate 1 (single answer) holds because the property is
functional, and gate 2 (no distractor is also correct) holds **by design**
because a different country's capital is *definitionally* not this country's
capital. Bounded domains (≈200 countries, 118 elements, ≈95 Best-Picture
winners) are inherently famous, so gate 5 (popularity) is satisfied for free.
This is the defensible "accurate Wikipedia trivia" wedge no incumbent owns.

**How to apply**: only use **mostly-functional** properties for this path, so
typed-sibling distractors are guaranteed wrong; for multi-valued properties
(e.g. co-directors) take one value and accept the small recall cost. Render
dates at year precision only (never ask "what day" — gate 4). Respect WDQS
limits: descriptive User-Agent, bounded `LIMIT`, serial queries spaced out,
honor `Retry-After` on 429 (the service rate-limits aggressively). The live
runtime path stays summary-based for now; adopting SPARQL there is a later
step. Regenerate `assets/corpus.json` (web) after any corpus change.
