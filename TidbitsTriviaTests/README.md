# Apple Core tests

`tools/test-apple.sh` — or `xcodebuild test -destination 'platform=macOS'
-only-testing:TidbitsTriviaTests`. The Windows analogue is `cd windows &&
dotnet test`.

## Why this target is shaped the way it is

**Not a hosted test bundle.** An earlier attempt wired the tests to the app as a
`TEST_HOST` and hit `Multiple commands produce TidbitsTrivia.swiftmodule` — the
universal app module built twice. That is why `project.yml` carried a "deferred"
note and the Apple side shipped with **zero** tests while Windows carried 443.
This target compiles `TidbitsTrivia/Core/` straight into the bundle instead, which
sidesteps the collision by construction and needs no app host in CI.

**macOS destination.** These are pure-logic tests over the platform-agnostic
Core — the 60–70% the universal target exists to share. No simulator boot, no app
install, so the suite runs in well under a second and is cheap enough to gate every
push.

**Swift Testing, not XCTest.** The project sets
`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, which makes an `XCTestCase` subclass
MainActor-isolated and collides with its own `nonisolated` inherited initialisers.
`@Test`/`#expect` has no such inheritance, so it simply works.

## What is covered

| Suite | What it protects |
|---|---|
| Standings outcome | A tie is announced as a tie, not as a win for whoever sorted first (QA-SWEEP-LOG Q23) |
| Scoring | Wrong answers never pay; the speed bonus never goes negative; the streak multiplier is capped |
| Daily pick | The cross-stack contract — golden FNV-1a64 vectors, order-independence, stability |
| Seeded RNG | Determinism across launches (Swift's `Hasher` is per-run salted) |
| Bot opponent | The believability spec — ~5% freeze, skill tracks base, times vary and stay in-window |
| Catalogs | Unique ids, stable raw values (they are persisted and sent over the Live wire) |
| Expedition catalog | Contiguous stages, reachable pass bars, real categories, valid difficulty bands |
| Weak-Spot Arena | The round really is built from the player's own misses |
| Knowledge Atlas | The sample floor withholds a trajectory arrow rather than guessing |
| Marathon | Resumability — the cursor survives a save/fetch round trip and skips exactly what was answered |

## What is NOT covered, and why

Anything that reads the bundled corpus (`CorpusDatabase`, `Marathon.startNew`,
`LinkWall`'s generator) needs `corpus.sqlite`/`match.json` from the app bundle,
which a logic-only bundle does not carry. Those paths stay covered by the
simulator sweeps (`tools/qa-sweep.sh`) and by the Windows mirror. Adding a test
resource bundle would close the gap — a real follow-up, not a silent hole.

UI, networking and StoreKit are likewise out of scope here.
