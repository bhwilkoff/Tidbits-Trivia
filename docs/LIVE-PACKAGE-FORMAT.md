# The Tidbits package — a night, with its media, in one file

**Binding.** A Tidbits Live night is distributed as ONE file, `<name>.tidbits`,
that carries the event document AND every picture, audio and video clip it
uses, and opens identically on the Mac and on Windows. This is the contract.
Neither client may invent its own package layout, and no importer may write a
different one. The research behind it is `docs/QUIZ-FORMATS-RESEARCH.md`;
the decision is DECISIONS.md #059.

**Why a package and not the JSON document:** `LIVE-EVENT-FILE.md` moves the
questions, and only the questions. Its pictures are URLs (which die when the
host they point at does), and its clips are STRIPPED on export (§3.1 there),
because a Mac bookmark means nothing on another machine. A host who built a
night with fourteen pictures and an audio round therefore could not give it to
a co-host, move it to their Windows box, or sell it to another venue. Every
format in the field that carries media is a zip with a manifest (QTI, Anki,
H5P) — this is ours.

---

## §1 — The container

1.1 **A `.tidbits` file is a ZIP archive.** Entry names are UTF-8 with
forward slashes; compression method 0 (store) or 8 (deflate) only; no
encryption, no zip64 (a package is under 4 GB and a single entry under 2 GB).
Readers walk the **central directory**, never the local headers, so an archive
re-zipped by Finder or Explorer (which write data descriptors) still opens.

1.2 **The first entry is `mimetype`**, stored uncompressed, containing exactly
`application/vnd.learningischange.tidbits+zip`. It is the sniffable signature
(the same trick EPUB uses), so a reader can refuse a foreign zip before parsing
anything.

1.3 **Fixed entries at the root:**

| Entry | Required | What |
|---|---|---|
| `mimetype` | yes | §1.2 |
| `manifest.json` | yes | §2 — what is in the package |
| `event.json` | yes | the LIVE-EVENT-FILE document, VERBATIM (§4) |
| `media/<id>.<ext>` | 0..n | §3 — the media files |

Anything else in the archive is ignored and preserved on a round-trip if the
writer chooses; it is never required.

1.4 **Directory entries are not required** and a reader never depends on
them.

## §2 — The manifest

```json
{
  "format":    "com.learningischange.tidbits.package",
  "version":   1,
  "kind":      "event",
  "title":     "Friday Pub Quiz",
  "createdAt": "2026-09-07T02:10:00Z",
  "createdBy": "Tidbits Trivia (macOS) 1.7.3",
  "media": [
    {
      "id":           "3a5f0c9b2d4e6f7a8b9c0d1e2f3a4b5c",
      "path":         "media/3a5f0c9b2d4e6f7a8b9c0d1e2f3a4b5c.png",
      "sha256":       "3a5f0c9b2d4e6f7a8b9c0d1e2f3a4b5c…64 hex…",
      "bytes":        23514,
      "mime":         "image/png",
      "kind":         "image",
      "originalName": "q01.png",
      "sourceURL":    "https://media.kahoot.it/94a3cd06-…",
      "credit":       "",
      "license":      ""
    }
  ]
}
```

2.1 **`format` is checked first**, then `version`, with the same rules as the
event document: a foreign `format` is "not a Tidbits package", a `version`
above the reader's is refused by name, never partially imported.

2.2 **`kind` is `event` or `bank`.** An `event` is a night: ordered rounds,
played top to bottom. A `bank` is a question library: the same `event.json`
shape, but its rounds are FOLDERS of reusable questions, not a running order
(§6).

2.3 **`media[]` lists every file under `media/`, and nothing else does.** A
file in `media/` that is not in the manifest is ignored; a manifest entry
whose file is missing is an error at import, named by `originalName`.

2.4 **`id` is the first 32 hex characters of the file's SHA-256; `sha256` is
all 64.** Content addressing gives de-duplication (the same picture used twice
is stored once) and integrity (a reader MAY verify the hash and MUST refuse a
mismatch it checks). `path` is always `media/<id>.<ext>`.

2.5 **`mime` and `kind`** are what the file is; `kind` is `image`, `audio` or
`video`. **Allowed types** (the H5P discipline — a package is not a
general-purpose archive):

| kind | extensions |
|---|---|
| image | png jpg jpeg gif webp svg |
| audio | mp3 m4a wav aac ogg flac |
| video | mp4 mov m4v webm |

A writer refuses anything else; a reader ignores it with a note.

2.6 **`sourceURL`** is the https twin of the file when one exists (the Kahoot
CDN picture the importer downloaded, an Unsplash photo). It is what a JOINER's
phone is given at show time (§5), because a phone cannot open a file inside
the host's package. `credit` and `license` are free text carried for the
host's benefit (Unsplash attribution, a venue's own photo) and never shown to
players.

## §3 — Media references inside the event

3.1 **A question's picture is `imageURL: "tidbits-media:<id>"`.** The URL
scheme `tidbits-media:` with the media id as its path. This keeps the shared
`Question` shape unchanged — every client already carries `imageURL` as a
string — and makes a reference that has no file behind it visibly fail
("Picture unavailable") instead of silently rendering nothing.

3.2 **A round's clips are two index-parallel arrays on the round,**
`audio: [id|null…]` and `video: [id|null…]`, one slot per question, absent
when the round has no clips. This maps onto both internal models without
translation: macOS `LiveRound.audioBookmarks/videoBookmarks` and Windows
`LiveEvent.RoundClips`. (A per-question field was considered and rejected: it
would add two keys to the wire `Question` that no joiner may ever see.)

3.3 **An https `imageURL` is still allowed** in a package (a question that
never had a local file). The writer does not download it. A writer that CAN
resolve it (the Kahoot importer) embeds the file and keeps the URL in
`sourceURL`.

## §4 — The event document inside

4.1 **`event.json` is the LIVE-EVENT-FILE document, byte-for-byte the same
contract** — same `format` id, same version, same `Question` shape. A reader
that only understands the bare document can still open `event.json` out of a
package and get every question; it will see `tidbits-media:` pictures as
unavailable, which is the truthful result.

4.2 **`droppedClipCount` is 0 in a package** unless a clip's file could not
be read at export (then it is counted and named to the host). Nothing is
stripped by design any more — carrying clips is the point.

## §5 — Media at show time

5.1 **Import copies media into the app's own store**, content-addressed:
macOS `Application Support/LiveMedia/<id>.<ext>` inside the sandbox;
Windows `%LOCALAPPDATA%\Tidbits\LiveMedia\<id>.<ext>`. The event the host
keeps references `tidbits-media:<id>`; the store resolves it. A round's
clips become the platform's native reference to the STORE file (a Mac
bookmark, a Windows path), so the existing cockpit playback needs no change.

5.2 **The projector and the cockpit resolve `tidbits-media:` locally.** A
missing file shows "Picture unavailable" on the glass — never a blank.

5.3 **Joiners are given `sourceURL`, never `tidbits-media:`.** A phone cannot
reach the host's disk. If the media has no https twin the picture is
PROJECTOR-ONLY, which is the ordinary pub-quiz idiom (Kahoot's phones show only
answer colours). Publishing package media to phones through Firebase Storage
is the tracked follow-up (§8); until then the cockpit says which pictures are
projector-only.

## §6 — Question banks

6.1 **A `bank` package is a library, not a night.** Its `event.json` rounds
are folders ("Geography — pictures", "80s music intros"); the importer offers
them to the host's question library, from which rounds are assembled. The
first bank importer is the Kahoot importer with `--bank`, and the app-side
library (search, tags, "add to round", "used in") is the next scope after this
one.

## §7 — Goldens (the test that keeps them honest)

7.1 **`tools/live-event/golden.tidbits` lives in the repo and both stacks
must open it**: one round with a `tidbits-media:` picture, one audio slot,
one https picture; manifest with two media entries. Each stack asserts the
media ids, hashes and byte counts, that the question's reference resolves to
the file, and that pack → unpack → pack reproduces the manifest and the
document on the fields §2–§4 name. `tools/live_package.py` is the reference
writer that produced it and the tool a host can use from a shell (`pack`,
`unpack`, `inspect`).

## §8 — Sequenced follow-ups

1. **Editors carry media** (Mac + Windows) — **DONE 2026-09-07 except
   Windows drag-and-drop:** "Choose picture…" on every question (copies into
   the store, writes `tidbits-media:`), a Clips section that attaches an audio
   or video file to any single question (the round's index-parallel arrays are
   created and kept aligned by the builder; the editor hands back a
   keep/remove/set CHANGE because the wire Question may not grow media keys),
   and on the Mac a picture/audio/video file dropped on a question row becomes
   that question's media by its kind. Windows drag-and-drop is tracked
   (WINDOWS-PARITY 3.39).
2. **File association**: double-click a `.tidbits` on the Mac
   (`UTExportedTypeDeclarations`, macOS-only Info.plist) and on Windows
   (`uap:FileTypeAssociation` in the MSIX manifest) opens the importer.
3. **Phones see package media**: at host time upload the night's media to
   Firebase Storage under `live/{code}/media/<id>` and publish the download
   URLs; delete at end of night. Stays inside the $0 guardrail at pub scale.
4. **The question library** (§6) in both apps.
5. **More importers/exporters** per the matrix in QUIZ-FORMATS-RESEARCH §4:
   Crowdpurr CSV, Kahoot xlsx export, Blooket/Quizizz, GIFT/Aiken,
   SpeedQuizzing folders, Open Trivia DB.
