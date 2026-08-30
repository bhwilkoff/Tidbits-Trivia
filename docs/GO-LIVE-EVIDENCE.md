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
| `tools/corpus/quality_gate.py` | corpus | 29 construction rules over the whole corpus |

Two harness details are load-bearing and easy to get wrong again:

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
- **The web "joined" while sitting on the join form.** `#/live/CODE` prefills the
  code and asks for a team name — correct behaviour — but the loose in-room
  pattern matched the form. Only post-join chrome (`YOU'RE IN`, `POINTS`,
  `Waiting for the host`) counts now.

---

## 4. Question quality

### Construction: the gate is green

`tools/corpus/quality_gate.py` runs **29 rules over all 110,496 shipped
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

**One measurement worth not repeating:** a "prompt shares no words with its own
answer" detector flagged 1,068 rows — and they were the *best* questions in the
corpus, because a good clue deliberately never contains its answer. The narrow
detector was the correct one. A signal that fires on quality is not a defect
signal.

---

## 5. Defects found and fixed in this pass

| # | Surface | Defect | Status |
|---|---|---|---|
| 1 | web | `#/dailyboard` was **unreachable** — `#/daily`'s prefix match swallowed it, so every Daily-board link started the Daily game instead | fixed; all route pairs audited for prefix collisions |
| 2 | corpus | 16 questions pairing a person clue with a work answer — unanswerable | removed + tombstoned + `CLUE-CROSSED` gate rule |
| 3 | Android | `sync_shared_assets.sh` would copy the repo's **0-byte** `corpus.sqlite` over Android's real 52MB one via `rsync --delete` | excluded + a guard that refuses an empty source over a non-empty target |
| 4 | Android | `corpus.json` (54.9MB) and `enrich.json` (2.9MB) shipped in every install while **no Kotlin source opens them** | removed; assets 125MB → 67MB |
| 5 | harness | the Mac capture graded a terminal window as the app | raise the app before capturing |
| 6 | harness | the multiplayer host was never woken, and joins were attributed by a name the hook hardcodes | wake step + counted joins |

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

## 7. Re-running it

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
