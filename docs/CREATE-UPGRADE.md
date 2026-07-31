# Create v2 — the world's best quiz creator

Owner brief: exhaustive common-topic list; every created quiz full of incredible,
engaging questions; multiple question AND game types; Apple Intelligence to pick the
best questions on Apple platforms; **quizzes saved to your account, replayable and
shareable**; working on all six platforms. Multi-loop by design.

---

## Wave 0 — MEASURE FIRST (done 2026-07-31)

`tools/create/topics.txt` (127 topics, Wikipedia most-viewed seeded, 11 domains) +
`tools/create/coverage.py`, which applies the SHIPPED relevance rule (QA-SWEEP-LOG
Q26–Q28) and reports what a player would really get.

```
topics: 127   can fill 8: 109   THIN: 18   median pool: 46
```

**The finding that sets the architecture:** the corpus is Wikipedia-derived *breadth*,
so it is thinnest exactly where public interest is highest — the most-searched topics
are the worst served.

| Topic | Pool | Topic | Pool |
|---|---|---|---|
| Beyonce | **0** | Vincent van Gogh | 3 |
| Great Barrier Reef | 1 | Black holes | 4 |
| The Simpsons | 2 | The Beatles | **5** |
| Time zones | 2 | Vaccines | 6 |
| Space exploration | 2 | Isaac Newton | 7 |

Thin by domain: tech 4/8, science 4/17, geography 3/12 — arts/music/screen headline
names (Beatles, van Gogh, Beyoncé, Simpsons) are the sharpest misses.

**Consequence:** live generation must become a **first-class path, not a fallback**.
Today `CreateQuizView` only calls Wikipedia when the corpus returns <3 — which is why
"The Beatles" silently yields a 5-question corpus quiz instead of a great 8-question
one. The right rule is *blend*: corpus questions are pre-vetted and instant, live
questions cover the long tail; a topic should draw from both and be judged on the
QUALITY of the final set, not on which source it came from.

---

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
