# Tidbits Club — the FEATURE build (running checklist)

**This is the sequel to `docs/CLUB-MONETIZATION-BUILD.md`.** That doc got the
*paywall* code-complete on all 6 platforms (entitlement spine + purchase code +
paywall UI). This doc tracks the **actual Club-exclusive features** — the reasons
a player would ever choose to pay. As of 2026-07-22 the spine exists and **zero
features are built.** That is the work.

## The frame (do not re-litigate — Decision 047, `MONETIZATION.md §4a`)

- **Club is "get better," not "play more."** It never gates core play. It adds a
  layer. R-MON-1 (never reduce the free tier after go-live) is binding.
- **Lead with new gameplay VERBS, not analytics.** Research finding worth not
  re-deriving: "five analytics screens reads as Sporcle (2.1★); four new ways to
  play reads as NYT." Our free tier is already rich in exactly what everyone else
  charges for (records/streaks/standings/archive), so the tier must be carried by
  *new verbs*, not a lock on stored data.
- **The line — one test:** *would a player with 5 hours of play notice this is
  gated?* Yes → free. Only legible at 50+ hrs → Club. Most Club features are
  **meaningless without a play history**, which is exactly why gating them passes
  the test and never cheats a casual player.
- **We are not upselling.** No dark patterns, no "upgrade to continue." A player
  converts only if they personally see value. Every gated surface shows a genuine
  preview of the value, never a nag.
- **$0 ongoing infra** (R-NET-1/2). Client-side computation first; RTDB REST +
  hourly-cron + static-JSON for anything shared; never a persistent socket for a
  global feature.

## Gating + verification convention (all platforms)

- One gate: `EntitlementStore.isClub` (Apple) / `Entitlement.isClub` (Android) /
  `entitlement.isClub` (web) / `EntitlementStore.IsClub` (Windows). Already wired.
- **Pre-launch there are no real purchases**, so every feature is verified behind a
  **debug entitlement override**: `TIDBITS_CLUB=1` (Apple env / `SIMCTL_CHILD_`),
  `?club=1` or `localStorage.tidbitsClubDebug` (web), a BuildConfig/DEBUG flag
  (Android), an env/DEBUG flag (Windows). Add the override to each platform's
  entitlement store the first time a feature needs it (once, then reused).
- **A gated feature always renders a real preview + an honest "what you get" panel
  for non-members**, linking to the existing paywall — never a blank wall.
- Verify per the repo rule: run it (sim / headless PNG / emulator) and observe,
  don't just compile. Update `PARITY.md` + this tracker in the same change set.

## Build order (self-contained + $0 first; backend-heavy last)

Front-loaded so momentum features (pure client-side, observable, no owner setup)
ship first; season/cron infrastructure is last.

| # | Feature | Pillar | Shape | Status |
|---|---|---|---|---|
| 1 | **Weak-Spot Arena** | 1 gameplay | client-only: round from your own miss history | **in progress** |
| 2 | **Story Archive** | 3 library | client-only: keep every unlocked "story behind the answer", searchable | todo |
| 3 | **Marathon** | 1 gameplay | client-only: 200-q graded endurance, cross-session scorecard | todo |
| 4 | **Knowledge Atlas** | 2 retrospect | client-only: accuracy by domain/sub-domain over 12mo | todo |
| 5 | **Friend Streaks** | 4 social | light RTDB (reuses friends): mutual daily accountability | todo |
| 6 | **Link Wall** | 1 gameplay | client-only: NYT-Connections-style 2nd daily (Daily stays free) | todo |
| 7 | **Expedition** | 1 gameplay | client-only: multi-week structured campaign, map + certificate | todo |
| 8 | **Ranked Seasons** | 1 gameplay | RTDB + hourly cron: 3-month arcs, tiers, promo/demotion | todo |

Also on deck to **research** (a parallel loop lane, low-cost): fresh incentive
ideas that deepen daily use + delight (see §Research log). The slate above is not
frozen — research may reorder or add.

## Per-feature × per-platform status matrix

Legend: ✅ done+verified · 🔨 in progress · ⏳ queued · 🚫 n/a (with reason)

| Feature | web | iOS/iPadOS | macOS | tvOS | Android | Windows |
|---|---|---|---|---|---|---|
| 1 Weak-Spot Arena | ✅ | ✅ | ⏳ | ⏳ | ⏳ | ⏳ |

> Note: the `.weakSpot` GameMode + `WeakSpotArena` generator live in the shared Apple
> `Core/`, so macOS/tvOS already COMPILE it — only their per-platform Home entry point +
> Club gating remain (small). iOS is the full reference.
| 2 Story Archive | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 3 Marathon | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 4 Knowledge Atlas | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 5 Friend Streaks | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 6 Link Wall | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 7 Expedition | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 8 Ranked Seasons | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |

---

## Feature 1 — Weak-Spot Arena (design spec)

**One line:** a Club round built entirely from *your own* misses — the legitimate
deeper layer above the free spaced-review weave (`dueReview()`, PARITY 214).

**Four-question test (passed 2026-07-22):** deepens understanding (re-teaches your
gaps with the story-behind-the-answer); invites participation (the round is
*authored by your play history*); supports agency (measured by a visible "gaps
closed" tally, it makes you more knowledgeable, not more dependent); clarity (each
question shows *why* it's here — "missed 2 weeks ago, ×3" — never an opaque model).

**Data source (local, per device — the miss store each platform already keeps):**
- Apple: SwiftData `MissedFact` (`questionID, missCount, lastSeen, resolved,
  question`). `RecordsStore.dueReview` already fetches unresolved misses
  most-missed + oldest-first.
- Web / Android / Windows: their existing miss/again stores (audit each; the
  spaced-review weave exists on all four so a miss list exists somewhere).

**Generation (transparent, not a model):** take unresolved misses, sort by
`missCount` desc then `lastSeen` asc (oldest gap first), take up to 10. If fewer
than a floor (say 4), fill the remainder from the *domains* you miss most (weakest
categories) so the round is always playable — and label those as "shoring up
[domain]" so it stays honest. Each item carries a reason string.

**Play:** reuse the existing engine (`startCustom(mode:.weakSpot, category:.named
("mixed"), questions:)` on Apple; the equivalent custom-question entry elsewhere).
Standard MCQ shell. Per-question: show the small "why you're seeing this" reason.
On a correct answer to a previously-missed question, that miss **resolves**
(already the engine's behavior via `resolveMiss` on re-ask-correct) → increment a
**gaps-closed** counter.

**Result screen:** headline = "You closed N gaps." Show which facts moved from
missed → known, and how many remain. This is the payoff and the reason to return.

**Gating:** Club-only. Non-members see the mode card with a real explanation +
one sample ("Here's a fact you missed — Club turns your misses into a round") and
a link to the paywall. Members launch it.

**Entry point per platform:** it is a *mode*, so it lives with the other modes but
visually marked Club (a small "Club" chip). Apple: add `.weakSpot` to `GameMode`
(NOT in `playableModes`' free Customize grid — a dedicated Club row/section on
Home). Empty state when the player has ~no misses yet: "Play a few rounds first —
your misses become your arena."

**Apple reference = the canonical implementation.** Other platforms mirror its
behavior in their native idiom (same verb, native idiom).

---

## Research log (additional incentive ideas)

*(populated by the research lane; owner-facing proposals land here before they
enter the build order.)*

## Log
- **2026-07-22** — doc created; build order set; Feature 1 (Weak-Spot Arena) spec
  written + four-question test passed. Apple reference implementation delegated to a
  sequential Sonnet agent. Next: verify + commit Apple, then mirror web → Android →
  Windows → tvOS/macOS, then Feature 2.
</content>
</invoke>
