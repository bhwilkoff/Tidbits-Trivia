# Archive — detailed session log

Full per-round detail moved out of `SCRATCHPAD.md` to keep the auto-loaded
snapshot lean. Newest last. See `docs/HANDOFF.md` for the current state and
the forward plan.

**2026-06-16 (round 1 — iOS foundation)** — *Found:* empty starter scaffold
(apple/ placeholders, template docs). *Did:* researched the trivia market +
quiz/learning theory (two agents; distilled into docs/ROADMAP.md +
docs/QUESTION-QUALITY.md). Generated `TidbitsTrivia.xcodeproj` via xcodegen
(universal iOS+tvOS, MainActor-default concurrency). Built the full Core layer
(models, template engine + quality gates, bundled-SQLite reader, question
provider, game-loop engine, scoring, SwiftData records + missed-fact spaced
review, Game Center bridge). Built the iOS UI: 90s sticker design system, home
(daily + modes + category grid), live gameplay with answer states + "learn the
fact" reveal, results with missed-fact recap + ShareLink, records/stats,
create-a-quiz. Wrote `generate_corpus.py`; generated a ~9k corpus. Fixed two
on-device bugs: Swift-6 actor isolation on the data models, and a ModelContainer
App-Group trap that crashed launch without the entitlement. *Left:* iOS SP loop
playable end to end; docs + parity written.

**2026-06-16 (round 2 — multiplayer + polish)** — local pass-and-play (2–4,
shared fair set, hand-off + scoreboard, reuses GameEngine per player); spaced
re-asking woven into solo games (GameEngine.weave + RecordsStore.dueReview,
skips Daily); haptics (Settings-gated); Settings sheet; CoreGraphics app icon.
Refactored GamePlayView to take an injected engine. Verified on the sim.

**2026-06-16 (round 3 — share + onboarding)** — spoiler-free Wordle-style emoji
grid on results + share text; 3-card first-run onboarding (play/learn/compete).

**2026-06-16 (round 4 — web mirror)** — vanilla-JS web app (no build):
js/engine.js, js/api.js (corpus loader + Wikipedia CORS client), js/store.js
(localStorage), js/app.js (hash router + full loop), css/styles.css, index.html,
manifest.json, sw.js; tools/corpus/export_json.py → assets/corpus.json. Verified
headless; fixed an IndexedDB-hang (timeout race).

**2026-06-16 (round 5 — Wikidata moat)** — `tools/corpus/wikidata.py`: SPARQL
generator over bounded domains, answers derived structurally. 1,117 verified Qs
across 8 templates. Corpus 8,889 → 10,006. Hardened for WDQS 429s.

**2026-06-16 (round 6 — tvOS)** — `tvOS/ContentView_tvOS.swift` +
`GameView_tvOS.swift`: dark-first focus-correct home + game loop + results,
reusing GameEngine. Caches-based SwiftData store (Decision 017). Moved
LaunchRequest to Core. Fixed nested-`Body`-vs-`ButtonStyle.Body` collision
(renamed `Inner`). Verified Apple TV sim.

**2026-06-16 (round 7 — Android)** — Kotlin/Compose/M3 app on the scaffold.
Package → com.learningischange.tidbitstrivia; lean stack (no Hilt/Nav3/Room/
Ktor — manual DI + sealed Route + BackHandler; in-memory JSON corpus).
data/Tidbits.kt + ui/GameState.kt + ui/AppRoot.kt + theme. Build fights: Gradle
8.13→9.4.1, kotlinOptions→compilerOptions, compileSdk 36→37, theme parent →
DeviceDefault. Verified Pixel 9 Pro. **Four-platform vision complete.**

**2026-06-17 (round 8 — question diversity & tell-free answers)** — corpus was
89% two templates ("best described" ≈45%) and answers guessable from form.
Researched the question-type taxonomy (33-type catalog) + MCQ distractor craft
(Haladyna/NBME → no-tells checklist). Rewrote the summary path into FIVE
rotating shapes (identify/jeopardy/cloze/categorize/oneliner) × ~19 stems,
seeded round-robin caps categorize to ~9%, two different shapes per subject.
Length-normalized typed-sibling distractors. `clean_clue` strips ()/[] clutter
(foreign scripts, IPA, romanizations, empty parens, acronym leaks). Mirrored
across all four engines. QUESTION-QUALITY v2. Corpus 9,945, "best described" = 0.

**2026-06-17 (round 9 + 9b — Wikidata question-TYPE expansion)** — rewrote
wikidata.py to be DATASET-driven (countries/elements/films/books/people, cached
to tools/corpus/cache/), generating many 4-option TYPES per dataset: forward +
reverse attribute, superlative, chronology, numeric closest-to, classification —
all render on every platform via the shared corpus (Decision 025). Fixed a qid
collision that had deduped fixed-stem types to 3 each (now keyed on the option
set); added dataset caching (instant/resumable regen); targeted DELETE. WDQS
~1000s throttling handled via cache + background `--fetch`. Fixed web staleness
(network-first + versioned corpus.json + SW v2). Corpus → **11,679 across 22
distinct types** (5 summary shapes + 17 Wikidata). All four platforms rebuilt
green.
