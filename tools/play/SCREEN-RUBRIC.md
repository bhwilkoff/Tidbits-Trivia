# What to check on a rendered game screen

Asked directly — "what are you auditing on the screens?" — the honest answer on
2026-08-01 was: two pixel statistics, and then whatever I happened to notice.
Noticing is what found every content bug this session, and it is also how you
walk straight past the one you were not thinking about. This is the checklist,
so the reading is the same every time.

Three layers, and they are not interchangeable.

## 1. Every frame, mechanically (`screen_audit.py`)

Catches only that the view **rendered at all**:

| flag | means |
|---|---|
| `BLANK` | one flat colour below the status bar — nothing drew |
| `LOW-INK` | technically not blank, but no readable content |

Two checks were built and cut, and the reasons matter more than the checks:
`BOTTOM-INK` could not tell a ScrollView's content from overflow; `EDGE-INK`
could not tell a chunky card's black border from clipped text. **A rule that
cannot distinguish the defect from the design gets its budget raised and then
ignored.** Do not re-add either without solving that.

## 2. Every question shown, textually (`SHOWN` lines → `audit.py`)

`GameEngine.beginQuestion` emits each question as it is PRESENTED during a
marathon, so content is audited for all ~16,000 questions a 1,008-game run
displays — not just the sampled frames. This is where the corpus-level rules
live (read-off answers, era spread, machine stems, duplicate options).

## 3. One frame in sixty, read (this list)

The only layer that sees meaning. Work down it deliberately:

**The question**
- [ ] Does the prompt read as written English, or as a template? ("founded or
      created", "In which country is Russo-Ukrainian war?")
- [ ] Is the subject named unambiguously — could this clue fit several answers?
- [ ] Does the category badge match what is being asked? (Netflix under `music`.)
- [ ] Is anything visually truncated — an option cut mid-word, a prompt clipped?

**The options**
- [ ] Could three be eliminated without knowing the fact? Check TYPE (a year
      among names), ERA (a pharaoh beside a modern politician), DOMAIN (three
      politicians beside a ski jumper), LENGTH (one much longer than the rest).
- [ ] Is more than one option defensibly correct?
- [ ] Is the answer's position varied across nearby screens, or always the same?

**The reveal**
- [ ] Is there an explanation, and does it teach something beyond restating the
      answer?
- [ ] Is the right answer marked clearly, and the player's choice distinguished?
- [ ] Does the points award match what happened? (In Order paid half marks for
      an untouched board.)
- [ ] Is the source link present and pointing at the real subject?

**The mode's own shape**
- [ ] Did the mode render AS that mode — a slider for Closest Call, a grid for
      Sweep, linked pairs for Match Up — or fall back to a plain MCQ?
- [ ] For Match Up / Odd One Out / Name as Many: is the round internally
      consistent (one category, one era, one kind of thing)?

**The results screen**
- [ ] Do correct / total / accuracy agree with each other?
- [ ] Is a tie or a zero described honestly, not as a win?

**The round, across consecutive frames**
- [ ] Does the same answer, subject or outsider recur?
- [ ] Is every question in a picked category actually from it?

## The standing rule

When reading finds something the machine missed, the finding is not the
deliverable — **the new rule is**. Add it to `quality_gate.py` if it can be
decided from the data, or to this list if it needs a person.

## The reveal panel (added 2026-08-01, from reading a Sweep round)

Read the reveal as a person who just got the question wrong and wants to know
why. Two failures found this way, both invisible to every counter that existed:

- **The description slot must describe.** "Brandon Spikes: 1987." and
  "Matthew Perry: 1969." — 29,020 rows opened the payoff with a bare year. The
  reason it survived so long is instructive: every classifier in `tools/corpus`
  skipped these rows on `not d[0].isdigit()`, so the one field the player reads
  was the one field no machine checked. Now gated by `STUB-REVEAL`.
- **A reveal is rendered VERBATIM** (`Text(q.explanation)` on iOS, `h(q.explanation)`
  on web). Before calling a reveal malformed, check whether the damage is in the
  data or in the tool that is reading it. 1,648 reveals looked broken under the
  "Subject: description" split and read perfectly on screen — the first colon was
  simply inside the text ("Parthia (Old Persian: Parθava...)"). The classifiers
  were the ones reading garbage, not the players.

## Invariants that look like bugs (do not "fix" these)

A rendered screen can make a deliberate choice look like sloppiness. Check the
data before changing it.

- **Numeric options are shuffled, not sorted.** 2011 / 2016 / 2019 / 2015 looks
  unfinished, and every other quiz app orders its numbers. Do not. Distractors
  here are generated AROUND the answer, so sorting puts the answer in a middle
  slot 80.8% of the time against 25% chance — an ordered list would be worth
  three times chance to a player who noticed. Gated by `NUMERIC-SORTED`, which
  watches the RATE (ascending happens by chance in 1 set of 24).

## Modes with an input surface (added 2026-08-01)

A text field and a slider fail differently from a list of options, and the
failures are only visible once the surface is on screen.

- **A free-text clue must produce ONE answer.** In multiple choice a weak clue is
  dull because the options carry the question. With a text field there is nothing
  to pick from: 'Who is this — "Swedish actress (1915-1982)"?' and
  'What is this — "U.S. state"?' were shipped as type-ins. Gated by
  `UNANSWERABLE-TYPEIN`.
- **Read a slider's BOUNDS, not just its question.** "In what year did Carole
  Lombard die?" ran 1000..2025 — the 20th century was 9% of the track. Measuring
  that annoyance found a scoring bug: the answer sat at a median 0.93 of the
  range, so one fixed guess of 1985 scored 61.7% of the mode. Gated by
  `SLIDER-FARMABLE`, which tests the two free strategies (one fixed guess for
  every question; never moving the slider off where it opens).
- **Ask which FILE the thing on screen came from.** The bare-number reveal was
  repaired in corpus.json and the gate went green, and "Whitney Houston: 2012."
  kept rendering — Closest Call carries its own explanation cell. A rule that
  names one file checks one file. Both the repair and the rule now walk every
  question file.

## Does the clue's own wording eliminate the distractors? (added 2026-08-01)

A prompt that states an attribute has made a promise about the options. Read the
stem and ask what it rules out before you ask whether the answer is right.

- **Nationality.** "Who is this American painter?" over Claude Monet, Bob Ross,
  Caravaggio and Raphael. One American among a Frenchman and two Italians — the
  player needs nothing but the adjective. Gated by `NATIONALITY-FREE`, which
  fires only when EVERY distractor's nationality is known and different, since
  one odd nationality among four does not decide a question.
- **The families matter more than the list.** English, Scottish and Welsh are
  British for this purpose; a hyphenated origin ("this Italian-American
  physicist") is two claims and exempt. Without those two exceptions the rule
  flagged 2,402 questions instead of 192, and would have rewritten good ones.
- **A repair must satisfy the OTHER rules too.** Swapping in same-nationality
  distractors pushed KIND-MISMATCH from 0 to 46 and broke an era spread. The
  constraints in tools/corpus are cumulative: same category, same kind, same era,
  no word shared with the prompt, nothing already on screen. Check the set the
  player will see, not each swap in isolation.

## The surfaces around play (added 2026-08-02)

Reading Records after a game found a bug six sweeps of gameplay could not, and
it was in shared Core logic rather than content.

- **Play a round, then read what the app SAYS you did.** A 10/10 Mixed Bag round
  left "Your knowledge" reading "You've explored 0 of 8 domains" with no rows.
  Domain progress was summarised from each ROUND's category, and a Mixed Bag
  round is filed under "mixed", which is no domain — so the default mode credited
  nothing, on all four platforms that show the section, and every badge keyed on
  mastery stayed dark forever. The per-answer categories were already stored;
  only the wrong field was being read.
- **A number that should have moved and didn't is a bug, even when nothing looks
  broken.** Nothing on that screen was misaligned, truncated or empty-stated. It
  was internally consistent and wrong.
- **Native behaviour is not a defect.** Content passing under the iOS 26 floating
  tab bar looks like a clipping bug and is the Liquid Glass design; `TabView`
  applies the bottom inset itself. Check the platform before "fixing" it.

## What the app OFFERS must work (added 2026-08-02)

- **Tap the app's own suggestions.** "Space exploration" was the first chip under
  "Need a spark?" on five platforms, and the shipped ranker returned ONE
  question for it — about robotics. A new player's first tap produced a
  one-question quiz on the wrong subject. Nothing checked it because the chips
  are hardcoded per platform while the ranker reads the corpus, so dropping or
  re-categorising rows can starve a chip that worked when it was chosen. Now
  `tools/create/check_suggestions.sh`, run by the corpus resync.
- **A screenshot only proves what is INSTALLED.** `xcodebuild build` does not
  install; a capture after a rebuild showed the old chip and looked like the edit
  had failed. `simctl install` before launching, or read the previous build.
