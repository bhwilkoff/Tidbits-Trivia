# Data Contract — Tidbits Question Corpus

> The shared content data plane. Every client (iOS now; Web/Android/tvOS
> next) is a CONSUMER of one corpus produced by one pipeline. No client
> re-implements generation or re-derives quality gates (Decision 016, 019).
> The quality rules the pipeline enforces live in `QUESTION-QUALITY.md`.

## Producer

`tools/corpus/generate_corpus.py` — pulls category-seeded popular Wikipedia
articles via the Action API (batched `extracts|description|info`), runs the
template shapes + quality gates that mirror `Core/Engine/TemplateEngine.swift`,
and writes a read-only SQLite database. Polite by contract: descriptive
User-Agent with contact, `maxlag=5`, serial requests throttled to ~5 req/s,
exponential backoff on 429/503.

Rebuild: `cd tools/corpus && python3 -u generate_corpus.py`. Idempotent —
drops and recreates the table each run.

## Artifact: `corpus.sqlite` (bundled in the app, read-only)

Single table `questions`. **Column order is load-bearing** — the iOS reader
(`CorpusDatabase.row`) maps by index, so never reorder; only append.

| # | Column | Type | Notes |
|---|---|---|---|
| 0 | `id` | TEXT PK | `corpus:<template>:<Title>` (spaces→`_`) |
| 1 | `prompt` | TEXT | the stem; answer never leaks (gate A6) |
| 2 | `option0` | TEXT | |
| 3 | `option1` | TEXT | |
| 4 | `option2` | TEXT | |
| 5 | `option3` | TEXT | exactly 4 options (gate B8) |
| 6 | `correct_index` | INT | 0–3; key position shuffled (gate B22) |
| 7 | `category_id` | TEXT | one of the 8 category ids |
| 8 | `difficulty` | INT | 1–5 proxy (pageview/extract length) |
| 9 | `explanation` | TEXT | the "learn the fact" payload |
| 10 | `source_title` | TEXT | Wikipedia article title |
| 11 | `source_url` | TEXT | canonical article URL |
| 12 | `template_id` | TEXT | `descriptionOf` \| `subjectFrom` |

Index: `idx_category` on `category_id`. Categories:
`mixed`(virtual, spans all) · `history` · `science` · `geography` · `arts` ·
`screen` · `music` · `sports`.

## Template shapes

**Summary-based** (`tools/corpus/generate_corpus.py`):
- **`descriptionOf`** — "How is *Title* best described?" Options are short
  descriptions; distractors ranked by word-overlap (homogeneity, gate B11).
- **`subjectFrom`** — "Which subject is this? '*<redacted first sentence>*'"
  Options are titles; the answer's title is blanked from the clue (gate A6).

**Wikidata structured** (`tools/corpus/wikidata.py`, `template_id` `wd:*` —
Decision 024): answers derived from typed SPARQL triples, distractors are
typed siblings (gates 1/2/4/5 hold by construction):
- `wd:capital` (P36), `wd:currency` (P38), `wd:continent` (P30),
  `wd:unescoCountry` (P17) — geography
- `wd:elementSymbol` (P246), `wd:elementNumber` (P1086, numeric band) — science
- `wd:bestPicDirector` (P57) — screen
- `wd:bookAuthor` (P50, prize-winning works) — arts

Re-run: `python3 wikidata.py [--only key1,key2] [--gap SECONDS]`. Honors WDQS
`Retry-After`; appends with `INSERT OR IGNORE` (idempotent).

## Consumers

| Client | Reader | Local store for records |
|---|---|---|
| iOS/tvOS | `CorpusDatabase` (raw SQLite3) | SwiftData |
| Web | (planned) IndexedDB seed | IndexedDB |
| Android | (planned) bundled Room DB (BundledSQLiteDriver) | Room |

Never-repeat: each client tracks seen `id`s locally (iOS: `QuestionProvider`
in UserDefaults) and excludes them until the pool is exhausted, then recycles.

## Evolution rules

1. **Additive only.** New columns append at the end; readers ignore unknown
   trailing columns. Never reorder or repurpose an index.
2. **Version the schema** when a breaking change is unavoidable: bump a
   `meta(schema_version)` row and key each client's cache on it (Android
   `dbVersion` pattern) so a stale on-device DB is replaced atomically.
3. **Gate changes touch both producers** (`generate_corpus.py` +
   `TemplateEngine.swift`) in one commit (Decision 019).

## Roadmap: the Wikidata validation layer (the moat)

v1 enforces the cheap gates from a single article's summary. The high-value
gates — distractor-correctness (no distractor also true), temporal anchoring,
popularity floor via the Pageviews API, vandalism/freshness cross-checks —
need a **Wikidata SPARQL** spine (typed siblings for distractors, qualifiers
`P580/P582/P585` for dates, ranks for canonical values). That is the top
content priority after the iOS loop ships (ROADMAP #2).
