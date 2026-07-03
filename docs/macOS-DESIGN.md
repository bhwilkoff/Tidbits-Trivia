# Tidbits Trivia — macOS Design (BINDING)

**Status: binding — foundation built; shell + Tidbits Live in progress.**
macOS is a live scope (Decision 042). The native Mac target now COMPILES
and LAUNCHES the `NavigationSplitView` shell (foundation committed
2026-07-03); the detail columns are still placeholders. This doc is the
contract to **build against**; quote the rule before adding any window,
view, sheet, command, or engine path. Amend, never silently contradict.

Division of labor: **this doc** = the binding macOS contract.
**`macos-platform-patterns` skill** = the mechanics + failure modes.
Shipping/submission = `docs/CLOUD-SUBMISSION.md` +
`cloud-appstore-submission` (`.pkg` signing, `-f platform=mac`) — not
duplicated here. **The Mac app is NOT the iOS app resized** — it is a
pointer + keyboard + menu-bar + resizable-window app that reuses Core
verbatim and rebuilds only the shell.

The Mac app is **two things** (Decision 043): **PART A — Tidbits Live**, a
Mac-exclusive pub/event trivia emcee system the touch/TV/web platforms
can't host; and **PART B — the parity face** (Play / Records / Create /
Trivia Night / everything iOS+tvOS do). Build order is parity-led: the
Part B shell + core screens first, then Part A layered on top.

---

# PART A — Tidbits Live (the Mac-exclusive event system, BINDING)

*A host/emcee dashboard that runs a live pub/bar/event trivia night: the
Mac drives a projected big screen while teams answer on phones. Grounded in
the competitive research (`docs/EVENT-TRIVIA-COMPETITIVE.md`) and the locked
scope (Decision 043). Every event surface quotes a rule here.*

## §A0 — Thesis & the three locked decisions

A0.1 **Why Mac-only.** An emcee cockpit needs a pointer+keyboard+menu,
multi-window (host cockpit on the laptop, big-screen output on the
projector), local-network hosting, a filesystem for event documents and
printable fallbacks, and long-running live control — things the
touch/TV/web platforms structurally can't host. Do not port a touch idiom
(a full-screen modal builder, one-pane nav) into it.

A0.2 **Serverless (Decision 043).** MVP is single-venue over the local
network + optional Firebase (the online-match transport). **No backend
in v1.** Cross-venue/season leaderboards and venue lead-capture are
deferred until a backend is a deliberate later decision — do not build a
server, and do not design a surface that requires one.

A0.3 **Tidbits-native rounds first (Decision 043).** Formats render in the
sticker-book design language (`chunkyCard`, the six pops, the type ramp) —
NOT game-show boards. Jeopardy/Feud/Wheel "show mode" is Phase C, gated
behind its own rules; never let it leak into the MVP round system.

## §A1 — Scenes & the two-surface split (load-bearing)

A1.1 **Tidbits Live is its own scene family**, distinct from the Part-B
`WindowGroup`. The event opens a **document-backed host window** (the
cockpit) plus a **separate big-screen output window** targeted at the
projector/second display. The cockpit and the big screen are DIFFERENT
views of one live event model — never the same view mirrored (the host
sees controls + upcoming questions + the answer key; the room must not).

A1.2 **The big-screen output is ten-foot UI.** It obeys the tvOS-grade
legibility bar (large type, high contrast, team names + scores readable
across a loud room), reusing the `mobile-first-density-design` "focus does
the work" discipline. It shows only: the current question/media, the QR +
join code, and the team leaderboard — never host-only affordances.

A1.3 **The event is a REFERENCE document, not a copy** (Rule 11: Library ≠
Project). The app-global **question library** (the corpus + the host's
saved questions) is SwiftData; a **saved event** is a `.package`-style
document that *references* library questions + its own edits — it never
re-hosts the corpus. A weekly night is a duplicated event document.

## §A2 — The event builder

A2.1 **An event is an ordered list of named rounds; a round is an ordered
list of questions.** First-class round + question objects (the wedge
against Crowdpurr, which has no round object). Reorder/clone rounds and
questions by drag (native `.draggable`/`.dropDestination`).

A2.2 **Three ways to fill a round, all yielding EDITABLE questions**
(`learning-orientation-design` — never a one-tap finished night): (a) pull
from the 20k+ corpus by category/difficulty; (b) **AI-generate** a themed
round via `DelightfulQuizGenerator`, which the host then edits; (c) hand-
author. Every generated question lands in the editor for the host to
approve/fix — automate the mechanical, preserve the editorial judgment.

A2.3 **Round formats (MVP set), Tidbits-native:** MCQ, True/False, Picture,
Nearest-Wins (numeric — also the tie-break unit), Ordering, Wager (Stake),
Poll/Majority. Audio round and Fastest-Finger (speed scoring) are Phase B.
Each format reuses the existing `GameMode`/question shapes where one maps.

## §A3 — The host cockpit (the emcee's live control — our differentiators)

A3.1 **Host-paced by default; reveal-on-command.** The host advances
questions and triggers the answer/score reveal ("dramatic pause") — never
an auto-timer that outruns the room. An optional per-question timer is a
host choice, not the default.

A3.2 **Manual score override is first-class** (the #1 field gap — almost
nobody ships it). The host can adjust any team's score on any question at
any time, with a visible audit of the change. This is the referee model:
the host is the authority, not the algorithm.

A3.3 **Free-text answers get a review lane with spelling leniency.** Typed
answers are grouped (identical → one row) and the host one-taps
mark-correct/incorrect; near-misses are surfaced for a judgment call. Auto-
matching (alias-based, reusing the corpus's accepted-answer sets) proposes,
the host disposes.

A3.4 **Live answer tally.** The host sees submissions arrive in real time
(counts per option, who's answered) before revealing.

A3.5 **A built-in tie-break engine** (the field punts this). On a tie, the
host triggers a Nearest-Wins numeric prompt (or sudden-death question)
resolved live; the engine breaks the tie and updates standings.

## §A4 — Player join & teams (serverless)

A4.1 **Teams, not solo, are the unit.** Several phones join one team; the
team name shows on the big screen. Join via **QR + short code** to a web
page (zero-install) over the local network; **native-Tidbits-app join is
Phase B** (the moat — deep-link the existing apps). No player app is ever
required.

A4.2 **Reconnect is designed in** (a field weak spot): a dropped phone
rejoins its team by code without losing the team's score.

A4.3 **Player transport reuses the existing serverless stack** (the
Trivia Night mDNS+TCP / Firebase islands) — no new backend (A0.2).

## §A5 — Reliability & integrity (Mac-native strengths — lean in)

A5.1 **Offline-capable.** The event runs on the local network with no
internet dependency; the Mac holds the authoritative event state.

A5.2 **Printable fallback.** Every event exports **printable answer
sheets + a question pack** (the Wi-Fi-dies contingency the field ignores) —
a native `NSPrintOperation`/PDF path.

A5.3 **Cheating deterrence (Phase B):** fast answer-lock windows, a
tab-switch/focus signal from the join page, and a brains-only tie-break —
addressing the #1 host complaint. Never claim more deterrence than shipped.

## §A6 — Out of scope for Tidbits Live v1 (deferred, with reason)

Cross-venue / season leaderboards & venue lead-capture (need a backend,
A0.2); game-show "show mode" boards (Phase C, A0.3); sponsor-ad monetization
& prize/coupon fulfillment (Phase C — decide the monetization stance first);
stream-out to Twitch/YouTube. Each is a `PARITY.md`/backlog row with its
reason, never silently attempted.

## §A7 — Implementation status (2026-07-03)

**Shipped + build-verified** (the MVP, paper-style + the differentiators):
event builder (§A2), host cockpit with reveal-on-command pacing + **manual
score override** + points-per-correct (§A3.1-3.2), the **tie-break engine**
(§A3.5, numeric closest-wins), the **big-screen projector window** (§A1.1/A1.2,
two-window session sharing), **offline** hosting + **printable** question
pack / answer sheet / results PDFs (§A5.1-5.2), and **venue branding** on the
big screen + printed sheets.

**Deferred (need capabilities not available to verify: a serverless
transport + 2-device testing), tracked — not dropped:** networked team JOIN
(QR/web phone submission, §A4.1) + reconnect (§A4.2); the formats that depend
on it — **fastest-finger speed scoring**, **audio round** (also needs audio
content the corpus lacks), **poll/majority**; **cheating deterrence** (§A5.3,
needs the join page's focus signal). These are the same networked gate as the
parity Trivia-Night host/join and online Quick Match. Free-text review (§A3.3)
also lands with networked join (paper mode has no typed answers to review).

---

# PART B — The parity face (Play / Records / Create / everything iOS+tvOS)

*The native-Mac face on the shared Core — pointer+keyboard+menu idioms, NOT
the iOS app resized. Build this shell + core screens first (Decision 043).*

## §0 — Foundation (DONE 2026-07-03)

0.1 **The UIKit compile blocker is guarded.** `GameCenterManager` wrapped
every UIKit presentation seam (`UIApplication`/`UIViewController`/`.present`)
in `#if canImport(UIKit)`; GameKit auth/submit/report stay cross-platform.
The macOS Game Center dashboard (via `GKDialogController`) is a tracked
parity stub. `Core/Services/Haptics.swift` was already guarded — the shape
to follow for any future UIKit-touching Core symbol.

0.2 **`Core/Design/Design.swift` is fully portable** — pure SwiftUI,
no UIKit/AppKit. macOS shares `Tidbits.Palette`, `TypeRamp`, `Metric`,
`chunkyCard`, and `ChunkyButtonStyle` verbatim (§5). No separate Mac
palette.

0.3 **Build the Mac destination as part of "done"** whenever a shared
Core file changes — a green iOS build is not proof the Mac slice compiles
(the phantom-error trap, `macos-platform-patterns`).

## §1 — Principles

1.1 **Mac-native, not iOS-resized.** Sidebar navigation, menu-bar
commands, keyboard shortcuts, resizable multi-window. Reuse Core (the
game engine, `AppStore`, `RecordsStore`, the corpus, sync); rebuild only
the shell.

1.2 **Same verb, Mac idiom.** The three verbs (Play / Records / Create)
match the siblings; the expression is a `NavigationSplitView` sidebar +
a single detail column, `.commands`, and pointer/keyboard affordances.

1.3 **Density from removing chrome** (`mobile-first-density-design`) — a
resizable window tempts sprawl; resist it. The Records dashboard rule
(§4) is binding on macOS too.

1.4 **One shared data plane + sync island.** Same corpus, same App Group
models, same CloudKit private DB (`per-ecosystem-sync-islands`).

## §2 — Scene graph & navigation (binding)

2.1 **Shell = `NavigationSplitView`**, a sidebar `Section` enum
(`SidebarSection`: play · records · create, already stubbed
`ContentView_macOS.swift:64`) feeding ONE `NavigationPath` into a single
detail column — **NOT** the iOS per-tab stack. A new sidebar row amends
this rule.

2.2 **Settings rides the app menu (`⌘,`), never a sidebar row**
(`ContentView_macOS.swift:61` comment). Menu-bar `.commands` are
first-class: `⌘N` starts a new game, `⌘,` opens Settings. Declare them in
the App scene (not yet present — `App/TidbitsTriviaApp.swift` has no
`.commands`).

2.3 **Deep links (`.onOpenURL` + Handoff) resolve into the detail
column** via the shared inbox — never mutate the sidebar selection from
outside the view tree.

2.4 **`minWidth`/`minHeight` on the main window** so the sidebar +
detail never collapse into an unusable strip.

## §3 — The game surface (the "player" analog, binding)

3.1 **A game in progress REPLACES the window root** — never an
`.overlay`/`.fullScreenCover` on the split view. An overlay leaves the
split view owning the window toolbar, so its sidebar toggle and the prior
view's title bleed through over the game. As root, the game's own close
button is the only chrome. (The iOS game-cover pattern maps to "swap the
window root" on Mac; `macos-platform-patterns`.)

3.2 **One `GameEngine`, one game surface** for all 17 modes, reused from
Core. Input is pointer + keyboard (number keys pick MCQ options, Return
submits, Esc closes) — the Mac idiom of the same verbs, not touch.

## §4 — Records (binding)

4.1 **Records is a dashboard, not a ledger** — build it to iOS-DESIGN
§5.3–5.6 from day one (don't port the iOS/Android inline-dump bug to a
new platform). Fixed order: streak → lifetime row → recent games
(bounded, 3 + "See all") → Your knowledge → calibration → personal bests
→ facts to review. Drill-ins are sheets or detail-column pushes; the
"See all" full history is a light `Table`/list, never a wall of chunky
cards.

4.2 **A wide window shows more columns, not longer rows.** Use the extra
width for a two-column dashboard (summary + selected detail) before ever
lengthening a single scroll — a resizable window is the affordance the
phone lacks.

## §5 — Look (binding)

5.1 **Shares `Tidbits.Palette` + `chunkyCard`** verbatim (§0.2) — the
cream sticker-book identity, same as iOS/web (NOT dark-first like tvOS).
`chunkyCard` reserves its own shadow gutter (iOS-DESIGN §7.1) — the same
rule holds; never hand-add shadow padding at a call site.

5.2 **Any hero/banner is full-width, aspect-*fit*, with NO `maxHeight`
cap** (the fill-image trap): a fixed height crops as the window widens; a
`maxHeight` cap insets it. Art rides `.background`/`.overlay` +
`.clipped()`, never a fill-image child in a `maxWidth: .infinity` frame
(`macos-platform-patterns`).

5.3 **Category/round art routes through one `ImagePipeline`** (decoded
`NSCache` + a capped `URLSession`), never bare `AsyncImage`; decode
non-RGB → sRGB once (`Image(nsImage:)`'s Metal path renders grayscale as
a white box). Only relevant once picture-round art shows on Mac.

5.4 **Six type levels from `Tidbits.TypeRamp`; brand vs semantic split
absolute** — same as iOS-DESIGN §8–§9.

5.5 **Replace any Combine `Timer.publish` with `.task(id:)` loops** in
views (a Combine timer into a `@MainActor` closure can fault into a
torn-down view on macOS; `macos-platform-patterns`).

## §6 — Capabilities & submission (binding)

6.1 **Shared with the other Apple platforms** (one ASC record): bundle
id, CloudKit container, App Group, Associated Domains.

6.2 **App Sandbox is required for the Mac App Store**: app-sandbox +
network.client (+ any narrow scopes actually used). Hardened runtime, an
app-icon set, `PrivacyInfo.xcprivacy`.

6.3 **Submission is the cloud path plus a 3rd-Party-Mac-Installer cert**
for `.pkg` signing (`gh workflow run appstore-build.yml -f
platform=mac`). The submission tooling (`tools/submit-appstore.sh` +
`asc_profiles.py`) needs a `mac` branch (DEST `generic/platform=macOS`,
`.pkg` export) — a known gap in this scope. See
`docs/CLOUD-SUBMISSION.md`.

## §7 — Anti-patterns (never)

7.1 The iOS app resized / a per-tab stack instead of the split view
(§2.1). 7.2 A game as an overlay/cover on the split view instead of the
window root (§3.1). 7.3 Settings as a sidebar row instead of `⌘,`
(§2.2). 7.4 An unguarded UIKit import reaching the Mac build (§0.1). 7.5
A fill-image hero with a fixed/`maxHeight` frame (§5.2). 7.6 Bare
`AsyncImage` for picture art (§5.3). 7.7 A Records inline dump — build
the dashboard, don't port the bug (§4.1). 7.8 A second game engine
(§3.2). 7.9 Hand-added shadow padding at a `chunkyCard` call site
(§5.1).

## §8 — The tests (before any surface ships)

8.1 Competent-designer test — rebuildable from a paragraph? 8.2 Mac-idiom
test — does this use pointer/keyboard/menu affordances, or is it a
resized phone screen? 8.3 Compile-everywhere test — does the Mac
destination build after this shared-Core change (§0.3)? 8.4 Parity —
`PARITY.md` updated same change set; name the sibling rule mirrored or
inverted.
