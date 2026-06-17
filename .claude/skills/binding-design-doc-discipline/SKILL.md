---
name: binding-design-doc-discipline
description: Use when a project has a binding design doc (DESIGN.md, WEB-DESIGN.md, STYLE_GUIDE.md, etc.) that governs UI/IA decisions. The workflow is: before proposing any new view/sheet/picker/nav level, quote the rule that justifies it. If no rule fits, the proposal needs a NEW rule (and discussion) before it ships. The doc is the source of truth; fix the doc first, then fix the feature. Triggers on design doc, binding spec, DESIGN.md, design rule, "follow the design system."
---

# Binding Design Doc Discipline

## When to invoke

The project has a markdown doc (commonly `DESIGN.md`, `WEB-DESIGN.md`, `BRAND.md`, `STYLE_GUIDE.md`, `ARCHITECTURE.md`) that's explicitly **binding** — meaning every new UI surface, IA decision, or feature shape must trace to a rule in that doc. Look for header text like:

> **Binding.** Every new view, sheet, button, filter in [this surface] must trace to a rule here. When something feels overwhelming or inconsistent, fix the document, then fix the feature.

When you see that, this skill is the methodology that makes the doc actually load-bearing instead of decorative.

## Why binding docs fail without discipline

A "binding" doc that nobody quotes during PR review becomes a museum piece — the rules stay in the file, but the features drift away from them. The discipline below is what keeps the doc and the codebase synchronized.

## The two-role contract

A binding doc only works when two roles are bound by it:

**The doc author's job** (project owner / lead designer): when an implementation choice contradicts a rule, point at the rule. The cost of NOT pointing is that rules erode silently.

**The implementer's job** (Claude / engineer): before proposing any new view, sheet, filter, picker, nav level, or toolbar item, **quote the rule that justifies the choice**. If no rule fits, the proposal needs a new rule (and discussion) before it ships.

You are usually the implementer. Apply the discipline below.

## The proposal-with-rule-quote pattern

When proposing UI work, ALWAYS open with the rule citation:

**Wrong** ("orphan proposal"):

> "Let me add a horizontal scrolling pill bar at the top of the Find tab with filter chips for weapon, treatment, and cost."

This proposal has no anchor. The user has to decide whether to push back, which is expensive. They will eventually flag a rule violation and the proposal gets reworked.

**Right** ("rule-anchored proposal"):

> "Per DESIGN.md §1.3 (Search is the universal navigator) and §6.5 (filter tokens replace pill-bar rows), I'll add a `.searchable` field with `BOBAFilterToken` for weapon/treatment/cost. This puts filters inline with search instead of in a parallel pill bar. The §3.2 anti-pattern (pill-bar pile-up) is explicitly avoided."

This proposal IS the review. The user can accept or push back on the rule interpretation, not the surface. If the rule's wrong, you propose an edit to the doc first.

## When no rule fits

Don't invent a new shape and ship. Three valid moves:

1. **Re-interpret an existing rule** — your proposal IS covered, you just hadn't read it carefully enough. Quote it.

2. **Identify a doc gap and propose a new rule** — start with the user-facing problem ("users frequently miss the new-deck button"), propose the rule that would address it ("primary creation actions live in the toolbar trailing slot, never in the empty state"), THEN propose the implementation that follows the new rule.

3. **Identify a doc contradiction and propose the resolution** — two rules disagree; the doc is wrong. Patch the doc first.

The cost of inventing a UI shape without an anchoring rule is that future proposals will copy the unanchored pattern, and the doc loses authority.

## Reading binding docs effectively

Binding docs are typically structured:

- **Principles** (the why) — usually 5-10 numbered statements
- **Anti-patterns** (the never) — concrete examples of what NOT to do
- **Patterns** (the how) — per-surface or per-feature recipes
- **Out of scope** (the intentional gaps) — things explicitly NOT designed

Before working on a surface, **read all four sections for that surface**. Anti-patterns are where binding docs encode the most hard-won learning — skim them once on entering a project and re-read when stuck.

## The doc-then-code order

Sequence matters when a binding doc exists:

1. **First**: read the doc section relevant to your work.
2. **Second**: ask "does the doc cover what I'm about to do?"
3. **Third (only if doc covers it)**: write code that obeys the doc.
4. **Third (if doc doesn't cover it)**: propose a doc edit + discuss + ship doc edit + then write code.
5. **Fourth**: in the commit/PR, quote the rule the change implements.

Skipping step 1-2 is the #1 cause of "rework after rule was pointed out" cycles.

## The "fix the document, then fix the feature" reflex

When a feature feels overwhelming, inconsistent, or hacky, the temptation is to add MORE UI to compensate. A binding doc rejects this — the fix is upstream:

- Feature has a `Settings → Display → Density → Adjust grid → Grid columns picker` 4-level nav drill? The doc rule (depth ≤ 2) says this is a structural bug. Fix isn't a better picker — it's collapsing the IA.
- Two views with similar headers but different button orders? The doc rule (canonical chrome) says align them. Fix isn't a new variant — it's making the existing pattern enforceable.

Reading the doc when something feels wrong is faster than redesigning blind.

## Daily review test (from DESIGN.md §10 pattern)

Before any feature ships, three questions tied to common binding-doc principles:

1. **The competent-designer test**: could a peer designer recreate this screen from a one-paragraph description? If no, you've added decoration. Strip.

2. **The verb test**: what verb does this surface own? Colliding with a sibling tab's verb? Structural bug — resolve before adding.

3. **The depth test**: count nav levels from the root. If >2, the third level should be a scope, a sheet, or a different tab — not another push.

When the answer is "no" or "I'm not sure," reread the relevant doc section.

## When the doc is silent or contradicts itself

The doc is wrong — propose an edit. Don't ship the feature with a hack.

The format for a doc-edit proposal:

> "DESIGN.md §6.5 says X. §8.4 says Y. They conflict for case Z (specific surface). I propose changing §6.5 to read [new wording] which resolves the conflict by [reason]. Once that's in, I'll implement Z accordingly."

A user who sees this knows you've read the doc, found the gap, and have a path forward. Much better than shipping a hack and waiting for them to catch it.

## Anti-patterns

### ❌ Shipping a UI choice and hoping the user doesn't notice the rule violation

This is what destroys binding-doc projects. The user inevitably notices, the feature gets reworked, and the doc loses authority because someone shipped past it.

### ❌ Asking "what does the design doc say about X?" before reading it

The doc is right there. Use grep + Read. Asking the user is asking them to do your reading work.

### ❌ Treating the doc as documentation rather than as a contract

A binding doc isn't there to TELL you what to do — it's there to BIND you. Read it that way: every rule is a "you must" not a "you might consider."

### ❌ Adding to the doc without discussion

The doc is a small thing changed often by one person (the owner). Adding rules without their sign-off creates rules that aren't actually binding (because the owner didn't agree). Propose; don't unilaterally write.

## In commit messages

Once a feature ships, the commit message should quote the rule it implements (in addition to whatever else):

```
Decks: replace pool filter pill bar with .searchable tokens — v2.245

Per DESIGN.md §1.3 + §6.5: filter tokens are the universal pattern,
pill bar rows are the §3.2 anti-pattern. This aligns Decks pool
search shape with Find tab.
```

This makes the doc visible in git history, which makes future contributors more likely to reference it.

## Real-world example

BOBA Playbook DESIGN.md is binding. ~50 entries in DECISIONS.md cite specific DESIGN.md rules. New UI proposals open with rule quotes. When a contradiction arises, the doc gets patched THEN the feature ships. The result: ~3000 lines of design doc that actually matches the codebase.

The discipline scales — it works for a 1-person project or a 50-person team. The cost is reading the doc + quoting it. The savings is avoiding the "rework after rule was pointed out" loop.

## See also

- [[architectural-decision-log]] — companion pattern: each binding-doc rule that's non-obvious gets a corresponding DECISIONS.md entry explaining the WHY
- [[feature-shipping-discipline]] — the full sequence from doc-read through ship
