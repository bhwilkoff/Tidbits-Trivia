# Solo / App-Alone Backlog — Game Types, Question Types, Functionality

> The build runway for modes the app delivers **on its own** — no TV↔phone
> collaboration, no realtime server. (Same-room buzzer / web-room work is tracked
> separately; see `GAME-MODES-RESEARCH.md` Part C/D2.) Every item is filtered
> through the mission (`DECISIONS` 022) and rides the **4-option MCQ corpus** (025)
> unless it "earns custom data."
>
> Source: `docs/GAME-MODES-RESEARCH.md` (Parts B + D). Each item passed the
> learning-orientation four-question test there. Status is the live truth; update
> it in the same change set as the work.

## Legend

`P0` ship now · `P1` next · `P2` later/needs-enrichment · `P3` marquee/rich-data
Status: ✅ shipped · 🚧 in progress · ⏳ queued · 🔮 needs prerequisite

The **single highest-leverage prerequisite** is the **Wikidata enrichment pass**
(`E1` below): one additive build-time pass emitting numeric facts + Commons image +
aliases unlocks SEVEN question types. Most `P2` items are gated on it.

---

## Game modes (solo)

| ID | Mode (ancestor) | What | Corpus | Pri | Status |
|---|---|---|---|---|---|
| M1 | **Stake** *(LearnedLeague / Pour House)* | 8-Q round; spend a fixed budget of confidence chips (Sure×2 / Likely×3 / Hunch×3) before each answer; correct = +chip, wrong = +0; **adds-only**, never negative. Score = confidence earned; calibration is the lesson. | **Yes** | P0 | ✅ all 4 platforms |
| M2 | **Sweep** *(Sporcle)* | A 12-Q set as rapid-fire MCQ with a persistent fill-grid (mint hit / coral miss); +1 per correct (count-scored, no speed bonus); beat **your own** best via per-mode best-score; ends on the existing miss-reveal recap. | Yes (sets from categories) | P1 | ✅ all 4 platforms |
| M3 | **The Pie** *(Trivial Pursuit)* | Earn one wedge per knowledge domain at a small mastery threshold; the pie completes only when **every** domain is filled — fights corpus/interest bias. Durable, never resets. | Yes (meta over records) | P1 | ✅ iOS/web/Android (tvOS ⏳ Records UI) |
| M4 | **Topic Levels** *(QuizUp)* | XP/levels per knowledge **domain** (the 7 non-mixed categories): a level + bar per domain, gentle triangular curve. Derived from game history, no new persistence. | Yes (category + records) | P2 | ✅ iOS/web/Android (tvOS ⏳ Records UI) |
| M5 | **Closest Call** *(higher-lower)* | A numeric answer (year / atomic number / elevation); estimate on a slider (tvOS: ±coarse/fine steppers); scored by **proximity**, adds-only (`closest.json`, 1,233 Qs). The first non-MCQ type (Decision 031). | +meta (E1 numeric) | P2 | ✅ all 4 platforms |
| M6 | **Link Wall** *(NYT Connections)* | 16 fact-tiles → 4 hidden groups by a Wikipedia/Wikidata link; keep "one away"; reveal **shows the link + a cited why**. The marquee daily puzzle. | Rich (curated groups) | P3 | 🔮 |

## Question / interaction types (solo-renderable in the existing game loop)

| ID | Type | What | Corpus | Pri | Status |
|---|---|---|---|---|---|
| Q1 | **This-or-That** *(binary speed)* | "Which came first?" between two same-category entities, rendered as a 2-option MCQ (`thisorthat.json`, 613 Qs from E1 chronology; 0 errors). Size/real-fake shapes deferred (population unreliable, real-fake needs statement-gen). | +meta (E1 years) | P1 | ✅ all 4 platforms (chronology) |
| Q2 | **True/False rapid** | A statement; tap T/F; tight timer; streak. Highest value when false = a **plausible misconception**. | +meta (statement gen) | P2 | 🔮 pipeline |
| Q3 | **Odd-one-out** | Four cards; three share a hidden property, one doesn't; pick the outlier (+ optionally name the link). **Zero new UI** (reuses MCQ surface). | +meta (E1 set membership) | P2 | 🔮 E1 |
| Q4 | **Ordering / ranking** | Arrange 4–6 items (chronological/size); partial credit by inversion count. Drag on phone/web; insert-via-focus on tvOS. | +meta (E1 orderable attr) | P2 | 🔮 E1 |
| Q5 | **Matching pairs** | Two columns (country↔capital); link each. Easy to validate (1:1). Study-aligned. | +meta (E1 paired facts) | P2 | 🔮 E1 |
| Q6 | **Type-the-answer** | Free-text recall + fuzzy/alias matching. Deepest retrieval; web/phone first (tvOS keyboard wall). Also closes `ROADMAP` #9. | +meta (E1 aliases) | P2 | 🔮 E1 |
| Q7 | **Picture ID** | A Commons image + "What is this?" + the corpus's 4 vetted options (`picture.json`, 816 Qs). iOS/tvOS AsyncImage, web img, Android Coil, each with a load-failure fallback. | +meta (E1 Commons image) | P2 | ✅ all 4 platforms |
| Q8 | **List / enumeration** *(Sporcle typed)* | "Name as many X in 60s"; fill-grid. Rich sets + alias coverage; web/phone (tvOS via voice/skip). | Rich | P3 | 🔮 |

## Functionality / infrastructure

| ID | Item | What | Pri | Status |
|---|---|---|---|---|
| F1 | **Calibration stats** | From Stake: per-tier accuracy (Sure/Likely/Hunch hit-rate) in Records — the self-knowledge mirror. | P0 | ✅ iOS/web/Android (tvOS ⏳ Records UI) |
| F2 | **Full missed-fact recap** | Post-game list of every missed Q + answer + cited fact, all 4 platforms (tvOS in a focusable ScrollView; Android in the results scroll). | P1 | ✅ all 4 platforms |
| F3 | **Derived difficulty rating** | Per-question difficulty (subject obscurity / answer page-view rank), build-time → enables 50:50, escalation, ladder. | P1 | ⏳ |
| F4 | **Answer-distribution telemetry** | Privacy-respecting per-option counts (local-first; aggregate later) → unlocks **Predict the Crowd** solo + an "X% picked this" reveal. | P2 | ⏳ |
| E1 | **Wikidata enrichment pass** | ONE additive build-time pass per answer entity: **numeric facts + units, Commons `P18` image, `also known as` aliases**. `tools/corpus/enrich.py` → `assets/enrich.json` (1,591 entities: 1,287 image / 1,187 numbers / 1,204 aliases). Also `gen_picture.py` → `assets/picture.json` (816 Picture ID questions). Unlocks M5, Q3, Q4, Q5, Q6, Q7 + Wits&Wagers. **The highest-leverage corpus work.** | P1 | ✅ data shipped (consumer UIs next) |

---

## Working order (smallest learning-valuable slices first)

1. **M1 Stake** — ✅ shipped on web + iOS + tvOS + Android (2026-06-20). **F1
   calibration** (per-tier accuracy readout in Records) is the queued follow-up;
   the in-game chip-spending already delivers calibration practice.
2. **E1 Wikidata enrichment** — ✅ data shipped (`enrich.json` + `picture.json`).
   Consumer UIs now unblocked; **Picture ID is the first** (reuses MCQ + an image
   header; note iOS/tvOS read SQLite so they need a small picture.json loader,
   web/Android are JSON-native already).
3. **M2 Sweep** — ✅ shipped on all 4 platforms (2026-06-20). **Q1 This-or-That**
   — corpus-native (real/fake) is the next verb to broaden; bigger/older needs E1.
4. **M5 Closest Call**, **Q3 Odd-one-out**, **Q7 Picture ID** — first fruits of E1.
5. **M3 The Pie** / **M4 Topic Levels** — long-horizon retention meta-progression.
6. **Q6 Type-the-answer**, **Q4 Ordering**, **Q5 Matching** — the richer E1 types.
7. **M6 Link Wall** / **Q8 enumeration** — marquee daily / rich-data bets.

**Parity rule:** every shipped mode/type mirrors across web + iOS + tvOS + Android in
the same change set (4 engines) and gets a `PARITY.md` row. A mode that's a *scoring/
meta* layer (Stake) is a client mode wrapper; a new *question type* lives in the
corpus (`DECISIONS` 025) and renders in all four template engines.
