# Project Scratchpad — Tidbits Trivia

> Active working notes. See `PARITY.md` for the cross-platform feature
> matrix (single source of truth). See `DECISIONS.md` for the why behind
> architecture. See `docs/QUESTION-QUALITY.md` for the question-engine
> rulebook and `docs/ROADMAP.md` for the competitive feature plan.

## Current state

- **Status**: iOS v1 SHIPPING (solo + daily + create + pass-and-play +
  records/learning loop). **Web mirror SHIPPING** (same corpus + engine +
  design; the canonical share-link target).
- **Active milestone**: M1 (iOS single-player core), wrapping up.
- **Platform set**: Web + iOS + iPadOS + tvOS + Android (Decision 020).
  tvOS earns its place — living-room trivia is lean-back (Decision 021).
- **Last session (2026-06-16)**: Built the whole iOS foundation from the
  starter scaffold. See session log below.
- **Round 2 shipped (2026-06-16)**: local pass-and-play (2–4 players),
  spaced re-asking woven into solo games, haptics, Settings sheet, real
  app icon. All verified on the simulator.
- **Round 5 shipped (2026-06-16)**: Wikidata SPARQL moat — 1,117 structurally-
  verified questions (capitals, currencies, continents, UNESCO sites, element
  symbol/number, Best-Picture directors, prize book authors). Corpus now
  **10,006** (crossed the 10k goal). Verified rendering on iOS; web JSON
  re-exported.
- **Next actions**:
  1. Gates 6/7/9: vandalism/freshness cross-checks, NPOV blocklist (e.g.
     contested continent-of-country: Cyprus/Russia/Turkey), human sampling.
  2. Wire Game Center entitlement + App Store Connect leaderboards/achievements.
  3. Branded launch screen (fresh launch currently shows the default white one).
  4. Mirror the SP loop to Web (canonical share target) then Android.
  5. Phase 2 MP continues: Game Center async head-to-head → tvOS living-room
     mode with phone-as-buzzer (Decision 023).
  6. Wikidata SPARQL validation layer (the moat — ROADMAP #2).

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

**2026-06-16 (round 2)** — *Found:* committed v1 SP foundation. *Did:* shipped
local pass-and-play multiplayer (2–4 players, shared fair question set,
hand-off screens, scoreboard — reuses GameEngine per player, Decision 023
step 1); wove spaced re-asking of due missed facts into solo games
(GameEngine.weave + RecordsStore.dueReview; skips Daily for fairness); added
haptics (answer + milestone, Settings-gated); a Settings sheet (haptics
toggle, reset data, Wikipedia attribution, version); and a real branded app
icon (CoreGraphics generator in tools/icon). Refactored GamePlayView to take
an injected engine so solo and party share it. *Verified:* full party flow to
scoreboard, party setup, home with new Party card + gear, icon compiled into
the bundle — all on the iPhone 17 Pro sim. *Left:* round-2 features playable;
launch screen still default white (polish TODO).

**2026-06-16 (round 3)** — Added the spoiler-free Wordle-style emoji grid to
results + share text (ROADMAP #1 retention loop) and a 3-card first-run
onboarding (play/learn/compete). Verified on the sim.

**2026-06-16 (round 4 — web mirror)** — *Did:* built the vanilla-JS web app
(no framework, no build): `js/engine.js` (TemplateEngine/Scoring/SeededRNG
mirror), `js/api.js` (corpus loader — fetch JSON, IndexedDB cache with a
timeout guard — + Wikipedia client with `origin=*` CORS), `js/store.js`
(categories/modes + records/streak/missed in localStorage), `js/app.js`
(hash router + full game loop + all views), rewrote `css/styles.css` (90s
sticker system, token parity), `index.html`, `manifest.json`, `sw.js`
(offline shell + cached corpus). Added `tools/corpus/export_json.py` → bundled
`assets/corpus.json` (8,889 Qs, 4.3MB / 0.7MB gzipped). *Verified:* headless
Chrome — home + daily game render with design parity; fixed a real
IndexedDB-hang bug (timeout race) surfaced by the headless test. *Left:* web
SP loop playable; PARITY web column now ✅ for the SP feature set. iOS share
text still says the placeholder "tidbits.trivia" — point it at the real web
URL once a domain is chosen. Pass-and-play + onboarding not yet mirrored to web.

**2026-06-16 (round 5 — Wikidata moat)** — *Did:* built `tools/corpus/wikidata.py`,
a SPARQL generator over bounded domains that derives answers structurally
(gates 1/2/4/5 hold by construction — a different country's capital is
definitionally wrong). Added 1,117 verified questions across 8 templates
(capital/currency/continent/UNESCO/elementSymbol/elementNumber/
bestPicDirector/bookAuthor); pruned 92 hypothetical-element entries for
recognizability. Corpus 8,889 → 10,006. Re-exported web JSON; rebuilt + verified
on iOS ("On which continent is Cyprus?" renders clean). Hardened the generator
for WDQS 429s (Retry-After, --only, spacing). *Left:* gates 6/7/9 outstanding;
live runtime path still summary-based (corpus is the moat for now).
