---
name: cross-platform-parity-discipline
description: Use when shipping ANY user-facing feature in a multi-platform repo, when asked to "check parity", "audit features", or before a launch wave on any platform. Carries the PARITY.md workflow — same verb / native idiom, same-change-set updates, deliberate-defer cells with reasons, platform-specific affordance sections — and the periodic parity AUDIT protocol that catches missing rows and silently-false cells. Triggers on PARITY.md, feature parity, parity matrix, "ship on all platforms", "does Android have", parity audit, cross-platform feature, launch readiness.
---

# Cross-Platform Parity Discipline

The single source of truth for "what ships where" is `PARITY.md`.
This skill is the workflow that keeps it true. It was battle-tested
shipping one app on four platforms (tvOS, iOS/iPadOS, web, Android)
through simultaneous store submissions — every rule below earns its
place from a real drift incident.

## The rule

**Same verb, native idiom.** The feature (the verb: search, save,
share, browse) is identical across platforms. The expression is
whatever is native — `.searchable` on iOS, `SearchBar` on Android,
`<input type=search>` + URL params on web, the focus-driven keyboard
on tvOS. Never let one platform own a different verb for the same
surface; never port one platform's layout to another.

## When you ship a feature

In the SAME change set (not a follow-up):

1. **Find or add the row** in PARITY.md under the right verb section.
2. **Update every platform's cell** — including the ones you didn't
   touch. A platform you can't reach right now gets ⏳ plus a Notes
   reason, never a blank. Blanks are drift.
3. **Mirror where feasible.** If the change is small on the other
   platforms, ship them together. If not, the ⏳ note says why and
   what wave it lands in.
4. **Cross-link the binding design doc section** that governs the
   feature on each platform that has one.
5. **Don't wait to be asked.** "Ship on one and see" is how a matrix
   rots.

## Cell honesty rules

- ✅ means *live and verified on that platform* — not "code merged."
  If you haven't seen it work (sim screenshot, emulator run, browser
  check), it's 🚧.
- A **deliberate defer is a healthy cell**: "⏳ Google Cast — needs
  Cast SDK + device-tested receiver, deferred to player wave" is
  good engineering. The reason in Notes is mandatory; it's what lets
  a future session pick the work up without re-deriving the blocker.
- **Owner-blocked is its own state**: when a cell waits on something
  only the human can do (an OAuth client, a store setting, a domain),
  say "OWNER:" in the note. Don't let owner-blocked items
  masquerade as engineering backlog.
- **n/a and 🚫 carry reasons.** "n/a — TV apps suspend in
  background" teaches; a bare n/a invites re-litigating.
- Platform-exclusive features go in the per-platform affordance
  sections (§9–§12), with the cross-platform equivalent named:
  "Top Shelf (tvOS) ↔ WidgetKit (iOS) ↔ Glance widgets (Android) ↔
  PWA shortcuts (web)."

## The parity audit (run before launch waves + once per milestone)

Day-to-day updates miss two failure classes that only an audit
catches. Real audits on a shipped 4-platform app found **5 missing
rows and 4 false cells** in a matrix that was being maintained
conscientiously.

**Protocol:**

1. **Inventory sweep**: walk each platform's actual surfaces (tab by
   tab, screen by screen — from the code, not from memory) and list
   every user-facing capability. Diff that list against the matrix.
   Missing rows get added. Typical finds: share buttons, media/lock-
   screen controls, result filters, tappable metadata (cast → person
   browse) — small verbs nobody recorded.
2. **Cell verification**: for every ✅, ask "have we observed this
   working on this platform, recently?" Suspicious cells get tested,
   not trusted. The canonical false cell: a "(synced)" claim where
   the sync payload never actually carried that record type — code
   existed, data never flowed.
3. **Stale-blocker check**: for every ⏳/🚫, is the recorded reason
   still true? Blockers expire (an API ships, a domain gets bought,
   a measurement gets re-run and contradicts the old one).
4. **Fix in the same pass**: small gaps (a missing toggle, a missing
   row) get closed during the audit; large ones get ⏳ cells with
   reasons and land in the milestone queue ordered by size.

## Working the gap queue

When closing parity gaps in bulk (a "parity wave"):

- **Order by shared-logic leverage**: a feature whose logic already
  lives in shared code (a deterministic scheduler, a query verb, a
  flag baked into the data plane) ports cheapest — do those first.
- **Port the logic, rebuild the layout.** A deterministic core
  (same constants, same seeds, same query) gives identical behavior
  across platforms; the layout around it is rebuilt in each
  platform's idiom. Never screenshot-match layouts across platforms.
- **Re-verify the platforms you didn't touch.** Shared-file changes
  must re-build every consumer (the tvOS build going green after an
  iOS-motivated Core change is part of done).
- Update PARITY.md per change set within the wave, not once at the
  end — a wave that dies mid-way must leave a true matrix.

## Verbs that deserve a row people forget

Share (and what a share URL opens on each platform) · lock-screen /
media-key controls · search-result filters · tappable secondary
metadata · account deletion (a store-review requirement, not a
feature) · error/empty/offline states for marquee surfaces ·
settings toggles that gate behavior shipped elsewhere · deep-link
routes (every emitted URL shape must be openable everywhere it
lands — including the manifest/intent-filter on Android).
