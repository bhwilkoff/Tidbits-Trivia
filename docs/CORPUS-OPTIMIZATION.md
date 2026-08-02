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
2. **Intern the tags.** A `tags` string table plus integer refs: 11.0 MB of text
   becomes 1.4 MB of table + 1.2 MB of refs. Saves ~8.4 MB. Touches every reader
   (Swift, Kotlin, C#, JS) and the sqlite schema.
3. **Derive the sourceURL.** Store only the 22,244 that differ from
   `wiki/<subject>`; synthesise the rest at read time. Saves ~4 MB.
4. **Shard the web corpus.** The web should fetch what a session needs, not the
   corpus: a small `index.json` (ids + category + difficulty, enough for the
   Daily pick and mode/category counts) plus per-category shards fetched on
   demand. Target: **first play under 1 MB**.
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
