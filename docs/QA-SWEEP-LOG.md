# QA sweep log — every game mode and feature screen, per platform

Driven by `tools/qa-sweep.sh <ios|ipad|tvos> [outdir]`, which launches the app once per
case with the `DebugHooks` env family, screenshots it, and reports a crash when the pid
simctl handed back is gone. ~47 captures per platform.

This is a **playability + completeness** pass, not the store capture
(`tools/capture-screenshots.sh`) — it draws real questions rather than the screened set,
because the point is to catch a mode that renders or plays wrong.

---

## Round 1 — iPhone 17 Pro (iOS 26 sim), 2026-07-30, build 1.6.69

**Swept:** 15 modes mid-question · 9 modes at reveal · 3 end-of-game · 20 feature screens.

### Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| Q1 | **Bug** | **Match-Up gave away 2 of 4 pairs.** The parenthetical added to disambiguate a WORK title also names its composer — the value being matched to. "Magnificat (Bach)" → Johann Sebastian Bach; "Symphony No. 3 (Górecki)" → Henryk Górecki. 18 pairs across the set. | **Fixed** — `tools/corpus/fix_match_giveaways.py`, all 3 shipping mirrors |
| Q2 | Judgement | 44 matching pairs where key and value are the **same name** (San Marino → San Marino, Monaco → Monaco). Factually true, and knowing city-states share the name IS knowledge — but in a 4-pair grid it is a free point *and* removes a distractor. | **Owner call** — not changed |
| Q3 | None | 25 pairs with partial overlap (Tunisia → Tunis, El Salvador → San Salvador, Saudi Arabia → Saudi riyal). Still require real knowledge. | No action |
| Q4 | Content | "In what year did William Penn die?" is filed **ARTS & LIT**; Penn was a colonial administrator. Corpus categorisation, not a rendering fault. | Noted |
| Q5 | Cosmetic | Enumerate prompts have no terminal punctuation ("…as you can"). | Noted |
| Q6 | Cosmetic | "Which of these is the most populous?" omits the noun (city). Inferable but loose. | Noted |

| Q7 | **Bug** | **Ordering and Matching gave NO reveal feedback.** Both are partial-credit modes, yet the reveal re-rendered the player's own grid unmarked — the only way to learn what you got wrong was to read the explanation and diff it by eye. Every MCQ mode colours correct/incorrect. Verified the scoring itself was right (ordering is inversion-based: 3 of 6 inversions → 40×0.5 = +20). | **Fixed (iOS)** — each row now marks ✓ / the position it should have had, mint/coral tinted |
| Q8 | Regression I caused | Tinting the Matching rows turned them muddy brown with grey text: they are `Button`s with `.disabled(!live)`, and SwiftUI's disabled dimming compounds any fill. Now rendered as a plain view at reveal. | Fixed |
| Q9 | **Bug** | macOS and tvOS had the **same missing ordering/matching reveal feedback** (separate game views). | **Fixed** — tvOS verified on the Apple TV sim (green ✓ / dark-red "→ N", legible at ten feet); macOS code-mirrored + builds, **not visually verified this round** |
| Q10 | Harness | The tvOS sim showed the **Game Center sign-in overlay** across the first capture attempt. `TIDBITS_NO_GAMECENTER=1` suppresses it — needed for every tvOS run. | Fixed in the run recipe |

### Harness defects found in the harness itself
- `launchctl list` does **not** reliably list simulator apps — it reported all 6 of
  home/profile/ladder/daily/multiplayer/weakspot as dead when every one rendered
  correctly. Now checks the pid `simctl launch` returns.
- A 12s settle was too short for a 10-question autopilot run, so `results-*` captured
  mid-game instead of the results screen. Raised to 30s.

### Verified working (rendered correctly, no crash)
Classic · Time Attack · Survival · Stake · Sweep · Picture Round (image loads, aspect-fit)
· This or That · Closest Call (slider + range + Lock In) · Ordering · Match-Up · Type
Answer · Odd One Out · Ladder · Enumerate (0/8 + Done) · Daily · Home · Records · Create ·
Settings · Profile · Customize · Daily archive · Night setup · Pass & Play · Versus ·
Multiplayer · Paywall · Club hub · Story archive · Atlas · Link Wall · Expedition map ·
Marathon · Weak Spot · Mix

---

## Round 2 — Apple TV (tvOS 26 sim), 2026-07-30

| # | Severity | Finding | Status |
|---|---|---|---|
| Q11 | **Bug** | **Closest Call was barely playable on a remote.** tvOS correctly swaps the iPhone slider for steppers, but they were `±spec.step` and `±step×10` — so a year question spanning 1000–2025 offered only ±1 and ±10, i.e. ~100 presses to cross the range. The slider hides this completely on iPhone, so it can only surface by playing the mode on a TV. | **Fixed** — steps now scale to the RANGE (≈20 presses end to end) with a middle tier: ±1 / ±10 / ±50. Verified on the sim |
| Q12 | Content | "Name as many of **The Beatles' studio albums**" filed under ARTS & LIT; should be MUSIC. Same class as Q4. | Noted — corpus categorisation |
| Q13 | Harness | The crash detector cried wolf a **second** time: `simctl spawn kill -0 <pid>` reported all 47 tvOS cases dead while every screen rendered. Replaced with "is there a `.ips` crash report newer than the launch" — the only signal here that means what it says. | Fixed |

### tvOS verified working
Home (focus ring on Quick Play) · Enumerate + Type Answer correctly use the **self-marking**
idiom ("name them in your head, then reveal") rather than remote text entry · Ordering and
Matching reveal feedback legible at ten feet · dark theme throughout.

---

## Round 3 — iPad Pro 13-inch (iOS 26 sim), 2026-07-30

| # | Severity | Finding | Status |
|---|---|---|---|
| Q14 | **Bug** | **The iPad was a stretched iPhone.** iPhone-first horizontal padding is right at 390pt and wrong at 1032pt: option buttons spanned the full screen with their answer text stranded at the far left, the HUD stretched edge to edge, and two-thirds of the display sat empty. Home had it too, so it is systemic rather than one view. | **Fixed** — new `.readableColumn()` (760pt, centred) + **iOS-DESIGN §2.2a**; applied to the game screen, its HUD, and Home. Verified on the sim |
| Q15 | Harness | The sweep picked an **iOS 18.5 iPad** against the app's iOS 26 floor, and simctl reported it only as `Invalid parameter not satisfying: installURL`. The device picker now requires a runtime ≥ 26. | Fixed |

| Q16 | Polish | Constraining Records left its **system `navigationTitle` orphaned** flush-left while the content centred beneath it. A nav title lives in the navigation bar and no content modifier can move it. | **Fixed** — `.readableColumn(alignment:)`; surfaces under a system title pass `.leading` so the column aligns with it, surfaces that own their heading (game, Home) stay centred |

### Applied so far
Game screen + its HUD · Home (centred) · Records · Create (leading, under a nav title).

### Still stretched
Settings · Profile · and the dialog surfaces. Applying `.readableColumn()` blind to views
I have not seen on iPad would be guessing; each needs a look first.

---

## Round 4 — Android (Pixel 9 Pro emulator), 2026-07-30

| # | Severity | Finding | Status |
|---|---|---|---|
| Q17 | **Bug** | **Every non-MCQ question also rendered four MCQ buttons.** `q.options.forEachIndexed { ... AnswerButton }` ran unconditionally, so an Ordering question drew its four items a second time below the ordering panel — and they were **tappable**, calling `game.submit(i)` and scoring the question as an MCQ, bypassing the mode entirely. iOS branches these shapes with `else if`; Android never did. | **Fixed** — buttons render only for a plain MCQ. Verified on the emulator |
| Q18 | Harness | **The first Android sweep was worthless and said it passed.** The debug build carries `applicationIdSuffix ".debug"`, so `am start` on the release id failed with a bare "Error type 3" — and because a failed launch is not a crash, all 28 "captures" were the launcher and every one reported healthy. The package is now resolved from the device, and each shot asserts the app is actually **foreground** rather than merely uncrashed. | Fixed |

### Android verified working
Closest Call (slider, correct range) · the 15 modes launch · Records/Create/Home/Party/
Night setup. **Not covered:** Club, paywall, atlas, link wall, expeditions, marathon, versus,
multiplayer, settings, profile — Android's `ScreenshotHooks` has no hooks for these, so they
are genuinely unswept rather than passing.

---

## Round 5 — Windows (Avalonia headless, Mac head), 2026-07-30

New `AllModesSweep` renders **every** game mode, not just Classic. The pre-existing
`GameSnapshot` covered Classic alone, which is precisely the blind spot that let the
Android bug (Q17) live: MCQ buttons drawn over every non-MCQ shape are invisible in a
Classic-only snapshot.

**Result: no findings.** All 15 modes reach `Playing` and render their own answer surface —
Ordering shows its move controls and Submit with no stray MCQ buttons, Type Answer shows
only the text field. Windows branches the shapes correctly where Android did not. 437 tests
green.

The sweep is now a permanent gate on Windows, so the Android class of bug cannot appear
there unnoticed.

---

## Round 6 — macOS (real app, no simulator), 2026-07-30

| # | Severity | Finding | Status |
|---|---|---|---|
| Q19 | Verification | The Q9 ordering-reveal fix **does render on macOS** — a coral row carrying "→ 1" beside the explanation. Q9 is now visually confirmed on all three Apple platforms rather than build-verified on one. | Closed |
| Q20 | Harness | An unattended macOS run hits a **keychain prompt** ("Tidbits wants to use … tidbits.fb.anonRefresh"), which blocks automation. It is an artefact of the UNSIGNED local build — the keychain ACL does not match, so the OS asks. A signed build does not prompt, so this is a QA constraint, not a shipping bug. Do not chase it as one. | Recorded |
| Q21 | **My error** | When the window-id helper failed (pyobjc/`Quartz` not installed), I fell back to a **full-screen capture**, which swept the developer's terminal and an emulator into the frame. Deleted immediately. `tools/mac_window_id.py` now falls back to AppleScript window **bounds** (`screencapture -R`), so a capture is always window-scoped — which is what the file's own docstring already warned about. | Fixed |

---

## Round 7 — deep per-feature pass (Pass & Play · Trivia Night · Club), 2026-07-31

Not "does the screen render" but "does the feature do what it claims". Driven by
playing each feature to completion rather than screenshotting a launch state.

| # | Severity | Finding | Status |
|---|---|---|---|
| Q22 | **Missing feature** | **macOS had no Pass & Play at all.** Windows shipped it (WINDOWS-PARITY 1.4), iOS and Android shipped it, and the Mac — the other desktop, and the likeliest shared-desk machine in the set — had only Versus-vs-CPU. Not a stale matrix cell: there was no Mac code path. | **Built** — `macOS/MacParty_macOS.swift` reusing Core verbatim (GameEngine/Player/QuestionProvider), rebuilt as a Mac shell: window-root swap (not a sheet, so the split-view toolbar can't bleed through), `CompactButtonStyle` + `.keyboardShortcut`, grape Home card. Verified end-to-end on the real app: setup → handoff → play → turn score → next player → ranked scoreboard |
| Q23 | **Bug (all platforms)** | **A tie was announced as a win.** Every board sorted by score and called element 0 "the winner", so two level players produced "Player 1 wins!" — an arbitrary sort order reported as a victory. Ties are NOT an edge case here: Pass & Play deals ONE shared question set, so identical play genuinely finishes level (the Mac run proved it — both players scored exactly 1,169). It also mis-highlighted, tinting only the first row gold. Present on **6 surfaces**: Pass & Play (iOS/macOS/Android/Windows) and Trivia Night standings (web/iOS/tvOS/macOS big screen/Android host + live). | **Fixed everywhere** — one shared rule per stack (`Core/Models/StandingsOutcome.swift`, `Tidbits.Core/Store/StandingsOutcome.cs`, mirrored inline in JS/Kotlin): 1 leader → "X wins!"; all level → "It's a tie!"; partial → "Tie — A & B"; and EVERY leader is highlighted. 6 new Windows tests pin it (443 green) |
| Q24 | Polish | **Expedition subtitles truncated mid-word** ("…to the dot-c…", "…how we know what…") under a `lineLimit(2)`, with half the screen empty below. | **Fixed** — 3 lines on iOS/macOS/tvOS/Android rows (Windows/web already wrapped freely) |
| Q25 | Harness | **The Q21 capture fix was incomplete.** `screencapture -R<bounds>` is window-SCOPED but not window-CONTENT — it grabs whatever pixels occupy that rectangle, so an editor sitting on top of the app window landed in the frame exactly as a full-screen grab would (it happened twice this round; both captures were deleted immediately). | **Fixed properly** — pyobjc/Quartz installed, so captures use `screencapture -l <windowid>`, which reads the window's own content and is immune to occlusion AND to the keychain dialog. `tools/mac_window_id.py` also activates the app before any bounds fallback |

### Verified as genuinely implementing their claim (not just rendering)
- **Weak-Spot Arena (Club F1)** — played a Classic round answering wrong to create real
  miss history, then launched the Arena: it drew back a question actually missed, captioned
  "Missed 25 sec. ago · ×1". The transparency claim is real.
- **Marathon (Club F3)** — hard-quit mid-run via `simctl terminate`, relaunched: the hub
  reported "Question 4 of 5 — resume where you left off". Resumability holds across a cold kill.
- **Link Wall (Club F6)** — a well-formed 4×4 with four clean groups (elements H/Fe/Al/Cu ·
  operas Orpheus/L'Orfeo/Nabucco/Nixon in China · leaders Gandhi/Churchill/Mandela/de Gaulle ·
  films A Trip to the Moon/Frankenstein/Koyaanisqatsi/Aguirre), 4-mistake budget, Shuffle +
  Deselect All + Submit.
- **Knowledge Atlas (Club F4)** — percentages match their own fractions (22/27→81%, 23/26→88%,
  15/24→63%), bars proportional, every domain row a door into a round.
- **Expeditions (Club F5)** — the row DOES report "Stage N of M — tap to continue" once a
  campaign is started; the plain subtitle in a fresh state is correct, not a missing feature.
- **Pass & Play fairness** — two players on the same dealt set with identical play scored
  identically, which is the "same questions, fair and square" promise actually holding.

## Round 8 — Create, played not screenshotted, 2026-07-31

| # | Severity | Finding | Status |
|---|---|---|---|
| Q26 | **Bug (all platforms)** | **Create built a quiz about the wrong subject.** Typing "Marie Curie" produced "In what year was Marie de' Medici born?". The corpus search ORs its tokens (a row need match only ONE typed word), and while the score does favour multi-word hits, `diversify` then round-robins by CATEGORY — so a one-word coincidence in an under-filled lane is *promoted over* a genuine match. Measured on the shipping corpus: "Marie Curie" has **15** real two-word matches (all science) against **211** one-word hits across 7 categories, **189 of which never mention Curie**. | **Fixed on 5 platforms** — rank by DISTINCT matched-token count and keep only the best tier, then rank/diversify within it (Swift/Kotlin/JS/C#; single-word topics unaffected, every row ties at 1) |
| Q27 | **Bug the Q26 fix exposed** | With relevance fixed the pool is usually single-domain, and `diversify`'s per-category cap (`max(2, ceil(limit/3))` = 3) then **starved** the set: a requested 8-question quiz came back as 4. The anti-monopoly rule was tuned for the noisy pool it was hiding. | **Fixed** — the cap is a preference, not a quota: after the round-robin, top up from the ranked remainder. Diversity is still preferred wherever it exists, and never costs length |
| Q28 | **Bug (same class, second code path)** | The first fix only covered `CorpusDatabase.search`. The shaped-question path (`JSONQuestionSource.searchMatch`, feeding Picture/This-or-That/Closest Call into every Create set) took **any** token match and then `.shuffled()` with no ranking at all — so the topped-up quiz led with "In what year did Jean-Marie Le Pen die?". Found only by re-playing after the first fix. | **Fixed** — same matched-token tier, Swift + Kotlin |

**Verified after the fix** by playing the generated set: "Marie Curie" now yields 8
questions, on topic, e.g. "In what year was Radium discovered?" and "Element 88 on
the periodic table, this silvery-white alkaline earth metal turns black when exposed
to air and glows via radioluminescence as it radioactively decays — which element?"

Regression cover added on both stacks that have suites: `CreateRelevanceTests.swift`
(Apple, now **87** tests) and `CreateRelevanceTest.cs` (Windows, now **447**).

**Also confirmed working:** Create's live-generation path end to end — topic →
Wikipedia fetch → playable quiz, with the reveal, the "Now you know" explanation and
the source link all correct.

## Round 9 — Online Multiplayer + Story Archive, 2026-07-31

Both verified as genuinely implemented, not shells:

- **Online Multiplayer** — every bot is visibly labelled CPU (the honesty rule),
  and each blurb matches its real `categorySkill` offsets (Rae sports+film, Tina
  history, Ace science). **Quick Match is not a dead end**: real GameKit
  matchmaking with host/join transports plus a "sign in to Game Center" state and
  a "couldn't find a match" state. The two-device gate still stands for a live
  human-vs-human run.
- **Story Archive** — real stories drawn from actual play history, with ✓/✗ marks
  matching what was answered, relative timestamps, favourite stars, All/Favorites/
  Missed/Got-it chips, domain chips and text search.

| # | Severity | Finding | Status |
|---|---|---|---|
| Q29 | Not a bug | The floating **"Search your stories"** pill looked like a compositing fault (card text bleeding through illegibly). It is SwiftUI's **native `.searchable()`**, which on the iOS 26 baseline renders as a bottom-aligned floating pill with Liquid Glass — the bleed-through is Apple's material showing content scrolling beneath, i.e. the intended appearance, exaggerated by a static screenshot. CLAUDE.md mandates exactly this 26-era API, so "fixing" it would mean fighting the platform. | **Closed — by design.** Same discipline as the Atlas sample-floor test: verify the contract before changing correct code |

## Round 11 — closing the Android coverage gap, 2026-07-31 (final tick)

The longest-standing honest gap in this log: ~10 Android Club/account surfaces had
**no `ScreenshotHooks` entry**, so the Android sweep skipped them entirely. They were
recorded as "not covered" rather than passing — correct, but it stayed unfixed for
several rounds because each round found louder bugs first.

**Fixed structurally, not one-off.** The hook family had a boolean per surface
(`tidbits_party`, `tidbits_night_setup`), which is why it stopped at two. Replaced with
ONE mapped string extra, `--es tidbits_open <route>`, so a new destination costs a single
line. Unknown values are ignored rather than crashing a capture run mid-sweep.

**Swept all 12 previously-unreachable surfaces** — clubHub · paywall · atlas · linkWall ·
expeditions · storyArchive · marathonHistory · settings · profile · leaderboard · duels ·
online. Every one launches, holds foreground, and logs no `FATAL EXCEPTION`.

**Scope of that claim, stated precisely:** this is the launch/render gate (the app really
reaches the screen and survives), not a deep per-feature review of each Android surface.
It closes "genuinely unswept" — it does not by itself promise Android feature parity in
behaviour, which is still carried by `PARITY.md`.

Stale checkboxes in "Still to do" below corrected: the macOS reveal (Round 6), iPad
(Round 3), tvOS (Round 2) and Android/Windows (Rounds 4/5) sweeps had all been done.

## Apple test suite — added 2026-07-31

The Apple side had **no test target at all** while Windows carried 443 tests, so
every Core regression could only be caught by driving a simulator by hand. That
was not an oversight: `project.yml` carried a note that a hosted test target hit
`Multiple commands produce TidbitsTrivia.swiftmodule` and had been deferred.

Fixed by not hosting the app — the bundle compiles `TidbitsTrivia/Core/` directly,
which sidesteps the double-build by construction, runs on the macOS destination
(no simulator boot, no app install) and finishes in well under a second.

**82 tests in 10 suites**, green. Run with `tools/test-apple.sh`; gated in CI by
`.github/workflows/apple-tests.yml`. Details and coverage table in
`TidbitsTriviaTests/README.md`.

Two things the work surfaced:

- **A real layering violation.** `Core/LiveNightHost.swift` instantiated
  `LiveHostNet`, which lived in `macOS/MacLiveHostNet_macOS.swift` — Core reaching
  into a per-platform folder, which CLAUDE.md forbids. It only ever compiled
  because the universal target builds every folder for every platform. The file
  had **zero** `#if os()` guards, imported only Foundation, and its own doc comment
  already said "Platform-agnostic (Core)" — it was simply misfiled. Moved to
  `Core/Networking/LiveHostNet.swift`.
- **One test failure that was mine, not the app's.** The Atlas reported a domain
  from a single answered question, which looked like the sample floor being
  ignored. Reading the implementation, `sampleFloor` deliberately guards the
  *trajectory arrow* ("don't **flag** a domain with <8 answers") while the row
  itself always shows its own visible sample size. The test was rewritten to pin
  the real contract rather than "fixing" correct code.

## Round 12 — the Round 1 backlog, finished, 2026-08-03 (build 1.6.72)

Round 1's own "still to do" was *"~12 of 47 captures examined in depth; the rest are
captured and awaiting review"*, and it stayed that way for four days — the captures live
in `/tmp`, so they were long gone. Re-swept (`tools/qa-sweep.sh ios`, 47 PNGs) and read
**all 47**, not the loud ones.

| # | Severity | Finding | Status |
|---|---|---|---|
| Q30 | **Bug** | **An Ordering round asked for people in order of birth and listed "Bill O'Reilly (1905)" among baseball figures.** That is `Bill_O'Reilly_(cricketer)`; the generators' `display_name()` strips every parenthetical, so a player who knows the broadcaster (born 1949) puts him last and is marked wrong. **Knowing more makes you likelier to get it wrong**, which is the worst thing a trivia question can do. Measured: **120 Ordering + 121 This-or-That rows** carry a name whose Wikipedia title was disambiguated. | **Fixed** — `fix_display_disambiguators.py` restores the qualifier, and both generators keep it now. A parenthetical with a DIGIT is still stripped: "Pinocchio (1940 film)" in a "which came first?" pair hands over the answer — the mirror image of this bug, and the reason Odd One Out had brackets REMOVED (a3eb5b0). Brackets leak there; their absence misleads here |
| Q31 | Content | "Waging 83 campaigns against the Cumans… which Grand Prince of Kiev…" is filed **ARTS & LIT**. Same class as Q4 (William Penn, also ARTS & LIT) — a ruler in the arts bucket. A regex over reveals finds 112 `arts` rows mentioning a ruler, but most are false positives (a novel that mentions an emperor), so the real number needs the SUBJECT's occupation, not the prose. | Noted, unmeasured — recorded rather than guessed |
| Q32 | None | Q5 (Enumerate prompts had no terminal punctuation) is **gone** — "…as you can." now ends in a period. Q7/Q9 (Ordering + Matching reveal feedback) verified present and correct on iPhone: green ✓ per row and a "+40" award that matches the inversion scoring. | Confirmed fixed |

**Everything else rendered correctly**: 15 modes mid-question, 9 reveals, 3 results
screens, 20 feature screens — no blank views, no clipped prompts, no crash. The results
screens agree with themselves (Sweep 12/12 · 100% · 12 best streak · twelve 🟢 in the
spoiler-free grid).

**Method note worth keeping:** this sweep ran while another launch was driving the SAME
simulator, and the second launch's screenshot showed the first's screen. One driver per
simulator — the CLAUDE.md "boot ONE at a time" rule applies to *driving*, not just booting.

## Still to do

- [x] Round 1 review — **finished in Round 12 above** (re-swept and all 47 read; found
      the Ordering disambiguator bug that the first 12 captures had missed).
- [x] Re-ran `results-*` at 30s — Classic (FLAWLESS, 2,825, 10/10, spoiler-free grid,
      streak, "Tough ones you nailed" + the reflection prompt) and Stake (15 on chips)
      both correct. Score SCALES differ hugely between modes (2,825 vs 15) and are
      presented identically; Records separates by mode, so noted not filed.
- [x] Mirrored the Q7 reveal-feedback fix to macOS + tvOS (Q9).
- [x] **Visually verify the macOS reveal** — done in Round 6 (Q19) — code-mirrored and building, but this round only
      confirmed iOS and tvOS on simulators. macOS needs a real run.
- [x] iPad sweep — done in Round 3 (Q14/Q16) — layout at a different size class.
- [x] Full tvOS sweep — done in Round 2 (Q11/Q13) — focus
      engine, the 10-foot ramp, self-marking modes. Only ordering/matching seen so far.
- [x] Android (Round 4, Q17/Q18) + Windows (Round 5) equivalents.
