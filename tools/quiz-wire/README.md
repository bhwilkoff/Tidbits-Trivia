# Saved-quiz wire goldens (`quiz.v1`)

`golden/quiz-v1.json` is the ONE fixture every platform must decode identically —
see `docs/QUIZ-CONTRACT.md`. It deliberately exercises all three entry situations in
one object:

1. a plain corpus **ref** (`src:desc:Q1`),
2. an **inline** live-generated MCQ, in `corpus.json` row shape, with an apostrophe
   and a URL in it so escaping is covered,
3. a bundled-set **ref** (`{"i":"src:describe:Ornette_Coleman","s":"picture"}`).

Entry 3 is the one that matters most. The bundled sets share the corpus `src:`
namespace -- 166 of 200 sampled Picture ID rows have an ID that ALSO exists in the
corpus as a *different question shape* -- so a bare ID is ambiguous and resolving it
corpus-first silently served a text question in place of a saved picture question.
A stack that decodes this entry as a plain ref, or that falls back to the corpus when
its set lookup misses, reintroduces that bug.

Keys are in sorted order because every writer emits sorted keys — two devices saving
the same quiz must produce byte-identical output, which is what makes the "created or
deleted, never edited in place" merge guard in QUIZ-CONTRACT §4 checkable.

Each stack asserts against this file in its own suite, so a drift shows up as a red
test on that platform rather than as a share link that opens the wrong quiz:

| Stack | Test |
|---|---|
| Apple | `TidbitsTriviaTests/SavedQuizTests.swift` (`goldenFixture…`) |
| Windows | `windows/Tidbits.HeadlessTests/SavedQuizTest.cs` |
| Android | `android/…/SavedQuizTest.kt` |
| Web | `tools/quiz-wire/check_web.mjs` |

Never edit the fixture to make a test pass. If the format genuinely changes, that is
a `v` bump plus a NEW fixture file — the v1 one stays, because quizzes already in the
wild are v1 forever.
