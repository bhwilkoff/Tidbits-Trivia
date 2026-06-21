# Corpus Source Pipeline — Design Doc (binding)

> **Status:** plan of record (not yet built). Supersedes the seed-search + live-API
> producer described in `DATA-CONTRACT.md` once Phase 1 ships. The shipped
> artifact contract (`corpus.sqlite`/`*.json` schemas, the bundled-set pattern)
> is **unchanged** — this doc only changes *where the producer gets its raw
> material*. See Decision 032.

## 1. The problem (why we're changing the source)

Every data path today is a **rate-limited live API over a tiny, badly-selected
slice of Wikipedia**:

- **4,540 questions from ~1,956 distinct articles.** Wikipedia has ~6.9M. We've
  touched **0.03%**.
- The selector is **search relevance to ~70 hand-written seed terms**
  (`CATEGORY_SEEDS` in `generate_corpus.py`), *not* popularity. Pageviews only
  enter after the fact as the F3 difficulty overlay. So we pull "whatever matches
  `['ancient history','world war',…]`," not "the most worth-knowing subjects."
- **Throttle ceiling:** corpus via `api.php` (~5 req/s, `maxlag=5`), E1 enrichment
  via the Wikidata API, F3 difficulty via the pageviews API — all serial, all
  backoff-on-429. Crawling millions of articles this way is days-to-weeks.
- The new non-MCQ types (closest / ordering / matching / odd-one-out / enumerate)
  are starved: they need **structured facts** (numbers, dates, 1:1 relations, list
  membership), and those come from the same throttled Wikidata API. Q8 enumerate
  could only muster 11 puzzles for exactly this reason.

The fix is **build-time source artifacts** (dumps + curated derivatives) instead of
live API crawling. The corpus ships offline and tiny (~1.3 MB); the source
artifacts live **only on the build machine** and never reach a client. Size is a
one-time local cost; the payoff is a 50–100× larger, *truly* popularity-ranked,
structured candidate pool.

## 2. Principle — layered, derivative-first

**Do NOT "download Wikipedia" (the 90 GB+ `pages-articles` wikitext dump).** Each
job uses the **smallest, cleanest artifact** that does it. Three of the four layers
are <500 MB; only the facts spine is large, and even that can be pre-scoped.

| Layer | Job | Chosen source | Why this one | Size / License |
|---|---|---|---|---|
| **Select** | Which subjects are worth asking about | **Vital Articles L4 (~10k) / L5 (~50k)** → resolve to QIDs, then rank/gate by **Qrank** | VA is the only *human-curated-for-importance* list, sized to our target band; Qrank is cross-project, trailing-12-mo popularity per QID. Together they replace seed-search and fix the "search-relevance not popularity" flaw. | VA: API/PetScan (KB). Qrank: ~104 MB, **CC0**, weekly |
| **Facts** | Numbers / dates / 1:1 relations for non-MCQ types | **Wikidata `latest-truthy.nt.bz2`**, filtered to our QIDs (optionally via **wdumper** to pre-scope) | Flat best-rank N-triples — trivially streamable; **CC0** (no ShareAlike on the structured facts); the backbone for closest/ordering/matching/odd-one-out/enumerate. Kills the enrich API ceiling. | ~43 GB bz2 (or a wdumper subset <1 GB), **CC0**, weekly |
| **Prose** | Clean stems for "what is X?" MCQs | **Kiwix `wikipedia_en_top_mini` ZIM** (proto) → **CirrusSearch content** (scale) | top_mini = ~50k most-read subjects with a clean lead + infobox in **316 MB**, near-turnkey. CirrusSearch = clean `opening_text`/`text` + `category[]` + `incoming_links` + QID, parse-difficulty 2, weekly. | 316 MB / ~43 GB gz, **CC BY-SA**, monthly/weekly |
| **Distractors** | Plausible wrong answers (the MCQ quality lever) | **Clickstream** confusables × **Wikidata P31/P279** type-match × **Qrank** fame-gate | Clickstream is *empirical human navigation* — its neighbors are entities people genuinely conflate (Monet → Manet/Renoir/Pissarro). Beats today's "category-pooled type-matched siblings." | ~hundreds MB/mo, **CC0/CC BY-SA**, monthly |

Verified source URLs:
- Vital Articles: <https://en.wikipedia.org/wiki/Wikipedia:Vital_articles>
- Qrank: <https://qrank.toolforge.org/download/qrank.csv.gz> (CC0)
- Wikidata dumps: <https://dumps.wikimedia.org/wikidatawiki/entities/> · wdumper: <https://wdumps.toolforge.org>
- Kiwix ZIM catalog: <https://download.kiwix.org/zim/wikipedia/> (`wikipedia_en_top_mini_*`, `wikipedia_en_top_maxi_*`)
- CirrusSearch: <https://dumps.wikimedia.org/other/cirrussearch/>
- Clickstream: <https://dumps.wikimedia.org/other/clickstream/>

**Alternates considered (kept on the bench):** Wikimedia `structured-wikipedia` on
Hugging Face (fresh May-2026 infoboxes+abstracts as Parquet, CC BY-SA, EN+FR only)
is the best *single* fresh facts+prose artifact and a strong substitute for the
Wikidata+CirrusSearch pair if the EN-only limit is acceptable; DBpedia
`mappingbased-*` + `short-abstracts` (small, ontology-clean, but 2022-vintage);
YAGO 4.5 (typed, SHACL-validated). See Decision 032 for the trade rationale.

## 3. Architecture — a local fact store between sources and generators

Today: `seed search → API crawl → generators` (everything coupled to the throttle).

Proposed:

```
sources (VA+Qrank · Wikidata truthy · Kiwix/CirrusSearch · Clickstream)
   └─ tools/corpus/build_source_index.py   (NEW; run ~monthly, streams the dumps)
        └─ corpus_source.sqlite            (build-time only, NOT shipped)
             tables: subject(qid, title, category, qrank, sitelinks, quality)
                     prose(qid, lead, infobox_json)
                     fact(qid, prop, value, unit, datatype)     ← Wikidata truthy
                     related(qid, neighbour_qid, n, type)        ← clickstream
   └─ generate_corpus.py + gen_*.py  (existing; read the LOCAL store, not the API)
        └─ assets/corpus.json + assets/<mode>.json  (SHIPPED — schema unchanged)
```

The generators keep their template shapes and quality gates (`QUESTION-QUALITY.md`)
but draw from a 100× larger, popularity-ranked, structured pool — and get *simpler*
(delete the retry/backoff/cache/maxlag machinery). The shipped artifacts and their
column-order contract (`DATA-CONTRACT.md`) **do not change**.

## 4. Phasing (de-risked, smallest-first)

- **Phase 0 — Selection (<500 MB total).** VA L4/L5 → QIDs; download Qrank; build
  `subject` table (popularity-ranked, quality-gated via WP1 `ratings`/PetScan).
  Re-point `generate_corpus.py` *candidate selection* at it. Content still via API
  for now, but aimed at the *right* ~10–50k subjects. **Proves the breadth/ranking
  lift with real numbers before any big download.**
- **Phase 1 — Prose (316 MB → 43 GB).** Add the `prose` table from Kiwix
  `top_mini` (proto) or CirrusSearch content (scale). Kill the content API.
- **Phase 2 — Facts + distractors (~43 GB CC0 + ~hundreds MB).** Add `fact` from
  Wikidata truthy and `related` from clickstream. Kill the enrich API; scale the
  non-MCQ types (enumerate 11 → hundreds of puzzles) and upgrade distractor
  quality (type-match × confusable × fame-gate).

## 4a. Build log

- **Phase 0 — Selection: BUILT (2026-06-21).** `tools/corpus/sources/build_subjects.py`
  + `fetch_qrank.py` → `corpus_source.sqlite` table `subject`. The L5 ∩ >C set
  comes straight from the per-class tracking categories (`Category:<CLASS>-Class
  level-5 vital articles`, members = article talk pages → strip `Talk:`), so the
  quality gate is exact and free; titles resolve to QIDs via `prop=pageprops`;
  Qrank (CC0, cached) joins by QID.
  **Result: 11,907 subjects (B 9,423 / GA 1,663 / FA 797 / A 24), 99% Qrank-ranked**
  — vs ~1,956 search-selected articles today (**6×**, and quality+popularity-gated).
  *Finding:* raw Qrank is trailing-12-month → recency/virality-biased (transient
  celebrity + adult brands surface at the top). Selection needs an
  **appropriateness + durability filter** (mission alignment) applied during
  categorization — gate, don't just rank by, Qrank. Next: Stage B (Wikidata facts
  + P31 categorization + lead prose for the 11,907 QIDs — targeted fetch, not the
  43 GB dump, since the curated set is small enough to enrich directly).

- **Stages B–D — Enrichment, Prose, Generate: BUILT (2026-06-21).**
  `enrich_subjects.py` (Wikidata facts/dates/relations/P18 image/aliases/sitelinks
  + P31/P106-stored categorization with an appropriateness gate),
  `fetch_prose.py` (lead + short description, 100% coverage), `recategorize.py`
  (offline category-map iteration — no re-fetch), then the exporters
  `build_enrich_json.py` / `build_corpus.py` (+ iOS `corpus.sqlite` mirror +
  Android copy) / `build_difficulty.py` (Qrank quintiles). The existing nine
  `gen_*.py` run unchanged on the regenerated `corpus.json` + `enrich.json`.
  **The lift (old → new):** enrich entities 1,591 → **11,906 (7.5×)**; Picture ID
  816 → **5,309 (6.5×)**; Type-the-answer 997 → **5,929 (6×)**; difficulty ratings
  1,951 → **11,906**; Closest Call 1,233 → **2,494 (2×)**; Odd-one-out 67 → 123;
  Enumerate 243 → 412 answer slots; main corpus 4,540 → **8,046** rows with
  same-category/same-fame distractors and Qrank-derived difficulty. **Verified on
  the iOS 26 sim**: Classic renders the new description-MCQs from `corpus.sqlite`;
  question quality sampled clean (non-leaking clues, alias-rich type-answer).
- **Stage 2 — Relation regen + clickstream distractors: BUILT (2026-06-21).**
  `resolve_relations.py` resolved 5,099/5,122 relation targets to labels, so
  `build_corpus.py` now **regenerates** the Matching/relation rows from the source
  (capital/currency/author + new **composer/director** types — Matching 136 → 214,
  6 types) instead of carrying them forward (only wd:elemSymbol is still carried,
  pending P246). `fetch_clickstream.py` streamed the 508 MB enwiki clickstream and
  kept **78,545 subject↔subject confusable edges over 11,128 subjects (94%)** —
  `build_corpus.py` now draws distractors from these (same-category +
  empirically-confused) before falling back to nearest-Qrank. **Verified on the
  iOS sim:** "American actress (born 1971)" → Winona Ryder, decoys Johnny Depp /
  Keanu Reeves / Stranger Things — genuinely confusable, not random. Main corpus
  12,782 rows; relation-MCQ 784 added as bonus Classic variety.
  *Open follow-ups:* mixed category 39% (cheap via `recategorize.py`); element
  symbols (P246) still carried-forward; partial-name cloze leaks.

- **Stage 3 — Question-quality audit + fixes: BUILT (2026-06-21).** Ben flagged
  (with TestFlight screenshots) that questions must read as a clever human asker
  wrote them: give real context (not luck-guessing), be grammatical, and never
  give the answer away — via wording OR distractors. `audit_questions.py` is the
  reusable measure (LEAK / CLOZE_PART / THIN / GENDER, with examples). Root-cause
  fixes in `build_corpus.py` (+ `fetch_attributes.py` for P21 gender):
  - **Type/gender/person-matched distractors** — the headline fix. A clue like
    "American actress (born 1958)" must have actress distractors, never 3 men +
    the answer (Sharon Stone was the only woman). Distractors now must match the
    answer's gender (P21, or inferred from the description when P21 is missing),
    occupation (P106), and person-vs-thing — graduated fallback relaxes occupation
    then gender last. Sharon Stone → Demi Moore / Raquel Welch / Jean Harlow.
    **GENDER giveaways 974 → 25.**
  - **Cloze rewrite** — mask the WHOLE leading name as one blank (no "Breaking
    ____" / "____ Lee ____"), strip pronunciation/IPA/native-script parentheticals
    that spell the answer ("(OH-klə-HOH-mə)" → Oklahoma; "(Korean: 김수현)"), keep
    dates as context. **Partial-name leaks 773 → 33.**
  - **Natural grammar** — "Who is this — '…'?" for people, "What is this — '…'?"
    for things (was the clunky "Which film, show, or star is this").
  - **Thin-clue removal** — drop date-only / contentless describe clues (pure
    guessing). **2 → 0.**
  Re-audit confirms the drops; all bundled sets regenerated (type-answer mines the
  cleaner clues). Verified on the iOS sim.

- **Stage 4 — Question SCORING + cut: BUILT (2026-06-21).** Ben: rate every
  question for type-fit, answer quality, and "sounds like a great question a human
  would write" — and eliminate the robotic/mundane (taxonomic stubs, facts no one
  would enjoy). `score_questions.py` scores 0–100 = 0.30·RECOG (Qrank percentile)
  + 0.38·INTEREST (hooky vs dry-classification description) + 0.32·FIT (type-suited
  + clean distinct options); `--apply` keeps ≥ threshold and propagates (the
  bundled generators mine the kept corpus). **Validated against a blind LLM judge**
  on samples (the judge independently trashed the same "genus of X" questions) —
  which surfaced one real gap the heuristic missed and one the fix introduced:
  - **Non-person distractors weren't type-matched** (Shrek → Pixar / a war film / a
    song). Extended the distractor compatibility to **P31 instance-of** for things
    (film↔film, compound↔compound, river↔river): Shrek → My Neighbor Totoro / The
    Lion King; Bon Jovi → Van Halen / Guns N' Roses; Mannitol → Sorbitol.
  - **Adult-industry subjects** slipped the appropriateness gate → a description-
    based content filter in `build_corpus.py` (family-friendly learning).
  - Cloze cleanup: normalize smart punctuation first (no "which—from" → "whichfrom"),
    strip locale/language alt-name labels ("Sardinian: Casteddu", "also UK: …").
  **Cut 1,696 (13%) + 17 adult subjects → corpus 12,809 → 11,054.** The blind LLM
  judge's median rose 52.5 → 60 ("solid") on the filtered set. `score_questions.py`
  and `audit_questions.py` are permanent, re-runnable quality gates.

- **Stage 5 — "Consistently delightful" LLM rewrite: BUILT (2026-06-21).** Ben:
  make questions read like a beloved human quizmaster wrote them (whimsy + learning),
  the differentiator vs algorithmic generators. A 125-batch parallel **workflow**
  (`delight-rewrite`) had an LLM rewrite each robotic "Who/What is this — '<dry
  clue>'?" into a hand-crafted question, **grounded strictly in that article's own
  summary** (facts only from the provided text → no hallucination), never naming the
  answer, still answerable with the type-matched options. `apply_delight.py` merges
  with SAFETY GATES — drops any rewrite that leaks the answer (287) or is malformed
  (176), keeping the original clue. **4,523 / 4,987 describe questions (91%) are now
  delightful**; `gen_typeanswer` reuses the prompt so Name It inherits them. (The run
  spans the usage-limit reset via workflow resume — cached batches return instantly.)
  e.g. "This Hungarian-born physicist conceived the nuclear chain reaction in 1933,
  then drafted the letter Einstein signed that launched the Manhattan Project — who
  was he?" → Leo Szilard.

## 5. Licensing (must hold)

- **Wikidata (facts spine): CC0** — public domain, no attribution, commercial-safe.
  This is *why* the truthy dump is the chosen facts source over CC BY-SA derivatives.
- **All Wikipedia text (prose, abstracts, clickstream-derived): CC BY-SA 4.0** —
  ShareAlike. This is already our obligation (we use Wikipedia today). Keep the
  in-app attribution + the web app's article-twin link as the attribution target.
  A derived corpus built from this text inherits share-alike; surface it.
- Qrank: CC0. Kiwix ZIM payload: CC BY-SA (it's Wikipedia text).

## 6. Open questions (decide before/within each phase)

1. **Selection set size** — VA L4 (~10k, tight/recognizable) vs L5 (~50k, broader)
   vs "VA ∪ Qrank top-N." Lead candidate: **L5 gated to Qrank-top + WP1 ≥ C-class**.
2. **Facts: full truthy (43 GB) vs wdumper subset (<1 GB).** wdumper avoids hosting
   43 GB but adds a per-rebuild manual step; truthy is reproducible but heavy.
3. **EN-only `structured-wikipedia` as a one-artifact shortcut** for Phases 1+2
   (infoboxes + abstracts in one 35 GB Parquet) vs the Wikidata+CirrusSearch pair
   (CC0 facts + weekly prose, more pipeline). Trade: freshness/simplicity vs CC0
   purity + language headroom.
4. **Rebuild cadence + reproducibility** — pin dump dates in a manifest so a corpus
   rebuild is deterministic; dumps are snapshots (weekly/monthly).
5. **Quality-gate load** — a 100× pool means 100× more vandalism/ambiguity/dated
   facts reaching the gates. Audit gate pass-rates on the bigger pool early.

## 7. Rejected / not now

- **Raw `pages-articles.xml.bz2`** (wikitext, parse-difficulty 5, full template
  expansion) — CirrusSearch is the pre-stripped clean version; only revisit if we
  need source wikitext.
- **API-only scaling** — the throttle is the ceiling; no amount of seed-tuning
  fixes the 0.03%-coverage / search-relevance-selection problem.
- **Shipping any dump to clients** — sources are build-time only; the bundled
  corpus stays small and curated.
