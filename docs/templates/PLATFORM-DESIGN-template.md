# [APP NAME] — [PLATFORM] Design (BINDING)

<!-- Seed for DESIGN.md (iOS), tvOS-DESIGN.md, WEB-DESIGN.md, or
     ANDROID-DESIGN.md. Create once the platform passes ~5 views.
     Invoke `binding-design-doc-discipline` for the workflow.

     The sibling docs share this shape: §1 principles are nearly
     identical across platforms; everything else diverges into the
     platform's native idioms. -->

**Binding.** Every new view, tab, sheet, grid, route, or toolbar item
on this platform must trace to a rule in this document. When
something feels overwhelming or inconsistent, **fix this document
first, then fix the feature.** Proposals (and commits) cite the rule
they implement, e.g. "per §2.3."

Division of labor:
- **This doc** = the binding contract for the [PLATFORM] surface:
  navigation shell, idioms, screen composition, state rules.
- **The sibling design docs** = the other platforms' contracts. The
  docs share verbs, never idioms (PARITY.md: "same verb, native
  idiom"). When a rule below deliberately inverts a sibling rule,
  it says so — do not "harmonize" them.
- **`PARITY.md`** = what ships where; updated in the SAME change set.
- **`DECISIONS.md`** = the why behind non-obvious rules.

---

## §1 — Principles (the why)

1.1 **Same verb, native idiom.** The feature set matches the other
platforms; the expression is whatever users of [PLATFORM] already
know. Never port another platform's layout here; never invent a
custom control where a native one exists (`native-platform-first`).

1.2 **[The platform's defining interaction].**
<!-- iOS: "Touch replaces focus — the tap is the verb, the tile is
     the chrome."
     tvOS: "Focus is the interaction model — subtract focusables
     before adding them; the focused card is the chrome."
     Web: "The URL is the state — every surface is a shareable
     canonical URL."
     Android: "Material is the language — M3 components first,
     predictive back always works." -->

1.3 **One shared data plane.** This client consumes the same
published data and editorial config as every other platform
(docs/DATA-CONTRACT.md). No platform-local data forks.

1.4 **[The platform's posture].**
<!-- lean-in companion / lean-back cinematheque / zero-install reach
     — and which idioms therefore do or don't belong here. -->

1.5 **Depth ≤ 2 from any root.** Root → list/grid → detail. A
would-be third push must become a scope control, a sheet/dialog, or
a different root.

1.6 **Density from removal.** Chrome is subtracted, not decorated
(`mobile-first-density-design`).

1.7 **Voice.** Copy is evocative and short; never pipeline language
("items", raw counts as a subtitle). Copy lives in shared config,
not platform code.

---

## §2 — Navigation shell

2.1 **[N] top-level destinations, hard set: [list].** Settings is
not a peer of content verbs — it lives [behind a gear / in a footer].
Adding a destination requires amending this rule first.

2.2 **One shell, all form factors.** [How the shell adapts —
size classes / window classes / breakpoints. One hierarchy, no
parallel code paths.]

2.3 **One destination registry.** Every pushable destination is a
route value registered in ONE place — never per-view destinations.
Any surface can push any screen.

2.4 **External entry points land in an inbox** (deep links, voice,
widgets), consumed by the root once foregrounded — they never mutate
navigation state directly.

---

## §3 — Screen recipes

<!-- One numbered subsection per screen archetype: the home surface,
     list/grid + filters, detail, player/canvas, search, settings.
     Each recipe: composition order, what's focusable/tappable,
     where state lives, and the universal states (loading / empty /
     error / offline — `universal-feature-states`). -->

---

## §4 — Idiom rules

<!-- The platform-specific bindings: which native components are
     mandatory for which verbs; the anti-patterns this platform
     rejects (with the incident that earned each); typography and
     spacing tokens as used here. -->

---

## §5 — State, persistence, sync

<!-- What's local-first, what syncs (per-ecosystem-sync-islands),
     what's session-only. Resume semantics. Settings storage. -->

---

## §12 — Out of scope (intentionally)

| Idea | Why declined | Revisit when |
|---|---|---|

<!-- Rejected UI directions live here so they aren't re-proposed.
     Same discipline as SCRATCHPAD's out-of-scope table, scoped to
     this platform's design. -->
