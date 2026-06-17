---
name: mobile-first-density-design
description: Use when designing or reviewing any UI — the principle is that visual density comes from REMOVING chrome, not adding decoration. Three weights × two sizes give six hierarchy levels with zero added pixels. Mobile-first means testing at 375px before 1440px. Apply the Tufte / Things 3 / Reeder lineage of dense-but-readable design. Triggers on UI design, density, layout, visual hierarchy, screen design, "design this view", "looks busy", "feels cluttered."
---

# Mobile-First Density Design

## The core principle

**Density doesn't come from adding decoration. It comes from removing chrome.**

Every divider, shadow, badge, chip, and tinted container you remove makes the remaining information read denser. Three weights of type × two sizes give six hierarchy levels at zero added pixel cost. Test at 375px before 1440px — mobile constraints force the discipline that reads beautifully on desktop too.

This is the Tufte / Things 3 / Reeder / Linear / Vercel lineage: information-dense without feeling busy.

## When to invoke

- Designing or reviewing any new view, list, grid, or detail surface
- Working on a "looks busy / cluttered / overwhelming" complaint
- Choosing between adding a separator vs spacing vs section header
- Reviewing typography: how many weights, how many sizes
- Deciding whether to use a tinted background on a card

## The six binding density rules

### 1. No tinted-box backgrounds on lists/cards

Row separation comes from `Divider()` or vertical spacing — not from a `background(.gray.opacity(0.05))` on every row. Container separation uses Liquid Glass (iOS) or surface tokens (web) at the container level, NOT on every child.

Why: tinted-box backgrounds tile visually. Three rows with the same tint look like three pieces of luggage on a conveyor belt. Three rows without the tint look like three lines of content — denser and more readable.

### 2. Three weights × two sizes = six hierarchy levels

Pick a display face (e.g., Bebas Neue bold) for L1 page titles. A heavy mono (Russo One) for L2 section headers. A body face (Chakra Petch) in three weights — semibold, regular, light — at two sizes (body, caption). That's six levels with zero added pixels.

The rule: **refuse a seventh weight or size.** If you need one, refactor what you have.

Why: every additional weight/size adds visual noise that competes with content for attention. Six levels is enough for any UI; a seventh dilutes the others.

### 3. Small multiples

Every card cell in every grid uses the same component (`BOBACardCell`, `ProductTile`, etc.). Every cell has the same aspect ratio, the same padding, the same badge placement. The user's eye trains to a single shape and scans faster.

The rule: **one canonical cell, used everywhere.** When you need a variant, ask whether the variant can fold back into the canonical shape with a parameter.

Why: small multiples are how Tufte / Bertin / NYT scrollers achieve density. Repetition + variation makes the variation pop.

### 4. Show the data; filter it

A persistent search field is denser than a category picker because it's zero-overhead access to everything. Search beats nav levels at scale (~50+ items).

When you find yourself adding "browse by hero / browse by element / browse by set" categories, ask: would these be better as `searchScopes` or filter tokens on a single search field?

Why: pickers gate access. Search opens access. Density = how much the user can reach in how few taps; search wins.

### 5. Progressive disclosure must be predictable

`DisclosureGroup` for inline expansion. `NavigationLink` for push. Never overload — a `DisclosureGroup` that sometimes inlines and sometimes pushes is a trust-destroyer. A row with a chevron must push; without one must inline.

Why: when disclosure is unpredictable, the user can't anticipate the consequence of tapping. They tap cautiously, slowly, with high cognitive load. That's the opposite of dense.

### 6. The Gruber test

> *Could a competent designer recreate this screen from a one-paragraph description?*

If no, you've added decoration. Strip and rebuild from the description.

This is the most powerful self-review tool. When in doubt, write the paragraph. If the paragraph wouldn't reproduce the screen, the screen has noise you can remove.

## Mobile-first sequencing

The constraint of 375px makes you make the right choices automatically:

- **No room for multiple horizontal scrolling pill rows** → you pick the one that matters
- **No room for both a sidebar and a sticky bottom bar** → you commit to one navigation chrome
- **No room for an inset card with shadows + dividers + badges** → you pick one and the result reads denser
- **No room for 30% of the screen to be padding** → you collapse it

Design at 375px first. Add affordances at 768px+ if and when desktop justifies them. Reverse-direction (desktop-first then "make it mobile") almost always ships with un-removable accumulated chrome.

## Anti-patterns (project-tested)

### ❌ Pill-bar pile-up

Multiple horizontal scrolling rows of equal-weight filter chips. At most ONE persistent filter row exists in a tab. Everything else moves to search tokens, a Menu, or a sheet.

### ❌ Tab-inside-tab

A segmented control at the top of a tab that switches between sub-modes IS a second tab bar. Either it becomes a different top-level tab, or it becomes `searchScopes` over a single content stream.

### ❌ Settings dump

Every config knob visible at once. Use a `Form` with `Section`s and `DisclosureGroup`s. Lead with the 3 most-changed; collapse advanced.

### ❌ Equal-weight horizontal scroll bars in feed surfaces

Horizontal scroll hides content below the fold and doesn't paginate predictably. Reserve horizontal scroll for genuinely-curated shelves (featured cards, recently-viewed) — never for primary navigation.

### ❌ Adding chrome to fix density

If a view feels sparse, the answer is rarely "add a tinted background to give it shape." The answer is usually "increase the information density by stripping padding and showing more rows."

## Color discipline

Most modern dark themes get this wrong. The pattern that works:

- **Brand colors** (UI chrome only): one primary CTA color, one accent, one dark background, one panel surface. ~4-5 brand tokens total.
- **Semantic colors** (content only): success / warning / error / info, plus any domain-specific (element colors, status colors). ~6-10 semantic tokens.

**The split is binding**: never use a brand color for content meaning (the primary CTA is for buttons, not for "this row is selected"). Never use a semantic color for chrome (success-green is for "saved successfully", not for the navigation bar).

If brand color and a semantic color overlap (e.g., your CTA orange = your `FIRE` element color), the overlap is intentional — but never let semantic carry brand meaning or vice versa.

## Typography ratio

Two practical hierarchies that work for dense UI:

**iOS / SwiftUI** (default at iPhone size):

- L1 (page title): 24-28pt bold, display face
- L2 (section header): 14-15pt bold uppercase, accent face
- L3 (body bold): 16pt semibold
- L4 (body): 16pt regular
- L5 (caption): 13pt regular
- L6 (tabular): 16pt monospaced numerals

**Web** (default at mobile 16px base):

- L1 (page title): `clamp(1.75rem, 5vw, 2.5rem)` bold display
- L2 (section header): `1rem` bold uppercase, letter-spacing 0.05em
- L3 (body bold): `1rem` semibold
- L4 (body): `1rem` regular
- L5 (caption): `0.85rem` regular
- L6 (tabular): `1rem` mono

Refuse a 7th level. If you think you need one, refactor.

## The daily review test

Before any screen ships:

1. **Gruber test**: paragraph → screen? If no, strip.
2. **Pixel count**: is every pixel doing work? Strip the ones that aren't.
3. **Mobile breakpoint**: does it read at 375px? If no, the desktop version isn't earning its density yet.

## References

- Edward Tufte — *The Visual Display of Quantitative Information* (the canonical text on information density)
- Things 3 by Cultured Code — best-in-class iOS density example
- Reeder by Silvio Rizzi — RSS reader density done right
- Linear — modern dark-theme density at scale
- Vercel — web density discipline
- Refactoring UI (Steve Schoger / Adam Wathan) — practical visual-hierarchy patterns

## See also

- [[binding-design-doc-discipline]] — these density rules typically live in a project's DESIGN.md
- [[native-platform-first]] — native components already obey these rules; custom usually doesn't
- [[universal-feature-states]] — empty/loading/error states must also obey density rules
