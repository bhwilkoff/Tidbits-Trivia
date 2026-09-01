# The Premier Push — the two scopes that gate promotion

Owner directive, **2026-09-01**: *"There are two major scopes of work that need
to be worked on extensively before I start promoting Tidbits Trivia as the
premier Trivia app across all of the platforms that we cover."*

This is the live tracker for both. It is append-and-amend: a line moves to DONE
only with **observed evidence** (a screenshot read, a harness RESULT, a query
count), never "it compiles."

---

## Scope 1 — the whole corpus, audited for INTEREST and COMPREHENSIBILITY

The bar is not "factually correct" (the corpus already passes that). It is:

- **Interest** — would the *majority* of players recognise BOTH the subject of
  the question and the answer? A question whose subject is a person, work, or
  place almost nobody has heard of is a dead question in a pub room, even when
  it is impeccably sourced.
- **Comprehensibility** — is the question understandable and unambiguous on ONE
  reading, with no missing context? Specifically: no "founded" applied to
  things that were not founded; nothing that needs an off-screen fact to parse;
  no answer that could equally be two of the options.
- **No repellents** — no overtly controversial framing that makes a player put
  the phone down.

### Evidence of the problem (2026-09-01)
The Mac cockpit's very first question on a cold host run was *"In what year was
Marta Fascina born?"* — sourced, correct, and worthless in a bar. That is the
class this scope exists to remove.

### Passes
| # | Pass | Status | Evidence |
|---|---|---|---|
| 0 | **CLUE-CROSSED (wide)** — one prose clue pasted onto two different subjects | ✅ | `audit_clue_crossed.py`: 248 prompts on >1 subject, 247 losers decided by lead-overlap, 12 lowest-margin read by hand and all correct |
| 1 | Notability floor — score every subject by recognisability; quarantine the tail | 🔬 | qrank measured: median subject qrank is 1.01M and **half the corpus is less famous than Marta Fascina**. Floor must be per-template, not global — see below |
| 2 | Birth/death-year questions about non-household names | ⏳ | 6,545 `In what year was X born?` rows exist; interest depends entirely on the subject |
| 3 | Missing-context detector (the prompt does not stand alone) | 🟡 | `bare-description` shipped (132 rows); the wider class is still open |
| 4 | Ambiguous-distractor detector (two options equally defensible) | ⏳ | |
| 5 | Controversy/repellent screen | ✅ | `repellent` check: 87 rows, **all 94 candidates read in full** before writing |
| 6 | Read a stratified sample by hand after EVERY bulk pass | ✅ | done for every pass below |

### Shipped 2026-09-01 — 469 rows removed (110,496 → 110,027)

New tools, both report-first and tombstone-only:
`tools/corpus/audit_clue_crossed.py`, `tools/corpus/audit_playability.py`
(checks: `bare-description`, `repellent`, `ambiguous-subject`,
`self-answering`), and `tools/corpus/apply_tombstones.py` which makes
"tombstone written" and "row actually gone from `assets/corpus.json`" a single
idempotent act instead of two that could drift.

| Class | Rows | What it was |
|---|---|---|
| CLUE-CROSSED | 247 | The God-of-War clue answered "House of Bonaparte". 248 prose clues had been pasted onto a second, unrelated article. |
| CORPUS-BARE-DESC | 124 | "Who is this — 'British actor (born 1977)'?" — a raw Wikidata description as the entire clue. Unanswerable by construction, and the same generator produced the corpus's most repellent prompts. |
| CORPUS-REPELLENT | 87 | Anatomy-as-quiz, the porn industry, named private individuals' killings, a suicide, and mass-casualty atrocities used as pub trivia. |
| CORPUS-SELF-ANSWERING | 9 | "Icelandair is headquartered in which country?" |
| CORPUS-AMBIGUOUS | 2 | "In what year did David die?" — which David? |

**Two detector mistakes caught by reading, not by the count.** The first
`repellent` pass matched prompt+explanation+options and returned **869 rows that
were the corpus's best questions** — *Who wrote The Murder of Roger Ackroyd?*,
the platypus cloaca question, and an **ankle** question flagged as genitalia.
Narrowing it to the question's SUBJECT, plus a creative-work exclusion read off
the article's own description, took it to 87. The first `self-answering` pass
used substring matching and called an umbrella-term question broken because
"arthritis" is inside "osteoarthritis". Both are `detector-that-fires-on-quality`
verbatim.

**Judgment calls the owner can reverse.** Three atrocity subjects were kept as
standard, undisputed quiz fare — Boston Massacre, St. Bartholomew's Day
massacre, Saint Valentine's Day Massacre — in `REPELLENT_KEEP`. Everything else
in that class went, including subjects that are live geopolitical flashpoints
(Bucha, Nova festival, Deir Yassin, Sabra and Shatila, Tiananmen, Nanjing) and
ones that are historically distant but still mass-casualty (Jallianwala Bagh,
Wounded Knee, Oradour-sur-Glane).

### The notability finding (pass 1, not yet acted on)

`subject.qrank` (Wikidata pageview rank) is a real signal — Taylor Swift 40.0M,
Einstein 21.8M, Shakespeare 10.1M, Pluto 4.5M — but the corpus median is
**1.01M**, and Marta Fascina sits at 1.66M, i.e. **above the corpus median**.
A single global floor is therefore the wrong instrument. Reading stratified
samples shows the failure is a **template × notability interaction**:

- `fact` ("In what year was X born?") and `num` ("Roughly how large is X by
  area?") are dead below household level — the subject is the only interest.
- `src` prose clues survive far lower, because the clue itself teaches something
  ("Fronted by Tyler Joseph and drummer Josh Dun, this Columbus, Ohio duo…").
- `chron` / `sup` / `class` / `rev` compare four options, so the floor has to
  apply to **every option**, not the subject.

Next pass builds per-template floors and calibrates each one by reading the
boundary, never by picking a percentile.

**Standing rule, from prior burns** (`detector-that-fires-on-quality`,
`randomness-inside-selection`): a detector that flags thousands of rows is
measuring quality, not defects. **Read the hits before any bulk UPDATE**, and
tombstone rather than delete.

---

## Scope 2 — Tidbits Live, actually usable for a real pub night (macOS + Windows)

Owner directive: broken audio/video rounds, malformed or dead buttons, no way to
edit or add an individual question, "most of the more intricate features are
just stubs", and controls that "look foreign" on both platforms.

The competitive checklist is already researched — `docs/EVENT-TRIVIA-COMPETITIVE.md`
(Crowdpurr, Quizado, SpeedQuizzing, Buzztime, TriviaMaker, Rapid Trivia + the
landscape survey). **The gap is implementation and verification, not research.**

### Observed on the glass, 2026-09-01 (`tools/mac_run.py --only live,livehost`)
1. **No per-question editor anywhere** — a round is generated wholesale and is
   then opaque. Violates the doc's own §A2.2. → new §A2.4.
2. **Sticker-book buttons on a work surface** — `Lock answers / Skip / Reveal
   answer / Correct / Wrong / Tick / Time! / Fanfare` are heavy-bordered pills.
   Foreign on a Mac. → new §5.6 (R-MAC-CTL-1).
3. **The event-name field is invisible** — a `.plain` `TextField` that reads as
   a heading; nothing says it is editable.
4. **Placeholder text clips** — the mailing-list and sponsor fields truncate
   mid-word at their fixed 340pt width.
5. **The Events list has no empty state** — a blank column
   (`universal-feature-states`).
6. **The cockpit never shows the room/join code** — `livehost.expect_any`
   failed on `QATEST`; a host cannot read out a code that is not on screen.
7. **Cockpit layout dead space** — a tall gap between the answer tally and a
   three-row pile of controls jammed bottom-left.
8. **No event export/import** — a host's night cannot leave the machine. → new
   §A2.5 / WINDOWS §6.7.

### Workstream
| # | Item | macOS | Windows | Evidence |
|---|---|---|---|---|
| L1 | Per-question editor + add/duplicate/delete/reorder (§A2.4 / §6.6) | ✅ | ⏳ | Mac: `MacLiveQuestionEditor_macOS.swift`; screenshot shows the expanded round with per-question Edit + ⋯ menu |
| L2 | Native control pass on builder + cockpit (§5.6 / §5.4) | 🟡 | ⏳ | Mac builder header + action bar done; the COCKPIT is still sticker-styled |
| L3 | Room/join code + QR visible in the cockpit | ⏳ | ⏳ | |
| L4 | Audio round: pick clip → plays on the PA, verified audible | ⏳ | ⏳ | |
| L5 | Video round: clip plays on the big screen, verified rendered | ⏳ | ⏳ | |
| L6 | Event export/import as JSON; CSV question-bank import (§A2.5 / §6.7) | 🟡 | ⏳ | Mac: `MacLiveEventFile_macOS.swift` (versioned, AV bookmarks dropped + counted); not yet driven end-to-end |
| L7 | Printing: question pack + answer sheet + scoresheet, verified as PDF | ⏳ | ⏳ | |
| L8 | Empty/loading/error states on every Live surface | 🟡 | ⏳ | Mac: saved-events empty state + expanded-round empty state; import/export now raise a real alert instead of a silent `try?` |
| L9 | Every button in builder + cockpit driven and asserted by the harness | ⏳ | ⏳ | |
| L10 | Cockpit layout: no dead space, controls wrap, reachable at min window | ⏳ | ⏳ | |

### Rules added this scope
- `docs/macOS-DESIGN.md` **§A2.4** (question editor), **§A2.5** (event file
  round-trip), **§5.6 / R-MAC-CTL-1** (native controls on work surfaces),
  anti-patterns 7.10–7.11.
- `docs/WINDOWS-DESIGN.md` **§6.6**, **§6.7**, anti-pattern 7.15.


---

## Side-effects fixed in passing

**`tools/corpus/resync_corpus.sh` re-created the strays its own check reports.**
Step 2 copied `assets/corpus.json` (51MB) into BOTH app bundles plus
`enrich.json` into Android — files no client reads; a previous session had
deliberately deleted them (Android 125MB → 67MB). Step 5 then flagged them as
STRAY on every single run. The copies are gone and the step now removes any a
previous run left behind.

**`tombstones.json` is keyed by SHAPE, not flat.** The first write from the new
audit tools flattened 469 ids to the top level, which would have corrupted every
shape's `genguard`. Caught before commit; both tools now write under `"corpus"`
and say why in a comment.
