---
name: resilient-media-streaming
description: Use when streaming video/audio from hosts you don't control (archives, CDNs with idle-connection resets, redirect-heavy origins), when playback "stalls every minute or two" despite good bandwidth, or when porting playback to a new platform. Carries the diagnose-first protocol (measure buffer + connection behavior before touching code), the own-the-connection pattern (AVAssetResourceLoaderDelegate with resume-from-byte-offset), streaming delivery + origin pinning, and the Media3 / web analogs. Triggers on AVPlayer stalls, buffering, playback stalls, ResourceLoader, ExoPlayer retry, LoadErrorHandlingPolicy, video reconnect, "video keeps pausing", progressive MP4, range requests.
---

# Resilient Media Streaming

Patterns for reliable playback from origins you don't control —
distilled from eliminating per-film stalls against an archive host
that resets idle connections and 302-redirects every download.

## Diagnose before you code (the order matters)

Stalls have at least four distinct causes with different fixes.
Instrument first — an env-gated diagnostic overlay/log that reports:
observed bandwidth, forward-buffer seconds, and per-request timing.

What the measurements distinguish:

- **Buffer grows then collapses instantly (140s → 0 in one second)
  on a connection error** → the player is FLUSHING its buffer on
  reset. A bigger buffer cannot fix this; you must own the
  connection (below).
- **Buffer grows in steps with multi-second flat holes** → bytes
  are reaching the player only at chunk completion → switch to
  streaming delivery (below).
- **Every request slow to first byte vs the same fetch direct to
  the final host** → you're paying a redirect round-trip per chunk
  → pin the post-redirect origin (below).
- **Genuinely low bandwidth** → only now is bitrate/derivative
  selection on the table — and prefer fixing selection at
  build/publish time over capping quality at runtime.

A real diagnosis run: 18–84 Mbps observed for a 1.15 Mbps file,
buffer banked 120–210s, still stalled every ~30s — proof the
problem was flush-on-reset, not throughput. Without the
measurement, every "fix" would have been a bigger buffer or a
quality downgrade (both wrong).

## iOS / tvOS: own the connection (AVAssetResourceLoaderDelegate)

Route remote progressive media through a custom loader on a private
URL scheme (`app-stream://`), serving AVFoundation's byte-range
requests over your own URLSession:

- **Short idle timeout (~12s) + resume-from-exact-byte-offset on any
  error.** Never restart a chunk at 0 — the resume is what turns a
  connection reset into an invisible re-request instead of a
  buffer-discarding stall. After this, `nw_read timed out` console
  lines are EXPECTED noise (your short timeout firing before an
  instant resume); judge health by playback continuity.
- **Stream bytes as they arrive** (per-task `URLSessionDataDelegate`
  delivering every `Data` slice immediately), not whole-chunk
  `session.data(for:)` — whole-chunk holds bytes hostage for the
  chunk duration and makes every failure cost the entire chunk.
  Advance the offset per delivered slice so retries are byte-exact.
- **Pin the post-redirect origin** after the first response; request
  it directly thereafter; DROP the pin on any failure (storage nodes
  rotate) and re-resolve through the origin before burning retry
  budget. Measured effect: 4× in-chunk throughput, startup metadata
  1.5s → 50ms.
- **416 = ranged past EOF = clean finish**, not an error.
- Large-ish ranges (8 MB) once streaming delivery is in place;
  generous `preferredForwardBufferDuration` (minutes, not seconds).
- Keep loader state confined to its serial queue; retain the loader
  in `@State` (the player's delegate reference is weak).
- Build assets via the loader for http(s) URLs only; pass everything
  else through untouched.

**Never** add a bitrate ceiling to compensate for transport problems
— fix the transport; keep source quality a product decision.

## Android: Media3/ExoPlayer

ExoPlayer's range handling is already strong; add patience and
reuse, don't rebuild:

- OkHttp `DataSource` on the SHARED OkHttpClient (same client as
  Coil/Ktor).
- A custom `LoadErrorHandlingPolicy` that retries generously with
  backoff on connection resets/timeouts instead of surfacing a
  player error — the "patient policy" analog of resume-from-offset.
- MediaSession from day one (lock-screen/controls are a parity row).
- Per-item position persistence for resume (timecode, not percent).

## Web: the browser already does ranges

`<video src>` issues ranged GETs natively (and media elements are
CORS-exempt — a `fetch()`-blocked host usually still plays fine).
Add a small reconnect wrapper:

- On `error`/`stalled` with a network cause: capture `currentTime`,
  reset `src` (or call `load()`), seek back, resume. Escalate to MSE
  only if measurements prove progressive playback can't be saved
  (it usually can).
- MediaSession API for lock-screen/media-key controls; persist
  resume position in IndexedDB.

## Cross-platform invariants

- **Resume = timecode, not percent**, persisted per item.
- **Derivative/quality selection happens at build/publish time**,
  identically for every client — never per-client ceilings.
- Diagnostics stay in the codebase **env-gated**
  (`APP_PLAYBACK_DIAG=1` → structured chunk/retry/stall/buffer
  lines; `APP_AUTOPLAY=1` + `APP_START_ITEM` → unattended playback
  runs on a simulator). Re-instrumenting from scratch costs a
  session each time stalls recur.
- Real-world failure conditions (living-room wifi, busy origin
  nodes) may not reproduce on the dev box — ship the fix with
  diagnostics available and judge on-device.
