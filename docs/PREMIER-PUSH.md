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
| 1 | Notability floor — score every subject by recognisability; quarantine the tail | ✅ | Shape-aware, not global: 9,290 rows. Every floor read at its boundary; the released/founded floor was **abandoned** because the read disproved it |
| 2 | Birth/death-year questions about non-household names | ✅ | 6,499 removed below a 3M qrank floor read at the boundary (below: Bruno Fernandes, Alba Baptista; above: Ben Stiller, Ethan Hawke) |
| 3 | Missing-context detector (the prompt does not stand alone) | ✅ | `bare-description` (132) + `fictional-chronology` (554) + `list-article-option` (33). Two crude versions were discarded first — see below |
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
| L1 | Per-question editor + add/duplicate/delete/reorder (§A2.4 / §6.6) | ✅ | ✅ | Mac: `MacLiveQuestionEditor_macOS.swift`, screenshot read. Windows: `LiveQuestionEditorDialog.cs` + the model change that made it possible; headless PNG read + 3 structural assertions |
| L2 | Native control pass on builder + cockpit (§5.6 / §5.4) | ✅ | 🟡 | Mac: all 20 cockpit buttons + the builder header are native. Windows: the Live button row now WRAPS (§6.3b, it did not) and uses the type ramp instead of hardcoded sizes; the cockpit is not yet audited |
| L3 | Room/join code + QR visible in the cockpit | ⏳ | ⏳ | |
| L4 | Audio round: pick clip → plays on the PA, verified audible | 🟡 | 🚫 | Mac: three real defects fixed + 6 tests. The panel-GRANT leg is not automatable — see below. Windows has no AV rounds at all. |
| L5 | Video round: clip plays on the big screen, verified rendered | 🟡 | 🚫 | Same fixes as L4 (shared clip layer); big-screen render still unobserved |
| L6 | Event export/import as JSON; CSV question-bank import (§A2.5 / §6.7) | ✅ | ✅ | ONE contract (`docs/LIVE-EVENT-FILE.md`), one golden file, **14 tests across both stacks** — 7 Swift + 7 C# against the same bytes. CSV import is Mac-only still. |
| L7 | Printing: question pack + answer sheet + scoresheet, verified as PDF | ✅ | ⏳ | Paginated to US Letter; **5 tests, A/B-proven to fail on the old code** (one page 2,621pt tall) |
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


---

## Tick 2 — 2026-09-01

**The Windows finding that explains the owner's complaint.** Windows stored a
round as `NightRound {kind, count}` and pulled its questions from the corpus at
host time. There were **no questions in the model to open** — which is why "there
is no ability to edit or add individual questions" was literally true there, and
why a question editor alone would not have fixed it. `LiveEvent.RoundQuestions`
(index-aligned, empty = still corpus-sourced, so every saved event decodes
unchanged) is the change that made an editor possible at all.

**The wiring is tested, not assumed.** `LiveNightHost.BuildNightQuestions` asks
the provider only for the rounds the host did NOT author, so a fully-authored
event never touches the corpus (and works offline); the corpus rows are re-tagged
against their REAL plan position, not the compacted index of the reduced plan.
Without that, the editor would have been theatre: edit a question, press Host,
and the night pulls a fresh corpus round over your work. Five tests assert it,
including the half-authored case.

**Preview and Host share one implementation** (`LiveNightHost.PreviewQuestions`),
so a preview can never vet a different night than the room plays.

**`docs/LIVE-EVENT-FILE.md` is new and binding.** Neither client exports its
internal model; both write the contract. `tools/live-event/golden.tidbitsevent.json`
is asserted by Swift AND C# — decode, round-trip, new-id-on-import, foreign-file
refusal, forward-version refusal, unknown-key tolerance, and clip-dropping.

**Also fixed:** `tools/create/golden/search.txt` was stale after tick 1's row
removals (the `GOLDEN-STALE` gate caught it); regenerated, 49 identical / 0
differing. Three concurrent `parity.sh` runs were fighting over one simulator —
the "boot ONE simulator at a time" rule applies to scripts that boot one too.

**Open on Windows:** the cockpit itself is not yet audited for §5.6-equivalent
polish, audio/video rounds do not exist there at all, and the ▲/▼/✕/📝 glyphs
render as tofu on the Mac head — which is NOT evidence about Windows and needs
`windows-repl.yml` to settle.


---

## Tick 3 — 2026-09-01

**Scope 1: 9,684 more rows out (109,633 → 100,343).**

| Class | Rows | Why |
|---|---|---|
| CORPUS-FOUNDED-MISUSE | 394 | The owner's own example. "In what year was New Zealand founded? → 1986" (that is the Constitution Act), "Japan → 660 BC", "Micronesia → 1947". A modern state has no single founding date a player can reason to. |
| CORPUS-LOW-INTEREST | 9,290 | 6,499 birth/death years below a 3M recognition floor, 1,450 areas below 5M, 901 person heights, 440 mean elevations. |

**Three times this tick a detector was wrong first, and reading caught it.**

1. `founded-misuse` v1 matched the WORD and returned 1,619 rows that were mostly
   fine — "This businessman co-founded a ride-hailing company" is a good Travis
   Kalanick question. The signal is **passive voice**: the subject has to be the
   thing being founded.
2. Narrowing still swept in dynasties and empires, which ARE founded — "Ming
   dynasty → 1368", "Umayyad Caliphate → 661". Dropping the `historical country`
   and `realm` classes took 587 → 394, and what is left is only modern states.
3. The **released/founded notability floor was abandoned entirely.** Reading the
   boundary showed it would cut *Before Sunrise*, *Point Break*, *Kung Fu Hustle*
   and "In what year was the YMCA founded?" while keeping *Terrifier 2*. qrank
   does not measure quality for that shape, and applying it would have destroyed
   ~970 good questions. **Height questions are dead even for Messi and Michael
   Jordan** — that one is a shape problem, not a fame problem, so all 901 go.

Losses are spread evenly (science 3.2% … sports 14.1%); no category is gutted.

**THE BUG UNDER THE BUG: every corpus repair ever shipped was invisible to
returning web players.** `fix_kind_distractors.py --apply` wrote new questions
under the OLD `version` string — and so did **29 of the repair tools**. The web
client busts its IndexedDB cache on that string and nothing else. Git proves it
shipped: `944cbad1` → `c8d110b7` → `38c80ba7` shipped **110,618 → 110,541 →
110,512 questions all under version `f3c1477ed04a`**. Every one of those repairs
reached a fresh install and no one else.

Fixed in all 29 tools (each now recomputes the hash), corpus.json re-stamped, and
`resync_corpus.sh` grew a **step 2b that fails** when the version does not match
the content — so it cannot regress silently a fourth time.

**Windows CI confirmed the render.** `windows-repl.yml` run 33547172791: the
expanded round, both prompts, "Answer: Lydia", and per-question Edit/Duplicate/✕
all render correctly on `windows-latest`. The ▲▼✕📝 tofu seen on the Mac head was
a font artifact and nothing more — which is exactly why the Mac head is never the
gate.


---

## Tick 4 — 2026-09-01

### Printing was broken in a way no one would notice until it mattered

`LivePrint.makePDF` called `beginPDFPage` **once**, with a media box the size of
the whole rendered content. A 40-question pack came out as a **single page
2,621pt tall** — Preview shows an endless strip, and printing it scales the whole
night onto one sheet. The Wi-Fi-dies fallback could not be printed.

Now paginated to real US Letter (612×792), the file is named for the document
(it was `tidbits-live-a1b2c3d4.pdf`), and a render failure raises an alert
instead of the old `guard let url else { return }`.

**Five tests, and I A/B-proved they fail on the pre-fix code** — reverted
`makePDF`, ran them, got `pageCount → 1` and `page 1 is 2621.0pt tall`, restored
the fix. A test that has never been seen to fail is not evidence.

### The audio/video root cause — and a hypothesis I had to throw away

Three real defects fixed:

1. **The Mac entitlements had no `files.bookmarks.app-scope`.**
   `user-selected.read-write` alone grants access for the CURRENT launch only, so
   a saved event's clips could never survive a reopen.
2. **`(try? url.bookmarkData(options: .withSecurityScope)) ?? Data()`** at both
   call sites turned every failure into an EMPTY bookmark. The round looked
   complete and played silence, with no error anywhere. Now `LiveClip.bookmark`
   proves a bookmark by resolving it before returning, and the builder reports
   what failed.
3. **The cockpit offered "Play this clip" for a dead bookmark.** It now shows
   "Clip unavailable — re-attach it in the builder".

**I was confidently wrong about #1 being *the* cause, and the A/B caught it.**
My first self-test wrote its probe file into the app's own temp directory — which
the sandbox already grants — so it reported OK **with and without** the
entitlement and proved nothing. That is `gate-blind-in-ci` in my own work, on the
same day I wrote a gate for it. Rewritten to take an external path, it now fails
loudly for a non-granted file, which is correct sandbox behaviour.

**What is still NOT proven:** the full host path (NSOpenPanel *grant* → bookmark
→ playback). A sandboxed panel could not be driven by System Events across five
attempts, so I stopped rather than rabbit-hole. What IS proven: 6 tests covering
bookmark round-trip, real WAV decode, and that empty / garbage / vanished
bookmarks all report unplayable. The remaining leg is Apple-standard behaviour
plus a now-correct entitlement — but it is untested, and it should be driven by
hand before this row goes green.

`LiveTeam` moved out of the 1,250-line cockpit view into the model file, so the
results sheet is testable without pulling a whole view into the test target.


---

## Tick 8 — 2026-09-01

**587 more rows out (100,343 → 99,756).**

| Class | Rows | Why |
|---|---|---|
| CORPUS-FICTIONAL-CHRONOLOGY | 554 | *"Which of these people was born first? — Scrooge McDuck / Punisher / Cedric Diggory / Voldemort"*. A character has a creation date, not a birth date; whatever Wikidata holds is in-universe canon nobody can reason from. The earlier pass fixed single-subject wording (characters "created", bands "formed") but never looked at the COMPARISON template, where the chronology **is** the question. |
| CORPUS-LIST-ARTICLE | 33 | *"Which one below is the oldest? — War and Peace / Rocky / James Bond films / **List of Marvel Cinematic Universe films**"*. A list article is a page, not a thing with an age. |

**Two crude detectors discarded before either was written.** I started from
"comparison options are different KINDS of thing" and matched regexes over the
articles' prose descriptions: 949 hits at roughly 30% precision — Goldman Sachs
vs JPMorgan flagged as mixed, "Ku Klux Klan" typed as a *band*. Switching to
structured Wikidata `p31` cut it to 558 at ~50%, still not good enough, because
unlabelled QIDs made four animated films look like four different kinds.

The reframe is the whole finding: the defect was never "mixed kinds", it was
**birth/founding language applied to fiction**, which the kind-mismatch framing
was only catching incidentally. Narrowed to that, precision is effectively 100%
and every sampled row is 4-of-4 fictional. That is three sessions running where
the first detector was measuring quality rather than defects
(`detector-that-fires-on-quality`), and the third where reading — not the count —
was what caught it.

**Windows verified on `windows-latest`** (run 33558017525): the builder render
shows "Audio round… / Video round…" and the round bar **wrapped to a second
line**, which is §6.3b working rather than being asserted.
