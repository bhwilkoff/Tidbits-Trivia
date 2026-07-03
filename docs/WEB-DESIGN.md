# Tidbits Trivia — Web Design (BINDING)

**Binding.** Quote the rule number before proposing any new view, tab,
card, modal, or data path in the web app. If no rule fits, propose a NEW
rule first. Companion to `PARITY.md`, the sibling design docs, and
`web-platform-patterns` (the mechanics this doc does not restate: view
system, service worker, CSS gotchas, headless verification). The
platforms share *verbs*, never *idioms*; when a rule below inverts a
sibling rule, that inversion is deliberate.

The web app is the **canonical link target** for shares from every
native platform — every `tidbits://…` has an `https://…` twin
(`DEEP_LINKS.md`).

## §1 Principles

- **§1.1 The web feels like the web.** Zero install, shareable,
  phone-first, works from a cold URL. Never port an iOS/tvOS chrome
  pattern; use the platform's own primitives (`<dialog>`, Popover API,
  `:has()`, container queries) before any custom JS
  (`native-platform-first`).
- **§1.2 No framework, no build step.** Vanilla HTML/CSS/JS in `/`,
  served raw by GitHub Pages (`main`, root). Revisit only if the app
  passes ~20 components.
- **§1.3 State stays in the browser.** Records, streaks, presets, and
  the review queue live in `localStorage` via `js/store.js` — no
  backend, no analytics, no third-party scripts. All API calls go
  through `js/api.js`; nothing else calls `fetch` directly.
- **§1.4 Mobile-first density.** Every media query is `min-width`; test
  375px before 720px. Density comes from removing chrome, not adding it
  (`mobile-first-density-design`). The one wide breakpoint caps `.main`
  at 680px centered (`styles.css:293`).
- **§1.5 Learning first.** Records exists so a player can revisit what
  they missed and compete against their past self — a door to curiosity,
  not a scoreboard dump (CLAUDE.md "Why we build").

## §2 Shell & routing

- **§2.1 Three content tabs, hard set: Play · Create · Records**
  (`TABS = ['play','create','records']`, `app.js:17`). Settings is NOT a
  tab — it is a section at the foot of Records (`settingsSection`,
  `app.js:603`). *(Parity note: iOS/tvOS/Android order the middle two
  Records·Create; web is Create·Records. Harmonize deliberately or leave
  noted — do not silently flip.)*
- **§2.2 One render path.** `render()` swaps `<main>` to
  `viewHome()`/`viewCreate()`/`viewRecords()` and calls the matching
  `bind*()` to wire events (`app.js:50-53`). A view's event handlers are
  (re)bound on every render; per-view listeners must not leak across
  swaps.
- **§2.3 Canonical share URLs are paths** (`/item/…`, `/daily`, etc.),
  forwarded into the app by `404.html`. The native Share buttons emit
  these — never change the shape; shipped apps depend on it
  (`DEEP_LINKS.md`).
- **§2.4 Deep links and game launches never leave the SPA shell.** A
  round runs inside the same document (the `.game` surface), not a new
  page.

## §3 Surfaces (the only allowed shapes)

- **§3.1 Home** = one Quick Play hero (`.banner.hero`) → Surprise /
  Customize pair → Daily card → Trivia Night card → "More ways to play"
  tiles → native-app promo foot (R-HOME-1, `styles.css:329`). One
  primary action; pickers live in the Customize modal.
- **§3.2 Records** = the dashboard (§5). **A summary, never a full
  ledger.**
- **§3.3 Create** = topic field → generated quiz.
- **§3.4 Card list** = a vertical stack of `.card`s. The canonical
  content surface.
- **§3.5 Grid** = `.cat-grid` / chip grids for pickers (`1fr 1fr`,
  widening to 3-up at 720px).
- **§3.6 Game** = the `.game` flex column (HUD → question → options),
  one surface for every mode.
- **§3.7 Modal** = `<dialog showModal>` ONLY (the Records drill-in
  sheets, Customize, Night entry). **No `position: fixed` overlays** —
  they break Safari's compositor at the Dynamic Island (§7.2).

## §4 The chunky card (`.card`) — binding

The 90s-sticker surface: thick ink border + a hard 5px offset shadow,
baked into `.card` (`styles.css:52-56`).

- **§4.1 Every stacked chunky element carries a bottom gutter that
  CLEARS the shadow.** `.card`/`.banner`/`.btn`/`.tile` all draw
  `box-shadow: 5px 5px 0`, which bleeds into whatever follows. A
  `margin-bottom` (or parent gap) of merely the shadow height reads as
  "squished" — use ≥ ~16px so there is real air, not a 3px sliver. This
  bit twice on 2026-07-03: the `.game-row` history cards shipped flush
  (no margin), and Home's `.banner` (8px) + `.quick-actions` (0) let the
  Quick-Play/Surprise/Daily shadows collide. Every stacked element gets a
  gutter; none is exempt.
- **§4.1a The top bar fits its narrowest target.** Brand + all three tab
  labels must fit at 360px (mobile-first compact sizing), scaling up at
  ≥480px — never let a tab clip off-screen (the "Records tab cut off"
  bug).
- **§4.1b A one-item grid fills its row.** `.home-tiles` uses
  `auto-fit`/`minmax` so the single web tile spans full width instead of
  sitting half-width beside an empty column.
- **§4.2 One canonical cell per list** (small multiples): every history
  row is `.game-row`, every domain row is `.topic-row`, every answer is
  `.ans-line`. A variant folds back with a class, not a new layout.
- **§4.3 Row padding is consistent and generous.** Row cards use ≥14px
  internal padding; content never butts against the border. Feature
  cards (hero, banners) use 18–20px.

## §5 Records — a dashboard, not a ledger (rule R-REC-1)

Mirrors iOS-DESIGN §5.3–5.6 as the web idiom.

- **§5.1 Records summarizes and drills in; it never dumps.** The tab
  shows an at-a-glance summary; detail lives behind drill-in modals
  (`openRecap`/`openDomain`/`openBests`, `app.js:704-730`).
- **§5.2 Fixed order:** streak banner → lifetime stat row → recent games
  (bounded) → "Your knowledge" → calibration (if any) → personal bests →
  facts to review (bounded) → Settings.
- **§5.3 Progressive disclosure is the core rule.** Each long list shows
  a **bounded preview + a "See all" affordance** opening the full set in
  a `<dialog>`:
  - **Recent games**: show the **3 most recent**, then "See all N games"
    opening the full history in a modal. Never `recs.slice(0, 40)`
    inline (`app.js:623`) — that inline dump is the kitchen-sink bug.
  - **Personal bests**: one row per mode actually played.
  - **Your knowledge**: the 7 domains shown in full (bounded, and the
    learning surface); each drills into a domain modal.
  - **Facts to review**: cap the inline preview (≤8).
- **§5.4 The full-history modal is a light list**, not 40 shadowed
  cards — divider/row separation, no per-row hard shadow (density §1).
- **§5.5 Drill-ins are `<dialog>` modals, never new views** (§3.7). A
  row that opens detail shows a chevron; one that doesn't, doesn't.

## §6 Look

- **§6.1 Tokens are CSS custom properties in `:root`** (`styles.css:5`),
  in lockstep with the Apple `Design.swift` palette (the DESIGN table in
  CLAUDE.md). Warm cream `--color-bg`, ink text, the six pops. Never a
  seventh hue.
- **§6.2 Brand vs semantic split is absolute.** `--color-primary`
  (coral) = CTA/chrome; `--color-accent` (blue) = links/interactive;
  `--color-mint`/`--color-primary` = correct/wrong *content* meaning; a
  category's pop = *content* meaning only. Never a brand color for
  meaning, never a semantic color as chrome.
- **§6.3 Six type levels** (`.page-title`/`.section`/`.body-strong`/
  body/`.muted`/tabular). System rounded font stack — **no webfonts** (no
  build step, no FOUT). Refuse a seventh level.
- **§6.4 Density from removing chrome**: a card is its content plus at
  most one meta line. No decorative dividers where spacing suffices.

## §7 Platform truths (Safari + PWA)

- **§7.1 Layout skeleton is fixed:** `body { height: 100dvh; display:
  flex; flex-direction: column; overflow: hidden; }` + `.main { flex: 1;
  overflow-y: auto; min-height: 0; }` (`styles.css:26-46`). NO
  `viewport-fit=cover`.
- **§7.2 No `position: fixed` overlays** — modals are `<dialog>`; toasts
  are `position: absolute` inside the scroll container (`styles.css:273`).
- **§7.3 Service worker**: shell cache-first; **bump the SW cache
  version on every shipped change** (`web-platform-patterns`).
- **§7.4 Image fallbacks retry** on jittered backoff before a local
  typographic placeholder — never a broken tile (picture-round art,
  `styles.css:167`).

## §8 Parity discipline

- **§8.1** Update `PARITY.md` in the same change set as any user-facing
  feature; proposals/commits quote these rule numbers.
- **§8.2** A feature that lands differently from a sibling is the native
  *web* idiom of the same verb — name the rule it mirrors or inverts.
- **§8.3 Headless-verify before "done"** — real JS in a Node DOM shim +
  pixel-measured screenshots; headless Chrome's virtual-time budget
  distorts timers (`web-platform-patterns`).
