---
name: web-platform-patterns
description: Use before any web (vanilla HTML/CSS/JS, no build step, static hosting) UI / routing / data / offline / image work. The web umbrella skill — view-system architecture, URL-driven state + canonical share URLs, the 404-forwarder, image fallback chains with jittered retry, service-worker versioning discipline, IndexedDB schema migration, the CSS gotchas that cost real iteration (sticky containing-box, scroll-snap rails, container-query heroes), bounded fetches, and the headless verification protocol (Node DOM shim, CDN cache-bust). Triggers on vanilla JS, hash router, showView, service worker, PWA, IndexedDB, GitHub Pages, scroll-snap, position sticky, image fallback, 404.html, URL params, AbortSignal, "works locally but not deployed".
---

# Web Platform Patterns

The umbrella skill for the framework-free web app — the patterns that
shipped three production web apps (two as PWAs) on GitHub Pages with
no build step and no backend. Most generic frontend skills cover
components; this covers the **architecture, data, offline, and
deploy-reality layer** that vanilla web apps live or die on.

## The five web backstops

1. **The URL is the state.** Every surface is a shareable URL;
   filters live in the query. If a view can't be reached by URL, it's
   not done.
2. **One router, one data module.** `route()` reads the location,
   `showView(name)` toggles `<section hidden>`; ALL external calls go
   through `js/api.js`. Never `fetch` from view code.
3. **Errors are user-visible, inline.** Console-only errors don't
   exist for users. Empty states are explicit sentences, never blank
   space.
4. **No `position: fixed` overlays; modals are `<dialog showModal>`.**
   (Safari compositor at the Dynamic Island; native focus trap + ESC.)
5. **Mobile-first, `min-width` queries only, test 375px before
   1280px.**

## View system architecture

- Each view is a `<section>`; `showView(name)` toggles `hidden`.
  **Per-view `IntersectionObserver`s are disconnected on every view
  switch** — leaked observers from a previous view fire on recycled
  sentinels and corrupt paging state.
- **Event delegation for dynamic content**: one listener on the
  container switching on `closest('[data-action]')`, not per-element
  listeners that vanish on re-render.
- Infinite scroll = an `IntersectionObserver` sentinel + page size
  (~60); always show the REAL total count, not the loaded count.
- Debounce text search ~180 ms; mirror the query into the URL.

## URL-driven state + the canonical-twin contract

- Hash routes for the SPA (`#/browse?type=x&decade=1930&sort=az`) —
  every filtered view shareable.
- **Canonical share URLs are PATHS** (`/item/{id}`) — the exact URLs
  native apps emit. On a static host, `404.html` forwards paths into
  the hash router. **Never change this shape once apps ship** —
  installed apps depend on it. Legacy routes get forwarder entries,
  not breakage.
- Percent-encode slugs in routes — non-ASCII slugs are real.
- "Open in app" on Detail: `appname://` scheme on Apple UAs, an
  `intent://` URL **with the current page as fallback** on Android.

## Data fetch hygiene

- **Bound every external fetch with `AbortSignal.timeout`.** A
  third-party metadata endpoint that "usually works" can hang 30s+
  on specific items; an unbounded await freezes the view. Measured,
  not hypothetical.
- **Build-time data beats runtime APIs.** If a value can be baked
  into your published data (a URL, a synopsis), the live API is a
  bounded FALLBACK only — never a runtime dependency.
- Never `fetch()` hosts that don't send CORS (verify with GET, not
  HEAD); `<img>`/`<video>` elements are CORS-exempt — use them. Full
  matrix in `shared-data-plane-contract`.
- **Auth/token refresh on `visibilitychange`, not timers** — a
  background tab's timers are throttled; refresh when the user
  returns, before the first action.
- Composing consumer surfaces from a live third-party search/scrape
  API bypasses every policy filter your pipeline bakes in — surfaces
  compose from YOUR published data only.

## Images: the fallback chain that survives throttling

Image hosts throttle burst loads with **transient 503s** — a
one-shot `onerror` fallback leaves broken tiles until a manual
refresh:

1. Try sources in order (primary → secondary host).
2. **Retry the whole chain up to 2× with jittered backoff.**
3. When nothing loads, render a **local typographic placeholder
   card** (title + accent bar) — never the host's generic gray
   placeholder, and never a broken-image icon.
4. Know which IDs are NOT fetchable images (synthetic/derived ids)
   and skip straight to the placeholder — don't burn requests on
   guaranteed misses.

Cards: `object-fit: cover` at a fixed aspect; poster + two text
lines, nothing else.

## Service worker discipline

- **Shell cache-first, with a version string bumped on EVERY shell
  change** (`const CACHE = 'shell-v7'`) — a forgotten bump is the
  classic "deployed but users see the old app."
- Data files (indexes, config JSON): **network-first with last-good
  fallback**.
- **Never cache video/streams.** Pass media requests through
  untouched.
- Skip admin/secondary tools' paths entirely (they stay live).
- Offline scope is honest: open + browse cached data; streaming
  playback offline is out of scope.

## IndexedDB

- Version the schema; add stores only in `onupgradeneeded`
  (schema v2 adds `playlists`, v3 adds `channels`, …).
- Progress/resume: persist every ~10 s + on close/end; resume only
  inside the 10s–95% window.
- localStorage is for tiny scalars and seen-flags (with a rolling
  window so it can't grow unbounded); structured user state lives in
  IndexedDB.

## CSS gotchas that cost real iteration

- **Two-axis sticky (rail `left:0` + ruler `top:0`) requires rows
  set to `width: max-content`** — otherwise the sticky containing
  block is the visible width and the pinned rail detaches mid-strip.
- Scroll-snap rails need `scroll-padding` matched to the container
  inset, or the first/last card snaps half-clipped.
- **Continuously-scaling heroes: every dimension a `clamp()` in
  container-query units (`cqi`)** — scales with the container, no
  breakpoint jumps. Never hard-crop key art into a banner: ambient
  blurred layer behind a sharp, fully-visible poster.
- Carousel auto-advance pauses on hover/touch AND hidden tabs, and
  is disabled (along with ambient drift) under
  `prefers-reduced-motion`. Dots are real `<button>`s synced from
  scroll position.
- System font stack when there's no build step — webfonts mean FOUT
  with no bundler to inline them.
- The Safari body rule (CLAUDE.md): `100dvh` flex-column body,
  `main { flex:1; overflow-y:auto; min-height:0 }`, no
  `viewport-fit=cover`.

## Porting deterministic logic to JS

When the same seeded logic must agree across platforms (schedules,
rotations, shuffles): port hash/PRNG with **BigInt** (53-bit floats
silently corrupt 64-bit mixers like SplitMix64); anchor "day" logic
to LOCAL time when the experience is local (6 AM local ≠ 6 AM UTC);
verify cross-platform agreement on a fixed seed before shipping.

## Verification protocol (web changes)

- **Execute the real JS in a Node DOM shim** to verify logic —
  headless Chrome's `--virtual-time-budget` distorts timers and
  `AbortSignal`, and `--timeout` dumps the pre-hydration DOM.
- Pixel-measure layout from screenshots (PIL/sharp) when a layout
  claim matters.
- **The Pages CDN caches ~600 s** — verify deploys with cache-busted
  URLs (`?v=...`), or you're testing the previous deploy.
- Local server: `python3 -m http.server 8080`. If it works locally
  but not deployed, suspect (in order): SW cache version, CDN cache,
  Jekyll dropping dot-paths, CORS.
