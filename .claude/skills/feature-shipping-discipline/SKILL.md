---
name: feature-shipping-discipline
description: Use as the end-to-end workflow for shipping any feature change. The sequence is read docs → propose with rule quote → build → validate (sim/test/build-verify) → bump version → commit message quotes user request → push (only on explicit authorization). Each step prevents a specific failure mode. Triggers on "ship a feature", "implement X", end-to-end workflow, before committing.
---

# Feature Shipping Discipline

## The sequence

Every feature change follows this seven-step sequence. Each step prevents a specific failure mode:

1. **Read relevant docs** (DESIGN.md / DECISIONS.md / CLAUDE.md / memory)
2. **Propose the change** with the rule it implements quoted
3. **Build** the change
4. **Validate** — sim render / iOS build / web open in browser / etc.
5. **Bump version** if the project version-tags (e.g., `AppVersion.xcconfig`)
6. **Commit** with user request quoted in the message
7. **Push** only on explicit authorization

Skipping any step is where bugs and trust-erosion enter.

## When to invoke

- Starting any feature implementation
- Reviewing what you're about to ship before pressing commit
- After a user pushback that the previous ship was broken — reset to step 1

## Step 1: Read docs

Before touching code, grep the project's binding/decision docs for keywords related to the feature:

```bash
grep -ni "<keyword>" CLAUDE.md DESIGN.md WEB-DESIGN.md DECISIONS.md
```

What you're looking for:

- Rules that govern this surface (DESIGN.md §X.Y)
- Past decisions that constrain the implementation (DECISIONS.md #NN)
- Memory entries about user preferences relevant to the surface
- Anti-patterns the project explicitly rejects

Common skipping consequence: implementing a pattern the project rejected six months ago, getting it pointed out at PR review, redoing the work. Cost: hours.

## Step 2: Propose with rule quote

Open your proposal with the rule citation. See [[binding-design-doc-discipline]] for the full pattern.

Short version:

> "Per DESIGN.md §X.Y, [rule]. I'll implement this as [approach]. The §Z anti-pattern of [forbidden shape] is explicitly avoided."

If no rule fits: propose a new rule first, get sign-off, THEN implement.

Common skipping consequence: building something the user immediately rejects because it violates a rule they care about. Cost: a full iteration.

## Step 3: Build

The actual code change. Keep it scoped:

- Fix only the bug — don't refactor surrounding code
- No feature additions beyond what's requested
- No "while I'm in here..." cleanup
- No premature abstractions

If you find yourself wanting to refactor, file a TODO + a memory note. Don't expand the diff.

## Step 4: Validate

This step is the corrective lens. Skip it and you ship blind.

Validation depends on the feature type:

| Feature type | Validation |
|---|---|
| 3D / RealityKit render | macOS RealityFoundation sim → PNG → Read tool (see [[3d-feature-sim-validation]]) |
| iOS UI | `xcodebuild build` on iPhone 17 Pro simulator, plus device test for non-trivial UI |
| Web UI | Open in browser, check at 375px AND 1280px breakpoints |
| Backend / Worker | Run locally with test inputs, hit endpoints with curl |
| Data pipeline | Run on a sample, diff outputs against expected |
| Catalog / schema | Run validator script, check no collisions |

The minimum bar: **describe what you observe** in the validation. Not "build succeeded" but "the home screen renders correctly with the new toolbar item visible at the top-trailing slot."

Common skipping consequence: shipping a feature that compiles but is visually broken. User catches it. Trust erodes. See [[3d-feature-debug-loop]].

## Step 5: Bump version

If the project uses version tags (e.g., iOS `AppVersion.xcconfig`, package.json), bump the patch / build number.

For BOBA Playbook style: `MARKETING_VERSION = 2.NNN` + `CURRENT_PROJECT_VERSION = NNN+1`.

The bump connects the commit to a specific release artifact. Skipping makes git history harder to map to TestFlight builds / production releases.

## Step 6: Commit with user-quote

Commit message structure:

```
<Subject — short imperative title — v<version>>

<User quote in quotes — verbatim what they asked for>

<Brief description of changes, organized as numbered fixes if multiple>

Co-Authored-By: <if appropriate>
```

Example:

```
Hero Shot v7.3 — brightness/glow/edge + menu trims — v2.270

User: "This is getting very close to the shipping version."

Five surgical changes:
1) Brightness -20%: post-process EV 0.0 → -0.3 (≈ -19% linear).
2) Glow -15%: rim halo material opacity 1.0 → 0.85.
3) Edge color: sampled palette tone → pure white.
4) Style menu: filtered to Reveal + Showcase only.
5) Length menu: 30s tag removed (5s/10s/15s remain).
```

Why the user quote matters:

- Future you / future contributors can map the commit to the request that drove it
- The quote anchors the change in user observation, not abstract refactoring
- Six months later, you can grep for the user feedback you addressed

Skipping consequence: commit history becomes opaque ("Hero Shot v7.3 — tweaks"). Hard to reason about what each version accomplished.

## Step 7: Push only on explicit authorization

The user has to say "push" or "ship" or equivalent. Pushing without authorization is destructive trust-wise — you've committed to a remote artifact they may not be ready for.

Exceptions where you can push without re-asking:

- The user has explicitly granted continuing authorization for the session ("ship each change as you make it")
- The repo's workflow explicitly auto-deploys main → production (so a commit is functionally a push)

When unsure, ask. The cost of asking is one extra message. The cost of mis-pushing is much larger.

## The shipping-discipline checklist

Before pressing commit:

- [ ] I've grepped the binding docs for keywords related to this change
- [ ] My proposal quoted the rule it implements (or proposed a new rule)
- [ ] The diff is scoped to the requested change (no scope creep)
- [ ] I've validated the change (sim render / build verify / browser check)
- [ ] I can DESCRIBE what I observe — not just "it compiles"
- [ ] Version is bumped (if applicable)
- [ ] Commit message quotes the user's request
- [ ] I have authorization to push (or am asking for it)

If any box is unchecked, stop. The cost of the missing step is bigger than the cost of the next 30 seconds.

## Anti-patterns

### ❌ Skipping the docs read because "I know this codebase"

Two reasons this fails:

1. Memory is fallible — you may misremember a rule that's actually different in the doc
2. The doc may have been updated since you last read it

Grep is fast. Read the matching sections.

### ❌ Validating by "build succeeded"

Build success is necessary but not sufficient. A build can succeed and still produce a broken UI. Always describe what you OBSERVE, not what you intended.

### ❌ Pushing without authorization "because the user obviously wants it"

What's obvious to you isn't always obvious to them. Authorization is one extra sentence. Mis-shipping is one extra apology + rollback.

### ❌ "I'll write the commit message after pushing"

Pushing locks the artifact. The commit message is part of the artifact. Write it carefully BEFORE.

### ❌ Bundling multiple unrelated changes into one commit

Each commit should be one logical change. If you find yourself writing "Also fixed X, Y, and Z" in the commit body, those are separate commits.

## The user-quote pattern in detail

The most distinctive thing in this discipline is quoting the user's request in the commit body. The pattern:

- **Verbatim**, in quotation marks
- **Above** the diff description
- **Captures the WHY** of the change, not the WHAT

This is more valuable than it looks. Commits become a conversation history with the user. Six months later, someone can grep `git log --grep="washed out"` and find every commit that addressed that complaint. Without the quote, that history is invisible.

## See also

- [[binding-design-doc-discipline]] — Step 2 (proposal with rule quote)
- [[architectural-decision-log]] — Step 6 (commits reference DECISIONS.md entries)
- [[3d-feature-sim-validation]] / [[3d-feature-debug-loop]] — Step 4 for 3D features
- [[universal-feature-states]] — Step 4 for any list/grid/feed feature (verify all states)
- [[native-platform-first]] / [[mobile-first-density-design]] — design rules to verify in Step 4
- [[learning-orientation-design]] — pre-Step-1 sanity check: does this feature serve the user's growth?
