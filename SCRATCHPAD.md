# Project Scratchpad — Tidbits Trivia

> Active snapshot (auto-loaded each session). **For the full state + how to
> build/run/verify each platform + the prioritized backlog, read
> `docs/HANDOFF.md`.** Other refs: `PARITY.md` (feature matrix, source of
> truth), `DECISIONS.md` (the why, 001–025), `docs/QUESTION-QUALITY.md`,
> `docs/ROADMAP.md`, `docs/DATA-CONTRACT.md`. Detailed per-round history is in
> `ARCHIVE.md`.

## Current state (2026-06-17)

- **All four platforms PLAY**, off one shared corpus, all pushed to `main`:
  - **iOS/iPadOS** — full SP (4 modes, 8 categories, learn-reveal), local
    pass-and-play (2–4), records + spaced repetition, create-a-quiz, daily,
    haptics, Settings, onboarding, app icon, Game Center scaffold (no-op until
    entitlement). Verified iPhone 17 Pro sim.
  - **Web** — full SP loop, PWA, network-first corpus, canonical share target.
  - **tvOS** — dark-first focus-correct home + game loop + results.
  - **Android** — full SP loop (home/game/results/records/create), Compose/M3.
- **Corpus**: **4,743 questions** = 1,657 summary (863 describe + 794 cloze) +
  1,144 deep-extraction `fact:*` (Decision 027) + 1,942 Wikidata. **Quality over
  quantity** (Decision 029): summary path reworked into bar-trivia "describe &
  identify" + cloze, gated by a fame floor (intro ≥600 chars) + a richness check
  (≥2 distinguishing tokens) — this deliberately cut summary from 7,834 → 1,657,
  dropping obscure subjects and content-free clues. Old identify/jeopardy/
  categorize shapes deleted. Fact questions mined from FULL articles via
  `wiki_extract.py`; geography stays Wikidata-led. All 4 engines mirror the rework.
  Wikidata source datasets cached in `tools/corpus/cache/` → regen is instant.
  Rebalanced for variety; fixed-stem Wikidata types capped (occClass 733→24).
  **Quality gates (drop-on-fail, enforced in the generator AND the 3 live
  engines):** no answer-leak (robust redaction: leading proper-noun run +
  content title words everywhere; 48%→0%), no foreign-script/math, no oversized
  clue (>320), list/glossary/LaTeX subjects filtered, paren/abbrev-aware
  first-sentence, global cross-category subject dedup. Web logs corpus version.
- **Platform set**: Web + iOS + iPadOS + tvOS + Android (Decisions 020/021).

## Next up (see docs/HANDOFF.md §6 for the full backlog)

Big tracks: online multiplayer (Game Center → Supabase), store submission prep
(iOS + Play), tvOS living-room phone-as-buzzer, more question types (on-this-day
/ connection / odd-one-out / picture-ID / type-the-answer), adaptive difficulty.
Quick follow-ups: `clean_clue` on explanation text; P31-typed distractors for
the summary path; quality gates 6/7/9; branded iOS launch screen; web
pass-and-play + onboarding parity; Android Room; real share domain.

## Build (quick ref — full recipes in docs/HANDOFF.md §3)

```
# iOS:   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -scheme TidbitsTrivia -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/tidbits-dd
# Android: (cd android; JAVA_HOME=…/Android Studio…/jbr/Contents/Home ./gradlew :app:assembleDebug --no-daemon)
# Web:   python3 -m http.server 8080
# Corpus: cd tools/corpus && python3 generate_corpus.py && python3 wikidata.py && python3 export_json.py  (then sync android asset + rebuild)
```
Screenshot hooks (no-ops in prod): `TIDBITS_AUTOPLAY=mode:category`,
`TIDBITS_AUTOPILOT=1`, `TIDBITS_TAB=…`, `TIDBITS_PARTY=1`, `TIDBITS_ONBOARD=1`,
`TIDBITS_AUTOCREATE="topic"`. Boot ONE sim/emulator at a time.

## Out of scope (intentionally)

| Idea | Why declined | Revisit when |
|---|---|---|
| Cash prizes / wagering for money | HQ Trivia's model is mathematically doomed and off-mission | never |
| Energy / lives / hearts gating | Universal 1-star complaint; contradicts learning mission (Decision 022) | never |
| Real-time-only live game show | Both real-time-only apps (HQ, QuizUp) died; appointment fatigue | a robust async base exists first |
| X/Twitter share target | Explicit product requirement | never |
| Pay-to-restore-streak | Textbook dark pattern (Decision 022) | never |
| Non-MCQ formats (timeline drag, grouping wall) | Need per-client UI; corpus is 4-option-only (Decision 025) | a format earns the custom UI |

## Session log

One-line-per-round; full detail in `ARCHIVE.md`.

- **R1** iOS foundation (Core + iOS UI + corpus + research). **R2** local
  pass-and-play + spaced repetition + haptics + Settings + icon. **R3** emoji
  share + onboarding. **R4** web mirror. **R5** Wikidata moat (10,006).
  **R6** tvOS. **R7** Android (4-platform vision complete). **R8** question
  diversity (5 shapes, no "best described", tell-free distractors, clean clues).
  **R9/9b** Wikidata question-TYPE expansion → 22 types, corpus 11,679; web
  caching fixed (network-first + versioned + SW v2).
- **2026-06-17** — prepped for first compaction: wrote `docs/HANDOFF.md`,
  archived the detailed log here-fileward, tightened this snapshot.
- **2026-06-18** — **deep Wikipedia fact-extraction** (push for better Qs).
  *Found:* summary path only ever parsed short-description + first sentence —
  every summary Q was "name the thing from its definition." *Did:* 3 research
  streams (API surface, QG/distractor literature, stdlib fact-extraction) →
  new vendored skill `wikipedia-fact-extraction` (the proprietary method) →
  new `tools/corpus/wiki_extract.py` (stdlib: infobox depth-scanner →
  protect-then-split segmentation → appositive/relation/date triples →
  coreference-safe stems → infobox-oracle verification → MCQ builder with
  type-matched distractors) → wired into `generate_corpus.py
  --facts-per-category N` (default 0). Verified end-to-end on real articles:
  "Who directed The Godfather? → Coppola" etc., all answers correct,
  distractors type-matched, the contradictory-multi-creator class gated out.
  Decision 027; QUESTION-QUALITY §3rd path; PARITY row. *Then SHIPPED:*
  hardened the extractor v2 (8 cross-domain precision fixes — person-gated
  born/died/nationality, dual-nationality drop, non-noun-type reject,
  nationality-as-creator reject, merged-name reject, album-artist
  misattribution, creators-from-sentence-0-only, infobox-direct facts) and
  regenerated the full corpus **8,630 → 10,776** (7,834 summary + 1,000 fact +
  1,942 wd), 0 errors, exported to `corpus.json` + Android asset, all 1,000 fact
  Qs structurally clean. The earlier summary dip was Wikipedia search variance,
  recovered via deeper search (`--per-category 2600`). *Left:* live engines stay
  summary-based (mirror gates only); ratchet `--facts-per-category` higher
  anytime (warm cache → cheap).
- **2026-06-19** — **bar-trivia question rework** (user: web questions "awkward",
  "what kind of thing is…" / "what subject is this" = nobody asks that; want
  "trivia night" feel). *Found:* summary path shipped obscure subjects + robotic
  framing. *Did:* reworked all 4 engines (generate_corpus.py + engine.js +
  TemplateEngine.swift + Tidbits.kt) → deleted identify/jeopardy/categorize;
  kept **describe** ("This {type} {clue} — who/what is this?", person/thing-aware)
  + **cloze**; added **fame floor** (extract ≥600) + **richness gate** (≥2
  distinguishing tokens, date-parens stripped) + leading-name-anchor reframe.
  Regenerated corpus **10,776 → 4,743** (quality over quantity). Verified: Film &
  TV samples read naturally, all bad patterns 0, iOS+Android BUILD SUCCEEDED.
  Decision 029. *Left:* domain migration done earlier today (Decision 028).
