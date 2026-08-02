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
