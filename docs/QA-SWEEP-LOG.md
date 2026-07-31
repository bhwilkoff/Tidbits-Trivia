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

## Still to do

- [ ] Round 1 review is **partial**: ~12 of 47 captures examined in depth; the rest are
      captured and awaiting review.
- [x] Re-ran `results-*` at 30s — Classic (FLAWLESS, 2,825, 10/10, spoiler-free grid,
      streak, "Tough ones you nailed" + the reflection prompt) and Stake (15 on chips)
      both correct. Score SCALES differ hugely between modes (2,825 vs 15) and are
      presented identically; Records separates by mode, so noted not filed.
- [x] Mirrored the Q7 reveal-feedback fix to macOS + tvOS (Q9).
- [ ] **Visually verify the macOS reveal** — code-mirrored and building, but this round only
      confirmed iOS and tvOS on simulators. macOS needs a real run.
- [ ] iPad sweep (`tools/qa-sweep.sh ipad`) — layout at a different size class.
- [ ] Full tvOS sweep (`tools/qa-sweep.sh tvos`, with TIDBITS_NO_GAMECENTER=1) — focus
      engine, the 10-foot ramp, self-marking modes. Only ordering/matching seen so far.
- [ ] Android + Windows equivalents.
