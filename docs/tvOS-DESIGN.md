# Tidbits Trivia — tvOS Design (BINDING)

**Binding.** Every new view, hero, shelf, cover, mode, or focus target
on the Apple TV app must trace to a rule here. When something feels
overwhelming or the focus is wrong, **fix this document first, then fix
the feature.** Proposals (and commits) cite the rule, e.g. "per
tvOS-DESIGN §6.2."

Division of labor:
- **This doc** = the binding contract for the living-room surface: the
  home shell, focus, the dark-first design system, per-surface IA.
- **`tvos-platform-patterns` skill** = the mechanics (focus APIs, card
  sizes, the writable-directory trap) — non-binding how-to.
- **The sibling design docs** = the other platforms. Same verbs, never
  idioms. **The look deliberately inverts iOS/web:** tvOS is dark-first
  (`TVTheme`), not the cream chunky-card sticker book — that inversion is
  load-bearing (§5). Never "harmonize" it.
- **`PARITY.md`** / **`DECISIONS.md`** as elsewhere.

All tvOS UI lives in `TidbitsTrivia/tvOS/*.swift`; Core is consumed
verbatim.

## §1 — Principles

1.1 **Lean-back, then lean-in.** The default is browsing at ten feet.
Every surface works as pure browse but offers a door to curiosity — a
recap of what you missed, a fact, a next round (CLAUDE.md "Why we
build").

1.2 **Focus does the work.** The focused element IS the chrome;
everything else stays quiet. Brightness is reserved for the focused
element on the dark canvas. Density comes from removing chrome
(`mobile-first-density-design`).

1.3 **Back is sacred.** Every cover honors the Menu button via
`.onExitCommand { dismiss() }` (`ContentView_tvOS.swift:46` and every
modal). Never intercept Back outside a game or a modal.

1.4 **Depth is flat: home → cover.** There is no `NavigationStack` in the
shell and no nav pushes; every destination is a `fullScreenCover`
launched from the home page (`ContentView_tvOS.swift:59-98`). A new
destination is a new cover, never a pushed screen. (This inverts iOS's
per-tab stack — deliberate; the remote has no swipe-back.)

1.5 **One shared data plane / no new state without a home** — same as
the siblings (`shared-data-plane-contract`, `per-ecosystem-sync-islands`).

## §2 — Information architecture

2.1 **The shell is ONE scrolling home page, not a tab bar or sidebar**
(`ContentView_tvOS.swift:42`). Fixed row order: header (wordmark +
Records/Settings chips) → Quick Play hero → Surprise/Customize chips →
Daily hero → Trivia Night hero → multiplayer panel (`:46-53`). Inserting
a row means amending this rule.

2.2 **Records and Settings are covers reached from the header chips,**
not tabs. Customize, the Daily archive, game launch, the three night
covers, versus, and Quick Match are all covers off the home page (§1.4).

2.3 **Every row is a `.focusSection()`** so the D-pad jumps row-to-row
cleanly (`:169`, `:192`, `:221`, `:272`). A new row declares its focus
section.

2.4 **Every list/grid/cover declares all four states** (loading · loaded
· empty · error), and **an empty state must contain a focusable
element** or focus traps (the classic tvOS empty-state bug;
`universal-feature-states`). Records' empty state is at
`RecordsView_tvOS.swift:78`.

## §3 — Surface taxonomy

3.1 **Home hero / chip row** — the big Quick Play button and the quiet
chip rows.
3.2 **Shelf** — a horizontal `.focusSection()` row of cards (the
Customize mode/category shelves, `:308`).
3.3 **Cover** — a full-screen `fullScreenCover`; the only push-like
shape. Declares default focus (§6) and Back (§1.3).
3.4 **Game surface** — `TVGameContainer` switching on `game.phase`
(`GameView_tvOS.swift:8`); HUD → prompt → shape panel.
3.5 **Read-only display card** — a `.focusable()` card whose only job is
to let the remote scroll a text page (`TVRecordsCard`,
`RecordsView_tvOS.swift:276`). Required because a ScrollView with no
focusable targets never reveals lower content on tvOS.

## §4 — Typography (binding)

4.1 **Introduce and use a tvOS type ramp — six levels, ten-foot scale.**
tvOS does NOT use `Tidbits.TypeRamp` (13–34pt is unreadable at ten feet)
and today hardcodes `.system(size:)` inline across every file (page
titles 56–76, section 40, body 27–31, caption 20–25). **That repetition
is a violation of "tokens, never hardcode."** Define a `TVType` ramp
(76 / 57 / 40 / 29 / 25 / tabular) and route every `Text` through it.
Body floor is **29pt**; never below 23pt. Refuse a seventh level.

4.2 **No long body text on transient surfaces** (hero, chip, HUD).
Synopsis/recap detail lives on the Records drill-in and the results
recap only.

## §5 — Color & materials (binding)

5.1 **Dark-first `TVTheme`** (`ContentView_tvOS.swift:7`): near-black
`bg 0x0E0C0B`, `panel 0x1C1916`, white text, soft `0xB9AE9F`. This is
the tvOS surface language — **not** the cream `Tidbits.Palette.bg` or the
`chunkyCard` sticker used on iOS/web. Reserve brightness for the focused
element.

5.2 **Category and mode accents come from `Tidbits.Palette`** (the six
pops, shared with every platform) and carry content meaning only;
`legibleForeground` keeps text readable on a pop
(`RecordsView_tvOS.swift:128`). Brand vs semantic split is absolute —
never a brand accent for content meaning or vice versa.

5.3 **Custom `ButtonStyle`s only; every one reads
`@Environment(\.isFocused)`** to draw its own focus ring/scale
(`TVHeroStyle`, `TVChipStyle`, `TVCategoryStyle`, `TVAnswerStyle`).

## §6 — Focus contract (binding; APIs in the skill)

6.1 **Never `.buttonStyle(.plain)`** — it destroys focusability. Use
`.borderless`, `.card`, or a custom `ButtonStyle` (`:423`). This is the
exact inverse of iOS-DESIGN §4.1 — **never port either rule across.**
Preserve focus by stable id, not index.

6.2 **Initial-focus surfaces claim focus with a `hasClaimedInitialFocus`
guard, not a bare `.task`/`.onChange` reassignment.** Today the shell
uses `.defaultFocus` + `onChange` reassignments (home `:58`, game
`GameView_tvOS.swift:158-166`, results `:678`, night setup/live) with
**no claim-once guard anywhere** — a known race (a lazy view recycling
re-fires the reassignment and yanks focus mid-browse;
`tvos-platform-patterns`). New initial-focus surfaces MUST add the guard;
existing ones should adopt it as they're touched.

6.3 **Every cover declares its default focus and its restoration
target** on dismiss.

## §7 — Records (binding)

7.1 **Records is a summarized knowledge map, not a raw ledger** — and it
already is (`RecordsView_tvOS.swift:12`). Fixed order: streak → lifetime
row → recent games (bounded) → "Your knowledge" (7 domains) →
calibration (if any) → personal bests → facts to review (≤8). Keep it
this way; a future "show everything inline" change is the regression this
rule forbids.

7.2 **Recent games are bounded (currently 20) and each is a focusable
card that drills into `TVGameRecapView`** (`:52`, `:321`). Past ~20, the
tail lives behind the drill-in, never expanded inline (the tvOS idiom of
iOS-DESIGN §5.4 "See all").

7.3 **Read-only sections are focusable** so the remote can scroll them
(§3.5) — never a non-focusable text wall.

## §8 — Game & modes (binding)

8.1 **One `GameEngine`, one `TVGameContainer` phase machine** for all 17
modes and Trivia Night (`GameView_tvOS.swift:8`). A new mode is a case +
a focus-driven input panel, never a second engine.

8.2 **Ten-foot input substitutions are the native idiom, not gaps.**
Closest Call uses ±coarse/±fine steppers (no `Slider` at ten feet,
`:338`); type-answer and enumerate are recall-then-self-mark (no
keyboard-heavy entry, `:259`, `:287`). Document each as a PARITY delta
with its reason — same verb, native idiom.

8.3 **Customize exposes all modes except `.daily` and `.barTrivia`**
(they have dedicated heroes, `ContentView_tvOS.swift:329`). One
category per launch; the multi-select Custom Mix builder is phone-only.

## §9 — Persistence (binding)

9.1 **The ModelContainer persists in `Library/Caches`, never Application
Support** — Application Support writes crash on real Apple TV and pass on
the simulator (Decision 017, `App/TidbitsTriviaApp.swift:42`). Fall back
to in-memory so the app always launches.

9.2 **App Group persistence (survive a cache purge) is a known deferred
gap** (`App/TidbitsTriviaApp.swift:34`) — records live in Caches until
the entitlement is wired. Note it; don't silently "fix" by writing to a
trapping container.

## §10 — Out of scope on tvOS (intentional gaps)

Onboarding, the Create/AI-quiz surface, and local Pass-and-Play Party are
phone-first and not on tvOS; the fine-grained per-round Night editor is
phone-only (presets only on tvOS, `NightView_tvOS.swift:67`); universal
`onOpenURL` topic/category routing is not observed by
`ContentView_tvOS` (deep links are effectively iOS/Android). Each is a
PARITY row with a reason, not a silent omission.

## §11 — Anti-patterns (never)

11.1 A tab bar / sidebar / nav push in the shell (§1.4, §2.1). 11.2
`.buttonStyle(.plain)` (§6.1). 11.3 A bare `.task`/`onChange` focus claim
with no `hasClaimedInitialFocus` guard on an initial-focus surface
(§6.2). 11.4 A hardcoded `.system(size:)` outside the `TVType` ramp
(§4.1). 11.5 An empty state with no focusable element (§2.4). 11.6 A raw
per-question Records dump inline instead of the bounded summary + drill
(§7.1). 11.7 Application Support persistence (§9.1). 11.8 A brand accent
for content meaning or a category accent as chrome (§5.2). 11.9 A second
game engine (§8.1).

## §12 — The tests (before any surface ships)

12.1 Competent-designer test — rebuildable from a paragraph? 12.2 Verb
test — colliding with another surface's verb? 12.3 Ten-foot test — does
every glyph read at 29pt+ from the couch, and can the remote reach and
scroll every surface? 12.4 Parity — `PARITY.md` updated same change set;
name the sibling rule mirrored or inverted.

---

## R-CLUB-1 — Tidbits Club has exactly one door (2026-07-29)

The app shows **at most one Club entry point, and it lives on Home**. Every Club
feature is reached from inside that door — never from Home, Records, Settings, or
anywhere else directly. Members get the Club hub; non-members get the paywall,
which is the only surface in the app allowed to make an offer.

**Why:** four Club cards on Home plus three Club "see all" rows in Records made a
mostly-FREE app read as a mostly-paywalled one (owner directive, 2026-07-29:
*"the whole point of Tidbits Trivia is that we are the world's best trivia app
with the least amount behind a paywall"*). The count of visible locks — not the
real free/paid ratio — is what a player perceives as the size of the paywall.

**How to apply:** see `docs/iOS-DESIGN.md` §5.2a–§5.2c for the full rule. The
principle is identical on every platform; only the idiom differs.

tvOS idiom: one quiet `clubHero` row on the home column, below the free
surfaces. The hub is a single `.fullScreenCover`, and its sub-surfaces SWAP
its content rather than stacking a second cover — modal-over-modal is the
trap that broke StoreKit's purchase sheet (Decision 048).
