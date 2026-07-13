# Corpus expansion to 100k+ — strategy & plan (2026-07-13)

Goal: the best trivia database in the space — grow from ~20k to **100k+**
questions across all 7 categories × all question types, spanning difficulty
tiers and weighted toward high-interest. Research: 3 Opus agents (sourcing,
writer, difficulty) + web (Wikimedia pageviews API, Wikidata SPARQL).

## Verdict: POLISH, not overhaul

The live writer is `tools/corpus/sources/build_corpus.py` (reads
`corpus_source.sqlite` → `assets/corpus.json`), already a correct **grounded
deterministic core → LLM delight-rewrite (`apply_delight.py`) → score/audit
gates → gen_*.py fan-out into 9 game types** hybrid. It is UNDER-FED, not wrong.
`tools/corpus/wikidata.py` already has the six generator families with polished
stem banks — they just run against live SPARQL for 5 datasets instead of the
local tables.

## The 10× is unused data

`build_corpus.py` mines only `prose` (describe/cloze) + 5 relations. It uses
**none** of:
- `fact` (25,163 rows): birth 7050, death 3712, inception 3041, height 2038,
  publication 1489, area 1414, mass 1369, population 1219, elevation 848,
  length 409, discovery 336, atomic_number 62.
- Resolved relations: country P17 (3862), language P37 (678), founder P112,
  creator P170, discoverer P61, manufacturer P176, performer P175.
- **7,708 subjects (38%) with `category=NULL` are silently skipped** by the
  category-partitioned build loop.
- `related` (157,090 co-visitation edges) — used for subject-answer distractors
  only, not value-answer/reverse.

## Phased path

| Phase | Action | Cost | Est. questions |
|---|---|---|---|
| **0** | Recategorize the 7,708 NULLs (extend P106/P31 maps; DROP list-articles like Q13406463) | 0 API | 20k → ~35k |
| **1** | `fetch_top_qrank.py --add 30000` + `fetch_prose.py` (incremental); per-category cap | ~30 min | ~50k subjects |
| **2** | Wikidata SPARQL typed backfill for thin categories (sports 748, geography 1157, music 1281) | ~1–2 hr | category parity + hard tier |
| **3** | `fetch_clickstream.py` refresh over the expanded set | ~15 min | distractor quality |
| **4** | **Wire fact/relation templates** into build_corpus.py (fold in wikidata.py's 6 families, driven off local tables) | code | **the multiplier → 100k+** |

Yield model: ~50–60k subjects × ~3–4 grounded questions each (identity +
describe/cloze + 2–3 fact/relation) clears 100k, then gen_*.py fan-out multiplies
into the 9 game types.

## Template families to add (Phase 4) — each grounded in a local table

- **Forward fact** ← `fact`: birth/death/founded/released/discovered year,
  atomic number. "In what year was X born?"
- **Forward relation** ← `relation`: country (P17, biggest single win),
  official_language, founder, creator, discoverer, manufacturer, performer.
- **Reverse relation** ← flip 1:1 relations. "Of which country is X the capital?"
- **Superlative** ← `fact` numerics: most-populous/largest/tallest/highest/
  longest (4 same-P31 subjects). Feeds oddoneout + thisorthat.
- **Chronology** ← `fact` dates: born-first/founded-first/released-first. Feeds
  the `order` game.
- **Classification** ← `subject.p106`/`p31`: "Which of these is a physicist?"
- **Numeric closest-call** ← `fact` numerics → closest.json.

## Difficulty: per-QUESTION, not per-subject

Composite hardness `H = 0.40·(1−fame) + 0.30·fact_obscurity + 0.15·(1−richness)
+ 0.10·(1−answer_recognizability) + category_offset`, where fame = log-rank
percentile of `subject.qrank`, fact_obscurity ranks the specific fact asked
(birth year easy; precise height hard). Map to tiers by FIXED thresholds to hit
the **target distribution 20/30/30/15/5** (easy→expert) — the current even
quintile split makes 40% hard, too brutal. Fix the two live bugs: 48% of
subjects default to difficulty 3; the corpus tuple's index-5 difficulty is dead.

## High-interest weighting

Sample subjects ∝ fame: top-40%-fame subjects yield 3–5 questions, middle 1–2,
bottom 0–1. Hard tier = "hard questions about famous things" (cap tier-4/5 with
obscure subjects at ~25%). Down-weight bare numeric facts on low tiers (dry).

## Distractors: tier-modulated via the 157k `related` table

- Tier 1: far / low-relatedness (one obviously-absurd option).
- Tier 2–3: same type, similar fame band, low co-occurrence.
- Tier 4–5: highest `related.n` neighbours + same P106/P31 + numeric proximity
  (birth year ±3). Extend the engine from subject-answers to value-answers
  (a director's confusables) and reverse questions.
- New gates: reverse-uniqueness (value→subject 1:1), numeric-separation,
  superlative-margin (≥10–15%), group type-consistency, stale-numeric.

## LLM (Sonnet) usage — triaged, grounded, re-gated

Deterministic-first: every question is generatable + correct WITHOUT the LLM.
Sonnet only (a) polishes phrasing/hooks on the top ~20–30k fame subjects (where
robotic phrasing is noticed), (b) writes a clue from passed-in structured facts
(may not invent), (c) proposes a hard distractor — all re-run through the SAME
deterministic gates + verified against the DB. Keeps 100k cheap and correctness
a property of the DATA, not the model. Opus = research/architecture; Sonnet =
authoring/polish (this split).

## Order of execution (highest leverage first)

1. **Phase 0** recategorize (free +15k) — `enrich_subjects.py` maps + drop lists.
2. **Phase 4** fact/relation template wiring (the multiplier) — fold `wikidata.py`
   families into `build_corpus.py` off local tables + new gates.
3. **Phase 1–2** subject expansion (QRank --add, SPARQL backfill).
4. Per-question difficulty rebuild + tier distractors.
5. Sonnet polish pass over top-fame subjects.

Each phase: rebuild → measure question count + per-category/tier distribution →
audit a sample → commit. Never ship an ungrounded or ungated question.
