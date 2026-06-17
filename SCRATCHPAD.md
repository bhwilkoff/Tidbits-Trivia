# Project Scratchpad — Tidbits Trivia

> Active working notes. See `PARITY.md` for the cross-platform feature
> matrix (single source of truth). See `DECISIONS.md` for the why behind
> architecture. See `docs/QUESTION-QUALITY.md` for the question-engine
> rulebook and `docs/ROADMAP.md` for the competitive feature plan.

## Current state

- **Status**: iOS v1 single-player loop SHIPPING — playable end to end.
- **Active milestone**: M1 (iOS single-player core), wrapping up.
- **Platform set**: Web + iOS + iPadOS + tvOS + Android (Decision 020).
  tvOS earns its place — living-room trivia is lean-back (Decision 021).
- **Last session (2026-06-16)**: Built the whole iOS foundation from the
  starter scaffold. See session log below.
- **Next actions**:
  1. Bump corpus toward 10k (both-template generation; currently ~9k).
  2. Wire Game Center entitlement + App Store Connect leaderboards.
  3. Mirror the SP loop to Web (canonical share target) then Android.
  4. Phase 2: local pass-and-play → Game Center head-to-head → tvOS
     living-room mode with phone-as-buzzer (Decision 023).

## Architecture at a glance

```
TidbitsTrivia/                 ← universal Apple target (iOS+tvOS)
  Core/                        ← platform-agnostic (compiles for every os())
    Models/      Question, TriviaCategory, GameMode, PlayerRecord (SwiftData)
    Engine/      TemplateEngine (the moat), Scoring, SeededRNG
    Data/        CorpusDatabase (bundled SQLite reader), QuestionProvider
    Networking/  WikipediaClient, APIClient
    Store/       AppStore (nav), GameEngine (loop state machine), RecordsStore
    Services/    GameCenterManager
    Design/      Design.swift (90s sticker design system)
  iOS/           Views + Components (#if os(iOS))
  tvOS/          ContentView_tvOS placeholder (Phase 2)
  Resources/     corpus.sqlite (bundled, ~9k questions)
tools/corpus/    generate_corpus.py (mirrors TemplateEngine, builds the DB)
```

Two question pipelines, one template engine:
- **Offline** — `tools/corpus/generate_corpus.py` pre-bakes a quality-gated
  SQLite corpus shipped in the bundle (never-repeat, offline, fast).
- **Live** — `WikipediaClient` + `TemplateEngine` generate from any topic
  at runtime (infinite supply, powers "create a quiz" + corpus fallback).

## Build & run (iOS)

```
xcodegen generate                       # regenerate .xcodeproj after adding files
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild build -scheme TidbitsTrivia \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/tidbits-dd
```

Screenshot/CI hooks (no-ops in production):
- `TIDBITS_AUTOPLAY=classic:science` — launch straight into a game.
- `TIDBITS_AUTOPILOT=1` — auto-answer to reach reveal/results screens.

Rebuild the corpus: `cd tools/corpus && python3 -u generate_corpus.py`.

## Out of scope (intentionally)

| Idea | Why declined | Revisit when |
|---|---|---|
| Cash prizes / wagering for money | HQ Trivia's model is mathematically doomed and off-mission | never |
| Energy / lives / hearts gating | Universal 1-star complaint; contradicts learning mission (Decision 022) | never |
| Real-time-only live game show | Both real-time-only apps (HQ, QuizUp) died; appointment fatigue | a robust async base exists first |
| X/Twitter share target | Explicit product requirement | never |
| Pay-to-restore-streak | Textbook dark pattern (Decision 022) | never |
| Typed/recall answer mode in v1 | Great differentiator but needs alias/redirect matching; MCQ ships first | corpus + Wikidata alias layer lands |

## Session log

**2026-06-16** — *Found:* empty starter scaffold (apple/ placeholders,
template docs). *Did:* researched the trivia market + quiz/learning theory
(two agents; reports distilled into docs/ROADMAP.md + docs/QUESTION-QUALITY.md).
Generated `TidbitsTrivia.xcodeproj` via xcodegen (universal iOS+tvOS,
MainActor-default concurrency). Built the full Core layer (models, template
engine + quality gates, bundled-SQLite reader, question provider, game-loop
engine, scoring, SwiftData records + missed-fact spaced review, Game Center
bridge). Built the iOS UI: 90s sticker design system, home (daily card +
modes + category grid), live gameplay with answer states + "learn the fact"
reveal, results with missed-fact recap + ShareLink, records/stats,
create-a-quiz-from-any-topic. Wrote `tools/corpus/generate_corpus.py` and
generated a ~9k quality-gated corpus from Wikipedia. Fixed two real bugs
caught on-device: Swift-6 actor isolation on the data models, and a
ModelContainer App-Group trap that crashed launch without the entitlement.
*Left:* iOS single-player loop playable end to end on the simulator; docs +
parity matrix written; Web/Android/tvOS rows marked ⏳ with notes.
