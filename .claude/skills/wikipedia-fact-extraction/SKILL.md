---
name: wikipedia-fact-extraction
description: Use before touching how Tidbits turns Wikipedia into trivia — the proprietary article-parsing + fact-extraction + question-construction method that powers the offline corpus generator (tools/corpus/) and, by mirror, the live TemplateEngine. Carries the API surface to build on, the stdlib precision-first extraction pipeline (infobox depth-scanner, sentence segmentation, appositive/relation/date triples, coreference-safe stems), the distractor-sourcing recipe (morelike / typed siblings / {{distinguish}} confusables / numeric bands), and the reject funnel that keeps a wrong "fact" from ever shipping. Triggers on Wikipedia parsing, article extraction, corpus generation, generate_corpus.py, wiki_extract, infobox parsing, fact extraction, fact triple, distractor sourcing, morelike, pageviews difficulty, question generation, "make better questions", answer leakage, MediaWiki API, Wikidata SPARQL, on-this-day.
---

# Wikipedia Fact Extraction — Tidbits' proprietary method

How we turn Wikipedia into trivia. Synthesized from the long history of
Wikipedia-based QG (Heilman & Smith 2010; Seyler/Yahya/Berberich 2015/2017;
Du & Cardie 2018; Mitkov & Ha; Susanti 2018; Stasaski & Hearst 2017; the
WikiTrivia / linkeddata-trivia open-source recipes) and the current
(2025-2026) Wikimedia API surface. We are not the first to do this; this
skill is how we are best at it.

## The one rule

**The corpus is the filter, not the fetch.** The open Wikipedia API is a
firehose of true-but-misleading, ambiguous, vandalized, and out-of-context
facts. Value is created by *rejecting* most of them. Every stage below has an
explicit drop-exit; a fact must survive all of them to become a question.

**Precision ≫ recall.** A wrong "fact" in a trivia app is far worse than a
missed one — it teaches the player something false and destroys trust. When in
doubt, drop the candidate. We would rather generate 3 excellent questions from
an article than 12 shaky ones.

**Build-time, not runtime.** Extraction is a corpus-build step
(`tools/corpus/`). Clients consume the published `corpus.sqlite` (see
`shared-data-plane-contract`); they never parse Wikipedia. So this method can
be arbitrarily heavy — it runs once, offline, cached — and every platform
inherits the quality for free.

## Stack constraint

`tools/corpus/` is **stdlib-only** (`urllib`, `re`, `html`, `unicodedata`) —
no spaCy/NLTK/transformers, no third-party deps (mirrors the no-deps rule the
clients live by). Everything here is achievable with rules + regex + the
Wikimedia API. That is a feature: rule-based extraction is high-precision and
auditable, which is exactly the trade a trivia app wants.

---

## A. The API surface — the six endpoints to build on

All calls: `User-Agent: TidbitsTrivia/1.0 (contact ben@learningischange.com)`,
`&maxlag=5` for bulk, serial (not parallel) requests, exponential backoff on
429/503, `Retry-After` honored. As of 2026 Wikimedia enforces REST rate limits
(Phase 1 Mar 2026, Phase 2 Apr 2026) — **cache every dataset to disk** so a
regen never re-hits the network (the `cache/` pattern `wikidata.py` already uses).

1. **`action=parse&prop=wikitext|parsetree|sections`** — the foundation. The
   only way to get the **infobox as structured key→value facts** and a real
   section TOC. One title per call; cache hard. (Core REST `/w/rest.php/v1/page/{title}`
   returns the same wikitext + Wikidata id in one tidy call — fine alternative.)
2. **`action=query&prop=extracts&explaintext=1&exsectionformat=wiki`** —
   **drop `exintro`** to get the FULL body as plaintext split by `== headers ==`.
   This is the single biggest upgrade over "first sentence." (Note: full-body
   extracts are *not* batchable — `exintro` is required for multi-title; fetch
   bodies one at a time, batch only intros, 20/call.)
3. **`list=search&srsearch=morelike:TITLE` + `hastemplate:"Infobox X"` +
   `deepcat:TOPIC`** — distractors done right. `morelike:` returns
   semantically-confusable same-domain entities (the best distractor source in
   the whole API); `hastemplate:`/`deepcat:` build type-matched candidate pools.
4. **`prop=pageassessments` + `/api/rest_v1/metrics/pageviews/per-article/.../user/...`**
   — quality + difficulty. Assessments give FA/GA `class` and `Top/High`
   `importance` (pick fact-dense, safe subjects); pageviews (`agent=user`) tier
   easy↔obscure and match distractor fame.
5. **`/api/rest_v1/feed/onthisday/{events|births|deaths}/{MM}/{DD}`** — turn-key
   date trivia: pre-vetted notable items already linked to articles+extracts.
   `selected` is editor-curated (highest quality). Marked experimental — pin behavior.
6. **`{{distinguish}}` / `{{about}}` hatnotes** (from `prop=wikitext` or the
   `hatnote` divs in `prop=text` HTML) — editor-curated "things people mistake
   this for." The highest-plausibility confusable distractors that exist.

Keep the **Wikidata SPARQL path** (`wikidata.py`) as the structured moat for
bounded famous domains — triples give single-answer + typed distractors by
construction. This skill is about making the **free-text path** nearly as good.

---

## B. The extraction pipeline (stdlib, precision-first)

Order is load-bearing: the two most reliable sources (infobox, lead definition)
are mined first and become the **verification oracle** for riskier body prose.

```
Stage 0  Fetch      action=parse&prop=wikitext (full) + extracts full-body. Cache both.
Stage 1  Infobox    depth-counting brace scanner → {key: cleaned value}.   ← oracle
Stage 2  Clean      comments→refs(record had_ref)→templates→links→tags→entities
                    →pronunciation/IPA parens (DROP)→superscripts→whitespace.
                    KEEP the (1867–1934) life-dates paren; DROP the (/ˈkjʊəri/) paren.
Stage 3  Segment    protect abbreviations/initials/decimals/acronyms → split only on
                    a terminal followed by a capital → restore. Tag each sentence
                    (index, from_lead, had_ref).
Stage 4  Define     DEF_COPULA / DEF_APPOS on the LEAD sentence only →
                    subject_is_title() GATE → parse paren (birth/death) →
                    split_type() → nationality + occupation facts.
Stage 5  Coref      leading pronoun / "The city" → title; DROP if any pronoun/deixis
                    remains (mid-sentence "it/they/this" = non-title referent).
Stage 6  Relate     per surviving sentence, split on coordinators → VERB_PATTERNS
                    (won/founded/wrote/directed/discovered/located_in/capital_of…),
                    object-sanity GATE; date/number/superlative regexes, normalized.
Stage 7  Score+gate score_fact(); infobox-match is a GATE for numeric facts;
                    keep only conf ≥ threshold; dedup (lead+infobox agree = 1 fact, higher conf).
Stage 8  Emit       (subject, relation, object, value_type, precision, confidence, source_url)
                    precision drives the template — never ask more precision than extracted.
```

### The non-obvious technique notes (don't re-derive these)

- **Infobox needs a depth-counting scanner, NOT regex.** Templates nest
  (`{{convert|{{...}}}}`) and `|` appears inside `[[a|b]]` links — a `\{\{.*?\}\}`
  regex corrupts every value. Match braces by depth; split fields on `|` only at
  template-depth-0 AND link-depth-0. ~30 lines; it's what `wikitextparser` does
  internally. The infobox is also the **oracle**: a prose `born 1867` that equals
  `infobox.born` is near-certain; a mismatch DROPS the prose fact.
- **Sentence segmentation = protect-then-split** (pySBD strategy). Don't write
  one perfect boundary regex. Replace every *non-terminal* period (abbreviations,
  `U.S.`, middle initials `Marie S. Curie`, decimals `3.14`) with a sentinel,
  split on the terminals that remain (require a capital/quote/paren follower),
  then restore. The capital-follower lookahead is the biggest precision lever.
- **The title is a free anaphora anchor.** The page is about exactly one entity,
  so a clause whose subject is a pronoun or absent resolves to the title. That's
  the whole coreference trick — and the reason to DROP any sentence still
  carrying a *mid-sentence* pronoun (it refers to something else introduced earlier).
- **Tag precision on every date/number.** `(1867–1934)` → year-precision facts,
  not a fake ISO date. The precision tag chooses the template ("In what year…?"
  vs "On what date…?") so we never ask for precision we didn't extract.
- **Split clauses on coordinators before verb patterns.** "won the Nobel Prize in
  Physics in 1903 and the … in Chemistry in 1911" must split on ` and ` first, or
  a non-greedy object swallows both.

---

## C. Question construction & answer-type → WH

Adopt **overgenerate-then-rank** (Heilman & Smith 2010 — nearly doubled
acceptable-question yield): emit several candidate (fact → stem) shapes liberally,
then keep the top by cheap proxies (short stem + short answer, clean WH word, no
residual pronoun/negation, superlative-anchored, answer is a proper-noun/date/number).

**Answer-type → WH table** (kills mismatched questions, one dict):
PERSON→Who · DATE/YEAR→When (or "In what year") · PLACE→Where · NUMBER→How many/much ·
ORG/WORK/THING→What/Which.

Favor **inference over recall** (the learning mandate, QUESTION-QUALITY rule 29):
superlatives ("first/largest/only"), chronology ("which came first"), and
relation triples are more thinking-rich than "name the definition."

---

## D. Distractor sourcing by answer type (the wrong-answer half)

The rule everywhere: **type-bucket, then select from a rank window 2..N — never
top-1, never random.** Too close (a synonym/alias of the key) is also-correct;
too far (wrong type/unit/magnitude) is obviously wrong. Hard-but-fair lives in the band between.

- **Entities** — primary pool from `morelike:ANSWER` (Wikipedia's own similarity
  graph) or same-`P31`/category siblings; rank by pageview/sitelink fame near the
  answer's; reject any alias/redirect of the key. **`{{distinguish}}` hatnote
  targets are the premium pick** — editor-curated confusables.
- **Dates/years** — era-tiered near-miss offsets (modern ±1–5, ancient ±10–100),
  same calendar precision, decade-consistent; never the exact median of the set.
- **Numbers** — multiplicative ratio bands straddling the truth (e.g.
  0.4/0.6/2.5×), jittered, consistent format, same unit, never all on one side
  (the existing `numeric_distractors` in `wikidata.py` is the reference impl).
- **Length/specificity parity** — distractors within ~1.3× the key's length;
  distinguishing detail belongs in the stem, not the key (the "longest option is
  the answer" tell).

Difficulty is tuned by the distractor **semantic-distance band**, not by changing
the fact. Match distractor fame to the answer's (pageviews) so the item isn't
trivially eliminable.

---

## E. The reject funnel (cheapest-first; the value is here)

A candidate dies at the first failing gate. In rough cost order:

1. **List/disambiguation/meta** — title `^(List|Index|Timeline|Glossary) of` or
   `(disambiguation)`; `{{disambiguation}}` / `__DISAMBIG__`; meta descriptions.
2. **Answer-alias leakage** — strip the answer + ALL its aliases (title, bare
   title, redirects, Wikidata labels), case/punct-folded, from the stem; reject
   if any distinctive (non-common) token survives. The principled version of the
   repo's 48%→0% fix (Seyler ICTIR §3.2). Also: reject if any distractor == key.
3. **Pronoun/deixis stem** — reject sentences with a residual mid-sentence
   `it/they/he/she/this/these/the former` after coreference resolution.
4. **Hedge / NPOV / Words-to-Watch** — reject `alleged/so-called/reportedly/
   arguably/notably/some say`; `{{citation needed}}`/`{{POV}}`/`{{disputed}}`;
   contested topics (sovereignty, ethnicity/religion of individuals).
5. **Relative-time / unanchored superlative** — reject `currently/now/today/
   recently/as of` and present-tense superlatives **unless** a year was captured
   and is stamped into the stem ("As of {year}…"). Pin time-varying facts.
6. **Ambiguity** — only build "what is the X of Y?" from single-valued properties
   (capital, birth year, director) where (subject,relation)→exactly one object.
7. **Foreign script / math / oversized** — non-Latin scripts, LaTeX, len > 320
   (existing `_FOREIGN` gate).
8. **Verification** — numeric prose fact must match the infobox (gate, not bonus);
   prefer lead + `<ref>`-backed; when prose and infobox disagree, trust the
   infobox and drop the prose fact.

---

## F. Difficulty (cheap, no-ML — Seyler WWW-2015 scalar)

`difficulty ≈ popularity + selectivity + coherence`, all from counts:
- **popularity** — pageviews (`agent=user`) / sitelink count of the answer (log-banded).
- **selectivity** — `1 / (#entities sharing that relation-value)` — a rare value is harder.
- **coherence** — overlap of the cue's and answer's backlink/category sets — a
  famous answer becomes *hard* when paired with a low-coherence (surprising) cue.

Serve at ~60–70% predicted success (flow channel), bookend easy. Never trust
auto-difficulty blindly — humans agree with ground truth only ~62.5% (Seyler).

---

## G. How this lands in the repo

- `tools/corpus/wiki_extract.py` — the stdlib extraction library (Stages 1–8).
  Has a `__main__` demo: fetch a few real titles, print extracted facts → **always
  verify the printout before regenerating the corpus** (debugging philosophy:
  observe, don't iterate blind).
- `tools/corpus/generate_corpus.py` — calls `wiki_extract` to add fact-based
  question shapes alongside the summary shapes; `wikidata.py` stays the structured moat.
- `docs/QUESTION-QUALITY.md` is the binding rulebook — the gates here must match
  it. **Fix the doc first, then the feature** when they diverge.
- Regen is build-time; clients just reload `corpus.sqlite`. Bump the corpus
  version the web logs, and re-sync the Android asset (`scripts/sync_shared_assets.sh`).
- Live `TemplateEngine.swift` is a separate summary-based fallback — mirror only
  the *gates* (leakage, reject funnel) there, not the heavy extraction.

## What good looks like

Before: "How is {X} best described?" with the real fuller description as the key.
After: "Marie Curie won this prize in both Physics (1903) and Chemistry (1911) —
what field did the Physics prize honor?" / "In what year was {redacted subject},
the {type}, founded?" — verifiable single answers, type-matched confusable
distractors, the form revealing nothing.
