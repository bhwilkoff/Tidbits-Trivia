"""Stop "In what year was X born?" from being one question in four.

Measured 2026-08-02 while looking for a way to unskew Mixed Bag (Decision 050).
Bare date questions — "In what year was Donald Glover born?" and its death and
release-date siblings — are 29,353 rows, 22.9% of the corpus. At that density:

    41% of ten-question rounds contain THREE or more of them
    93% contain at least one

That is the single most repetitive thing in the app, and it is what the owner
means by dry padding: the prompt teaches nothing, the four options are years, and
2,347 of them have no reveal at all because no description could be found for the
subject.

The shape is not worthless. "In what year did Whitney Houston die?" about someone
the player has heard of is a fair guess with a real answer. It is worthless when
the subject is someone they have not. So the prune keeps the shape for the most
recognisable subjects and drops the rest, using the QRank the corpus pipeline
already stores — the same prominence measure that chose these subjects in the
first place.

  * every row whose reveal is EMPTY goes, whatever its rank: a dry prompt with no
    payoff cannot teach anything, and the reveal is the app's stated purpose
  * of the remainder, the top 40% by subject QRank stays

725 subjects lose their only question. That is the right outcome: a subject whose
entire presence in a 128k-row corpus was "what year were they born" was padding.

    python3 tools/corpus/prune_date_padding.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
import json
import pathlib
import re
import sqlite3
import sys


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SOURCE_DB = ROOT / "tools" / "corpus" / "corpus_source.sqlite"

DATE_QUESTION = re.compile(r"^In what year (?:was|did|were)\b", re.I)
KEEP_TOP = 0.40


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--keep-top", type=float, default=KEEP_TOP)
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    qrank = {}
    if SOURCE_DB.exists():
        db = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
        qrank = {t: (q or 0) for t, q in db.execute("select title, qrank from subject")}
        db.close()

    dated = [q for q in rows if DATE_QUESTION.match(q[1] or "")]
    if not dated:
        print("no date-shaped questions found")
        return 0

    ranks = sorted((qrank.get(q[7], 0) for q in dated), reverse=True)
    cut = ranks[min(len(ranks) - 1, int(len(ranks) * a.keep_top))]

    drop, why = set(), collections.Counter()
    for q in dated:
        if not (q[6] or "").strip():
            drop.add(q[0])
            why["no reveal at all"] += 1
        elif qrank.get(q[7], 0) < cut:
            drop.add(q[0])
            why["subject too obscure for a year guess"] += 1

    kept_rows = [q for q in rows if q[0] not in drop]
    kept_dated = [q for q in dated if q[0] not in drop]

    # A subject whose only question was a date row leaves with it.
    per_subject = collections.Counter(q[7] for q in rows)
    lost = {q[7] for q in dated if q[0] in drop}
    orphaned = {s for s in lost
                if per_subject[s] == sum(1 for q in rows
                                         if q[7] == s and q[0] in drop)}

    print(f"date-shaped questions: {len(dated):,} of {len(rows):,} ({len(dated)/len(rows):.1%})")
    print(f"dropped: {len(drop):,}   {dict(why)}")
    print(f"kept:    {len(kept_dated):,}  (QRank >= {cut:,})")
    print(f"corpus:  {len(rows):,} -> {len(kept_rows):,}")
    print(f"date share: {len(dated)/len(rows):.1%} -> {len(kept_dated)/len(kept_rows):.1%}")
    print(f"subjects whose ONLY question was a date row: {len(orphaned):,}")

    after = collections.Counter(q[4] for q in kept_rows)
    tot = sum(after.values())
    print("\ncategory shares after:")
    for k, v in after.most_common():
        print(f"   {k:11} {v:7}  {v/tot:6.1%}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(kept_rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{corpus_version(body)}","count":{len(kept_rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
