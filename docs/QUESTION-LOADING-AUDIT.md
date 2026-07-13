# Question loading & coverage audit (2026-07-13)

Triggered by: "significant issues loading questions, particularly Surprise
(novel category × type combinations)." Two root causes, two tracks of fix.
Both shipped across web / iOS / iPadOS / macOS / tvOS / Android / Windows.

## Root cause 1 — corpus coverage holes (data)

Questions are split into per-type files (byte-identical on every platform). The
(category × type) matrix had holes, so a combination could resolve to **zero**
questions:

| Type | Before | Hole |
|---|---|---|
| oddoneout | only `geography` (161) | 6 of 7 categories = 0 |
| enumerate | 11 rows, mis-cased `Geography`/`Science` | all 7 lowercase ids = 0 |
| match | sports=0, history=2 | sports empty, history stunted |

`gen_oddoneout.py` builds only from country→continent data (geography-only by
construction); `gen_enumerate.py` emitted capitalized ids and only continent +
a few hardcoded sets; `gen_match.py` produced no sports pairs.

## Root cause 2 — the load path errored instead of falling back (code)

Same design on every platform: **Surprise** picks `random(mode) × random(category)`
with no coverage check; six special types filter by category with **no fallback**
(only the classic MCQ path tops up from live Wikipedia). Result on an empty pool:
web/Apple/Android showed a **misleading error screen** ("couldn't reach
Wikipedia"); Windows showed a **blank dead screen** (no error phase, no in-game
quit). A short pool played a **silently truncated game**. `oddOneOut`/`enumerate`
dodged their holes by forcing `"mixed"` — but that showed **wrong-category
content** (Odd One Out was always geography).

## Track A — never error (code, all platforms)

Each platform's provider gained a `filled()` fallback for the category-filtered
special types:

> picked category → **relax to the whole type pool (`"mixed"`)** to top up →
> **Classic corpus backstop** only if a type file is missing entirely.

Because every *type* has ≥ its required count in total, an empty round is now
**mathematically impossible** for any (category × type) — Surprise included. Keeps
the MODE pure (a Match Up round stays Match Up). Incidental fixes: tvOS Surprise
double-roll; enumerate lowercase-id defense.

- Web `js/app.js` `_pullType`; Apple `QuestionProvider.filled`; Android
  `GameState.filled` + `filledType`; Windows `QuestionProvider.Filled`.
- Verified: web sim (sports match 0→6); iOS `xcodebuild` SUCCEEDED; Android
  `compileDebugKotlin` SUCCEEDED; Windows test asserts **all 56 (category ×
  special-type) combos non-empty**.

## Track B — full coverage (data) via an authoring pipeline

A robust **author → adversarial-verify** pipeline (`tools/corpus/` + workflows)
filled the holes; only questions that pass an independent ruthless fact-check are
kept:

- Odd One Out: 72 authored → **67 verified** across the 6 empty categories.
- Match Up: sports 0→11, history 2→13.
- Enumerate: was geo/science only → **all 7** categories; casing fixed.

Merged with `tools/corpus/merge_authored.py` (type-aware row schema, dedupe,
content-hash version, syncs assets + iOS Resources + Android assets; Windows via
its Content link). **Every (category × type) cell now has ≥1 question.**

Finally, now that oddoneout/enumerate have per-category coverage, both were
flipped from forced-`"mixed"` to **category-filtered** (with the Track A
fallback) — so picking Sports + Odd One Out gives sports questions, not the
geography-dominated mix.

## Reusing the authoring pipeline

`tools/corpus/merge_authored.py <oddoneout|match|enumerate> <survivors.json>`.
Authoring workflow scripts live under the session's `workflows/scripts/`. The
non-negotiable rule: **every authored question passes an independent verifier**
(answer correct, all distractors wrong, unambiguous, well-known) before merge —
LLM-authored trivia is only safe with the gate.
