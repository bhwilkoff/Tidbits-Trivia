# Data Contract — Saved Quizzes (`quiz.v1`)

> A created quiz is **saved to your account, replayable, and shareable with other
> users**. That makes it the first user-authored object in Tidbits, so it needs a
> contract before it needs a screen — six platforms writing their own JSON is how
> a share link ends up opening a different quiz on Android than on iOS.

Status: **contract frozen at v1**. Consumers: iOS · iPadOS · macOS · tvOS ·
Android · Windows · web.

---

## 1. The core idea: refs, not text

A quiz does **not** store its questions. It stores an ordered list of **references**
into the corpus every platform already ships. A 20-question quiz is well under 1 KB,
so it costs nothing to sync, nothing to host, and nothing to put in a URL.

```
qs: [ "src:desc:Q1339", "pic:0142", "closest:0007", … ]
```

Each entry is type-disambiguated — the same trick `corpus.json` already uses for its
10th element (string = image URL, array = tags):

| Entry type | Meaning |
|---|---|
| **string** | A CORPUS question ID |
| **object** | A BUNDLED-SET question: `{"i": "<id>", "s": "<set>"}` |
| **array** | An INLINE question, in the exact `corpus.json` row shape |

### Why a bundled-set ref carries its set

A bare ID is **ambiguous**. The bundled sets share the corpus `src:` namespace: of
200 sampled Picture ID rows, **166 have an ID that also exists in the corpus as a
different question shape**. Resolving corpus-first therefore returned a text question
in place of a saved picture question — the exact silent substitution this section
forbids, and invisible unless you replay a quiz and notice the photograph is gone.

Two rules follow, and both are pinned by tests on all four stacks:

1. A question from a bundled set is saved as `{"i","s"}`, never as a bare string.
   Which set is derived from the question's **shape** (it has an image → `picture`, a
   `closest` spec → `closest`, and so on), so provenance survives without being
   threaded through every call site.
2. A set ref that its own set can't resolve is **left missing**. It must never fall
   back to the corpus, because the corpus is exactly where the wrong question lives.

### Why inline exists, and why it is narrow

When the corpus is thin on a topic, Create falls back to live Wikipedia generation.
Those questions exist only on the device that made them, so they must travel with the
quiz. They are **always plain MCQ**, so the inline form is exactly a `corpus.json`
row — every stack already has a decoder for it (`rowToQuestion` in JS, `Question.row`
in Swift, and so on). No new per-platform parsing code, and no chance of the six
implementations drifting.

Shaped questions (Picture ID, Closest Call, Ordering, Match-Up, Type-Answer,
Odd-One-Out, Enumerate) come from bundled sets with stable IDs, so they are **always
refs and never inlined**. This is a real constraint, not an oversight: it keeps the
inline path to one shape.

### Unresolvable refs degrade, they do not fail

A ref can go missing — an older app build, a corpus row retired, a platform that
doesn't ship a given bundled set. The rule (`universal-feature-states`):

- Resolve every ref you can, in order.
- If **≥ 3** questions resolve, play the quiz and tell the player it is short:
  *"3 of this quiz's 8 questions aren't in your version yet."*
- If **< 3** resolve, show an honest empty state offering to re-create from the topic.

Never silently substitute a different question. A shared quiz that quietly changes
content is worse than one that admits it is incomplete.

---

## 2. Wire format

```jsonc
{
  "v":  1,                  // contract version (integer)
  "id": "k7m3qp9x2r",       // 10 chars, see §3
  "t":  "Jazz Legends",     // title, 1–60 chars, user-editable
  "tp": "Jazz",             // the topic as typed — lets us re-create if refs die
  "by": "<uid>",            // creator's player uid
  "bn": "Ben",              // creator's display name at save time (denormalised)
  "at": 1753900000000,      // created, ms since epoch (UTC)
  "m":  "mix",              // game mode: mix | classic | timeAttack | survival | stake
  "qs": [ "src:desc:Q1339",                       // corpus ref
          {"i": "src:describe:Ornette_Coleman", "s": "picture"},   // bundled-set ref
          [ /* corpus row */ ] ]                  // inline (live-generated)
}
```

Field names are terse because this object rides in share URLs and RTDB. **Do not
rename them.** Additive evolution only — a v1 reader must ignore unknown keys, and a
v2 writer must keep every v1 key meaningful.

`bn` is denormalised on purpose: a shared quiz should say who made it without a second
network read, and it is a snapshot — renaming your profile does not rewrite quizzes
you already shared.

---

## 3. Quiz IDs

10 characters from `23456789abcdefghjkmnpqrstvwxyz` (30 chars) — Crockford-style,
with `0/o`, `1/l/i` and `u` removed so an ID read aloud in a pub or typed off a
projector is unambiguous, and a random ID can't spell something unfortunate. That is
30^10 ≈ 5.9 × 10^14 values; random generation client-side, no coordination, no
server.

IDs are **random, not derived from content**. Two people who both create a "Jazz" quiz
must get different IDs, and an ID must not leak what is inside it.

Every platform's generator takes an injectable random source so the codec can be
tested deterministically.

---

## 4. Storage

| Layer | Where | Purpose |
|---|---|---|
| Local | SwiftData (Apple) · Room (Android) · `localStorage` (web) · JSON file (Windows) | Your quizzes work offline and before sign-in |
| Account | RTDB `playersPrivate/{uid}/quizzes/{id}` | Sync across your own devices |
| Shared | RTDB `quizzes/{id}` | Public read, so a share link opens for anyone |

**Local is the source of truth for your own quizzes.** Sync is additive and
merge-guarded: a quiz is only ever created or deleted, never edited in place by a
remote writer, so two devices cannot clobber each other.

Publishing to `quizzes/{id}` is an explicit user action (Share), not a side effect of
saving. A quiz you never share never leaves your account bucket.

### Rules

```jsonc
"quizzes": {
  "$id": {
    ".read": true,                                        // a share link must open for anyone
    ".write": "auth != null && (!data.exists() || data.child('by').val() === auth.uid)",
    ".validate": "newData.hasChildren(['v','id','t','by','at','qs'])"
  }
}
```

Public read matches `dailyBoard` and `standings`, which are already world-readable. A
quiz is content its author chose to publish; the bucket holds no personal data beyond
the display name the author attached.

---

## 5. Share URLs

Canonical (per `DEEP_LINKS.md`): `https://tidbitstrivia.com/quiz/<id>`
Native twin: `tidbitstrivia://quiz/<id>`

The web app is the canonical link target on every platform, so a quiz shared into a
group chat opens for people who don't have the app — the whole point of the mechanic.

---

## 6. Evolution rules

1. **Additive only.** New optional keys are fine; renaming or repurposing one is not.
2. **Bump `v` only for a breaking change**, and keep reading v1 forever — quizzes are
   user-authored content and outliving one app version is the point.
3. **Every change lands in all six clients in the same change set**, or the row goes
   into `PARITY.md` with a date. A wire format that is only half-mirrored is the
   failure this document exists to prevent.

---

## 7. Migration: the web's existing `tidbits.savedSets`

Web already shipped a partial version of this mechanic (PARITY row "Create — varied
retrieval… + saved sets", 2026-07-03). It is **not** compatible and must be migrated,
not left as a second format:

| | `tidbits.savedSets` (old) | `quiz.v1` (this contract) |
|---|---|---|
| Identity | `label` string, deduped case-insensitively | random 10-char `id` |
| Questions | **full question objects inline** | refs, inline only for live-generated |
| Portability | web only | six platforms |
| Shareable | no | yes |
| Cap | 20, silently truncating | none |

**Migration rule:** on first load after the upgrade, convert each saved set to a
`quiz.v1` object — `label` becomes `t` and `tp`, `savedAt` becomes `at`, and each
stored question becomes a **ref if its ID resolves in the corpus, inline otherwise**.
That last part matters: a naive conversion would inline all of them and turn a 400-byte
quiz into a 40 KB one. Keep the old key until the converted list is written, then
delete it — a half-finished migration must not lose the player's quizzes.

Nothing else reads `tidbits.savedSets` after that, and no other platform ever adopts
it.
