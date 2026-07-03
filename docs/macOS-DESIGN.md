# Tidbits Trivia — macOS Design (BINDING)

**Status: binding spec — the shell is not yet built.** macOS is the next
platform (Decision 042). Today only a 79-line `NavigationSplitView` stub
exists (`macOS/ContentView_macOS.swift`, placeholder detail columns) and
the app has no macOS `.commands`. This doc is the contract to **build
against**; quote the rule before adding any window, view, sheet, command,
or engine path. Amend, never silently contradict.

Division of labor: **this doc** = the binding macOS contract.
**`macos-platform-patterns` skill** = the mechanics + failure modes.
Shipping/submission = `docs/CLOUD-SUBMISSION.md` +
`cloud-appstore-submission` (`.pkg` signing, `-f platform=mac`) — not
duplicated here. **The Mac app is NOT the iOS app resized** — it is a
pointer + keyboard + menu-bar + resizable-window app that reuses Core
verbatim and rebuilds only the shell.

Tidbits macOS is **parity-only** — a browse/play/records/create face on
the shared Core. There is no Mac-exclusive heavy editor, so this doc has
no "Part A." If one is ever proposed, it earns its own part first.

## §0 — Before the shell compiles (the blocker)

0.1 **`#if os(iOS)`-guard every Core symbol that imports UIKit.** The
concrete blocker is `Core/Services/GameCenterManager.swift`: `import
UIKit` is unguarded (line 3) and it uses `UIViewController` /
`UIApplication.shared.connectedScenes` (lines 133-134) with no guard, and
it is on the launch path (`App/TidbitsTriviaApp.swift:7`). Guard it (and
provide a macOS no-op or `NSViewController`/GameKit-macOS path) before the
Mac destination will build. `Core/Services/Haptics.swift` is already
correctly guarded — follow its shape.

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
