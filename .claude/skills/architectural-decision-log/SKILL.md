---
name: architectural-decision-log
description: Use when a project has a DECISIONS.md (or ADR log) capturing architecture choices. Write entries that explain the WHY behind a decision — not the WHAT (which the code already shows). Each entry should answer "what would the next developer get wrong if they didn't know this?" Lead with the decision, then **Why:** + **How to apply:** Triggers on DECISIONS.md, ADR, architecture decision record, decision log, why-did-we-do-this.
---

# Architectural Decision Log Discipline

## When to invoke

Project has a `DECISIONS.md` (or `docs/adr/`, `docs/decisions/`) capturing architecture / technology / pattern choices over time. The discipline below makes the log durable — entries that survive 12+ months of churn and that future developers actually read.

## The question every entry must answer

> *What would the next developer get wrong if they didn't know this?*

If the entry's deletion would change nothing about future work (because the WHY is obvious from the code), don't write it. The decision log isn't documentation — it's encoded judgment about non-obvious choices.

## What belongs in a decision log

✓ **Non-obvious technology choices** ("we use vanilla HTML/CSS/JS — no framework" — the choice IS visible in the code, but the WHY isn't).

✓ **Constraint-driven choices that constrain future work** ("Supabase for auth and user data only — NOT for catalog browsing" — knowing this prevents the next dev from putting catalog queries against Supabase).

✓ **Choices that look weird until you know the context** ("Xcode project at repo root — required for Xcode Cloud auto-discovery, costs hours to debug if violated").

✓ **Anti-patterns we've burned ourselves on** ("Image-byte collision guard in pipeline — caught a silent overwrite that would have shipped wrong card art").

✓ **Trade-offs we've consciously accepted** ("No retained legal counsel — risks documented in §3; user is accepting").

## What does NOT belong

✗ **What the code already says** ("we use SwiftUI for the iOS UI" — anyone reading the code can see that). The entry's value is in the constraint or alternative-rejected, not the choice itself.

✗ **Implementation detail** ("we use `@Observable` macro" — that's a tactic, not a decision worth preserving). Unless the choice has surprising implications.

✗ **Decisions still in flux** — write them up when settled. A "we're considering X" entry is noise.

✗ **Personal preferences without a forcing function** ("I like tabs over spaces"). Decisions need rationale that's load-bearing.

## The entry format

Each entry follows this shape:

```
## NNN — Short imperative title
*YYYY-MM-DD*

One-paragraph lead: WHAT the decision is, in concrete terms. Avoid
prose buildup — the first sentence states the choice.

**Principle**: The general rule this encodes. Often one sentence.

**Why**: The context that makes this choice make sense. Past
incidents, constraints, alternatives rejected, references.

**How to apply**: When does the next developer encounter this
decision? What should they do or not do?

(Optional) **Consequences**: Forward-looking implications.
```

The bold **Why** + **How to apply** keys are what make the entry skimmable when the log is long. Future contributors search for those bolded keys.

### Why the WHY matters most

A decision with the WHAT but no WHY decays the moment someone wants to revisit. They have no way to evaluate whether the constraint still holds. They re-derive (badly) or override (worse).

A decision with WHY preserves the judgment. Future contributors can ask: "is the original WHY still true?" If yes, keep the decision. If no, the entry tells them what changed.

## Example — well-formed entry

From a real BOBA Playbook DECISIONS.md entry:

```
## 020 — Web Layout: Body Flex Column, No viewport-fit=cover
*2026-04-04*

`body { height: 100dvh; display: flex; flex-direction: column;
overflow: hidden }` with `main { flex: 1; overflow-y: auto;
min-height: 0 }`. The body does not scroll — content scrolls
inside `main`.

**Why**: `position: fixed` headers land in a separate GPU
compositor layer that Safari browser-mode misorders during
address-bar transitions, causing content to bleed into the
Dynamic Island. Body flex-column keeps the header in document
flow. Reference: github.com/bhwilkoff/Bsky-Dreams.

**Consequences**: No `viewport-fit=cover`, no `env(safe-area-
inset-top)`. IntersectionObserver must use
`root: document.getElementById('main-content')`.
```

This entry:
- Leads with the concrete decision in code-like detail
- The WHY references a specific bug (Dynamic Island bleed in Safari)
- The Consequences section warns about downstream changes (IntersectionObserver root)
- A developer reading it later can decide: "is Safari still broken this way? If yes, keep. If fixed, revisit."

## Example — poorly-formed entry

```
## 042 — Use SwiftData for persistence
*2026-04-12*

We use SwiftData for local persistence on iOS.
```

This is noise. The code shows SwiftData usage. No WHY, no constraint, no past-incident motivation. Delete or expand.

## Linking decisions to design rules

If your project also has a binding design doc (DESIGN.md), the relationship is:

- **DESIGN.md** = the rules a feature must obey (the WHAT)
- **DECISIONS.md** = the rationale behind specific non-obvious choices (the WHY)

Sometimes they overlap. When DESIGN.md says "Liquid Glass = navigation only" and DECISIONS.md has an entry about WHY we chose Liquid Glass over a custom blur, both serve different readers (the implementer reads DESIGN.md; the curious future-contributor reads DECISIONS.md).

Cross-reference: DESIGN.md rules can reference DECISIONS.md entries by number ("see DECISIONS.md #036").

## When to write a new entry

Trigger moments:

- After a multi-hour debugging session where the fix required a non-obvious choice
- After choosing between two seemingly-similar options (Lanczos vs nothing, .unlit vs .pbr, etc.)
- After accepting a trade-off (e.g., "we're shipping without insurance, here's why that risk is OK")
- After discovering a constraint that bit us (Xcode Cloud requiring repo-root project, etc.)
- After rejecting an architecture proposal — the rejection rationale is as valuable as the acceptance

DON'T write an entry for every commit. The log should be ~50-100 entries per multi-year project, not 1000.

## Maintenance — when entries decay

Decisions age:

- A constraint that drove the choice can change ("Safari fixed the Dynamic Island bug in 17.6")
- A trade-off can be revisited ("we said no auth UI; now we have one")
- A pattern can be superseded ("DECISIONS.md #025 lifts the feature-gating principle for Wall + Price Overlay specifically")

When an entry decays, either:

1. **Patch it in place** with a dated note ("Updated 2026-05-03: ...")
2. **Write a superseding entry** that references the old one ("DECISIONS.md #036 lifts the gate from #025 for Wall + Overlay")

Don't delete old entries — they're history. They tell the next developer "this was true once, and here's how the thinking evolved."

## How decisions feed the working session

When starting work on a new feature:

1. **Grep DECISIONS.md** for keywords related to your feature ("auth", "card image", "filter")
2. **Read the matching entries** — they're 200-400 words each
3. **Note constraints** that affect your implementation choices
4. **Cite relevant entries** in your commit message / PR description

This makes the log load-bearing instead of decorative.

## Anti-patterns

### ❌ Writing entries that just say "we chose X"

The code shows X. The entry's value is the WHY. Skip entries that don't say WHY.

### ❌ Letting entries decay into "true ten years ago" museum pieces

Active projects revisit decisions. Update or supersede; don't leave a stale entry to confuse a future contributor.

### ❌ Confusing DECISIONS.md with TODO list

Decisions are SETTLED. If something is still in flux, it goes in SCRATCHPAD.md / SHIPPED.md / a tracker — not the decision log.

### ❌ One-sentence entries

If you can write the WHY in one sentence, it probably wasn't a hard decision (or the WHY is obvious). Skip it. Decisions worth logging usually need 2-3 paragraphs.

## Real-world examples

- **BOBA Playbook DECISIONS.md** — 40+ entries, all bold-Why-and-How-to-apply formatted. The codebase makes sense reading them in order.
- **Architecture Decision Records (ADRs)** — Michael Nygard's original ADR pattern uses a similar shape. ([github.com/joelparkerhenderson/architecture-decision-record](https://github.com/joelparkerhenderson/architecture-decision-record))

## See also

- [[binding-design-doc-discipline]] — companion pattern: each non-obvious design rule gets a DECISIONS.md entry
- [[feature-shipping-discipline]] — when shipping, cite the relevant DECISIONS.md entry in your commit
