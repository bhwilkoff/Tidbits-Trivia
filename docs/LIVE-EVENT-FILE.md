# The Tidbits Live event file — the portable night

**Binding.** macOS-DESIGN §A2.5 and WINDOWS-DESIGN §6.7 both require that a
host's event export as one self-describing document and import back — on either
platform. This file is that contract. Neither client may invent its own export
shape.

**Why a contract and not "each side writes its own model":** the two internal
models are genuinely different, and always were. macOS `LiveEvent` stores a
round as `{title, format, categoryID, questions[…]}` — the questions are IN the
event. Windows `LiveEvent` stored a round as `NightRound {kind, count}` and
pulled the questions from the corpus at host time, which is exactly why Windows
had nothing to edit: there were no questions in the model to open. Exporting
either internal shape directly would produce a file the other side could not
read, and would bake one platform's storage decisions into a user's document.

---

## §1 — The envelope

```json
{
  "format":  "com.learningischange.tidbits.live-event",
  "version": 1,
  "exportedAt": "2026-09-01T18:22:04Z",
  "app": "Tidbits Trivia (macOS)",
  "droppedClipCount": 0,
  "event": { … }
}
```

1.1 **`format` is checked before anything else.** A JSON file that parses but
carries a different `format` is not a Tidbits event, and the importer says so
rather than producing an empty night.

1.2 **`version` is an integer and forward-refusing.** A reader refuses a
document whose `version` exceeds the one it knows, naming the version in the
message. It never partially imports a newer file.

1.3 **`droppedClipCount`** records the audio/video clips that could NOT travel
(see §3). It exists so an importing host is told at import time instead of
finding out mid-night.

## §2 — The event

```json
{
  "id": "…", "name": "Friday Pub Quiz", "venue": "The Anchor",
  "createdAt": "2026-08-01T00:00:00Z",
  "sponsor": "", "leadCaptureURL": "", "brandHex": "", "weekday": null,
  "rounds": [
    {
      "id": "…", "title": "Round 1 — Warm Up",
      "format": "classic", "categoryID": "history",
      "timerSeconds": 60, "hostNote": "read slowly",
      "isWager": false, "isSpeed": false,
      "questions": [ … ]
    }
  ]
}
```

2.1 **A question is the shared `Question` shape, verbatim** — the same keys the
corpus and the live wire use (`id, prompt, options, correctIndex, categoryID,
difficulty, explanation, sourceTitle, sourceURL, templateID, tags, imageURL,
closest, ordering, matching, accepted, enumerate`). Swift's synthesized
`Codable` keys and the C# `JsonPropertyName`s already match; do not add a
per-file question encoding.

2.2 **`format` is the `GameMode` raw value** (`classic`, `typeAnswer`,
`closestCall`, `ordering`, `matching`, `enumerate`, `pictureId`, `oddOneOut`,
`thisOrThat`, `stake`, …) — the same string both stacks already serialize.

2.3 **`id` is advisory.** An importer assigns a NEW event id, so importing a
co-host's copy ADDS a night instead of silently overwriting one you already have
under the same id. Round ids may be regenerated freely.

2.4 **Unknown keys are ignored, missing optional keys take their default.**
That is what makes §1.2 a real forward-compat policy rather than a version
number nobody can bump: additive fields ship without a version change.

2.5 **The round is the unit of truth for question count.** There is no separate
`count`; a round has as many questions as its `questions` array. Windows'
`NightRound.Count` is DERIVED on import, never read from the file.

## §3 — What cannot travel

3.1 **Security-scoped bookmarks are stripped on export** and counted into
`droppedClipCount`. A macOS bookmark is meaningless on another machine, and a
Windows path is meaningless on a Mac. Writing one anyway would make a round look
complete and play silent — strictly worse than an empty clip slot the host can
see and re-fill.

3.2 **A clip slot is preserved even when empty**, so `questions[i]` still lines
up with clip *i* after a round-trip. Anything that inserts or removes a question
must keep the clip arrays index-parallel on both platforms.

## §4 — The mapping each platform owns

| Contract | macOS | Windows |
|---|---|---|
| `rounds[i].questions` | `LiveRound.questions` verbatim | `LiveEvent.RoundQuestions[i]`; `NightRound.Count` derived from its length |
| `rounds[i].format` | `LiveRound.format` | `NightRound.Kind` |
| `rounds[i].hostNote` | `LiveRound.hostNote` | `LiveEvent.RoundNotes[i]` |
| `rounds[i].timerSeconds` | `LiveRound.timerSeconds` | `LiveEvent.RoundTimers[i]` |
| `rounds[i].isWager` | `LiveRound.isWager` | `LiveEvent.WagerFinalRound` on the LAST round only |
| `rounds[i].title` | `LiveRound.title` | derived from the mode's title when absent |

4.1 **Windows' index-aligned side arrays are a storage detail, not the
contract.** They exist because `NightRound` is the wire type published to every
joiner and Apple pins its `CodingKeys` to `{kind, count}` with golden coverage
on it. The importer/exporter absorbs that difference; nothing else should know
about it.

## §5 — The test that keeps them honest

5.1 **A golden document lives in the repo and both stacks must round-trip it**
byte-for-byte on the fields §2 names. A change to either internal model that
breaks the golden is a contract break, not a refactor — the same rule the night
wire and the Daily golden already run under.


---

## §6 — The CSV question bank (binding)

A host's own questions arrive as CSV far more often than as an event file, and
the two clients diverged silently on what a CSV column means.

6.1 **A NAMED HEADER decides.** If the first row starts with `prompt` or
`question`, columns are mapped by name and their order does not matter.
Recognised: `prompt`/`question`, `correct`/`answer`/`correctanswer`,
`optionA…optionD` / `option1…option4` / `wrong1…wrong3` / `a`,`b`,`c`,`d`,
`category`, `difficulty`, `explanation`/`reveal`/`note`. **Emit a header on every
export.** It is the only shape that cannot be misread.

6.2 **`correct` may be the answer TEXT or a 1-based INDEX** into the options.
Both are common in the wild and both must resolve to the same question.

6.3 **Without a header, the two shipped orders are told apart by field 5.**
An integer 1–4 there means the Windows order
(`prompt, optionA..D, correct(1-4), [explanation]`); anything else means the
macOS order (`prompt, correct, wrong1..3, [category], [difficulty],
[explanation]`).

**Why this rule exists:** before it, a Windows-format CSV imported on the Mac
read field 1 as the answer. For `…,Phrygia,Lydia,Caria,Lycia,2,…` it marked
**Phrygia** correct when the answer is **Lydia** — silently, and it marks a
correct player wrong. In the other direction a macOS-format file imported
**nothing** on Windows, because field 5 would not parse as 1–4.

6.4 **A row whose answer is not among its options is DROPPED, not guessed.**
An answer no option matches is a question nobody can get right.

6.5 **The reader tries more than UTF-8.** BOM first, then UTF-16 only when the
bytes look like it (interleaved NULs), then the 8-bit encodings, rejecting any
decode containing a NUL or a replacement character. Excel on Windows writes
UTF-16LE with a BOM; assuming UTF-8 silently imported nothing.


---

## §7 — Importing a Kahoot (binding)

A host who already has a night in Kahoot does not rebuild it by hand. The
import is `tools/kahoot_import.py`, and it writes THIS document — never a
Kahoot-shaped file and never a client-specific one — so the night opens on the
Mac and on Windows through the ordinary "Import event…" with no new code path.

7.1 **The source is Kahoot's own JSON, not the slides.** A share link's quiz is
served by `https://create.kahoot.it/rest/kahoots/{uuid}` (the payload the
details page itself loads) with every choice and its `correct` flag, so nothing
is scraped off the slide DOM and the editor never has to be opened. A private
quiz needs `--token` (the `token` key in create.kahoot.it's localStorage) or the
JSON saved from the browser. The raw JSON is always written next to the output
so a re-import is offline.

7.2 **Block → question mapping.** `quiz` / `true_false` → `classic`;
`multiple_select_quiz` → `classic` keeping the FIRST correct choice (reported,
so the host edits it); `jumble` → `ordering` (Kahoot stores jumble choices in
the correct order); `open_ended` → `typeAnswer` with every choice accepted.
`survey` / `poll` / `word_cloud` / `brainstorm` / `scale` and the other
answerless blocks are skipped and named in the output; a content slide becomes
the next round's `hostNote`, because the host reads it aloud. Nothing is
dropped silently — every deviation is printed as a note.

7.3 **One round per format.** A `LiveRound` holds one format, so a format
change always starts a round. Kahoot times each question; a round has ONE
timer, so the round takes the LONGEST time in it (no question is cut short;
the host reveals early) and the note says so. `--rounds by-timer` splits on
timer changes instead, at the cost of a standings break at each boundary.

7.4 **Pictures travel as `imageURL` and are verified.** Every question image
(and the cover) is downloaded into `<stem>.images/` so the host owns a copy,
and `imageURL` points at Kahoot's public media CDN, which the Mac projector,
the cockpit and every joiner load at show time. Each URL the file references
is HEAD-checked for an `image/*` answer first; one that fails is left OFF the
question and reported, because a broken picture on the projector is the one
failure nobody in the room can diagnose. `--rehost BASE` rewrites `imageURL` to
a folder the host serves themselves (and checks that too). Choice images
(picture answers) have no Tidbits equivalent: the choice is labelled
"Picture A…" and reported.

7.5 **The host surfaces render the picture.** The Mac big screen shows it in
the video's slot under the prompt (the prompt yields part of its band, as it
does on reveal), the cockpit shows a thumbnail so the host sees what the room
sees, and the whole night's pictures are prefetched when hosting starts.
Animated GIFs animate (an `NSImageView`, not a SwiftUI `Image`, which shows the
first frame only). A load failure says "Picture unavailable" on the glass.
Windows: the joiner side is unchanged; the Windows big screen's picture band is
tracked in `docs/WINDOWS-PARITY.md` 3.36.
