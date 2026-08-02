# Corpus schema, delivery and enrichment — the pre-launch pass

Measured 2026-08-02 against 111,599 rows. Every number here came from the shipped
data, not an estimate. Nothing in the data plane is immovable pre-launch, so this
is the moment to fix the shape rather than work around it.

## Where the bytes are

`assets/corpus.json` is **52.7 MB** (13.0 MB gzipped). By field:

| # | field | size | share | notes |
|---|-------|------|-------|-------|
| 9 | `tags` | 12.3 MB | **23.4%** | 426,806 instances, only **53,159 distinct** |
| 1 | `prompt` | 11.1 MB | 21.2% | irreducible — it is the question |
| 6 | `explanation` | 11.1 MB | 21.1% | irreducible — it is the payoff |
| 2 | `options` | 6.4 MB | 12.2% | irreducible |
| 8 | `sourceURL` | 4.9 MB | 9.4% | **80% derivable** from `subject` |
| 0 | `id` | 2.6 MB | 4.9% | |
| 7 | `subject` | 1.7 MB | 3.3% | |
| 4,3,5 | category, answerIdx, difficulty | 1.1 MB | 2.1% | |

**Two fields carry a third of the file and neither is information.** Tags repeat
8× on average; sourceURL is `https://en.wikipedia.org/wiki/` + the subject for
89,352 of 111,599 rows.

## The platform problem is the web, and it is severe

| platform | reads | cost |
|---|---|---|
| web | `assets/corpus.json` over the network | **13 MB gzipped, then the whole thing parsed into RAM** |
| iOS/macOS/tvOS | `corpus.sqlite` in the bundle | 63 MB app payload, queried not loaded |
| Android | `corpus.sqlite` in the bundle | 63 MB, queried (Decision 049) |
| Windows | `corpus.json` on disk | 52 MB, desktop RAM is not the constraint |

Android already hit this: holding the corpus in RAM peaked at **299 MB** and Play
rejected the build (Decision 049). It moved to SQLite. **The web app still does
the thing that got Android rejected** — `Corpus.load()` fetches the whole file
and `rowToQuestion`s every row before the first question is drawn.

A player who opens the site to answer seven Daily questions currently downloads
13 MB and materialises 111,599 objects.

## Cruft

- **7,800 rows are exact duplicates** — same normalised prompt, same answer. Two
  can land in one round.
- 2,690 subject+generator pairs appear 3+ times; the heaviest subjects carry 67
  questions each (San Diego, Delhi, Lhasa).
- 2 rows still have an empty reveal.

## The plan, in dependency order

Each step keeps the 28 gate rules and the five-engine goldens green, and each is
verified on a rendered screen before it counts as done.

1. **Dedupe.** Drop the 7,800 duplicate rows. Pure loss of nothing; no schema
   change, no client change. *(do first — it shrinks everything downstream)*
2. **Intern the tags.** — DONE for the app bundles. `questions.tags` holds
   pipe-joined INTEGER ids and a new `tag_names` table resolves them; the readers
   already split on `|`, so only resolution is new. 426,806 instances are just
   **53,147 distinct** strings — the corpus was writing "American male film
   actors" nineteen hundred times.

   | | before | after |
   |---|---|---|
   | tags column | 11.2 MB | 2.2 MB (+1.4 MB table) |
   | **corpus.sqlite** | **62.9 MB** | **50.0 MB** |

   Proven by the tag round-trip (5,000 rows resolve to exactly the names in
   corpus.json, 0 mismatches) and by Create parity passing UNCHANGED — Apple
   ranks from sqlite, the web from JSON, tags score at the highest weight, and
   the two still select identically.

   The web does not carry tags at all now (the shards drop them), so this is a
   bundle-size win for Apple and Android.
3. **Derive the sourceURL.** — DONE for the app bundles. `build_corpus.py` stores
   `""` when the url is exactly `wiki/<source_title>`, which is 80% of rows, and
   the Swift and Kotlin readers rebuild it. Followed by `VACUUM`, since a shipped
   artifact should not carry the free pages of the rewrite that made it.

   **corpus.sqlite 62.9 MB -> 58.5 MB, in BOTH the Apple bundle and the APK.**

   Verified by reproducing the original url for 4,000 sampled rows: 4,000 exact,
   0 mismatches. The rebuild is not optional — without it the reveal loses its
   "Read on Wikipedia" link, which is the door out of the app into the subject.
   That regression already happened once on the web shards and was caught there.
4. **Shard the web corpus.** — DONE. `assets/web/shard-NN.json` × 64, built by
   `build_web_shards.py` and rebuilt by the resync. Each category's rows are
   dealt round-robin so a shard carries the corpus's exact mix; one shard is a
   representative corpus, not a slice.

   | path | before | after |
   |---|---|---|
   | Quick Play / any mode | 13 MB gzip | **200 KB** |
   | Daily | 13 MB gzip | 13 MB (ranks every id — see below) |
   | Create search | 13 MB gzip | 13 MB (reads every prompt) |

   Two paths still need every row and now say so: `daily()` ranks the whole id
   space (a shard would compute a different seven than iOS, Android, Windows and
   the cron, which is exactly what the daily golden exists to catch), and Create
   search reads every prompt. Both call `loadFull()` explicitly.

   `countIn()` reads the MANIFEST rather than what is loaded, so a shard-loaded
   client still reports the real per-category totals instead of claiming the
   corpus is 64x smaller than it is.

   NEXT for the Daily: the cron already computes the day's seven ids
   server-side. Publishing them (or the seven questions) would take the Daily to
   a few KB, at the cost of the web trusting a published set instead of
   computing it — a contract change worth its own decision.
5. **Enrich what the player sees**, not the schema: the reveals that still say
   nothing, and picture-round images. Enrichment that does not reach the screen
   is more bytes for no gain.

## Rules this pass must not break

- Every question file stays byte-identical across the three platform mirrors
  (`check_mirrors.py`).
- The five-engine daily golden and the Create golden stay green.
- `authored/` content is never deleted by a generator
  (`generated-files-hide-authored-content`).
- A schema change lands in ALL readers in the same change set, or the mirrors
  diverge silently.
