# Question-Quality Rulebook

> The binding contract for every question Tidbits generates — offline
> (`tools/corpus/generate_corpus.py`) or live (`Core/Engine/TemplateEngine.swift`).
> Both must satisfy these gates. Synthesized from psychometric item-writing
> research (Haladyna's 31 rules, NBME item-writing guide), professional
> pub-quiz craft, and the auto-generation literature (Seyler/Yahya/Berberich
> 2017; Wohlan 2019). **The open Wikipedia API is a firehose of
> true-but-misleading facts; the product is this filter, not the fetch.**

## The north star

A trivia question is an *engineered information gap* (Loewenstein 1994)
whose resolution is itself a learning event (Roediger & Karpicke 2006).
Every mechanic must resolve that gap with substance, never exploit it for
session time. That single rule is also the app's learning-orientation
mandate.

## A. Stem rules (the question text)

1. **One focused question**, answerable from the stem alone before the
   options are seen (NBME "cover-the-options" test).
2. **Central idea lives in the stem**, not smeared across the options.
3. **No window dressing** — cut words not needed to answer.
4. **Word positively.** Avoid NOT/EXCEPT; if unavoidable, emphasize it.
5. **Low reading load, simple vocabulary** — measure knowledge, not reading speed.
6. **The answer's surface form must NOT appear in the stem** (no clang clue).
   → enforced by `redact()`: blanks the title + any parenthetical disambiguator.
7. **Prefer multiple reasoning pathways** ("guessable"): give enough context
   that a player can triangulate the answer, not just know-or-don't.

## B. Option rules (answer + distractors)

8. **3–4 options; 3 is psychometrically optimal** (Rodriguez 2005). One
   correct + 2–3 plausible distractors. We use 4 for familiarity.
9. **Exactly one defensible correct answer.** Reject anything that admits a
   second (area vs. population; "director of"). → unique-answer gate.
10. **Every distractor verified WRONG.** Substituting a distractor must not
    also validate as true (the single most dangerous auto-generation bug).
11. **Distractors homogeneous with the answer** — same type/`P31` class,
    same grammatical form, similar specificity. → `pickDistractors` ranks by
    shared-description-word overlap to keep them in-domain.
12. **Option lengths roughly equal** — the key must not be the longest.
13. **Plausible distractors, ideally from real misconceptions** (diagnostic).
14. **Numeric/date options**: consistent format, ordered, plausible band, no
    overlapping ranges, no impossible values.
15. **No "All of the above."**
16. **"None of the above" only where objectively verifiable** (we avoid it).
17. **No specific determiners** (always/never/completely) — they cue the key.
18. **No vague frequency terms** (often/usually) — break rank-ordering.
19. **No convergence cues** — distractors must not be permutations that make
    the key "share the most elements."
20. **No grammatical cueing** — every option follows from the stem.
21. **Options not collectively exhaustive** (increase/decrease/no-change).
22. **Vary the key's position** across the bank. → `options.shuffle(using:)`.

## C. Content & integrity

23. **Important, interesting content; avoid trivial-trivia** — tie facts to
    significance (popularity floor proxies this).
24. **No opinion, no trick questions, no "best/most beloved" subjectivity.**
    *Tricky* (fair lateral thinking) is fine; *trick* (misleading) is not.
25. **Never penalize the player who knows more.**
26. **Pin time-varying facts to a date.** Never "the current X"; phrase
    "As of {year}…" and check Wikidata time qualifiers (`P580/P582/P585`).
27. **Avoid contested/NPOV topics** (sovereignty, disputed territory,
    ethnicity/religion of individuals) via a topic blocklist.
28. **Source verification is cardinal.** Prefer referenced facts; cross-check
    infobox vs. Wikidata vs. DBpedia; watch reversibility.
29. **Favor inference over pure recall** — deduction is thinking; recall is
    regurgitation. This is the learning-orientation mandate in one rule.

## D. The 9-gate verification funnel (cheapest-first, reject early)

The generator is a **candidate funnel, not a publisher.**

1. **Single-answer** — exactly one answer in the source.
2. **Distractor-correctness** — no distractor also validates as true.
3. **Distractor type/plausibility** — same coarse type; numerics in band.
4. **Temporal** — time-varying facts need a date anchor + qualifier check.
5. **Popularity floor** — answer + anchors clear a pageview threshold
   (popular subjects are more fun AND far less often vandalized).
6. **Freshness/vandalism** — referenced statement, non-deprecated rank,
   sane numeric bounds, not edited in the last N hours, sources agree.
7. **NPOV/blocklist** — property/topic not contested.
8. **Phrasing** — no empty slots, no answer leakage, grammatical.
9. **Human-in-the-loop sampling** — spot-check; route near-boundary
   difficulty to review. Humans agree with ground-truth difficulty only
   ~62.5% (Seyler), so never trust auto-difficulty blindly.

### What the engine enforces today

**Two corpus paths, both in `corpus.sqlite`:**

1. **Summary-based** (`template_id` `descriptionOf` / `subjectFrom`) —
   `isUsable` + `redact` + `pickDistractors` implement gates 1, 3, 8 and rule
   6 (disambiguation/list rejection, length bounds, answer-leak redaction,
   homogeneous distractors, key-position shuffle). Popularity proxy: appears
   in a category-seeded search with a usable short description.

2. **Wikidata structured** (`template_id` `wd:*`, Decision 024) — the moat.
   `tools/corpus/wikidata.py` derives the answer from a typed SPARQL triple,
   so gates hold **by construction**:
   - **Gate 1 (single answer)** — the property is functional (a country has
     one capital).
   - **Gate 2 (distractor-correctness)** — distractors are typed siblings
     from the same query; a different country's capital is *definitionally*
     wrong for this country.
   - **Gate 4 (temporal)** — dates rendered at year precision only.
   - **Gate 5 (popularity)** — bounded domains (≈200 countries, 118 elements,
     ≈95 Best-Picture winners) are inherently famous.

Still outstanding for both paths: gate 6 (vandalism/freshness cross-checks),
gate 7 (NPOV blocklist), gate 9 (human sampling), and adopting the structured
path in the **live** runtime engine (today live is summary-based only).

## E. Difficulty model (target, not yet shipped)

- **Dual Elo / Glicko-2** = online Rasch/1PL IRT. One rating per *player*
  (θ) and per *question* (δ) in shared logit units; both co-update from each
  answer's surprise term `(X − E)`.
- **Guessing floor**: clamp predicted P(correct) ≥ 1/k (0.25 for 4 options).
- **Engagement set-point: serve questions at ~60–70% predicted success**,
  NOT 50% — the flow channel sits just into the challenge side; 50/50 feels
  punishing.
- **Cold-start** seeds δ from cheap proxies: Wikipedia pageview obscurity of
  the answer (log-banded), extract length, category, presence of dates.
  v1 ships the proxy (`difficulty(for:)`); live co-rating is Phase 2+.
- **Fixed-round distribution** (Daily, assembled quizzes): 40% easy / 40%
  medium / 20% hard, easy-bookended so no one leaves with zero.

## F. Learning integration (the wrong-answer screen is the most valuable in the app)

1. **Ask-before-reveal** is the default flow — pretesting + generation +
   curiosity + retrieval-practice effects, all at once. *Shipped.*
2. **"Why / learn more" card on every answer**, linking the Wikipedia
   source. *Shipped* (the reveal card + `MissedFact.explanation`).
3. **Spaced re-asking of missed facts** (Leitner/SM-2). *Shipped (data):*
   `MissedFact` records misses + resolves them on later correct answers;
   weaving them back into games is the next step.
4. **Hypercorrection on confident errors** — surface confident-wrong
   corrections prominently. *Phase 2* (needs a confidence signal).
5. **Post-game fact recap.** *Shipped* (Results "Tidbits to remember").
6. **Interleave categories** (desirable difficulty). Mixed Bag does this.
7. **Connection/deduction question types.** *Phase 2+.*

---

# v2 — Question diversity & tell-free answers (2026-06-17)

Driven by two research passes (question-type taxonomy across quiz-bowl /
pub-quiz / game-shows / Sporcle / daily-puzzles / assessment item types; and
MCQ distractor-construction craft from Haladyna's 31 rules + the NBME guide +
the KG distractor-generation literature). Problem being fixed: 89% of the v1
corpus was two templates and "How is X best described?" alone was ~45% — a
tedious cliché — and the correct answer was guessable from its form (it was
the real, fuller, more-specific description next to mismatched distractors).

## G. The shape system (kills the monotony)

The summary-based path (and all three live engines) now rotate among **five
question shapes** via a seeded round-robin, each with a **bank of stems**, so
no single phrasing dominates. The round-robin (`SHAPE_ROTATION`) weights
**categorize** (the old "best described") to **1 of 10 slots (~10%)**.

| Shape | What it does | Stems | Answer / distractors |
|---|---|---|---|
| **identify** | Redacted clue → name the subject | 6 | title / typed-sibling titles |
| **jeopardy** | "This {thing} …" declarative → name it | 3 | title / sibling titles |
| **cloze** | First sentence with the subject blanked | 3 | title / sibling titles |
| **categorize** | Subject → pick its description (capped ~10%) | 4 | description / length-matched sibling descriptions |
| **oneliner** | Short description → which subject | 3 | title / sibling titles |

~19 stems total; the seeded rotation guarantees an even spread. Two questions
per subject always use two *different* shapes. The richer question **types**
(superlative, which-came-first, reverse-attribute, odd-one-out, numeric
closest-to, on-this-day, connection) come from the Wikidata path — see the
ranked 33-type catalog in docs/ROADMAP.md → "Question-type backlog".

## H. The no-tells checklist (form must never reveal the answer)

The root tell: writers over-elaborate the key and treat distractors as an
afterthought. Defenses the option-generator applies:

1. **Length band** — prefer distractors within ~1.3× the key's length
   (`descDistractors` ranks siblings by length proximity; the "longest option
   is the answer" tell). 
2. **Specificity parity** — distinguishing detail belongs in the stem, not the key.
3. **Typed siblings only** — distractors share the subject's domain (ranked by
   description word-overlap) so none is the odd-one-out (Haladyna G23).
4. **No clang** — the answer/title is redacted from any displayed clue (G28b).
5. **Random position** — options shuffled per question (programmatic shuffle is
   unbiased; the middle-position tell is a human-authoring artifact).
6. **Numeric** (Wikidata numeric templates): distractors straddle the true
   value in multiplicative ratio bands, consistent format — never all on one
   side, never the exact median (Haladyna G22).
7. **Self-test**: if you can pick the answer with the stem hidden, the set leaks.

## I. Distractor sourcing by answer type (target state)

- **Entities**: same-P31 siblings ranked by `sitelinks` (fame) + a second
  shared property; **P1889 "different from"** edges are the best confusables.
- **Dates**: era-tiered offsets (modern ±1–5, ancient ±10–100), decade-consistent.
- **Numbers**: multiplicative ratio bands (e.g. 0.55/1.35/1.9×), jittered.
- **Misconception distractors** (most diagnostic + fun): P1889, "not to be
  confused with" hatnotes, "list of common misconceptions" — tag provenance.

Difficulty is tuned by **distractor semantic distance band [Δ₁, Δ₂]** (close =
hard but below the "also-correct" ceiling), not by changing the fact. v2 ships
the typed-sibling + length-normalization layer; the P1889/embedding-band and
the numeric/date recipes land with the Wikidata template expansion.
