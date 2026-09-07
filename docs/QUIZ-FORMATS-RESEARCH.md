# Quiz and trivia file formats — what the field uses, and what Tidbits takes from it

*Researched 2026-09-07 for the portable Tidbits Live package
(`docs/LIVE-PACKAGE-FORMAT.md`). The question this answers: when a host wants
to move a night between machines, share it with another venue, or bring a
quiz in from another tool, what shapes will they arrive with, and which of
those shapes carry MEDIA?*

## §1 — The survey

| Format | Container | Questions | Media | Notes |
|---|---|---|---|---|
| **Kahoot** spreadsheet import | `.xlsx` (their template, ≤1 MB) | one row per question: Question (≤95 chars), Answer 1–4 (≤60), Time limit (5/10/20/30/60/90/120/240 s), Correct answer(s) as "1" or "2,3" | **none** — pictures are added in the editor afterwards | Multiple-correct via the comma list. No explanations, no categories, no question types beyond MCQ. |
| **Kahoot** REST JSON (`/rest/kahoots/{uuid}`) | JSON | `questions[]` with `type` (quiz, true_false, jumble, open_ended, survey, poll, slide, content, …), `choices[{answer, correct}]`, `time` ms, `pointsMultiplier` | `image` (upload) **or** `media[]` (Giphy `giphy_gif`, Unsplash `unsplash_image` — with `url`, `stillUrl`, dimensions, attribution), `video` (YouTube start/end) | What `tools/kahoot_import.py` reads. Three of thirteen questions in the first real import had ONLY `media[]`. |
| **Quizizz / Wayground** spreadsheet | `.xlsx` template | Question text, type (Multiple Choice, Checkbox, Fill-in-the-blank, Poll, Open-Ended), options, correct answer, time | **none** in the template; media added after upload | Same "spreadsheet is text-only" pattern as Kahoot. |
| **Blooket** CSV | `.csv` template | Question #, Question Text, Answer 1–4, Time Limit, Correct Answer(s) by number; column J `typing` marks a type-in question (answers become "is exactly") | **none** | Explicit "typing" flag is a nice touch — it is the only spreadsheet that names a second question type inline. |
| **Gimkit** | CSV template, Quizlet URL, or public question bank | question / correct / incorrect columns | none | Quizlet import is the interesting bit: a URL is an import source. |
| **Quizlet** export | tab- or comma-delimited text, custom separators | term / definition | none in export | Flashcards, not MCQs — a distractor generator is needed to make questions from them. |
| **Crowdpurr** CSV | `.csv` template (≤100 questions) | Question Text, Question Type Code (`multipleChoice`, `text`, `numerical`, `reorder`, `yesNo`, `likeDislike`), Points (1–1000), Time, **Question Media URL**, Question Note, Question Link, Correct Answer(s) separated by `@@@`, Answer Options… | **by URL only**; self-hosted uploads only survive if they remain on Crowdpurr's servers — external GIF/YouTube URLs round-trip | The closest to a pub-trivia interchange format: points, time, media, note, `reorder` and `numerical`. Its media weakness is exactly the one a package fixes. |
| **SpeedQuizzing** Quick Questions | a **folder** of files | the FILENAME is the question and answer (`.txt`); a `.jpg/.png` named that way is a picture question; `.mp3/.wav/.m4a` an audio question | **the file IS the media** | The dominant UK pub platform stores a quizpack as a folder you drag on. Media-first by construction; metadata-poor (no explanation, difficulty, type beyond what the file kind implies). A quizpack is 61 questions: 3 rounds of 20 + a Nearest Wins. |
| **Moodle GIFT** | `.txt` | `::title:: question { =right ~wrong ~%50%half }`, `{T}`/`{F}`, short answer `{=a =b}`, numerical `{#42:2}` / `{#40..44}`, matching `{ =a -> b =c -> d }`, missing word, essay `{}`; `#feedback`, `[html]` format tag, `//` comments, backslash escapes | HTML `<img>` only if the question text is `[html]` and the image is hosted elsewhere | Expressive, text-only, human-writable. Numerical tolerance and matching map directly onto Closest Call and Match-Up. |
| **Moodle Aiken** | `.txt` | question line, `A. option` … `ANSWER: B` | none | The simplest MCQ text format in the world. Worth accepting as an import for that reason alone. |
| **IMS QTI 3.0** | **zip** = 1EdTech Content Package: `imsmanifest.xml` at the root listing every resource (items, assets) with dependencies; items are XML | **inside the zip**, declared as resources and referenced by identifier | The education-sector standard. Heavy (XML, response processing, adaptive items) but its container discipline — a manifest that lists every file with a type, relative paths from the root — is the right idea. |
| **Anki `.apkg`** | **zip**: `collection.anki2` (SQLite), `media` (a JSON map "1" → original filename), files named `0`, `1`, `2`… | **inside the zip**, renamed to integers and mapped back by the `media` JSON | The most-shipped user-generated quiz container on earth. Proves that zip + one JSON map + numbered files is enough for millions of decks moving between platforms. |
| **H5P `.h5p`** | **zip**: `h5p.json` (package definition, dependencies), `content/content.json`, `content/<media>` | **inside the zip**, under `content/`; an allow-list of extensions (png jpg gif svg mp3 mp4 webm wav vtt …) | Cleanest modern example: a package definition at the root, content plus its media in one folder, an explicit allow-list of media types. |
| **Jeopardy datasets / players** | JSON (J! Archive dumps, `jeopardy-parser`) | `category`, `value`, `question`, `answer`, `round`, `air_date` | none | A category × value grid is a legitimate round shape (Tidbits' BOARD round, G5). |
| **Open Trivia DB** | JSON API | `category`, `type` (multiple/boolean), `difficulty` (easy/medium/hard), `question`, `correct_answer`, `incorrect_answers[]` | none | A public bank of MCQ/TF with difficulty and category — the natural "seed a round from a bank" source. |

## §2 — What the survey says

2.1 **Spreadsheets are text-only, everywhere.** Kahoot, Quizizz, Blooket,
Gimkit, Quizlet: not one carries a picture. Media is always "add it later in
the editor" or "leave it on our servers". A host who has built a night with
pictures cannot move it with a spreadsheet, and the vendors know it — the
spreadsheet is a funnel INTO the tool, not a way OUT.

2.2 **Every format that moves media is a zip with a manifest.** QTI (content
package + `imsmanifest.xml`), Anki (`.apkg` + `media` map), H5P (`.h5p` +
`h5p.json`). Three independent communities, one answer. There is no serious
media-bearing quiz format that is a bare JSON file with URLs in it.

2.3 **The pub world stores media as files, not references.** SpeedQuizzing's
quizpack is literally a folder of pictures and MP3s. Crowdpurr, which uses
URLs, has to warn that self-hosted images stop working the moment they leave
the account. A pub host's clips are on their laptop, not on a CDN.

2.4 **Content addressing is the cheap, correct way to name media.** Anki
renames files to integers and keeps a map; that works but makes de-duplication
and integrity impossible. Naming a file by its SHA-256 gives both for free.

2.5 **The good spreadsheet columns are worth accepting.** Crowdpurr's
(question type, points, time, media URL, note, link, `@@@`-separated correct
answers) and Blooket's `typing` flag show what hosts actually author: a type,
a time, a picture, a note. GIFT's numerical tolerance and matching syntax are
the text forms of Closest Call and Match-Up.

2.6 **Character caps are a Kahoot artefact, not a rule.** 95-character
questions and 60-character answers exist because of Kahoot's tile layout. A
pub question is routinely longer, and Tidbits' projector already shrinks and
wraps. Do not import those caps.

## §3 — What Tidbits takes from it

| Decision | Source |
|---|---|
| The package is a **zip with a JSON manifest at the root and media in a folder** — `.tidbits` | QTI, Anki, H5P (§2.2) |
| Media is **inside the package, content-addressed by SHA-256**, referenced from questions by id | SpeedQuizzing's files-not-URLs (§2.3) + §2.4 |
| The inner document is the existing `event.json` contract, unchanged | LIVE-EVENT-FILE §2 — one question shape everywhere |
| An **allow-list of media types** (png jpg jpeg gif webp svg mp3 m4a wav aac mp4 mov m4v webm) | H5P |
| A **question bank package** (`kind: "bank"`) is the same container with rounds as folders | Anki decks + Gimkit's bank |
| Every import prints what it could NOT carry, by question number | Crowdpurr's silent "image gone" is the failure to avoid |

## §4 — Import / export matrix (target state)

| Source / target | Import | Export | Media | Status |
|---|---|---|---|---|
| `.tidbits` package | ✅ Mac · ✅ Windows | ✅ Mac · ✅ Windows | embedded | **shipped 2026-09-07** (this wave) |
| `.tidbitsevent.json` | ✅ | ✅ | by URL only | shipped 2026-09-01 |
| CSV (named header) | ✅ | ✅ | by URL | shipped (LIVE-EVENT-FILE §6) |
| Kahoot (share link / JSON) | ✅ `tools/kahoot_import.py` → package | — | downloaded + embedded | shipped |
| Kahoot spreadsheet template (exported as CSV) | ✅ both hosts' CSV import (2026-09-07) | ⏳ (their template, text only) | none | instruction rows above the header are skipped; `1,3` keeps the first |
| Crowdpurr CSV | ✅ both hosts (2026-09-07) | ⏳ | by URL → `imageURL` | type codes (text → type-in, reorder → ordering, polls dropped), `@@@` answers, media URL, note |
| Blooket CSV / Gimkit CSV | ✅ both hosts (2026-09-07) | ⏳ | none | `Typing Answer` → type-in; Gimkit's Correct/Incorrect columns |
| Quizizz xlsx | ⏳ (export it as CSV) | ⏳ | none | its header names are read once saved as CSV |
| Moodle GIFT | ✅ both hosts (2026-09-07) | ✅ both hosts (2026-09-07) | none | MCQ (with `%50%` weights), T/F, short answer → type-in, numerical (`:tol` and `..range`) → Closest Call, matching → Match-Up, missing word, `::title::`, `####` feedback, `[html]` tags, backslash escapes. Ordering exports as a short answer of the sequence so nothing is silently dropped |
| Moodle Aiken | ✅ both hosts (2026-09-07) | — | none | lettered options + `ANSWER:`; the simplest MCQ text format there is |
| SpeedQuizzing Quick Questions folder | ⏳ | ⏳ | files | drag a folder in: filename → question, file → media |
| Open Trivia DB JSON | ⏳ | — | none | seed a round from a public bank |
| QTI 3.0 | 🚫 for now | 🚫 | embedded | education-only demand; revisit if a school asks |

## Sources

- Kahoot spreadsheet import — https://support.kahoot.com/hc/en-us/articles/115002812547-How-to-import-questions-from-a-spreadsheet-to-your-kahoot and the template https://kahoot.com/files/2018/08/KahootQuizTemplate-3.xlsx
- Quizizz import formats — https://wayground.com/admin/quiz/6738b6386671354b71dccc07/import-formats-for-quizizz
- Blooket spreadsheet import — https://help.blooket.com/hc/en-us/articles/16002377931543-How-to-Import-Questions-from-a-Spreadsheet-into-Blooket
- Gimkit CSV — https://help.gimkit.com/en/article/create-a-kit-with-a-csv-file-wv72i9/
- Quizlet export — https://help.quizlet.com/hc/en-us/articles/360034345672-Exporting-your-sets
- Crowdpurr import — https://help.crowdpurr.com/en/articles/10524880-importing-questions-from-a-spreadsheet
- SpeedQuizzing Quick Questions — https://www.speedquizzing.com/docs-pro/quick-questions/ and Question Manager https://www.speedquizzing.com/docs-pro/question-manager/
- Moodle GIFT — https://docs.moodle.org/502/en/GIFT_format · Aiken — https://docs.moodle.org/502/en/Aiken_format
- QTI 3 beginner's guide — https://www.imsglobal.org/spec/qti/v3p0/guide · content packaging — https://www.imsglobal.org/content/packaging/cpv1p1p3/imscp_bestv1p1p3.html
- Anki `.apkg` — https://eikowagenknecht.com/posts/understanding-the-anki-apkg-format/ and https://brandur.org/fragments/apkg
- H5P specification — https://h5p.org/documentation/developers/h5p-specification and https://h5p.org/documentation/developers/json-file-definitions
- Open Trivia DB — https://opentdb.com/api_config.php
- Jeopardy JSON / parser — https://github.com/tpavlek/jeopardy-parser
