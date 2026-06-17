---
name: learning-orientation-design
description: Use before implementing any new feature — the test is whether the feature serves human learning and growth, not replacement. Ask four questions: Does it deepen understanding? Invite participation? Support human agency? Pass the clarity-over-cleverness check? Features that fail these tests get refactored or rejected at proposal stage, not after shipping. Triggers on new feature proposal, building a tool, "should we add X?", AI feature, automation, learning product.
---

# Learning-Orientation Feature Design

## The "why" frame

Every feature should serve **human learning and growth — not replacement.** The tool exists to make someone more capable, more engaged, more themselves. Not to think for them, not to take over what they could do themselves.

Before implementing any feature, ask:

1. **Does it deepen understanding?** Does the user come away knowing more about the domain, or just having gotten a task done?
2. **Does it invite participation?** Does the feature let the user contribute their judgment, or does it tell them what to think?
3. **Does it support human agency?** Does it make the user more capable on their own, or more dependent on the tool?
4. **Does it pass the clarity-over-cleverness check?** Is the implementation the simplest thing that could work, or is there a fancier approach we're tempted by?

A "yes" to all four is the bar. A "no" to any is a redesign signal, not a continue signal.

## When to invoke

- Proposing a new feature, especially one with AI / automation / recommendation
- Reviewing a feature spec before implementation
- Deciding between "smart" automation and a "manual but understandable" approach
- Auditing an existing feature that "feels off" but you can't articulate why
- Working on educational, learning, or growth-oriented products

## The four questions, expanded

### 1. Does it deepen understanding?

Features should leave the user with more domain knowledge than they started with. Not always explicitly (we don't lecture), but structurally.

Examples:

- **Search with explicit filter tokens** (Weapon: Fire, Treatment: Battlefoil) → user learns the catalog's organizing concepts as they search.
- **Recommendation engine that just shows "Top 10 for you"** → user learns nothing about WHY those are the top 10. They become dependent on the recommender.

Pattern: **expose the structure of the domain through the UI**, don't hide it behind an opaque "for you" surface.

### 2. Does it invite participation?

Features should give the user something to contribute. Their judgment, their preferences, their data, their context — the feature should let them shape the output.

Examples:

- **Custom Rainbows** (user-defined collecting goals) → user picks what THEY want to collect, the tool tracks their progress against THEIR criteria. Their judgment is the input.
- **AI "best deck for you" generator** → user is a passive recipient. No contribution, no participation.

Pattern: **the user is a co-author of the result**, not a recipient.

### 3. Does it support human agency?

The user should be more capable AFTER using the feature than before. Not dependent on the tool to do the thing again.

Examples:

- **Walkthrough that demonstrates a feature anchored on real UI** → user learns by doing. They can do it again without the walkthrough.
- **"Smart" UI that detects what the user is "trying to do" and silently does it for them** → user never learns the underlying action. If the smart detection fails, they're stuck.

Pattern: **the feature is a teacher, not a replacement**. After using it once, the user knows how to do it.

### 4. Clarity over cleverness

Pick the simplest thing that could work. Not because clever is bad, but because simple is REVISITABLE. Future you (or another developer, or the user themselves) needs to be able to understand the feature.

Examples:

- **Card-detail layout with 6 cells in canonical order** → simple to read, simple to extend.
- **AI-generated card detail layout that varies per card** → clever, impossible to predict, hard to debug.

Pattern: **the user's mental model is the constraint, not the tool's capability**. A clever feature the user can't predict is worse than a simple one they can.

## The "what would we get wrong by automating this?" test

Many features tempt automation. Before automating any user-facing action, ask: **what would the user lose by not doing this themselves?**

Examples of valuable losses (= reasons NOT to automate):

- **Learning the structure of the data** — a recommender that scores cards for you removes the need to develop your own taste.
- **Building intuition** — auto-generated decks remove the iteration loop that develops a player's skill.
- **Discovering preferences** — auto-fill of preferred contacts removes the moment of considering who to invite.

Examples of OK automations:

- **Tedious repetition** — autocomplete of card names you've typed 50 times.
- **Pure mechanical work** — calculating deck cost from card list.
- **Error prevention** — flagging duplicate cards before submission.

The line is: **automate the mechanical, preserve the meaningful.**

## Anti-patterns

### ❌ "AI will figure out what they want"

If the feature relies on a model knowing the user's mind, the user is reduced to a recipient. Find a way for them to contribute their judgment.

### ❌ Onboarding that explains the app via a slide deck

Slide decks bypass the user's engagement — they're passively reading marketing. Walkthroughs that anchor on real UI let the user learn by doing.

### ❌ Features that "do everything in one tap"

Sometimes the user benefits from the intermediate steps. A "buy this in one tap" flow that skips review removes a moment of consideration. Sometimes that's right (cheap purchases); sometimes that's wrong (expensive purchases, public actions). Don't default to one-tap; pick deliberately.

### ❌ Hiding the domain to make the UI "simpler"

A trading-card app that calls weapons "categories" because "weapons" is jargon is robbing the user of vocabulary they'd benefit from learning. Real users want real terms.

### ❌ "Smart" inference that the user can't predict

When the tool guesses what the user wants and silently does it, two failure modes appear: (a) the user doesn't notice the inference and trusts the result wrongly, (b) the user notices the inference is wrong and loses trust. Either way, the user is worse off than if the tool had been explicit.

## Sequencing — when to apply this skill

This skill is most valuable BEFORE implementation. Once a feature ships, redesigning around these values is expensive.

The right invocation point:

1. **Feature proposal stage** — user requests "build X." Before writing code, run the four questions. If any are no, propose the redesign.
2. **Spec review stage** — feature is specified but not implemented. Same questions. Catch issues before code is written.
3. **Code review stage** — feature is implemented. Last chance to flag. Often the answer here is "ship + iterate" rather than redesign.

## Real-world example

BOBA Playbook (the project this skill came from) has a CLAUDE.md "Why We Build" statement that's exactly this framing:

> Every feature is built in service of human learning and growth — not to replace thinking, but to deepen it. Ask at each decision point: Does this invite the user to engage more fully, think more critically, or connect more meaningfully? The goal is never a slick product — it is a tool that makes someone more human.

Concrete decisions that flowed from this:

- **Search exposes filter tokens** (weapon, treatment) rather than hiding them behind an opaque "for you" model — user learns the catalog's organizing concepts
- **Walkthroughs anchor on real UI** instead of slide decks — user learns by doing
- **Custom Rainbows let users define their own collecting goals** — user contributes judgment
- **Card-detail uses a canonical 6-cell layout** consistently — user builds mental model of the data
- **NO algorithmic trader recommendations** in the trade feature — pure passive matching, §230 protected and human-judgment-preserving

## See also

- [[binding-design-doc-discipline]] — the "why we build" statement usually lives in a binding doc, often at the top
- [[mobile-first-density-design]] — the design taste this skill is paired with (show the data, let the user filter)
- [[universal-feature-states]] — walkthroughs and hints (teaching surfaces) flow from this skill's "support human agency" value
