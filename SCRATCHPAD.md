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
- **Corpus**: 10,120 questions, **22 distinct question types** (5 rotating
  summary shapes + 17 Wikidata structured types; ~1,940 Wikidata-verified).
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
  Decision 027; QUESTION-QUALITY §3rd path; PARITY row added. *Left:* engine
  built+verified but NOT yet shipped to the corpus — next step is the deliberate
  regen `generate_corpus.py --facts-per-category 150` (crawls 1 full article/
  subject, cached) + version bump + Android asset re-sync.
