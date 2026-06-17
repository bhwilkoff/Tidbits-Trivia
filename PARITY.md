# Tidbits Trivia — Cross-Platform Feature Parity

> **Single source of truth** for what's shipping where. Updated in
> the SAME change set as any user-facing feature.
>
> Companion to `CLAUDE.md` (project context), `SCRATCHPAD.md` (active
> milestone), `DECISIONS.md` (architecture decisions). Per-platform
> design rules live in `DESIGN.md` (iOS), `tvOS-DESIGN.md` (tvOS),
> `WEB-DESIGN.md` (web), `ANDROID-DESIGN.md` (Android) when those
> binding docs exist. The full workflow — including the periodic
> parity audit — is the `cross-platform-parity-discipline` skill.

---

## Legend

- ✅ **Shipped** — live in production on this platform
- 🚧 **In progress** — being built; some parts may already be in main
- ⏳ **Planned** — committed; targeted for an upcoming milestone
- 🔮 **Future** — agreed direction; no timeline yet
- 🚫 **Out of scope** — explicitly not built on this platform (with reason)
- n/a — platform-inapplicable (e.g., lock-screen controls on tvOS)

A ⏳ or 🚫 cell carries its reason in Notes. "Deliberately deferred,
because X" is a healthy cell; a silent blank is drift.

---

## Parity rule

When shipping any user-facing feature:

1. **Confirm the verb is identical across platforms.**
   Find = explore, Profile = identify, etc. Don't let one platform
   own a different verb for the same surface.
2. **Pick the native idiom per platform** — `<dialog showModal>` on
   web, `.sheet` on iOS, focus-driven full-screen on tvOS,
   `ModalBottomSheet` on Android.
3. **Update this table** in the SAME PR. Drift here is what causes
   "the web has X but iOS doesn't" complaints six months later.
4. **Cross-link to the binding design doc** for each platform that
   has one.

---

## 0. Platform set

Web + iOS + iPadOS + tvOS + Android (Decision 020). tvOS earns its place
because living-room trivia is lean-back (Decision 021). iOS is the lead
platform; everything ships there first, then mirrors. A platform not yet
reached is ⏳ with a note, never silence.

## 1. Top-level navigation

| Verb | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Play (home: daily, modes, categories) | ⏳ | ✅ | ⏳ | ⏳ | iOS: bottom Tab. Web: nav + URL state. tvOS: shelf. Android: NavigationSuiteScaffold |
| Records (stats, streak, review) | ⏳ | ✅ | ⏳ | ⏳ | |
| Create (quiz from any topic) | ⏳ | ✅ | 🚫 | ⏳ | tvOS: typing a topic on a Siri Remote is hostile — consume shared links instead |

---

## 2. Core gameplay (single-player)

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Classic mode (10 Qs, speed scoring) | ⏳ | ✅ | ⏳ | ⏳ | Same GameEngine loop on every platform |
| Time Attack (60s) | ⏳ | ✅ | ⏳ | ⏳ | |
| Survival (until one wrong) | ⏳ | ✅ | ⏳ | ⏳ | |
| Daily Tidbit (deterministic, streak) | ⏳ | ✅ | ⏳ | ⏳ | Same 7 Qs for everyone per calendar day |
| 8 categories | ⏳ | ✅ | ⏳ | ⏳ | Mixed/History/Science/Geography/Arts/Film&TV/Music/Sports |
| Countdown clock + speed bonus | ⏳ | ✅ | ⏳ | ⏳ | Per-question or global per mode |
| Streak multiplier | ⏳ | ✅ | ⏳ | ⏳ | Capped at 2× (bounded reward) |
| "Learn the fact" reveal + Wikipedia link | ⏳ | ✅ | ⏳ | ⏳ | The mission-critical screen |
| Post-game missed-fact recap | ⏳ | ✅ | ⏳ | ⏳ | |
| Four content states (load/empty/error/offline) | ⏳ | ✅ | ⏳ | ⏳ | |

---

## 3. Content pipeline (shared data plane — see docs/DATA-CONTRACT.md)

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Bundled offline corpus (~9k, never-repeat) | ⏳ IndexedDB | ✅ SQLite | ⏳ SQLite | ⏳ Room | One corpus, per-platform reader |
| Live generation from any Wikipedia topic | ⏳ | ✅ | 🚫 | ⏳ | Powers Create + corpus fallback |
| Template engine + quality gates | ⏳ JS | ✅ Swift | ✅ (shared Core) | ⏳ Kotlin | Mirrors `tools/corpus/generate_corpus.py` |
| Wikidata SPARQL validation layer (the moat) | 🔮 | 🔮 | 🔮 | 🔮 | Top corpus priority (QUESTION-QUALITY gates 2,4,5,6,7) |

---

## 3b. Records, sharing, multiplayer

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Personal bests + lifetime stats | ⏳ | ✅ | ⏳ | ⏳ | SwiftData on Apple; IndexedDB/Room elsewhere |
| Daily streak + missed-fact review | ⏳ | ✅ | ⏳ | ⏳ | Spaced re-asking is data-ready |
| Compete vs. your past self | ⏳ | ✅ | ⏳ | ⏳ | New-best detection on each game |
| Share score (NO X/Twitter) | ⏳ Web Share | ✅ ShareLink | ✅ QR | ⏳ Sheet | Decision 022 |
| Leaderboards | 🔮 Supabase | ⏳ Game Center | ⏳ Game Center | 🔮 Play Games | Apple: GameKit wired, ASC config pending |
| Achievements | 🔮 | ⏳ Game Center | ⏳ Game Center | 🔮 Play Games | |
| Local pass-and-play | 🔮 | ✅ | ⏳ | 🔮 | 2–4 players, shared fair question set, hand-off + scoreboard |
| Spaced re-asking of missed facts | ⏳ | ✅ | ⏳ | ⏳ | Due misses woven into solo games (skips Daily); resolve on correct |
| Haptic feedback | n/a | ✅ | n/a | ⏳ | Correct/wrong/milestone; Settings toggle |
| Settings (haptics, reset, attribution) | ⏳ | ✅ | ⏳ | ⏳ | Toolbar gear → sheet, not a tab |
| Async head-to-head / groups | 🔮 | ⏳ Game Center | ⏳ | 🔮 | Async > real-time for survivability (ROADMAP) |
| Living-room mode (phone-as-buzzer) | 🔮 controller | n/a | ⏳ host | 🔮 controller | The biggest open market gap (ROADMAP #4) |
| Cross-platform online | 🔮 | 🔮 | 🔮 | 🔮 | Supabase, after Apple online proves out (Decision 020) |

---

## 4. Authentication + profile

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Sign in with Apple | ✅ | ✅ | ✅ | 🚫 | Apple ecosystem; Android uses Sign in with Google instead |
| Sign in with Google | 🔮 | 🔮 | 🚫 | ✅ | Android Credential Manager one-tap; web GIS when sync ships |
| Email/password | ✅ | ✅ | 🚫 | ✅ | Typing a password with a Siri Remote is hostile — tvOS uses SiwA only |
| Biometric gate for sensitive actions | n/a | ✅ Face ID | n/a | ✅ BiometricPrompt | |
| Account deletion | ✅ | ✅ | ✅ | ✅ | App Store + Play review requirement when sign-in exists |

Sign-in is **optional and gates only sync** — every browse/use verb
works signed-out on every platform (see `per-ecosystem-sync-islands`).

---

## 5. Universal Links / App Links / deep linking

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Universal Links / App Links (HTTPS) | n/a | ⏳ | n/a | ⏳ | `/.well-known/` files; tvOS has no Safari hand-off — custom scheme only |
| Custom scheme | n/a | ⏳ | ⏳ | ⏳ | `appname://` — tvOS needs it for Top Shelf + Siri deep links |
| URL params reflect filter state | ✅ | n/a | n/a | n/a | Web-specific affordance |
| Canonical share URLs (`https://…/item/{id}`) | ✅ renders | ✅ emits | ✅ emits (QR code — a TV can't "send" a link) | ✅ emits | Web is the landing twin for every native share (DEEP_LINKS.md) |

---

## 6. Notifications

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Push notifications | 🚫 | 🔮 APNs | 🚫 | 🔮 FCM | Web push too inconsistent; TV notifications are hostile in a living room |
| Cross-platform dispatcher | n/a | 🔮 | n/a | 🔮 | One Worker, two transports (APNs + FCM) — symmetric payload |
| Notification permission request | n/a | 🔮 | n/a | 🔮 | At opt-in moment, NOT app launch |

---

## 7. Payments / subscription

| Feature | Web | iOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| In-app purchase | n/a | 🔮 IAP | 🔮 IAP (same StoreKit) | 🔮 Play Billing | |
| Web subscription | 🔮 | n/a | n/a | n/a | Stripe / Paddle when scoped |
| Cross-platform subscription state sync | 🔮 | 🔮 | 🔮 | 🔮 | Webhooks → `user_subscriptions` table |

---

## 8. Backend services / shared data plane

All clients consume the same backend / published data. List the
canonical services and assets here so references stay aligned.
If the app has a content data plane, the full contract lives in
`docs/DATA-CONTRACT.md` — this table just indexes it.

| Service / asset | Purpose | Where | Consumed by |
|---|---|---|---|
| <!-- e.g. catalog.sqlite.zz | full content DB, query-on-disk | GitHub Release (rolling) | iOS, tvOS, Android download+inflate; web via index --> | | | |

---

## 9. Web-specific affordances

These are web-only by design; other platforms handle the same
need natively.

| Feature | Web | Why |
|---|---|---|
| URL params reflect filter state | ✅ | Shareable deep links; native apps use in-memory state |
| Web Share API + clipboard fallback | ✅ | iOS/Android use the system share sheet; tvOS shows a QR code |
| View Transitions API (cross-view) | ✅ | iOS uses `.navigationTransition(.zoom)`; Android `sharedBounds` |
| Container queries on components | ✅ | Native platforms use size-class branching |
| Installable PWA + offline shell | ✅ | The zero-install reach play; stores cover the rest |

---

## 10. iOS-specific affordances

| Feature | iOS | Why |
|---|---|---|
| Liquid Glass tab bar / toolbar | ✅ | Web uses `backdrop-filter`; Android M3 tonal elevation |
| Live Activities / Dynamic Island | 🔮 | No equivalent elsewhere — accept the asymmetry |
| WidgetKit home-screen widgets | 🔮 | tvOS analog is Top Shelf; Android analog is Glance widgets |
| Hardware-keyboard shortcuts | ✅ | Web n/a (browser conflicts); Android Ctrl+1..5 on tablets |
| Picture-in-Picture + background audio | 🔮 | tvOS PiP exists but TV apps suspend in background |

---

## 11. tvOS-specific affordances

These are ten-foot / lean-back idioms by design. The general rule:
**idle/ambient surfaces belong to lean-back devices** (TV first,
iPad/tablet/desktop second, phones rarely).

| Feature | tvOS | Why |
|---|---|---|
| Top Shelf extension | ⏳ | The marquee surface when your icon is focused on the TV home screen; reads an App Group snapshot the app refreshes via `BGAppRefreshTask` |
| Siri "Up Next" via NSUserActivity | ⏳ | System watchlist integration — tiny code surface |
| App Intents voice launches ("surprise me") | ⏳ | Pairs with any random/serendipity verb |
| Focus-driven UI (no pointer, no touch) | ✅ | The defining constraint — see `tvos-platform-patterns` |
| Idle screensaver / ambient mode | 🔮 | Lean-back idiom; opt-in, never over playback |
| Layered parallax app icon (imagestack) | ⏳ | tvOS icons are layered; see `branding/README.md` |

---

## 12. Android-specific affordances

| Feature | Android | Why |
|---|---|---|
| Predictive back gesture | ⏳ | iOS swipe-back is fixed-animation; Android is user-driven |
| Adaptive icon (foreground / background / monochrome) | ⏳ | iOS uses static; tvOS uses layered imagestack |
| App Shortcuts (long-press app icon) | ⏳ | iOS has AppIntents; tvOS has Top Shelf |
| Material You dynamic color (opt-in) | ⏳ | Other platforms have brand-only theming |
| Google Cast sender | 🔮 | AirPlay analog; needs Cast SDK + device-tested receiver |
| 16 KB page size support | ⏳ | Mandatory for new releases targeting Android 15+ |

---

## Maintenance protocol

When you ship a feature:

1. Find the row in this table. Add new rows under the right section
   if needed.
2. Update each platform's status with one of the legend symbols.
3. Link to the relevant section of the platform's binding design doc.
4. Note any platform-specific deltas in the Notes column.

When a feature ships on one platform but is meaningfully different
elsewhere, add an entry to §9 / §10 / §11 / §12.

When a platform explicitly rejects a feature, add an "Out of scope"
row in the relevant design doc and link from this table.

**Run a parity audit** (the `cross-platform-parity-discipline` skill,
"audit" mode) before any launch wave and roughly once per milestone:
walk the shipped feature list per platform and verify every cell is
honest. Real audits on shipped apps have found both missing rows
(features nobody recorded) AND false cells (a "synced" claim that
never actually synced) — the audit is what keeps this file true.
