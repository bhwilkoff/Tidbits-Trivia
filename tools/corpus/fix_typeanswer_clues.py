"""Drop free-text questions that cannot be answered.

Rendered a Type Answer round and read it:

    Who is this — "Swedish actress (1915-1982)"?
    [ Type your answer... ]

The clue is a Wikidata description quoted verbatim, quote marks and all. In
multiple choice a bare description is merely dull, because the options carry the
question. With a text field there is nothing to pick from, and the player must
produce one exact name from a phrase that fits dozens of people.

Two generators produce unanswerable rows:

1. "Who is this - <description>?" / "What is this - <description>?" — 474 rows.
   The worst are not close calls: "What is this - 'Medical condition'?",
   "'U.S. state'?", "'Chemical compound'?". 268 of the 474 name a description
   that does not identify a unique subject even within this corpus.

2. "Fill in the blank: ..." where the blanking replaced EVERY occurrence of any
   answer word rather than the answer itself — 313 of 476 rows. "Luna moth"
   blanks both "Luna" and "moth", so "also called the American moon moth" became
   "also called the American moon ____", and the clue reads:

       "____ (Actias ____), also called the American moon ____, is a Nearctic..."

   The nine-blank case is "____ (____ UAE or ____) is a country in ____ eastern
   part of _...". A single blank is fine and 163 rows have exactly one; those are
   kept.

Dropped rather than rewritten: a clue this damaged has no original text left to
recover, and inventing one would be writing trivia rather than repairing it.

    python3 tools/corpus/fix_typeanswer_clues.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
import json
import pathlib
import re
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
TYPEANSWER = ROOT / "assets" / "typeanswer.json"

BARE_DESC = re.compile(r'^(?:Who|What) is this\s*[—-]\s*[""“][^""”]{4,120}'
                       r'[""”]\s*\?$')
BLANK = re.compile(r"_{2,}")


def verdict(prompt):
    """Why this clue cannot be answered, or None if it can."""
    p = str(prompt or "")
    if BARE_DESC.match(p):
        return "bare description quoted as the whole clue"
    blanks = len(BLANK.findall(p))
    if p.startswith("Fill in the blank:") and blanks > 1:
        return f"{blanks} blanks — the answer's words were blanked everywhere"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(TYPEANSWER.read_text())
    rows = data["questions"]

    drop, why = [], collections.Counter()
    examples = []
    for r in rows:
        v = verdict(r[1])
        if v:
            drop.append(r[0])
            why[v.split("—")[0].strip() if "blanks" not in v else "multi-blank"] += 1
            if len(examples) < 8:
                examples.append((str(r[1])[:76], r[2], v))

    print(f"unanswerable type-in clues: {len(drop)} of {len(rows)}")
    print(f"remaining after the drop:   {len(rows) - len(drop)}")
    print("   by reason:", dict(why.most_common()))
    for p, ans, v in examples:
        print(f"\n   {p}\n     answer: {ans}   [{v}]")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    keep = [r for r in rows if r[0] not in set(drop)]
    body = json.dumps(keep, ensure_ascii=False, separators=(",", ":"))
    TYPEANSWER.write_text(
        f'{{"version":"{corpus_version(body)}","count":{len(keep)},"questions":{body}}}')
    print(f"\n{len(rows)} -> {len(keep)} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
