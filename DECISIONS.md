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
ships.

**Amended 2026-07-19 (reconciled with Decision 047).** The original final clause
read *"Monetization, when it comes, is convenience/cosmetic — never
content-gating."* That was written before a paid tier existed and it is **too
narrow** — Decision 047 makes Tidbits Club the *learning* tier, which includes
new content and new gameplay, not just cosmetics. The rule 022 was actually
reaching for is not "never gate content" but **"never take value away from a
free user"** — which is the dark-pattern tell, and which R-MON-1 already states
precisely. The reconciled boundary:

- **A dark pattern removes or withholds something the free user relies on** to
  pressure a purchase (energy to keep playing, a streak-restore, a
  previously-free feature). **Still banned, absolutely.**
- **A fair paid tier adds NEW value a free user never had** and never needed to
  play well. **Allowed** — this is what Club is.

The operative test is unchanged and still decides every case: *would removing
this feature help the free user?* Energy gating: yes, removing it helps them →
banned. The Knowledge Atlas or Ranked Seasons: no, a free player is unaffected
by its absence → fair. This is the same line as R-MON-1 (free tier never
reduced after go-live) and R-MON-4 (never gate a seat, gate the view from the
seat). See `docs/MONETIZATION.md`.

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

---

## 025 — Question-TYPE diversity lives in the corpus; every type is a 4-option MCQ

**Decision**: New question TYPES (superlative, chronology/"which came first",
reverse-attribute, numeric "closest-to", classification, plus the five summary
shapes) are all expressed as **4-option multiple-choice** and generated into
the shared `corpus.sqlite` / `corpus.json`. The Wikidata generator is
**dataset-driven**: a few bounded SPARQL queries each pull a rich dataset
(countries, elements, films, books, people), cached to `tools/corpus/cache/`,
and MANY question types are generated from each dataset.

**Why**: Keeping every type to the same 4-option shape means **all four client
platforms render new types with zero code changes** — they just read the
corpus (a `Question` is a prompt + 4 options + correctIndex). That's how we got
~17 types onto iOS/tvOS/Web/Android at once. The dataset+cache architecture
minimizes WDQS calls (the endpoint rate-limits hard, ~1000s `Retry-After`) and
makes regeneration instant + resumable: re-deriving questions from cached
datasets needs no network, so fixing a generation bug (e.g. the qid-collision
that deduped superlative questions to 3) is a one-second re-run.

**How to apply**: add a new type as a generator over an existing cached dataset
where possible (no new query). qids must key on the full **option set**, not
just the prompt — fixed-stem types (superlative/chronology) otherwise collide
under `INSERT OR IGNORE`. Run cache-only by default; use `--fetch` to pull
un-cached datasets when WDQS is cool. The generator deletes only the `wd:*`
types it actually produces, so a skipped dataset's questions survive. Non-MCQ
formats (timeline drag, grouping wall, type-the-answer) would need per-client
UI and are out of scope until a type earns it.

---

## 026 — Distractors are same-TYPE siblings, never word-overlap; oneliner dropped

**Decision**: Multiple-choice distractors are drawn ONLY from subjects sharing
the answer's `type_key` (a coarse type derived from the Wikipedia short
description's head noun — actor↔actor, genre↔genre, settlement↔settlement). If a
subject can't be typed, or has fewer than 3 same-type siblings, the question is
**dropped** — never widened to a different type. The `oneliner` shape ("which
one is '<description>'?") is removed entirely.

**Why**: Distractors previously ranked by description WORD-OVERLAP, which
conflates types — "Cardiff Capital Region" (city region) drew a tidal strait, a
Djibouti city, and a Welsh park; the one on-type option gave the answer away. A
wrong-type distractor is the single biggest "the answer is obvious" tell.
Type-bucketing makes all four options plausibly the same kind of thing. Oneliner
was 46% answer-in-clue (the description IS the clue and routinely contains the
answer's words, e.g. subject "Comedy horror" / desc "genre combining horror and
comedy") and is unfixable since redaction can't run on the description.

**How to apply**: `type_key` + `typed_distractors` live in
`tools/corpus/generate_corpus.py` and are mirrored in all three live engines
(`TemplateEngine.swift`, `js/engine.js`, `Tidbits.kt`) — same leading-adjective
strip, same synonym fold, same drop-on-<3 rule. When adding a question shape,
its distractors MUST go through `typed_distractors`. Prefer dropping a question
over shipping a cross-type distractor. The Wikidata path (`wikidata.py`) is
already typed-by-construction and is the model this extends.

---

## 027 — Deep article fact-extraction is a third corpus path (proprietary, stdlib)

**Decision**: A new build-time path, `tools/corpus/wiki_extract.py`, parses the
**full Wikipedia article** (infobox + lead + early body) into verifiable fact
triples and turns the single-valued ones into 4-option MCQs
(`fact:birth_year`, `fact:death_year`, `fact:directed_by`, `fact:written_by`,
`fact:composed_by`, `fact:painted_by`, `fact:nationality`). It runs from
`generate_corpus.py --facts-per-category N` (default 0 = off), is stdlib-only,
and caches every article to `cache/articles/`. The method is captured in the
vendored skill `wikipedia-fact-extraction` (the API surface, the precision-first
pipeline, the reject funnel, the distractor recipe — synthesized from
Heilman & Smith 2010, Seyler 2015/2017, Du & Cardie 2018, Susanti 2018, and the
WikiTrivia / linkeddata-trivia recipes).

**Why**: The summary path only ever saw the short description + first sentence —
the entire factual surface was one definitional sentence, so every summary
question was a variant of "name the thing from its definition." The article body
holds the actual quizzable facts (who directed it, when they were born, what
nationality). Extracting them is a **build-time** change: clients consume
`corpus.sqlite` unchanged (the shared-data-plane contract), so all four
platforms get richer questions with zero client work. Precision is the whole
game — a wrong "fact" teaches something false — so the pipeline is precision-first:
the infobox is the verification oracle (a prose `born 1867` that matches the
infobox scores 0.9+; a mismatch drops the fact), every stage has a drop-exit, and
**multi-valued / coordinated attributions are dropped** ("Who wrote X?" with two
authors is ambiguous — the bug that made three contradictory "Who created
Goodfellas?" questions until the gate was added).

**How to apply**: read the `wikipedia-fact-extraction` skill before changing the
extractor. Only single-valued relations become forward MCQs (gate 6). Distractors
are category-pooled type-matched siblings (`_type_bucket` keeps a director from
distracting a painter) — wrong by construction, same rule as Decision 026.
Verify by running `python3 wiki_extract.py --mcq "Title" …` and reading the
printout BEFORE regenerating (observe, don't iterate blind). The full corpus
regen (`generate_corpus.py --facts-per-category 150`) crawls one full article per
subject — heavy on first run, instant after (cached); bump the corpus version and
re-sync the Android asset after. Live engines (`TemplateEngine.swift` etc.) stay
summary-based — mirror only the *gates*, not the heavy extraction.

---

## 028 — Canonical domain is tidbitstrivia.com (apex, GitHub Pages)

**Decision**: The product's canonical home is **`https://tidbitstrivia.com`** —
an apex custom domain served by GitHub Pages via the repo-root `CNAME`. All
public URLs (web app, share links, social previews, deep-link HTTPS twins,
`/.well-known/` verification) reference this domain. The custom scheme is
`tidbits://`. Web share text already builds from `location.origin`, so it
inherits the domain automatically.

**Why**: A custom apex domain is a hard requirement, not branding polish —
**iOS Universal Links / AASA do not verify from a project-pages subpath**
(`user.github.io/repo/.well-known/…`), so app↔web deep links are impossible
without it (see `DEEP_LINKS.md`). It's also the stable share/landing target for
every native platform and the anchor for app promotion as the native apps ship.
A stable origin matters for the PWA identity (`manifest.id`) and for
social-preview caches (OG/Twitter), which key on the URL.

**How to apply**: keep the `CNAME` file at repo root (one line, the apex — do
not delete; GitHub Pages drops the custom domain if it vanishes). New public
URLs use `https://tidbitstrivia.com`; never hardcode `*.github.io`. Social meta
in `index.html` (`og:url`/`og:image`/canonical) and `sitemap.xml`/`robots.txt`
all point at the domain. The AASA + `assetlinks.json` files are added to
`/.well-known/` at first store submission (they need the real TEAMID / bundle /
Play signing fingerprint — see `.well-known/README.md`). Native-app store links
live in `APP_STORES` (`js/store.js`): null renders "Coming soon" on the home
screen, a URL flips it live per platform at release.

---

## 029 — Summary questions are "describe & identify", fame-gated and content-gated

**Decision**: The free-text/summary path produces exactly two shapes — **describe**
("This Australian actor who won a posthumous Oscar for the Joker in The Dark Knight
— who is this?") and **cloze** — and nothing else. The old `identify` / `jeopardy`
/ `categorize` shapes are deleted. Two hard gates apply in all four engines
(`generate_corpus.py` + the three live mirrors):
1. **Fame floor** — the intro extract must be ≥ 600 chars (a free notability
   proxy; obscure stubs are short).
2. **Richness** — after stripping parenthetical dates, the clue must carry ≥ 2
   distinguishing tokens (proper nouns / years). A bare "American actor" or a
   "(born 1963)" birthdate scores 0 and is dropped.
The `describe` shape anchors on the **leading proper-noun run** (the full birth
name, which differs from the title — "Thomas Jeffrey Hanks" vs "Tom Hanks"),
reframes it to "This {type} {distinguishing clause}", and asks **who** (people)
or **what** (things) — never "what is it?" of a person. `difficulty` rescaled to
the new floor (≥2000 easy / ≥1000 medium).

**Why**: Real users called the old output out — "————— was an American actor.
What is it?" with four obscure names, and "What kind of thing is 62nd Academy
Awards?". Those fail as trivia three ways: the subject is unknown, the clue
carries no distinguishing fact, and the framing ("what kind of thing", "what is
it?", "which subject is this?") is something **no human asks**. The goal is a
question a host would read on bar trivia night: lead with the interesting facts,
ask a natural question, and only about a recognizable subject. Fewer, better
beats many, weak — the fame + richness gates intentionally shrink the summary
count; the fact (Decision 027) and Wikidata (024) paths carry verifiable depth.

**How to apply**: the gates + shapes live in `tools/corpus/generate_corpus.py`
and are mirrored verbatim in `js/engine.js`, `TemplateEngine.swift`, and
`Tidbits.kt` (the live "Create a quiz" path) — change all four together. The
`reframe` anchor must stay on the leading name run, not the title (the full-
birth-name mismatch silently drops every famous subject otherwise). Drop a
question rather than ship a thin clue. Verify shape output before regenerating.

---

## 030 — Phone-as-buzzer transport is phased: Apple-native local (Bonjour/PSK) → web-room

**Decision**: The living-room phone-as-buzzer ships in two phases (extends 023).
**Phase 1 (foundation landed)** is **Apple-native local**: the Apple TV host
publishes a Bonjour service (`_tidbits-buzz._tcp`) over `Network.framework`
(`NWListener`), iPhones discover it with `NWBrowser`/`NWConnection`, and the
link is secured by a **TLS pre-shared key derived from the room code** shown on
the TV (`SHA256("tidbits-buzz-v1:" + CODE)`). The host owns the **single
authoritative `BuzzArbiter`** — it stamps each buzz on its own clock and
subtracts a per-seat one-way-delay estimate (½ measured RTT) so the truly-first
finger wins regardless of link speed. **Phase 2 (later)** adds the universal
**web-room** (Cloudflare Durable Object, `tidbits.tv/<code>`) so any phone
browser joins, same-room *or* remote; the host picks the transport by
connectivity. Skipped: MultipeerConnectivity (deprecated, 8-cap), `GKMatch`
(relayed + sign-in), `GCVirtualController` (touch, not transport).

**Why**: Heed doctrine 023 — async/offline survives, real-time is fragile — so
the buzzer is **additive, never load-bearing**: solo/pass-and-play stay fully
offline and must never regress. Phase 1 buys real "phones as buzzers" for the
common case (everyone Apple, same room) at **zero backend cost, full offline,
lowest latency, no third-party packages** — exactly Tidbits' identity. The
**room code → PSK** is the whole security model: a phone that can read the TV's
code computes the same key and pairs; one that can't, can't. **Never compare
client timestamps** (unsynchronized, spoofable) — one clock, host-stamped, RTT-
compensated, targeting sub-100 ms (below "we tapped together" perception). tvOS
has **no web view**, so the host is always native; only phones are browsers
(which is why Phase 2's universal cell is the phones, not the TV).

**How to apply**: the wire protocol, room-code/PSK, and the pure `BuzzArbiter`
live in `Core/Networking/BuzzerProtocol.swift` (no `Network` import → compiles
for every os() target AND is offline-unit-testable — the arbiter fairness is
proven by a standalone harness, not a live run). Transport is
`BuzzerTransport.swift` (shared PSK params + length-prefixed JSON framing) +
`BuzzerHost.swift` (`#if os(tvOS)`) + `BuzzerClient.swift` (`#if os(iOS)`).
`Info.plist` declares `NSLocalNetworkUsageDescription` + `NSBonjourServices`.
**Build-verified is not two-device-verified**: Bonjour discovery, the iOS
local-network prompt, and the PSK handshake only truly exercise on real
hardware — wiring this into a "Buzz Night" game mode and the two-device pairing
test is the next slice, and nothing is wired into a user-facing flow until that
passes. On tvOS use `receive(minimumIncompleteLength:maximumLength:)` (raw
receive can fire only on close there). Android's analog is Nearby Connections
(separate native path); the web/Android universal path is Phase 2's web-room.

---

## 031 — Non-MCQ question types earn custom data; they read a separate bundled set

**Decision**: A question type may break the 4-option-MCQ shape (Decision 025)
only when it **earns custom data**, and when it does it ships as a **separate
bundled JSON set** the client loads for that mode — never bloating or reshaping
the main corpus. Closest Call (M5) is the first: numeric estimation. Its
questions carry a `ClosestSpec { answer, min, max, step, tolerance, unit }`
instead of options, generated by `tools/corpus/gen_closest.py` from the E1
numeric enrichment into `assets/closest.json` (+ iOS Resources + Android assets
copies). Picture ID (`picture.json`) and This-or-That (`thisorthat.json`) are
the MCQ-shaped precedents for the same "separate bundled set per enrichment
mode" pattern.

**Why**: 025 kept every type a 4-option MCQ so one render path + one quality
gate served all. Estimation genuinely can't be MCQ without becoming
multiple-choice-of-numbers (which kills the *estimation* skill — the whole
point). So it earns custom data — but it must not destabilize the shared corpus
contract (024/016): the main `corpus.sqlite`/`corpus.json` stay MCQ-only, and
the new mode reads its own additive file. One generic loader per platform
(`JSONQuestionSource` on Apple, `makeJsonSet` on web, `JsonQuestionSet` on
Android) detects MCQ vs numeric rows by shape (index 2 is an options array vs a
number), so each new bundled mode is a one-liner.

**How to apply**: a new non-MCQ type adds (1) a generator → its own
`assets/<mode>.json` (+ bundled copies for iOS/Android), (2) optional fields on
`Question` (e.g. `imageURL`, `closest`) — additive, defaulted nil, Codable-safe,
(3) a mode case routed in `QuestionProvider` to the right `JSONQuestionSource`,
(4) a render branch keyed on the new field. tvOS has **no `Slider`** (no touch) —
numeric input there is focusable ±coarse/±fine stepper buttons, not a slider.
Scoring for adds-only modes stays non-negative (Decision 022). Keep the answer-
display safe when `options` is empty (`correctAnswer` falls back to the numeric
answer) so the missed-fact recap never indexes an empty array.

---

## 032 — Corpus source: build-time dumps + curated derivatives, not the live API

**Decision**: The question pipeline migrates its **raw material** from live,
rate-limited Wikipedia/Wikidata APIs over a seed-search slice to **build-time
source artifacts** — dumps and curated derivatives — assembled into a local,
unshipped `corpus_source.sqlite` fact store that the existing generators read.
The approach is **layered and derivative-first**, not "download Wikipedia":
each job uses the smallest, cleanest artifact that does it —
**Selection** = Wikipedia Vital Articles L4/L5 resolved to QIDs, ranked/gated by
**Qrank** (CC0, ~104 MB);
**Facts** (numbers/dates/relations) = **Wikidata `latest-truthy.nt.bz2`** (CC0),
optionally pre-scoped with **wdumper**;
**Prose** = Kiwix `wikipedia_en_top_mini` ZIM (316 MB, proto) → **CirrusSearch
content** (scale);
**Distractors** = **Clickstream** confusables × Wikidata P31/P279 type-match ×
Qrank fame-gate. The full design + verified sources/sizes/licenses live in
`docs/CORPUS-SOURCE-PIPELINE.md`. The **shipped artifact contract is unchanged**
(Decisions 016/024/031): same `corpus.sqlite`/`*.json` schemas, same bundled-set
pattern, same quality gates — only the producer's input changes.

**Why**: The live-API pipeline is capped at the throttle (~5 req/s, `maxlag=5`)
and selects by **search relevance to ~70 seed terms, not popularity** — so we
ship 4,540 questions from ~1,956 of Wikipedia's ~6.9M articles (**0.03%**), and
the new non-MCQ types starve for structured facts behind the same throttle
(enumerate could only build 11 puzzles). Dumps lift the candidate pool 50–100×,
rank it by *true* cross-project popularity (Qrank), and supply structured facts
at scale with no rate limit. The corpus ships offline and tiny (~1.3 MB), so the
source artifacts are a **one-time build-machine cost, never a client cost** — the
exact case dumps are built for. **Wikidata is CC0**, which is why the facts spine
is the truthy dump and not a CC BY-SA derivative (DBpedia/structured-wikipedia):
the structured answers carry no ShareAlike obligation. Layering keeps three of
four source layers <500 MB and avoids the 90 GB raw-wikitext dump (parse-
difficulty 5) entirely — CirrusSearch is the pre-stripped clean version.

**How to apply**: build `tools/corpus/build_source_index.py` (streams the dumps →
`corpus_source.sqlite`, run ~monthly, NOT shipped) and re-point the generators at
the local store, deleting their retry/backoff/cache/`maxlag` machinery. Phase it
smallest-first: **Phase 0** selection (VA+Qrank, <500 MB — proves the breadth/
ranking lift before any big download); **Phase 1** prose (Kiwix top_mini →
CirrusSearch); **Phase 2** facts + distractors (Wikidata truthy + clickstream).
Pin dump dates in a manifest for reproducible rebuilds. Honor licensing: CC0
facts need no attribution; all Wikipedia **text** is CC BY-SA — keep the in-app
attribution + web article-twin link. Audit quality-gate pass-rates early: a 100×
pool means 100× more vandalism/ambiguity/dated-fact candidates reaching the
gates. Do NOT change the shipped artifact schemas or ship any dump to clients.
This is a `shared-data-plane-contract` change — update `DATA-CONTRACT.md`'s
Producer section as each phase lands.

---

## 033 — Create feature: pre-baked corpus everywhere + Foundation Models on-device on Apple

**Decision**: "Make a quiz on any topic" is served two ways, never by a paid
cloud LLM. (1) A large **pre-baked delightful corpus** (Decision 032 expansion to
the top Wikipedia subjects by Qrank) covers what people actually search, so most
play pulls ready-made questions. (2) For the live/arbitrary tail, **Apple
Intelligence's Foundation Models framework** generates delightful questions
**on-device** — `Core/AI/DelightfulQuizGenerator` fetches the topic's Wikipedia
summary, then an `@Generable` `GeneratedQuestion` is produced by
`LanguageModelSession`, GROUNDED strictly in that summary (no invented facts),
leak-guarded, converted to the app `Question`. `QuestionProvider.liveQuestions`
tries it first and falls back to `TemplateEngine` when unavailable. Free, private,
offline, first-party framework (fits "Apple frameworks only").

**Why**: delightful questions for an arbitrary live topic need an LLM at request
time; a backend LLM is a cost + privacy + infra burden. On-device Foundation
Models (iOS/iPadOS 26 baseline) removes all three. Grounding in the fetched
summary keeps the compact on-device model accurate — the same safeguard the
build-time corpus uses. Pre-baking the top searches means the on-device model is
only ever the long tail, so even non-AI devices get great questions.

**How to apply**: gate the framework with `#if canImport(FoundationModels) &&
!os(tvOS)` — the framework is in the tvOS SDK but its `@Generable`/`@Guide`
macros are currently `unavailable in tvOS` (no Apple Intelligence on Apple TV
hardware yet). When a future Apple TV ships Apple Intelligence, **delete
`&& !os(tvOS)`** — no other change; the template/corpus fallback runs on tvOS
until then. Always check `SystemLanguageModel.default.availability` at runtime
(device eligibility / AI enabled / model downloaded) and fall back to the corpus
+ template. Web/Android have no on-device Apple LLM → corpus + template now; a
shared backend is a later option only if needed. Keep generation GROUNDED in the
fetched summary and leak-guard the output (never name the answer).

---

## 034 — Trivia Night is device-agnostic, host-paced, everyone-plays (supersedes the TV-only buzzer)

*Date: 2026-06-24*

There is ONE multiplayer Trivia Night, and **any Apple device can host
it or join it** — iPhone, iPad, and Apple TV are peers; none is
special. The format is **host-paced, everyone-plays**: every player
(the host included) answers on their OWN screen, and the host taps
**Reveal → Next** to pace the night. The race-to-buzz mechanic and the
"Buzz Night" name are **retired** — the name is "Trivia Night"
everywhere, on every device.

**Why:** the TV-only buzzer (Decision 030) made the living-room screen
load-bearing and turned phones into dumb buzzers — only the fastest
thumb engaged with each question, and the host couldn't really play.
Ben's redesign: local multiplayer where everyone plays on their own
device and the host plays too. With no shared screen to "buzz into,"
buzzing stops making sense; the natural model is everyone-answers,
host-reveals. This also passes the learning-orientation test harder
than buzz-in did — *every* player engages with *every* question and
gets the reveal, not just whoever buzzed first.

**How to apply:**
- The whole networking stack is **platform-agnostic Core** (no
  `#if os` role split): `NightHost` (advertises, owns the roster +
  standings, paces), `NightClient` (browses, joins, follows), and
  `LiveNight` (the coordinator that wires the transport to a local
  `GameEngine`). Hosting runs an `NWListener` on iOS just as on tvOS.
- **Ship the night once.** The host builds the question list and
  broadcasts plan + the full `[Question]` in one `.night` message;
  every device runs its OWN `GameEngine` over the identical list. The
  engine is deterministic given the list, so no per-device divergence.
- **Each device scores itself; the host trusts the self-report.** A
  joiner reports its running total + correctness per question; the host
  aggregates. For a friendly living-room game this is the right
  tradeoff — no server, no judge, no anti-cheat.
- **Host-paced reveal is a `GameEngine` mode, not a UI hack.**
  `startNight(…, hostPaced: true)` makes the engine HOLD each reveal
  (`awaitingReveal`) behind a "waiting for the host" beat and never
  auto-advance; `releaseReveal()` / `goToQuestion()` / `advance()` are
  driven by the host's `reveal` / `begin` / `finished` signals. A
  device that never answered is force-submitted as a miss on reveal so
  everyone reveals together. Solo / pass-and-play pass `hostPaced:
  false` and are unchanged.
- **The play view is shared.** `GamePlayView` / `TVGamePlayView` take
  an optional `live: LiveNight?` — nil = solo (untouched); non-nil adds
  the host's Reveal/Next controls (host) or holds the reveal + shows
  "waiting" (joiner), plus the live standings at each reveal.
- Device-based silent rejoin (stable per-device id → same seat + score)
  and mid-night catch-up (host replays night + current question) carry
  over from Decision 030.
- **Still Apple-only, still hardware-gated.** The Bonjour discovery +
  local-network prompt + PSK handshake only exercise on real devices —
  a two-device test is the gate before this is "done". Web/Android
  networked play is the Phase-2 web-room (different transport); their
  multiplayer today is pass-and-play on one device.

## 035 — Home: exactly one primary action (Quick Play); pickers are progressive disclosure (rule R-HOME-1)

The home screen has ONE visually dominant call-to-action — **Quick Play** —
that starts a game in ≤2 taps with a smart default (the last mode+category
played, else Mixed Bag + Classic). Everything else (Daily, Trivia Night,
Pass & Play, Create) is visually secondary, and the mode + category pickers
are **never permanently open** — they live behind a "Customize a game" sheet.

**Why:** the old home stacked five equal-weight cards plus an always-open
13-mode rail and 8-category grid — a scan-heavy, scroll-heavy, decision-heavy
wall before a single question appeared, and overwhelming to a first-time user.
There was no front door. Competing equal-weight surfaces defeat the home's one
job: get a returning or new player into a question fast. (Owner complaint,
2026-07-01; design in `docs/HOME-REDESIGN-PROPOSAL.md`.)

**How to apply:** one saturated hero, everything else quieter (density by
subtraction, not decoration). Selection is a *task* → a native modal
(iOS `.sheet`, Android `ModalBottomSheet`, web `<dialog>`, tvOS focus screen),
not inline sections. The default resolver + last-selection persistence + preset
model are shared Core logic (four mirrors); the hero/sheet presentation is
native per platform. **Do not "harmonize" a second hero back onto the home** —
the single-primary-action rule is load-bearing. Trivia Night is likewise ONE
entry with host/join inside it, never separate home buttons.

**Related (same 2026-07-01 pass):** Records made self-explaining — the confusing
domains Pie removed, per-domain rows now say "N more to Level X", no cryptic
abbreviations ("Accuracy"/"Correct", not "Lifetime acc."/"Right"). Create made
corpus-grounded — retrieves REAL vetted corpus questions for a topic instead of
hallucinating (Decision 033's on-device generation was "obvious or nonsensical";
grounded retrieval is the every-device baseline). Daily made deterministic
(seeded pool, not `ORDER BY RANDOM()`). Android icon aligned to the canonical iOS
mark (confetti moved to a full-bleed background layer). Achievement taxonomy in
`docs/achievements.json` (GC + Play API creation owner-blocked).

## 036 — Design-audit pass: single-action hero, platform icons only, play-once Daily (rules R-HOME-1a, R-ICON-1, R-DAILY-1)

Four rules from the owner's audit of the R-HOME-1 redesign (2026-07-01): the
redesign's *structure* was right but several surfaces drifted from
native-platform-first.

**R-HOME-1a — the hero is ONE action.** The Quick Play hero contains no
embedded second button. "Surprise me" and "Customize" are a compact
secondary-actions row directly beneath the hero — two quiet, equal-weight
buttons in the platform's native secondary-button idiom. (This replaces the
full-width Customize row AND the capsule-inside-the-hero.)

**Why:** a tap target inside a tap target is awkward on every platform —
it splits the hero's affordance ("which half do I press?"), breaks
accessibility grouping, and on web required a nested `role="button"` span
inside a `<button>` (invalid interactive nesting). Owner: "the Quick Play
button that is half a surprise button looks incredibly awkward."

**R-ICON-1 — UI icons come from the platform icon system; emoji are content,
never chrome.** Apple = SF Symbols. Android = Material Symbols
(material-icons-extended, already a dependency). Web = inline SVG where an
icon is truly needed, otherwise typographic text. Emoji remain ONLY in
*content*: share-score grids, celebration copy ("You won! 🎉"), reveal
headers, onboarding hero art, streak data strings.

**Why:** emoji render inconsistently across OS versions/vendors, can't take
tint/weight/size tokens, read as unfinished next to real iconography, and
violate each platform's design language. Owner: "stop using Emojis as icons."
iOS already did this right — it is the mapping reference (the audit's
cross-platform icon table lives in the 2026-07-01 session log).

**R-DAILY-1 — the Daily is played ONCE per day; previous dailies are
replayable from an archive.** Today's Daily locks after completion (the card
flips to a "done — come back tomorrow" state showing your score). Tapping the
completed card opens **Previous Tidbits**: a list of recent days (capped ~30)
with each day's played/score state; an unplayed past day can be played —
the Daily generator is deterministic-by-date, so any past day's set
regenerates from its date, no question storage needed. Past days never
affect the streak (streak = played on the day, as today).

**Why:** a replayable daily is a self-defeating skill test — the second run
is memorization, and it cheapens the one-shot shared-set social contract
("everyone gets the same 7"). The archive keeps the learning value (catch-up,
revisit) without the exploit. Owner: "you shouldn't be able to replay the
Daily Tidbit… You should be able to play previous daily tidbits, though."

**Also in this pass (no new rule):** the home "Create" tile becomes the
**Online Multiplayer placeholder** (coming-soon, disabled) — Create remains
one tap away in its own tab; online multiplayer is the next marquee feature
(docs/ONLINE-MULTIPLAYER-PLAYBOOK.md) and earns the home slot Create didn't
need twice. The Customize sheet's labels were de-shouted (sentence case, no
"★" in headers, native section-header idioms) and every mode now
self-explains: the selected mode's one-line blurb renders under the mode
picker, because bare names like "Stake" or "Which First?" were unreadable
options (owner: "the text on buttons and options within the Customize a Game
interface is particularly bad").

**Documented inversion (do not harmonize):** the tvOS Customize picker starts
the game on category selection — no Start button — because selection-is-action
is the ten-foot idiom; phone/web/tablet commit with an explicit Start.

## 037 — The Daily is picked by hash-rank, not seeded shuffle (one algorithm, three mirrors, golden-tested)

The Daily's set for a day is: rank every corpus question id by
`FNV-1a64(UTF-8 "daily:<day>:<categoryId>:<id>")` and take the 7 smallest,
presented in ascending rank order. No RNG, no shuffle, no pool ordering.
Mirrors: `Core/Engine/DailyPick.swift`, `Tidbits.kt pickDailyIds`,
`engine.js pickDaily`. Prove any change with `tools/daily-parity/run.sh`
(runs the REAL code on all three stacks against each platform's own bundled
corpus and diffs) — and keep `tools/night-wire/check_id_parity.py` green,
because identical sets also require identical id sets.

**Why:** the owner caught the Daily differing on Android vs iOS vs web —
defeating its whole premise ("everyone gets the same 7", comparable scores).
The old "same FNV-1a/SplitMix64 constants" claim was never true END-TO-END:
the three platforms had different seed strings (`day:category` vs bare day),
different hashes (web was 32-bit FNV over UTF-16 code units), different pools
(sorted ids vs corpus load order), and three different shuffle algorithms
(Swift stdlib `shuffled(using:)` consumes the RNG differently than both
hand-rolled Fisher-Yates variants). Making three shuffles byte-compatible is
fragile forever; hash-ranking each id independently is order-independent BY
CONSTRUCTION, so platform storage/sort differences simply can't matter.

**How to apply:** never re-introduce a shuffle or RNG into daily selection.
Any change to the rank string lands in ALL THREE mirrors + the golden test in
the same change set. The golden immediately caught a real divergence:
Kotlin's `Byte` is signed, so Android's FNV-1a sign-extended every non-ASCII
UTF-8 byte (`Skarsgård`) — mask with `and 0xFF` when hashing bytes in Kotlin.
Caveat: the web corpus refreshes network-first, so around a corpus publish
the web may briefly hold a NEWER id set than the store apps — the daily can
differ across platforms for that window only; id parity is the invariant.

## 038 — Online multiplayer is per-ecosystem + bot-first; v0 ships Play vs CPU with honest labels

Online play ships in phases (docs/ONLINE-MULTIPLAYER-PLAYBOOK.md). **v0 (this
pass): Play vs CPU** — a fully-offline believable opponent behind the home's
"Online Multiplayer" surface, with the online Quick Match row visible and
honestly marked coming-soon. The surface is ONE entry (R-HOME-1 idiom, like
the unified Trivia Night sheet): pick The House / Rookie / Regular / Ace and
play a classic round head-to-head.

**Why bot-first:** neither store ecosystem can host cross-platform online
(GameKit is Apple-only; Google killed Play Games multiplayer in 2020 —
playbook §1–2), so real online needs either GameKit per-ecosystem or a
neutral relay (Cloudflare DO / Supabase, §3) — both owner-gated (infra, auth,
identity). The bot mode is owner-unblocked, delivers competitive trivia
everywhere immediately, and becomes v1's timeout-fill / dropout brain.

**The believability spec (all three mirrors — BotOpponent.swift / Bots.kt /
js/bots.js, keep in lockstep):** per-question correct-rate = clamp(baseSkill
+ categorySkill + difficultyAdj, .02, .98) — never certain, visibly uneven
across categories; answer time = log-normal jitter (correct ≈15% faster,
~5% freeze-and-miss); scores use the player's own Scoring rules. Presets:
Rookie .55 / Regular .70 / Ace .85 + **The House**, which tracks the
player's rolling accuracy (fair fight; "meet the learner where they are").

**HONESTY RULE (learning-orientation, non-negotiable): a bot is always
visibly labeled CPU** — a tag on every roster row, strip, and standings line.
Never present a bot as a human; when v1 backfills empty online seats with
bots, the label and a visible notice come with it.

**How to apply:** vs-CPU matches don't write GameRecords (same as
pass-and-play — solo records stay honest). v1 (owner-gated next): pick the
backend (Cloudflare DO room actor recommended) + the identity story, then the
room state machine in playbook §3d reuses this exact bot spec server-side.

## 039 — Online play rides native platform multiplayer; no third-party backend (owner decision)

Owner (2026-07-02): "all of the online multiplayer [flows] through the native
platform multiplayer options (Game Center and Google Play Games). I don't
think Cloudflare should have to enter into the picture." So: **Apple online =
GameKit**, no neutral relay, no server costs.

**The consequence to keep honest (playbook §2, owner informed):** Google
killed Play Games multiplayer in March 2020 — PGS v2 has sign-in/friends/
leaderboards but NO match transport, and Google's own migration path is
"build your own backend," which this decision rules out. Therefore **online
play exists on Apple platforms only**; Android and web keep Play vs CPU +
local Trivia Night, and their Quick Match slot stays honestly "coming soon"
(it can only ever light up if this decision is revisited).

**How it's built (reuse, not reinvention):** GameKit is just another link
behind the `NightPeerLink` seam (`Core/Networking/GameKitTransport.swift`) —
the entire proven Trivia Night machinery (NightHost/NightClient/LiveNight,
wire protocol, rejoin) runs unchanged over a `GKMatch`. A match has no host,
so every device elects the SAME leader (lowest gamePlayerID); the leader runs
NightHost, everyone else NightClient. The wire's GCM is keyed by the fixed
`Night.gameKitCode` (GameKit already authenticates + encrypts the link; the
app-layer crypto degrades to framing, keeping the wire byte-identical to the
local night). Stranger matches are **auto-paced**: the leader's LiveNight
reveals when everyone answered (or clock + grace) and advances after a
readable beat — no human host taps. Matchmaking UI = Apple's stock
`GKMatchmakerViewController` (invites + automatch, 2–4 players).

**How to apply:** the hardware gate applies double here — GameKit matches
can't run on simulators without sandbox Game Center pain; the 2-device
REAL-DEVICE test (two Game Center accounts) is the acceptance gate. If
matchmaking errors on TestFlight, check App Store Connect → the app's Game
Center config (compatibility matrix) — flagged as the owner-verify item.

## 040 — Android + web online play rides Firebase Realtime Database (owner-approved backend)

Online Quick Match on Android and web uses **Firebase Realtime Database**
(project `tidbits-trivia-f2ddb`), chosen in `docs/MATCHMAKING-SERVICES-RESEARCH.md`
and approved by the owner (2026-07-03). Apple stays on GameKit (Decision 039);
Firebase covers the platforms GameKit/Play Games can't (Play Games multiplayer
is dead — playbook §2).

**Why RTDB:** genuinely free tier (no card, hard-stops instead of billing),
official Kotlin + no-build-step browser SDKs, and rooms need **zero server
code** — Security Rules + Anonymous Auth enforce the shape. It's also Google's
own designated replacement for the Play Games multiplayer it retired.

**Model (mirrors local Trivia Night's trust model):** a room is a short code;
each device runs its own engine over the shared question set and self-reports
its score; a leader-elected coordinator paces. Anonymous auth gives each device
a uid so rules can scope writes — no accounts, no PII. Frames/scores are RTDB
children, not a socket; the low-frequency trivia traffic fits the free tier
(~25 concurrent rooms on 100 connections).

**Provisioned via CLI (this session):** RTDB instance
`tidbits-trivia-f2ddb-default-rtdb` (us-central1), Security Rules
(`database.rules.json`, deployed), a registered Web app (config in
`js/firebase-config.js` — non-secret by design). **The one console-only step:**
Firebase Auth's first-time provisioning + the Anonymous provider toggle are
gated behind the console (the API path requires Blaze billing, which we don't
want) — owner enables Authentication → Anonymous once, free.

**How to apply:** never require real accounts for v1 (anonymous is the
identity). The `js/firebase.js` transport + the Android `FirebaseRtdbTransport`
implement the same `NightPeer` seam the local night uses, so the match
machinery is reused, not reinvented. The 2-device hardware test remains the
acceptance gate for anything networked.

## 041 — Records are interactive: per-game answer detail is persisted; history + drill-ins everywhere

Every completed game now persists its per-question detail (`AnswerDetail`:
qid, prompt, categoryID, correct, answer) alongside the aggregate — SwiftData
`GameRecord.answers` (optional Data, automatic migration), Android
`Store.Rec.answers` (record JSON), web localStorage. This is the foundation
for an interactive Records tab (owner request, Threes-inspired).

**Why:** aggregate-only records ("you scored 640, 7/10") are a dead end — you
can't revisit which questions you missed, compare attempts, or scroll your
history. The owner wanted to drill into domains + personal bests and scroll
previous games the way Threes shows past runs. That requires the per-question
detail on disk.

**How to apply:** the detail is spoiler-safe (it's the player's own history) so
it persists in the clear. Records surfaces it three ways — a game-history scroll
(each game a card + a category-colored answer-dot strip, tap → recap), a domain
drill-in (Missed / Got right, latest outcome per question), and a personal-best
drill-in (every attempt, best crowned). Old records with no detail degrade to
totals-only — never crash, never fabricate. Keep the four stores in lockstep:
adding a field to AnswerDetail means all four writers + readers.

**Also (share redesign):** the uniform red/green squares became answer dots
(🟢/🔴/⚫️) + a proportional accuracy meter (▰▱) + a 🔥 best-run flourish — more
compelling and more informative, still spoiler-free. Mirrored on all four.

## 042 — macOS joins the universal Apple target (amends 013); it's the next scope

The one Xcode target that serves iPhone, iPad, and Apple TV (Decision 013)
gains **macOS** as a fourth destination. macOS reuses the entire Apple `Core/`
verbatim (AppStore, the game engine, RecordsStore, the corpus, sync) and rides
the same CloudKit private database; only the shell is new. Skills
(`macos-platform-patterns`, `cloud-appstore-submission`, `play-cli-submission`)
+ a starter `TidbitsTrivia/macOS/ContentView_macOS.swift` are in place — the
shell itself is the next major scope of work.

**Why:** once a universal target exists, macOS is the cheapest platform to add
(~60–70% of the Swift is already platform-agnostic). Trivia is genuinely
lean-in — a pointer + keyboard + menu-bar Mac app is a natural fit, unlike the
tvOS lean-back constraint. Adding it as a destination (not a separate target)
keeps versioning (`AppVersion.xcconfig`), sync, and the shared destination
registry unified for free.

**How to apply:** in Xcode, add native **Mac** (NOT "Mac (Designed for iPad)")
to the target's Supported Destinations. New UI goes in `TidbitsTrivia/macOS/`
behind `#if os(macOS)`; the `_macOS.swift` suffix marks Mac-only views. The
`RootView` branches explicitly (`#elseif os(macOS) ContentView_macOS()`).
`#if os(iOS)`-guard any Core symbol that imports UIKit. Build the Mac
destination as part of "done" whenever a shared file changes — a green iOS build
doesn't prove the Mac slice compiles. Read `macos-platform-patterns` before the
shell: NavigationSplitView (not resized tabs), game-in-progress replaces the
window root, the fill-image layout trap, ImagePipeline for art, menu-bar
`.commands`. Submission is the same cloud path plus a 3rd-Party-Mac-Installer
cert for `.pkg` signing (`-f platform=mac`).

## 043 — Tidbits Live: the Mac-exclusive pub/event trivia system (scope locked)

macOS earns a Mac-exclusive **Tidbits Live** — an emcee/admin dashboard that
runs a live pub/bar/event trivia night driving a projected big screen while
teams answer on phones (web now, native Tidbits apps later). It ships alongside
the full parity face (Decision 042), not instead of it. Scope decisions, locked
2026-07-03 with the owner (research: `docs/EVENT-TRIVIA-COMPETITIVE.md`):

1. **Sequencing = parallel, parity-led.** Stand up the Mac parity shell + core
   screens first (reuses Core, unblocks everything), then layer Tidbits Live on
   top. Each phase ships something runnable.
2. **Serverless for now.** MVP is single-venue over the local network + optional
   Firebase (already used for online match). Cross-venue/season leaderboards and
   venue lead-capture (which need a backend) are deferred — NOT built until a
   backend is a deliberate later decision. Do not add a server for v1.
3. **Tidbits-native rounds first.** Build a clean round/format system in the
   Tidbits sticker-book design (MCQ, picture, audio, nearest-wins,
   fastest-finger, wager). Game-show boards (Jeopardy/Feud/Wheel "show mode")
   are Phase C, not MVP.

**Why:** the whole competitor field (Quizado — native Mac but 1.0-rated —
SpeedQuizzing, Buzztime, Crowdpurr) shares the same gaps, and they map exactly
to host pain: no manual score override, no real tie-break engine, weak cheating
deterrence, no Wi-Fi/paper fallback, no built-in monetization. Tidbits has three
moats none of them combine: a consumer install base to join with (every event
funnels into daily play), a 20k+ corpus + `DelightfulQuizGenerator` already
built, and native-Mac quality where incumbents read dated. The locked scope
targets the under-served differentiators first and avoids a premature backend.

**How to apply:** MVP (Phase A) is the host cockpit end-to-end — event builder
(corpus/AI/manual) → manual pacing + reveal-on-command + **manual score
override** + **free-text review** → big-screen output (question, QR join,
ten-foot team leaderboard) → phone/web team join with reconnect → auto-scoring +
cumulative leaderboard + **tie-break engine** → recap; offline-capable with a
**printable answer-sheet fallback**. The event is a `.package`-style REFERENCE
document (Rule 11: Library ≠ Project — the corpus/question library is app-global
SwiftData, the event references it, neither embeds a re-hosted copy). Any
"generate" assist yields an EDITABLE round the host shapes, never a one-tap
finished night (`learning-orientation-design`). The full binding spec is
`docs/macOS-DESIGN.md` Part A; every event surface quotes a rule there.

## 044 — Trivia Night + Tidbits Live share ONE backend; host from any platform (amends 034)

Trivia Night and Tidbits Live are now two PRODUCTS on ONE backend — Firebase
Realtime Database `live/{code}` (the contract in `docs/LIVE-ROOM-CONTRACT.md`) —
with UNIFIED host and join code paths. Owner architecture, 2026-07-03:

1. **Trivia Night = casual, host from ANY platform.** iOS, iPadOS, tvOS, Android,
   **and web** can host a quick game with friends AND join one. It's lightweight.
2. **Tidbits Live = the marquee, macOS-only host** for large-scale venue events —
   far more feature-rich than Night, built for continual expansion (Decision 043).
   It rides the same rooms, so its players come from the same unified join.
3. **Join is one flow everywhere.** "Join a game" → a 4-letter code → the shared
   player (`LivePlayerClient` on Apple, `FirebaseNet`/`LiveRoomScreen` on Android,
   `js/live.js` on web). The player never knows or cares which product hosts them.
4. **One QR** — `https://tidbitstrivia.com/live/CODE` (works via `404.html`). Every
   host lobby (Night on all platforms + the Mac Live cockpit/projector) shows it;
   scanning joins with the code prefilled.

**Why:** Decision 034's Trivia Night was **local mDNS/Bonjour**, which a web browser
physically cannot reach (no LAN discovery) and which the owner wanted available
everywhere. RTDB is the only backend all six surfaces share, and it already powered
Tidbits Live join. Unifying makes "host anywhere, join anywhere, incl. the web" real
with no new infrastructure, and collapses two join flows into one.

**How to apply:** the shared host is `LiveHostNet` (RTDB bridge, promoted to Core)
+ `LiveNightHost` (Apple) / `FirebaseNet` host methods (Android) / `js/firebase.js`
host methods (web) — open a room, publish each `pub` (answer withheld until reveal),
**auto-score on reveal**, pace Reveal→Next, standings. A host may "play too" (self-
joins as a team). The **old mDNS Night stack** (`NightHost`/`NightClient`/
`BonjourTransport`, Wi-Fi Aware, BLE, `net/Night*` on Android) is **legacy** — no
longer wired for Trivia Night; `LiveNight` survives only as the GameKit Quick Match
coordinator (Decision 039). Do not add mDNS to new join/host flows.

## 045 — There is no free remote Windows box; `windows-latest` IS the Windows machine

Windows development is **CI-driven, not VM-driven**. `windows-latest` on this
public repo is unlimited-free and is the only Windows compute in the loop. It is
driven from the CLI via `.github/workflows/windows-repl.yml`
(`gh workflow run` → `gh run watch` → `gh run download` → `Read` the PNGs, ~2-4
min round trip). Do NOT go looking for a free Windows VM again, and do NOT RDP
into a runner.

**Why:** researched 2026-07-17, and the answer is genuinely "none exists":

- **Azure** — 750h/mo B1S Windows is **12 months only**, then nothing. No
  always-free Windows tier. 1 vCPU / 1GB is also miserable for an Avalonia GUI
  over RDP.
- **AWS** — the 750h/mo free tier is **gone for accounts created after
  2025-07-15**; new accounts get $200 in credits that expire in 6 months and
  then the account auto-closes.
- **Google Cloud** — the Windows license is a per-vCPU premium the free tier
  never covers; Windows images can't even be created during the trial.
- **Oracle Always Free** — "Microsoft BYOL is not available on Free Tier or
  trial tenancies."
- **Windows 365** — 1-month trial; **Dev Box closed to new sign-ups 2025-11-01**.
- **RDP-into-a-runner** — technically possible, but GitHub's Actions terms limit
  hosted runners to "activity related to the production, testing, deployment, or
  publication of the software project associated with the repository," GitHub
  *does* disable repos for the ngrok+3389 pattern, the 6-hour job cap is
  unextendable (idle burns it identically), and Tailscale's free tier allows
  1,000 ephemeral min/mo — under three sessions. Not sustainable, and it risks
  the account for a 1024x768 software-rendered desktop.

The deeper reason this is fine: **the loop never needed a desktop.**
`Avalonia.Headless` with `UseSkia()` + `UseHeadlessDrawing = false` renders real
Skia pixels in-process, with deterministic frame timing and full input
simulation — no window station, no session, no GPU. So CI gives strictly more
than an RDP session would, reproducibly and forever.

**How to apply:**

1. **Iterate on the Mac head** (`dotnet test`) for speed; it renders real pixels
   but is NOT the ship target.
2. **Gate on `windows-latest`.** "Renders on the Mac" is not "correct on
   Windows" — Mica, window chrome, DPAPI, Win32 interop, LibVLC natives and snap
   are Windows-only, and several are arm64-macOS-impossible.
3. **Visual baselines are captured ON Windows and enforced only there**
   (`VisualBaseline`), because Skia rasterization/font fallback are not
   guaranteed identical across heads. Refresh with
   `gh workflow run windows-repl.yml -f update_baselines=true`, then commit the
   artifact.
4. **Baseline-gated renders must be deterministic** — use `StartCustom` with
   fixed questions. `engine.Start()` draws from the 131k corpus and can never be
   baselined.
5. **Structure Windows-only work so the BEHAVIOUR is pure and the platform call
   is a thin edge** — `Win32HostInterop.RoundIndicator`, `VideoFrameSink`
   (a raw BGRA pointer, no LibVLC). That is what keeps it testable off Windows at
   all, and it is why 3.34 and 0.2 got unblocked without a Windows box.
6. **`CopyPixels` returns each bitmap's NATIVE format** — a captured frame is
   RGBA, a PNG-decoded file is BGRA. Comparing them directly reads R against B,
   which reports pixel-identical images as differing *only where they are
   coloured* (grey has R==G==B and agrees). This produced a false 0.651%/8.391%
   drift on the visual gate's first real run. Always normalize through one decode
   path before comparing.

**The cost model:** $0/month, forever, on a public repo. The only thing ever
worth paying for is an Azure VM as a rare eyes-on escape hatch for the few things
headless genuinely cannot show (native window chrome, OS font substitution, real
GPU behaviour) — and its 12-month clock starts at signup, so defer it until
something forces the issue.

---

## 046 — Windows 10/11 is the 6th platform and a fully supported channel

*Date: 2026-07-18*

Windows is a **first-class shipping platform**, on equal footing with web / iOS /
iPadOS / tvOS / macOS / Android — not an experiment. Native **Avalonia 12 +
FluentAvalonia 3 + .NET 10** (C#), shipping to the **Microsoft Store** as an MSIX
via the same CLI shape as Apple/Play. The shared game logic is hand-ported to a
6th mirror, `Tidbits.Core` (C#), byte-compatible with the Swift/Kotlin/JS stacks
on the shared Firebase `live/{code}` + `queue/mixed` plane. First submission is in
certification (Store ID `9NRKS9LDRCWC`, v1.6.45); every future ship is
`gh workflow run windows-store.yml -f submit=true -f commit=true`.

**Why:** desktop trivia is genuinely lean-in, Windows is the largest desktop
install base, and Avalonia's headless-Skia rendering made a **$0, CI-only**
pipeline real (Decision 045) — so the platform could reach ~full Mac parity and
ship without ever owning a Windows machine. Avalonia over WinUI specifically
*because* only Avalonia renders real pixels off-Windows; that is the whole reason
the platform is observable and testable from an arm64 Mac. The universal-Apple
lesson (60–70% of an app is platform-agnostic) held again: the expensive part was
the shell + the Store bootstrap, not the logic.

**How to apply:**

1. **Treat Windows as a parity row, never a follow-up.** When shipping a feature,
   mirror it in `Tidbits.Core`/`Tidbits.App` in the same change set where feasible
   and update `docs/WINDOWS-PARITY.md` (the authoritative Windows column) alongside
   `PARITY.md`. A platform you can't reach right now gets `[~]`/⏳ with a note,
   never silence.
2. **Same verb, native idiom.** Windows feels like Windows — Fluent + Mica,
   `NavigationView` shell, `FAContentDialog`, pointer + keyboard, taskbar progress.
   Don't port the iOS/Android look; port the verbs. Binding rules:
   `docs/WINDOWS-DESIGN.md`.
3. **Observe every UI change headlessly and gate on `windows-latest`** (Decision
   045). "Renders on the Mac head" is never "correct on Windows."
4. **Determinism-critical Core (daily pick, season/venue keys, wire types) must
   pass golden vectors** against the other stacks — byte-compatibility is what lets
   a Windows player match a phone/web player.
5. **Every ship bumps `MARKETING_VERSION`** (`AppVersion.xcconfig` →
   `tools/stamp_msix_version.py` stamps both the csproj and the MSIX manifest); the
   Store reserves the 4th version segment, so an un-bumped rebuild is indistinguishable.
6. **The Store bootstrap is one-time and DONE** — don't repeat §1 of
   `docs/WINDOWS-STORE-SUBMISSION.md`; it's the runbook for the *next* app in the
   template. Two non-obvious first-submission blockers are recorded there
   (runFullTrust justification; the Xbox-services "Test" that clears the
   access-policies banner for Game-type products).

---

## 047 — Monetization: hosting is free forever; players pay (the two-sided model)

**Tidbits Live hosting is free forever and unconditionally — unlimited players,
events, and venues. Revenue comes from players (Tidbits Club, $29.99/yr) and from
venues buying Club passes in bulk as PRIZES ($99 / 10 passes), never as a software
fee.** Full strategy + per-platform mechanics: `docs/MONETIZATION.md`.

**Why:** Every vendor in the category monetizes exactly ONE side of the room —
consumer apps charge the player, host tools charge the host/venue. Nobody bridges
them. Sporcle is the proof: it owns both a consumer subscription ($3.99/mo) and a
national bar-trivia network ($3/player/night), and runs them as two unconnected
businesses — players at a Sporcle Live bar are never converted into app
subscribers.

The economics say why the bridge is the right side to stand on. Venues pay hosts
$150–250/night and make $2,000–4,000 off the night, so host *software* is ~4% of
the spend — the least valuable and most price-resented slice. That is exactly
where every complaint in the research clusters ("wildly overpriced" — Kahoot;
"$149 and I've not seen the value" — Crowdpurr; "price gouging" — Wayground).

So we give the 4% away. It costs ~$0 (Firebase Spark + GitHub Pages) and deletes
the revenue basis of Crowdpurr, Kahoot, Quizado, Trivnow, Slido, and AhaSlides.
**They cannot follow — host software IS their business; for us it is customer
acquisition.** A 40-person bar night is 40 qualified installs delivered by someone
already paying a human $200 to make those people play trivia. That is the funnel
nobody is capturing, and it is the moat `docs/EVENT-TRIVIA-COMPETITIVE.md` §5.1
already identified from the feature side.

**How to apply:**

1. **Never gate a hosting feature.** Any later proposal to cap players, events, or
   venues, or to add a "Pro host" tier, violates this decision — it is not a
   pricing tweak. The unconditionality is the competitive weapon.
2. **R-MON-1 — the free tier is never reduced AFTER GO-LIVE.** From launch day
   forward, nothing free may move behind the paywall, ever. *Why:* Sporcle's
   defining complaint is that previously-free stats went behind a subscription;
   that single act generates more anger than any price. **Scope (owner correction,
   2026-07-19): this binds from go-live forward, NOT today — we have not launched,
   so there are no users to take anything from. We are DRAWING the initial line,
   not moving it, and any already-built feature may be assigned to Club at launch.**
   The earlier "premium must be net-new only" reading is withdrawn. *How to apply:*
   decide the line ONCE before go-live and treat it as frozen after — which makes
   the pre-launch scoping call the only cheap moment to get this right.
3. **R-MON-2 — entitlement unlocks by account sign-in ONLY.** Never a code, key,
   coupon, voucher, or QR redeemed in-app. *Why:* App Store Guideline 3.1.1
   explicitly bans those mechanisms; our `sha256(verified email)` spine is already
   the compliant shape. Venue prize passes are assigned to an email and simply
   appear on sign-in. A well-meaning "have a code?" field would convert a
   compliant app into a rejection.
4. **R-MON-3 — clients never write to `entitlements/`.** A Cloudflare Worker is
   the sole writer. *Why:* `players/{key}` is world-readable and owner-writable by
   design, so a client-written `isPro` flag is trivially forged by anyone with the
   RTDB URL.
5. **Club is "get better," not "play more."** The premium tier is the *learning*
   tier — knowledge map, practice-your-misses spaced repetition, ranked seasons,
   story archive, host question library. This is the only framing that satisfies
   both the learning charter and R-MON-1.
6. **Local store receipts are authoritative and checked offline first**; the
   remote entitlement is the fallback for web purchases. Never gate a
   store-proven entitlement behind a network read.
7. **Cost stays $0 ongoing** — Firebase Spark + Cloudflare Worker free tier +
   Merchant of Record (variable only). Fixed cost is the $99/yr Apple membership
   already carried. Never enable a metered tier.

**Also decided:** a **Founding Member lifetime unlock at $79.99, first 90 days
only** ships alongside the subscription (owner call, over a subscription-only
recommendation). The cannibalization risk is accepted and bounded by three
binding constraints — the 90-day window, the $79.99 price (~2.7yr breakeven, not
$59.99), and a Founding Member badge. **Day-90 review is part of the decision:**
if lifetime take-up dominates annual, that is evidence the annual price is wrong,
not that lifetime should continue.

**Go-live (rule 7): all six platforms ship the paywall simultaneously**, and
**Windows sets the date** — it has no sign-in at all today
(`windows/Tidbits.Core/Networking/PlayerIdentityStore.cs` is local-only), so it
cannot resolve an email-keyed entitlement. Windows sign-in + the Avalonia
`StoreContext` IAP spike are the critical path and the only items not verifiable
on the Mac head (Decision 045). Enroll in the Apple Small Business Program
immediately — free, 15-day activation, halves year-one subscription commission.

---

## 048 — Account deletion is a launch requirement on every platform, and the
## account we must delete is the ANONYMOUS one too

**Every platform that lets a player sign in must offer in-app account deletion,
and the delete has to reach the anonymous account Tidbits provisions for
everybody — not just the Sign-in-with-Apple one.**

**Why:** App Review rejected tvOS 1.6.52 (96) under Guideline 5.1.1(v) — "supports
account creation but does not include an option to initiate account deletion."
The trap is that we read that guideline as being about *sign-in*, and Tidbits'
sign-in is optional. But `PlayerIdentityStore.bootstrap()` creates a real Firebase
Identity Toolkit user for every player on first launch and writes
`players/{uid}` — a server-side account holding a name, rating, streak, Daily
history, and standings. That is an account by Apple's definition and by any
reasonable privacy one. Offering deletion only to signed-in players would have
left the majority of records undeletable, and gating the button behind sign-in
would also have hidden it from a reviewer who never signs in.

A second trap sits in the security rules: a Firebase delete is a write of `null`,
so a `.write` rule phrased as `newData.val() === auth.token.email` (which
`emailOwners/$key` was) silently **denies the owner's own delete**. Any rule that
validates the shape of the new value must also spell out the delete case.

**How to apply:**
- Put "Delete Account" in the Profile/Account section of Settings on every
  platform, **always visible**, never behind sign-in, and never a link out to a
  website (5.1.1(v) forbids a support-ticket or web-only flow for anyone outside
  a highly-regulated industry).
- Delete in this order: account-keyed nodes → auth-uid-keyed nodes →
  `emailOwners` (the ownership proof other rules read — drop it LAST) → the
  Identity Toolkit user (`accounts:delete`, which invalidates the token) → local
  SwiftData/UserDefaults/Keychain → re-bootstrap a fresh anonymous identity.
- Shared records are not yours to delete: a duel drops only *your* player slot,
  never the whole node, or you erase the opponent's game.
- Every node delete is best-effort; only the auth delete is authoritative and
  reported. A stale leaderboard row must not strand a player mid-deletion.
- Record a screen recording of the flow in App Store Connect → App Review
  Information → Notes. Review asks for it by name on any 5.1.1(v) re-submission.

**Related:** the same submission was rejected under 2.1(a) for a purchase error.
One StoreKit `Product.products(for:)` attempt is not enough — it can return an
empty array (not an error) before the store's first sync, most visibly on tvOS
where the paywall is often the process's first App Store traffic. Retry it, and
make an empty product list a **recoverable** state with a Try Again control, never
a bare error string. And never stack the paywall as a second `.fullScreenCover`
on tvOS: StoreKit then has to present its sheet third in a modal stack.

## 049 — A bundled corpus is queried, never loaded: RAM is a shipping constraint,
## and "works on my emulator" hides it

**Rule:** any client that ships the full ~128k-question corpus reads it from the
prebuilt `corpus.sqlite` and queries per request. No client decodes the corpus
into objects and holds them. Apple already did this (`CorpusDatabase`); Android
now does too, off the **same** database file.

**Why:** Google Play rejected version code 75 under the Broken Functionality
policy — "the app opens, but it keeps crashing." There was no stack trace: the
reviewer's evidence is the stock Android crash dialog, Android vitals showed
**zero** user crashes, and the build could not be made to crash on Android 11 or
16, release or debug, with or without network, or under 3,000 monkey events.

Measurement found it where reproduction could not. Decoding `corpus.json` into
128,670 `Question` objects cost ~180MB of Java heap:

| | before | after |
|---|---|---|
| resident after load | 230 MB | 74 MB |
| peak during `Corpus.search` | **299 MB** | 96 MB |

The app needed `android:largeHeap` merely to open. A 299MB peak survives a
512MB largeHeap cap (every emulator image on hand) and dies on the 256MB cap
that mid-range hardware ships — which is exactly "opens, then crashes," and
exactly why no local device reproduced it.

**How to apply:**
- Ship `corpus.sqlite`, not `corpus.json`, to any memory-constrained client.
  Copy it out of the APK once (SQLite needs a real file) and key that copy on
  the app version, or a corpus update stays invisible behind the copy on disk.
- Keep only the `id` space resident (~13MB) — the Daily rank and Marathon need
  it, and nothing else does.
- Push filters into SQL, then score the narrowed candidate set in code. The old
  `search` called `.lowercase()` five times per row across all 128,670 rows;
  that transient garbage was most of the 299MB spike.
- **An emulator's heap cap is not the device's.** `largeHeap` is a smell, not a
  fix: it converts a memory bug into one that only appears on hardware you do
  not own. Measure `Java Heap` in `dumpsys meminfo` against the *smallest*
  supported cap, not the one that happens to be booted.
- This is the second OOM on this exact path (the first made every mode silently
  show "No questions yet"). Holding the corpus in RAM is the recurring defect;
  querying it is the ratchet.

**Not changed:** the web app (browser-managed) and Windows (a desktop with GBs
free) still read `corpus.json`. The constraint is a phone's per-process heap
cap, not the file.
