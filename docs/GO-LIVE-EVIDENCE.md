# Go-live evidence — the eight-surface test suite

What exists to answer "are we ready to promote this everywhere?" with evidence
rather than confidence. Every claim below is backed by an artifact under
`build/qa/` that can be re-read, and every check is re-runnable.

The suite covers **eight surfaces**: macOS, web, Apple TV, iPad Pro 12.9,
iPhone 12, Pixel 8a, Fire TV, and the Google TV dongle.

---

## 1. The rule the whole suite is built on

**The app's own claim is never evidence for what a viewer sees; the screen is.**
And its corollary, which costs more to learn: **an instrument must say when it is
blind.** A readable frame of the WRONG screen survives every other check and then
answers questions about a screen nobody tested.

Three failures in this repo came from ignoring that, and each one is now a
permanent guard:

| What went wrong | The guard that now exists |
|---|---|
| A TV walk reported 26/26 while every capture was the Home screen | every capture polls for that screen's **own** text signature |
| Six store screenshots were all Home and passed every per-file check | the set is compared **against itself** for duplicates |
| A rule read 0 for a whole session because its column index was wrong | a rule must be **shown to fire** before it is trusted |

That last one recurred in this very session: the new `CLUE-CROSSED` rule read
`q[10]` for a source title that lives at `q[7]`, reported a clean **0**, and was
completely inert. A rule that cannot fire is not an assertion.

---

## 2. What each harness does

| Tool | Surface | What it proves |
|---|---|---|
| `tools/mac_run.py` | macOS | six sections render, no error text, nothing clipped |
| `tools/web_run.py` | web | 14 routes at **375px and 1440px**, plus a distinct-screen check |
| `tools/atv_run.py` | Apple TV | scenario sweeps with verified wake + wrong-screen guard |
| `tools/ios_run.py` | iPad / iPhone | six scenarios each, calibrated per device |
| `tools/adb_run.py` | Pixel / Fire TV / Android TV | same scenarios over adb |
| `tools/tv_focus_audit.py` | Fire TV / Android TV | 26 surfaces reachable **by remote** |
| `tools/multiplayer_run.py` | all at once | one hosted room across every device |
| `tools/qa_suite.py` | the fleet | one matrix; unreachable devices SKIP, never pass |
| `tools/question_sample.py` | corpus | stratified, seeded sample for **reading** |
| `tools/corpus/quality_gate.py` | corpus | 32 construction rules over the whole corpus |

Three harness details are load-bearing and easy to get wrong again:

- **An OCR failure is not a dark screen.** `ocr()` used to swallow a failed OCR
  process and return an empty dict, which every frame then graded as
  "0 OCR lines — SCREEN OFF/LOCKED". On a loaded machine a five-device
  multiplayer run reported all five devices asleep while their screenshots sat on
  disk, perfectly readable a minute later. The instrument now reports itself
  (`ocr_available`) before any claim is made about a device — and says how to
  rebuild the binary, which lives in `/tmp` and does not survive a reboot.

- **The Mac capture must raise the app first.** `screencapture -R` grabs *screen*
  pixels, not window pixels. Without an `activate`, a terminal in front is
  captured and its text is graded as the app's — which happened, and put the
  harness's own source code into an OCR transcript.
- **The Apple TV must be woken over Companion before launching.** `devicectl` has
  no wake verb; a launch into a sleeping TV is refused or comes up backgrounded.
  The first multiplayer run reported "the host never opened the room" because the
  host was never running.

---

## 3. Cross-platform multiplayer — the headline result

`multiplayer_run.py` grades **two independent sources of truth**, because either
one alone can lie:

- **the wire** — `live/{code}` read straight from RTDB. Says who actually joined
  and what the host actually published. Independent of any UI.
- **the glass** — a screenshot of every device. Says what a human in the room
  would see. The wire being right proves nothing about that.

### Apple TV hosts Trivia Night → 4 devices join

`build/qa/multiplayer-2026-08-30/atv-QANITE-1788098442/`

The TV showed `SCAN TO JOIN QANITE` and then
`ROUND 1/3 • GENERAL KNOWLEDGE - Q1/5`. iPad, iPhone, Pixel 8a and Fire TV each
showed **the same question at the same moment**, verified word-for-word against
the prompt the host published to the wire:

> "This Slovenian-American character actor won a Primetime Emmy for playing Ray
> Fiske on Damages…"

4/4 devices matched 4/4 keywords. Four platforms — tvOS, iPadOS, iOS, Android
phone, Android TV — in one TV-hosted game.

### Mac hosts Tidbits Live → 4 devices join

`build/qa/multiplayer-2026-08-30/mac-QALIVE-1788098720/` — **RESULT: OK**

The Mac hosted "FRIDAY PUB QUIZ", listed all four players on its own scoreboard,
and published a question. iPad, iPhone, Pixel and the Google TV dongle all showed
`Which of these four is the eldest?` with the same four options. 4/4 in sync.

### Final confirmation on the shipped state

`build/qa/multiplayer-2026-08-30/mac-QAFINAL-1788103118/` — **RESULT: OK**

Re-run after every corpus change in this pass. The Mac hosted, its scoreboard
listed all four players, and iPad, iPhone, Pixel 8a and Fire TV each matched
**4/4 prompt keywords and 4/4 answer options** of:

> "A War Democrat who ran on Lincoln's National Union ticket, he took the
> presidency after the assassination…"

### The gap this closed

Android had **no join-by-code hook**, so the only way to put an Android device in
a host's room was blind tapping — meaning cross-platform multiplayer was the one
feature no harness could exercise. `--es tidbits_live_join CODE` now mirrors
Apple's `TIDBITS_LIVE_JOIN`, and it is what made the two runs above possible.

### Two assertions that were wrong, and why it matters

Both of these *passed or failed for the wrong reason* before being fixed, which
is exactly as dangerous as a broken feature:

- **Joins were attributed by name.** The iOS hook hardcodes the team name
  ("iOS Tester"), so the iPad and iPhone arrive under the *same* name and a
  name-keyed set collapses them. The harness reported the iPad missing while its
  own screenshot showed it in the room. Joins are now **counted**, and per-device
  attribution comes from the glass, which cannot collide.
- **The sync check read only the prompt.** Ten-foot type OCRs badly: the Fire TV
  rendered the prompt as "Craganmed doappreoen ghose pesponsibe" while its answer
  options read cleanly, and the check called that a desync. The options are the
  published question just as much as the prompt is, so either now proves it.
- **The join delta was meaningless when the roster clear failed.** RTDB rules do
  not let an anonymous client delete another player's row, so the clear 401s and
  the previous run's players are still listed — every joiner rejoins its existing
  row and the delta is 0. It reported "0 new of 4" for a room whose own roster
  listed all four. A delta is only asserted when the clear actually happened.
- **The web "joined" while sitting on the join form.** `#/live/CODE` prefills the
  code and asks for a team name — correct behaviour — but the loose in-room
  pattern matched the form. Only post-join chrome (`YOU'RE IN`, `POINTS`,
  `Waiting for the host`) counts now.

---

## 4. Question quality

### Construction: the gate is green

`tools/corpus/quality_gate.py` runs **32 rules over all 110,496 shipped
questions** — not a gameplay sample — and passes. Read-off answers, duplicate
options, fame tells, era spreads, machine stems, broken shapes, prompt
repetition, category skew: all zero.

### Sense: the gate cannot check it, so we read

A construction gate cannot tell whether a question is *true*, or whether its clue
identifies its answer. That is a semantic judgement and the only honest way to
make it is to read questions. `tools/question_sample.py` draws a stratified,
seeded sample for exactly that.

**A 40-question sample found a real shipping defect on the first read.** This one:

> "This actress rose to fame in the late 1970s playing a spoiled rich kid on the
> sitcom *Diff'rent Strokes*. Who is she?" → correct answer: **"Servant"** (a TV
> series).

The clue and the answer came from different articles. Every existing rule passed
it, because the question is *individually well-formed* — it is only wrong when
you read the clue against the answer. Sixteen rows shared the shape, including a
Grand Admiral Thrawn clue answered by "The Quarry", a video game.

All 16 are removed, tombstoned so no generator revives them, and the class is now
`CLUE-CROSSED` in the gate at budget 0.

A second sample (seed 42) found a second class: the chronology reveal said
**"Superman (founded 1938)"**, "Sherlock Holmes (founded 1887)",
"Buzz Lightyear (founded 1995)", "Led Zeppelin (founded 1968)". One template
applied one verb to every kind of subject. A character is *created*, a band is
*formed*; only an organisation is *founded*. 20 characters and 95 bands repaired,
`FOUNDED-PERSON` added to the gate.

### Two measurements worth not repeating

Both of these looked like large findings and were not, which is the more
expensive mistake than missing something:

- A "prompt shares no words with its own answer" detector flagged **1,068 rows**
  — and they were the *best* questions in the corpus, because a good clue
  deliberately never contains its answer. A signal that fires on quality is not
  a defect signal.
- The first `founded` repair matched `\bgroup\b` and `\bband\b` and rewrote
  **273** rows, turning the correct "Goldman Sachs (founded 1869)" into "formed".
  Companies really are founded. The repair now reads the subject's own
  description rather than its name, and the gate rule was tested against
  Goldman Sachs and the Franciscans to prove it does **not** fire on them.

---

## 5. Defects found and fixed in this pass

| # | Surface | Defect | Status |
|---|---|---|---|
| 1 | web | `#/dailyboard` was **unreachable** — `#/daily`'s prefix match swallowed it, so every Daily-board link started the Daily game instead | fixed; all route pairs audited for prefix collisions |
| 2 | corpus | 16 questions pairing a person clue with a work answer — unanswerable | removed + tombstoned + `CLUE-CROSSED` gate rule |
| 3 | Android | `sync_shared_assets.sh` would copy the repo's **0-byte** `corpus.sqlite` over Android's real 52MB one via `rsync --delete` | excluded + a guard that refuses an empty source over a non-empty target |
| 4 | Android | `corpus.json` (54.9MB) and `enrich.json` (2.9MB) shipped in every install while **no Kotlin source opens them** | removed; assets 125MB → 67MB |
| 5 | corpus | `export_json.py` wrote **9 fields for a 10-field row**, blanking the tags on all 110,496 rows — and the Create ranker scores a tag match at 3, above title (2) and prompt (1), so web and Windows were ranking with no tag signal | export resolves tags through `tag_names`; `TAGS-STRIPPED` gate rule |
| 6 | Apple | `corpus.json` (54.9MB) shipped in the iOS/tvOS/macOS bundle while only `corpus.sqlite` is read | removed; iOS bundle measured at 87MB |
| 7 | harness | the Mac capture graded a terminal window as the app | raise the app before capturing |
| 8 | harness | the multiplayer host was never woken, and joins were attributed by a name the hook hardcodes | wake step + counted joins |
| 9 | harness | the Pixel's reachability probe returned **False while its own evidence said "adb ok"**, so the device was silently skipped | one verdict, one evidence string, full serial matched per line |

### The tags bug is the one worth reading twice

It is the clearest example of why this suite exists. The row still *parsed*, so
`ROW-SCHEMA`, `check_mirrors`, all 30 gate rules and both mirror counts passed.
The only thing in the repo that noticed was Android's `CreateGoldenTest`, and
only because removing 16 questions moved the ranking boundary enough to expose
it. For "Michael Jackson", Apple sees the tag *"Albums produced by Michael
Jackson"* and returns **Off the Wall** at score 10; a tagless web ties Beat It
and Off the Wall at 4 and takes **Beat It** on the id tiebreak. Seven of fifty
golden topics diverged.

It was also diagnosed wrong twice before being measured — a stale golden
(regenerating produced a byte-identical file) and the documented unstable-sort
tie-break (all three languages already sort score-then-id). The third guess,
Apple's `LIMIT 25000` candidate cap, died on measurement: the diverging topics
match 136–6,772 rows. **A row that parses is not a row that fits.**

---

## 6. Open, and honest about it

- **macOS keychain prompt.** The shipped Mac app raised *"Tidbits wants to use
  your confidential information stored in `tidbits.fb.anonRefresh`… enter the
  'login' keychain password"* over the Home screen, and in one run it blocked the
  app from opening its Live room at all. Root cause is the **legacy file-based
  login keychain**, whose per-item ACL is signature-bound. `Keychain.swift` now
  sets `kSecUseDataProtectionKeychain` on macOS, which is Apple's documented
  guidance and removes the ACL mechanism entirely.

  **This fix is not verified to remove the prompt.** The dialog is a *one-time*
  decision per signing identity, not per launch — once answered it does not
  recur — so it could not be A/B tested on this machine after the first answer.
  Worse, the dialog is presented by `SecurityAgent` and **survives killing the
  app**, so three "the prompt is still there" observations were the same orphaned
  window being re-photographed. Treat the change as hardening, and confirm on a
  machine that has never run this app.

- **Billing 8 purchase path** is still unproven end-to-end: the debug package
  cannot transact, so one real purchase on a Play-signed build is outstanding.

- **Fire TV** ships through the Amazon Appstore, a separate submission that has
  not been made.

- **Version skew**: iOS marketing version trails Android.

---

## 7. The fleet run

`build/qa/suite-2026-08-30/` — every reachable device, smoke set:

| Device | Result |
|---|---|
| Apple TV 4K | 5 pass, 0 fail |
| iPad Pro 12.9 | 6 pass, 0 fail |
| iPhone 12 | 6 pass, 0 fail |
| Fire TV | 5 pass, 0 fail |
| Google TV dongle | 5 pass, 0 fail |
| macOS | 4 pass, 0 fail |
| Pixel 8a | 6 pass, 0 fail |
| Web | 6 pass, 0 fail (`#/dailyboard` fix verified live in production) |

The Pixel 8a shows the value of the SKIP discipline and its limit. On the first
fleet run it was reported SKIP with the evidence string **"adb ok"** — a probe
that returned False while saying the device was fine, because it matched a
serial *fragment* that the real serial continues past. A SKIP is quiet by
design, so an untested device slipped through a run that otherwise looked
complete. The probe now returns one verdict and one evidence string that cannot
disagree, and the Pixel's own 6/6 above is from the re-run.

**Total: 43 scenarios across eight surfaces, 0 failures**, plus two cross-platform multiplayer
runs and a corpus gate of 32 rules over 110,496 questions.

---

## 8. Re-running it

```bash
python3 tools/qa_suite.py                       # every reachable device, smoke set
python3 tools/qa_suite.py --devices mac,web
python3 tools/multiplayer_run.py --host mac --players ipad,iphone,pixel,androidtv
python3 tools/multiplayer_run.py --host atv --players ipad,iphone,pixel,firetv --start
python3 tools/corpus/quality_gate.py            # non-zero exit on any violation
python3 tools/question_sample.py --n 60 --seed 7
```

A device that is off is reported **SKIP**, never a pass. Silence about an
untested platform is how a green board comes to mean nothing.
