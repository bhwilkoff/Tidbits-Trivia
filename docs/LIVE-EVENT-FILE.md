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
