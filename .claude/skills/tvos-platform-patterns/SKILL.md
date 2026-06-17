---
name: tvos-platform-patterns
description: Use before any tvOS UI / focus / layout / animation / image-pipeline / persistence work. Captures the load-bearing patterns that the generic SwiftUI / iOS skills do NOT cover — focus engine API decision tree, sidebar / hero / shelf / detail / search / playback recipes, ten-foot type & color rules, the writable-directory trap (Caches + App Group only; the simulator won't warn you), and the gotchas that cost real iteration time (`buttonStyle(.plain)` destroying focus, stacked-banner carousels trapping focus, `@Query` cascading "Cannot find X in scope" errors, defaultFocus vs. onAppear racing). Triggers on tvOS, Apple TV, Siri Remote, focus engine, hero carousel, shelf row, ten-foot UI, "the focus is wrong", focusable, defaultFocus, prefersDefaultFocus, focusSection, hoverEffect, .card button style, Top Shelf, NSUserActivity, AVPlayerViewController, ten-foot, 10ft, dark-first, 29pt.
---

# tvOS Platform Patterns

A compact reference for building tvOS 17+ apps. Captures the rules that don't fit anywhere else — most of the generic SwiftUI/iOS skill content applies on tvOS, but **focus, the Siri Remote, ten-foot typography, the image pipeline at 4K, persistence, and the sidebar/hero/shelf/detail/search/playback shape** are tvOS-specific and have to be learned the hard way otherwise.

For depth — canonical animation values, the full image-loader implementation, layout measurement tables, player-metadata suppression — see `references/production-deep-dive.md` in this skill. It doubles as the seed for a project `docs/tvos-playbook.md` once your tvOS app passes ~3 core screens.

## When to invoke

- Building or debugging any tvOS view
- Focus is wrong: skipping items, trapping, lighting the wrong thing, not landing where you want on appear
- Image render is slow or blurry on Apple TV
- Touching a `Button` and discovering it's not focusable
- Designing a Home / Browse / Detail / Player screen
- Anything writing to disk (the writable-directory trap)
- Wiring App Intents, NSUserActivity (Up Next), or Top Shelf
- Anything that involves the Siri Remote's directional surface, play/pause, or back

If the question is purely about SwiftUI patterns (state, view composition, environment) and would apply on iOS too, use the generic SwiftUI skills. This skill is the **tvOS-only complement**.

---

## Five unbreakable rules (the backstops)

1. **Dark-first, 29 pt body floor, 90/60 safe area.** Light themes lose; body text under 29 pt is unreadable at 8–12 ft.
2. **Back is sacred — never intercept outside player / modal.** App Store Guideline 4.0 treats reassignment as rejection risk.
3. **Reachability contract.** Every focusable element is reachable from every other via directional arrows, in every direction that has content.
4. **No `.buttonStyle(.plain)` on tvOS.** It destroys focusability silently. Use `.borderless` + custom focus treatment, or `.buttonStyle(.card)`, or a custom `ButtonStyle` that reads `@Environment(\.isFocused)`.
5. **Preserve focus across state changes by stable identifier, not by index.**

---

## Persistence — the writable-directory trap (device-only crash)

tvOS apps **cannot write to Application Support or Documents** — only `Library/Caches`, `tmp`, and App Group containers. The SIMULATOR is lenient and lets Application Support writes through, so this bug **passes every simulator test and crashes only on real hardware** (`NSCocoaErrorDomain 513`, EPERM).

- Never `FileManager.url(for: .applicationSupportDirectory, …, create: true)` — it throws on device. Use `FileManager.urls(for: .cachesDirectory, …)` (non-throwing) for any file cache. Re-fetchable data belongs in Caches anyway.
- Never `try!` a directory/file creation — a permissions error becomes a fatal crash.
- **SwiftData/Core Data's DEFAULT store is Application Support → `.modelContainer(for:)` crashes on device.** Build the container explicitly: App Group `ModelConfiguration` first (writable, persistent, shared with a Top Shelf extension), then plain, then in-memory — so the app always launches.
- The App Group container is the right home for anything that must persist (user state, Top Shelf snapshot). Caches can be purged under pressure — treat as performance cache, not source of truth.

---

## Focus engine — the API surface

| API | Role | When to use |
|---|---|---|
| `@FocusState` (Bool) | Single focusable's state | Only one item being programmatically focused |
| `@FocusState` (enum) | Multi-target in one scope | 2+ possible focus targets |
| `.focused($state)` / `.focused($state, equals: .x)` | Bind a view to FocusState | Read and drive focus programmatically |
| `.focusable()` | Make a non-interactive view participate | Custom views — `Button`s are focusable for free |
| `.focusEffect()` / `.focusEffectDisabled()` | Custom focus treatment / suppress system halo | When rendering focus yourself via `@Environment(\.isFocused)` |
| `.focusSection()` | Mark a container as a traversal unit | Sidebar, content pane, each shelf — use for irregular layouts |
| `.focusScope()` + `@Namespace` | Reset-able focus boundary | Modal roots where `defaultFocus` should retarget on re-entry |
| `.defaultFocus($state, .value)` | Declarative initial focus | **Preferred** over imperative `onAppear` (avoids race) |
| `.onMoveCommand` / `.onExitCommand` / `.onPlayPauseCommand` | Intercept Siri Remote commands | Sparingly — only when the focus engine wouldn't consume them |
| `.hoverEffect(.highlight \| .lift)` | System focus treatment | `.highlight` for poster art, `.lift` for buttons/text — don't stack with custom scale |
| `@Environment(\.isFocused)` | Read current view's focus | In `PrimitiveButtonStyle` / custom styles |

The engine is **geometric, not hierarchical**: it scores all on-screen focusables in the pressed direction by angle + distance. `.focusSection()` changes the scoring to treat containers as traversal units; it is a hint, not a wall.

### Decision tree — "I need X focus behavior"

- **One initial focus on appear?** → `.defaultFocus($state, .x)`. Not `onAppear` — that races. If the view loads data, gate with `if !items.isEmpty`.
- **Set focus after data loads?** → `.task { focus = .x }` or `.onChange(of: items)`.
- **Refocus on each modal re-entry?** → `.focusScope($ns)` + `.defaultFocus(_, in: ns)`.
- **Custom view that needs focus?** → `.focusable()`, or wrap in a `Button` and style it.
- **Sectioned layout traverses weird?** → `.focusSection()` on each container — on the CHILDREN, never also the parent (they conflict).
- **Card renders its own focus state?** → `.focusEffectDisabled()` + `@Environment(\.isFocused)` in the style.

---

## Gotchas that cost real iteration time

- **`.buttonStyle(.plain)` destroys focusability.** Silent. Looks correct on iOS, dead on tvOS.
- **A carousel is ONE focusable surface whose content swaps — never a ZStack of all pages.** `opacity(0)` and `allowsHitTesting(false)` do NOT remove focusability; N stacked banners bound to one `@FocusState` register as N overlapping focus candidates and the geometric engine can't route into the hero — focus gets stuck below. Render only the current banner (`.id(item)` + `.transition`).
- **Claim initial focus exactly once** (a `hasClaimedInitialFocus` guard). A bare `.task { focused = true }` re-fires when a lazy hero is recycled on scroll and yanks focus back mid-browse.
- **`.focusSection()` on the hero AND each shelf row; never on the outer ScrollView/LazyVStack.** Sectioning each row is what lets vertical moves jump row-to-row regardless of horizontal scroll position.
- **Never put a fill-mode image (`scaledToFill`) in a `frame(maxWidth: .infinity)`** — the frame ADOPTS the oversized cover size and blows the layout, intermittently (depends which artwork loads). Ambient/hero art goes in `.background` + `.clipped()`, which can't influence layout.
- **`@Query` macro in a view can cascade "Cannot find X in scope" errors across other views in the same file** (macro expansion confuses SourceKit). Move data fetching out of that view.
- **SourceKit phantom errors are stale index, not real.** Trust `xcodebuild`, not editor squiggles.
- **`defaultFocus` race on first appear** if you also imperatively focus in `onAppear`. Pick one.
- **`NavigationPath` bleeds across tab switches** unless you reset it when the user leaves the tab via the sidebar.
- **`Text("\(intValue)")` adds a locale grouping comma** — a decade renders as "1,960s" (`LocalizedStringKey` formats Ints). Use `Text(verbatim:)` or `Text(String(n))` for years/IDs.
- **Pushing `AVPlayerViewController` via SwiftUI `fullScreenCover(isPresented:)` with the item in separate `@State` races** (cover renders empty/black). Use `fullScreenCover(item:)`.
- **The "wrong year" above the player scrubber is the MP4's embedded `creation_time`, not your metadata** — see the deep-dive for the `externalMetadata` override recipe.

---

## Shape recipes (the load-bearing screens)

### Sidebar / nav
- 5+ destinations → sidebar (`TabView(.sidebarAdaptable)` on tvOS 18+/26; manual HStack + `.focusSection()` per child on tvOS 17). 3–4 → top tabs.
- Settings is a sidebar footer item or Home toolbar destination, not a peer content tab.
- Reset each tab's `NavigationPath` when the user leaves the tab.

### Hero carousel
- 7–8 s rotation, crossfade (0.6–0.8 s), subtle Ken Burns (1.00 → 1.05 over the dwell). Pause on focus entry.
- Title + category + year/runtime. **No synopsis** at 10 ft.
- Randomize the pool per launch from top-N; one focusable surface (see gotcha above); claim focus once.

### Shelf row
- Card 200×300 pt portrait / 380×214 pt landscape; 30–40 pt gaps; ≥80 pt between rows (the 1.1× focused card must not collide).
- Title under card **on focus only** (cleanest), or always-visible 1 line at 20–22 pt.
- Focus effect: scale 1.08 + soft shadow (radius 20, opacity 0.3) + accent glow. `.scrollClipDisabled()` so the bloom isn't clipped.

### Detail screen
- **Auto-focus Play on entry** (the #1 complained-about miss in shipping apps).
- Full-bleed backdrop top ~45–60% (in `.background`!). Poster lower-left, metadata right. Play pill at the seam (~Y=55%). "More Like This" shelf at bottom. Back = pop, don't intercept.

### Search
- `.searchable` — directional keyboard + free Siri dictation. Live results. Never invent a grid keyboard.

### Playback
- `AVPlayerViewController` baseline, minimal custom chrome. Persist timecode (not percent). For unreliable origins, see `resilient-media-streaming`.

---

## Ten-foot rules

- **Type**: 29 pt body floor; ramp 76/57/48/38/29/23. System tokens only — Dynamic Type does not exist on tvOS; Bold Text is honored automatically.
- **Safe area**: 90 pt horizontal, 60 pt vertical, constant across 1080p/4K.
- **Color**: dark-first. Reserve brightness for the focused element. ~7:1 contrast for text on hero art (couch glare eats 1.5–2 stops).
- **Motion**: gate parallax/auto-rotate/springs on `accessibilityReduceMotion`. Never animate blur radius; budget ~20 shadowed views.
- **Touch-target → focus-reach.** Think in arrow presses, not finger points.

---

## Image pipeline at 4K

- Match decoded size to displayed size at @2x (a 240×360 pt card needs 480×720 px decoded, not the 1500×2250 source).
- ImageIO one-pass downsample (`CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceShouldCacheImmediately: true` — decode NOW, not at draw).
- Cache decoded `UIImage`s (NSCache, cost-limited); coalesce in-flight loads; prefetch from the data source (focus-direction: `[i+1…i+6]` high, `[i-2…i-1]` low).
- AsyncImage is wrong for poster grids (no prefetch, decode-on-draw hitches, re-downloads on identity churn). Full loader implementation in the deep-dive.

---

## Remote, App Intents, Top Shelf

- Back contract: tab root = exit app; stack = pop; modal = dismiss; player = exit. All system — don't touch.
- Play/Pause on a focused media card = start playback (`.onPlayPauseCommand` on the card). In the player, AVKit handles it.
- App Intents + `AppShortcutsProvider` for "Hey Siri, [verb]" — pairs naturally with surprise/random verbs.
- NSUserActivity on Detail → "add this to my Up Next."
- Top Shelf: separate extension target, `.sectioned` style, reads an App Group snapshot the app refreshes via `BGAppRefreshTask`. Deep links route through the same intent inbox as everything else.
- RTL: use semantic `.leading`/`.trailing` in `onMoveCommand` logic, never physical left/right.

---

## When to bootstrap a project playbook

Once your project has ≥ 3 of {Home / Browse / Detail / Player / Search}, the patterns above need project-specific adaptations (shelf taxonomy, hero pool, per-tab focus contract). Bootstrap `docs/tvos-playbook.md` from `references/production-deep-dive.md` and record the project's concrete choices with decision references.

## Sources

- Apple HIG — Designing for tvOS; WWDC20 #10049; WWDC21 #10046 + #10153; WWDC23 #10162; App Store Review Guidelines 2.5.1, 4.0
- Field analysis: Apple TV app (17.2+), Channels, UHF, Plex, Infuse
- Production iteration: Archive Watch (tvOS approved on the App Store, 2026) — the writable-directory trap, the stacked-carousel focus trap, the fill-image layout trap, and the player-metadata lessons all carry commit-level receipts in that repo's `docs/tvos-playbook.md`
