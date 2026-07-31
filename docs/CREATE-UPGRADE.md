# Create v2 — the world's best quiz creator

Owner brief: exhaustive common-topic list; every created quiz full of incredible,
engaging questions; multiple question AND game types; Apple Intelligence to pick the
best questions on Apple platforms; **quizzes saved to your account, replayable and
shareable**; working on all six platforms. Multi-loop by design.

---

## Wave 0 — MEASURE FIRST, then CORRECT THE MEASUREMENT (2026-07-31)

`tools/create/topics.txt` (127 topics, Wikipedia most-viewed seeded) +
`tools/create/coverage.py`.

**First pass concluded the corpus was thin on popular topics (Beyoncé 0, van Gogh 3,
The Beatles 5). That conclusion was WRONG** — and the owner was right to push back: a
QRank-seeded corpus cannot plausibly be thin on Beyoncé. Investigating it found THREE
REAL SHIPPED BUGS in Create's search, which my measurement had faithfully reproduced.

### B1 — `LIMIT 400` truncates BEFORE ranking (severe)

`CorpusDatabase.search` pre-filters with an OR clause capped at 400 rows, then ranks.
When any token is a common substring the cap is exhausted by noise before a genuine
match is ever seen. Measured for "van gogh" (3,310 OR-matches, 20 genuine):

| Cap | Rows returned | Genuine "van gogh" rows surviving |
|---|---|---|
| **400 (shipped)** | 400 | **0** |
| 4000 | 3310 | 20 |
| none | 3310 | 20 |

So typing "Vincent van Gogh" returns **none** of the 20 real van Gogh questions. The
relevance fix in Q26–Q28 was necessary but sits *downstream* of this truncation.

### B2 — no diacritic folding

`beyonce` → **0** rows. `beyoncé` → **22** rows. The corpus has Beyoncé questions; a
user typing the unaccented spelling (i.e. nearly everyone) gets nothing.

### B3 — 3-letter stopwords blow up the candidate set

The token filter keeps anything ≥3 chars, so "the" survives — and "the" matches almost
every row, guaranteeing B1's truncation for any topic containing it ("The Beatles",
"The Simpsons"). "van" behaves the same way.

### Corrected picture

The corpus is **rich** on these topics — The Beatles has 109 matching rows, Grand
Canyon 1,683, van Gogh 3,310 (20 precise). The 18 "thin" topics were mostly an
artefact of B1–B3, so the coverage table from the first pass must be re-run after the
fixes and is NOT a basis for planning.

**Wave 1 is therefore B1+B2+B3, not blended sourcing.** The earlier conclusion that
"live generation must become first-class" was premised on a corpus shortage that does
not exist; revisit it only after re-measuring.

## Wave 1 — B1 + B3 fixed (2026-07-31)

- **B1 fixed**: pre-filter cap 400 -> 4000, so genuine matches survive to the ranker.
- **B3 fixed**: stopword list; "the" no longer floods the candidate set (falls back to
  the raw tokens if a topic is nothing but stopwords).
- `coverage.py` now mirrors the shipped rule. Re-measured: **111/127 can fill 8**
  (was 109); "The Beatles" and "The Simpsons" both cleared — screen is now 0 thin.

**B2 (diacritics) still open** and needs a *data-plane* change, not a hack: a folded
`search_text` column written by the corpus build tool, so `beyonce` matches `Beyoncé`
on every platform identically. Do NOT approximate this with prefix trimming.

**Newly understood, and NOT a bug:** the residual thinness on person-topics like
Vincent van Gogh is the **answer-giveaway rule** — Create deliberately drops questions
whose ANSWER is the typed topic, and for a painter most questions are "who painted X?".
20 genuine van Gogh rows become 3 after that filter. This is a real design tension to
decide, not a defect: a quiz *about* van Gogh that never answers "van Gogh" is honest
but thin. Options for Wave 2: allow giveaway questions when the pool would otherwise
starve, or prefer them last rather than excluding them.

## Waves (each its own loop tick)

- **W1 — Blended sourcing.** Corpus + live in one ranked pool; target N always met or
  an honest "we could only find K". Re-measure with `coverage.py` after.
- **W2 — Multiple question + game types.** A created quiz should be able to mix MCQ,
  Closest Call, Ordering, Match-Up, Type-Answer, Odd-One-Out, Picture — and to be
  played as Classic / Time Attack / Survival / Stake. Today Create hardcodes `.classic`.
- **W3 — Apple Intelligence question selection.** `DelightfulQuizGenerator` already
  uses `FoundationModels` to WRITE questions; extend it to RANK/curate a candidate set
  (hook quality, difficulty spread, no near-duplicates). Apple-only; the other
  platforms need a deterministic fallback ranker so sets stay comparable.
- **W4 — Saved quizzes (the new mechanic).** Persist a created quiz to the account:
  SwiftData/Room/localStorage locally + the shared player bucket for sync. Replay,
  rename, delete.
- **W5 — Sharing.** A quiz gets a canonical URL (`/quiz/<id>`) with a deep-link twin
  per DEEP_LINKS.md, so a created quiz opens natively on any platform and on the web.
- **W6 — Parity + polish.** All six platforms, PARITY.md row, per-platform design docs.

## Definition of done (the owner's bar)

Fully customizable AND shareable quizzes that work across all platforms — not "Create
returns 8 questions". Every wave ends with a played-not-screenshotted verification and
a `coverage.py` re-run.

## Guardrails carried in

- Relevance rule (Q26–Q28): matched-token tier; diversity is a preference, never a quota.
- R-SHOT-3: screened questions for store captures.
- No new blank walls — `universal-feature-states` for every list/empty/error.
