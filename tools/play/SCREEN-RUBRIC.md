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

## Generate the surface you cannot sit and watch (added 2026-08-02)

The Daily is one set of seven per day; you cannot read a year of it on a
simulator. Generate it instead and audit the sequence.

- **Sixty days of Daily sets** exposed that 9 of 60 put four or more of seven
  questions in ONE category, three of them at five-of-seven Film & TV. The
  picker was innocent — a uniform 7-draw over this corpus does that 18% of the
  time — so the finding was upstream: the corpus is 31% Film & TV and 2.4%
  Business, and "Mixed Bag" is only as mixed as what it draws from. Decision 050;
  guarded against worsening by `CATEGORY-SKEW`.
- **Check whether the thing you want to change is a live contract.** The shared
  Daily leaderboard posts a 7-char marks string aligned to `pickDaily`'s ORDER,
  so changing the draw desynchronises marks from already-shipped clients on the
  same day. Five determinism mirrors and a board migration is not a same-tick
  change; measuring it, recording why, and fencing the regression is.

## Read the prompt as a sentence (added 2026-08-02)

Three defect classes came out of one rendered geography round, and none of them
is about facts — they are about English. Read the prompt aloud before checking
whether the answer is right.

- **"Approximately what is the elevation of Appalachian Mountains?"** A template
  dropped a title into a slot that wanted "the". 608 prompts. The fix list must
  stay short: matching every "Sudan" and "Valley" yields "the Sudan" and "the
  Death Valley", which is worse than the defect. `MISSING-ARTICLE`.
- **"What currency is used in the Songhai Empire?"** — which fell in 1591. 769
  prompts asked a present-tense template of a historical subject. Prose-sniffing
  caught 528; Wikidata's Q3024240 ("historical country") caught the rest exactly,
  because it is on the Kingdom of Navarre and not on France. Prefer the
  structural signal to the adjective. `PRESENT-TENSE-PAST`.
- **"In which country is the Andaman Islands?"** — introduced BY the article fix.
  Adding "the" made a number disagreement audible that "is Andaman Islands" had
  hidden. A repair that only half reads the sentence leaves it half wrong; the
  gate rule for it says so in as many words. `NUMBER-AGREEMENT`.

## Say what is being compared (added 2026-08-02)

- **A headline fragment is not a question.** "Most people of the four — which
  one?" is not English; "Longest of the four — which one?" does not say longest
  WHAT. 3,692 rows, while the same question type was already phrased properly
  elsewhere in the corpus. The dimension came from the row id's Wikidata
  property, never guessed from the fragment. `TERSE-STEM`.
- **The prompt should not say less than its own reveal.** These rows answered
  "has the greatest population of the four (23.9 million)" under a prompt that
  never mentioned population. When the answer panel is more specific than the
  question, the question is the thing to fix.
- **Count how often a round repeats a SENTENCE.** Four phrasings of "founded
  earliest" covered 7,526 rows, so a ten-question draw showed one prompt twice
  7.4% of the time — which reads as a bug, not as two questions. Spreading each
  comparison class over more true phrasings (assigned by a stable hash of the row
  id, so every platform agrees) took it to 4.5%. `PROMPT-REPETITION` caps any one
  prompt at 1% of the corpus.

## Read the reveal as typesetting, not just as content (added 2026-08-02)

Scanning all 110,140 reveals for things wrong as TYPOGRAPHY found what reading
220 prompts had not:

    Arkansas ( , AR-kən-saw) is a landlocked state...
    Delaware (  DEL-ə-wair) is a state in the Mid-Atlantic...
    Ottawa (; Canadian French: [ɔtawɑ]) is the capital...

An IPA transcription was stripped out of the Wikipedia lead and left its
delimiters behind. None of it changes a fact; it is the difference between a
payoff that looks written and one that looks scraped. `REVEAL-TYPOGRAPHY`.

Also: 30 prompts opened lowercase ("plutonium is denoted by which symbol?") —
a template dropped an element name, lowercase by convention, into the first slot.
`LOWERCASE-PROMPT`, with an allowance for iPhone/eBay/macOS.

**Two traps this pass, both mine:**
- The shape-source sweep would have appended a full stop to OPTION text —
  "Yesterday (song)." on an answer card — because it treated every long cell as
  prose. 24,269 "fixes" became 88 once it stopped adding stops to option cells.
  A cleanup script must know which cells the player reads as sentences.
- The cleanup was not idempotent: collapsing "(; " exposes a
  space-before-punctuation the earlier rule already passed, so one run left 8
  rows dirty and the gate caught them. It now iterates to a fixed point. This is
  the second non-idempotent repair this session; the first shipped "based based
  based based" to 1,022 questions.

## A classifier that agrees with itself is not the same as one that is right

"This form of cancer... what is it?" rendered against Tsetse fly, Vocal cords and
Hypertrophy. KIND-MISMATCH read 0 — because "Tsetse fly: Genus of
DISEASE-spreading insects" matched the disease pattern, so the fly and the cancer
agreed and the rule stayed silent on a free question. Two substring traps in one
description:

- **`\bdisease\b` matched "disease-spreading".** A hyphen compound is a
  modifier, not the type. Now excluded.
- **`\binsect\b` never matched "insects".** The animal and plant vocabularies had
  no plurals at all.

Fixing both exposed 338 mismatches that had been hidden, and widening `chemical`
(alkaloid, drug, medication, acid...) and moving it AHEAD of plant and animal
exposed 96 more: "Theobromine: Bitter alkaloid of the cacao PLANT" and
"Theophylline: Drug used to treat respiratory DISEASES" were both typed by what
they come from or treat rather than by what they are. 434 repaired, validated
against 13 subjects labelled by hand.

**A gate rule reading zero is evidence only if the classifier under it is sound.**
Check the rule against a case you can see before believing its silence.

## Test the rules, not just the data (added 2026-08-02)

`tools/corpus/test_quality_gate.py` plants one known-bad row per rule into a copy
of the real corpus, runs the real gate against it, and asserts the rule reports a
hit. It exists because KIND-MISMATCH read 0 for a whole session while looking at
a free question — the rule was not disabled and its budget was not raised, it
simply could not see. **A rule that has never been shown to FIRE is a rule nobody
has tested.**

Three things it found in its first run:

- Two rules reported BLIND and both times the TEST was wrong, not the rule.
  `MACHINE` looks for a Wikidata property with its colon ("P31:"), and
  `PLACEHOLDER` looks for format specifiers, not the word TODO. Check the
  harness against the rule before believing it.
- "TODO" in a shipped prompt genuinely IS a defect the rule did not cover, so the
  pattern was widened — the test was wrong about the rule and the rule was wrong
  about the world.
- Widening it to `\bXXX\b` then flagged 15 legitimate questions, because xXx is a
  Vin Diesel film franchise. An editing marker that is also a real title is not a
  signal. The gate failed loudly instead of me quietly "fixing" 15 good rows.

16 rules need input this harness does not plant (shape-source rows, corpus-wide
rates). They are listed by name in COVERED_ELSEWHERE with what they would need,
so the coverage gap is visible rather than implied.
