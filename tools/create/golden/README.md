# Create search golden

`search.txt` is `<topic>\t<sorted question ids>` for the topic list in
`tools/create/parity-topics.txt`, captured from the **shipped Apple ranker** on the
iOS simulator (`TIDBITS_CREATE_SWEEP_SEARCH_ONLY=1`).

It exists because "the same topic returns the same quiz on every platform" is the
six-platform contract, and until this file existed nothing checked it. The four
engines were unit-tested against the same cases, which is not the same thing: the
first end-to-end comparison found a real divergence immediately — Swift's sort is
not stable and JavaScript's is, so rows tied on score ordered differently and
`diversify`'s per-category cap then kept a different SET.

**Nineteen of the 49 topics correctly return nothing.** They are in the file on
purpose — a golden listing only the topics with results would happily pass a
regression that answered "Harry Kane" with Spokane and Butane again. Each consumer
asserts the empties separately.

Order is not part of the contract (`diversify` shuffles so a quiz does not march
category-by-category), so ids are sorted here and compared as sets.

Regenerate after any deliberate ranker change, then re-run the consumers:

    tools/create/parity.sh --regenerate

## Consumers

- **Swift** — captured from; `tools/create/parity.sh` re-verifies against the
  shipped ranker on the simulator.
- **JS** — `tools/create/parity.sh`, which runs the real `js/api.js` in node
  against the real corpus (not a re-implementation).
- **C#** — `windows/Tidbits.HeadlessTests/CreateGoldenTest.cs`.
- **Kotlin** — `android/.../CreateGoldenTest.kt`, via the `Corpus.rank` seam.
  `search` reaches into Android SQLite, so the ranking POLICY was split out to run
  on the JVM. `rank` re-applies the difficulty and continent-template rules that
  `search` pushes into SQL, which makes SQL a pure optimisation: feeding `rank`
  every row in the corpus produces exactly what feeding it the pre-filtered subset
  does. That is what makes the test measure the shipped behaviour rather than a
  convenient subset of it.

All four engines are held to this file.
