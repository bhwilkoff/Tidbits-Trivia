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

**B2 (diacritics) FIXED** in Wave 3, at the data plane rather than with a hack: the
corpus build writes a folded `search_text` column, so `beyonce` matches `Beyoncé`
identically on every platform. Sparse — only the 9.1% of rows whose folded text
actually differs carry it (+3.3 MB; dense would have cost ~35 MB of bundle for the
same behaviour). See the Wave 3 log below.

**Newly understood, and NOT a bug:** the residual thinness on person-topics like
Vincent van Gogh is the **answer-giveaway rule** — Create deliberately drops questions
whose ANSWER is the typed topic, and for a painter most questions are "who painted X?".
20 genuine van Gogh rows become 3 after that filter. This is a real design tension to
decide, not a defect: a quiz *about* van Gogh that never answers "van Gogh" is honest
but thin. Options for Wave 2: allow giveaway questions when the pool would otherwise
starve, or prefer them last rather than excluding them.

## Wave 2 — B1/B3 mirrored to every platform (2026-07-31)

Create now behaves the same everywhere, which it did not after Wave 1 (Swift only):

| Platform | B1 pre-filter cap | B3 stopwords |
|---|---|---|
| Apple (Swift) | 400 -> 4000 | added |
| Android (Kotlin) | already 6000 | added |
| Windows (C#) | 400 -> 4000 | added |
| Web (JS) | in-memory, no cap | added |

Android's cap was already 6000, so B1 never bit there — worth noting because it means
the Android and Apple Create results genuinely differed before this pass, which is
exactly the class of drift `cross-platform-parity-discipline` exists to catch.

Verified: Android `assembleDebug` green, Windows 447 tests green, `js/api.js`
syntax-checked, Apple builds green.

## Waves (each its own loop tick)

- **W1 — Blended sourcing.** ✅ SHIPPED 2026-07-31. Live generation used to fire ONLY
  when the corpus returned fewer than THREE, so a topic with six corpus questions
  silently delivered six — every thin topic in `coverage.py` sat in exactly that band
  (5–6). Live now TOPS UP the shortfall, deduped by id. On Apple the assembly moved
  into `QuestionProvider.createSet`, because it had been hand-copied across iOS,
  macOS and tvOS — which is how a fix lands on one surface and not the others.
- **W2 — Multiple question + game types.** ✅ SHIPPED 2026-07-31 (see the W2 log at the end).
  Original note: A created quiz should be able to mix MCQ,
  Closest Call, Ordering, Match-Up, Type-Answer, Odd-One-Out, Picture — and to be
  played as Classic / Time Attack / Survival / Stake. Today Create hardcodes `.classic`.
- **W3 — Apple Intelligence question selection.** `DelightfulQuizGenerator` already
  uses `FoundationModels` to WRITE questions; extend it to RANK/curate a candidate set
  (hook quality, difficulty spread, no near-duplicates). Apple-only; the other
  platforms need a deterministic fallback ranker so sets stay comparable.
- **W4 — Saved quizzes (the new mechanic).** ✅ SHIPPED on all six platforms.
  Original note: Persist a created quiz to the account:
  SwiftData/Room/localStorage locally + the shared player bucket for sync. Replay,
  rename, delete.
- **W5 — Sharing.** ✅ SHIPPED on all six platforms (tvOS via QR).
  Original note: A quiz gets a canonical URL (`/quiz/<id>`) with a deep-link twin
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

---

## Wave 3 log — the retrieval bugs (2026-07-31)

Two rules were making Create return the wrong questions, or none. Both are fixed on
all four stacks and pinned by tests.

### B4 — the answer-giveaway rule starved real subjects

Create dropped any question whose ANSWER contained the typed topic. Correct for a
place ("Chicago" → answer "Chicago"), badly wrong for a PERSON: 17 of the 20 genuine
van Gogh questions answer "Vincent van Gogh", so the rule deleted the subject's own
best material and the quiz could not be filled.

Giveaways are now held in RESERVE rather than dropped, and used only to fill the tail
when the clean pool would otherwise starve. A player asking about a place still never
sees the giveaway; a player asking about a person gets a full quiz.

### B2 — diacritics made a whole class of subjects invisible

`LIKE` cannot strip accents, so "Beyonce" matched **0** of 22 Beyoncé rows, "Bjork" 0
of 8, "Dvorak" 0 of 10. Fixed at the DATA PLANE, not with a per-platform hack:

- The corpus build writes a **sparse folded `search_text` column** — only the 9.1% of
  rows whose folded text actually differs carry it. Measured: **+3.3 MB**. A dense
  column would have cost ~35 MB of app bundle for identical behaviour.
- Apple + Android (SQL-backed) OR that column into the pre-filter; web + Windows hold
  the corpus in RAM and fold at compare time, so `corpus.json` needs no new field.
- Scoring folds too — otherwise the pre-filter surfaces an accented row and the ranker
  immediately discards it for scoring 0 against folded tokens.

### Two structural hazards found while fixing the above

- **Two sqlite writers had diverged.** `build_corpus.write_sqlite` emitted 12 columns
  while `resync_corpus.sh` emitted 14, so whichever ran last decided whether the
  shipped corpus had `tags` at all — and Create weights tags highest. Now ONE writer;
  resync calls it, and it also writes the Android copy.
- **Windows never received the Wave 2 stopword fix** (only the cap change), so "The
  Beatles" flooded its pool with "the" while the other three platforms didn't. The
  same topic produced two different quizzes. Fixed and pinned by `FoldingTest`.

### Measured result

| | Before Wave 3 | After |
|---|---|---|
| Topics that can fill 8 questions | 111/127 | **121/127** |
| "Beyonce" | 0 questions | 15 |
| "Bjork" / "Dvorak" | 0 / 0 | 8 / 10 |
| Music domain thin topics | 1 | **0** |

Remaining thin (6): Great Barrier Reef, Robotics, Black holes, Vaccines, Vincent van
Gogh, Cryptography. These are genuine corpus gaps, not retrieval bugs — they are W1's
job (blend live generation), not more ranking work.

Verification: Apple 90 tests / 12 suites, Windows 456, Android `assembleDebug`, web
`node --check`; Apple app rebuilt for iOS + macOS + tvOS.


---

## W2 complete — multiple game types (2026-07-31)

The wire had reserved `m` for this from the start, and every surface wrote `"mix"`
and then **ignored it on replay**. So a quiz's mode was recorded and thrown away: a
quiz saved as Survival replayed as a mixed round. That was a live bug, not a missing
feature.

All six surfaces now let you choose when creating, and honour the stored mode when
replaying — so a **shared** quiz arrives as the game its author meant. The same eight
questions play very differently as Survival than as Time Attack, which is what makes
this a feature rather than a dropdown.

| Surface | Picker idiom |
|---|---|
| iOS | menu `Picker` |
| macOS | inline `Picker` beside the input |
| tvOS | focusable chips — focus IS the selection model there |
| Android | M3 `FilterChip` row |
| Web | `<select>` |
| Windows | `ComboBox` |

`playableModes` is deliberately a **subset** of the full mode list. A saved quiz deals
a FIXED set of questions, so any mode that draws its own (daily, marathon, weak-spot,
expedition) would silently ignore the very questions the quiz exists to preserve. An
unknown mode from a newer build falls back to mix rather than refusing to play, per
the contract's evolution rules.


---

## Doc hygiene note (2026-07-31)

`B2 (diacritics) still open` sat in this file for hours after B2 was fixed, because
the wave list and the wave logs were updated separately. A doc that claims an open
bug which is actually closed is worse than no doc — it sends the next person chasing
something that isn't there. When a wave ships, update the LIST as well as the log.
