#!/usr/bin/env python3
"""Make the odd one out odd for the RIGHT reason.

Rendered an Odd One Out round and read it:

    Three of these were created by Marta Kauffman. Which one is not?
    The Big Bang Theory / Friends / Ross Geller / Joey Tribbiani

Two of the four are fictional characters rather than shows. Wikidata's `creator`
covers both, so the relation is true — and the round is broken anyway, because in
a mode whose whole premise is "which doesn't belong", a difference in TYPE is an
answer. Here it points at the wrong option: the outlier is The Big Bang Theory,
but the two that stand out are the characters.

Worse cases came from the same generator drawing the odd option out of an
unrelated domain entirely:

    created by Leonardo da Vinci -> Salvator Mundi / Mona Lisa / SHERLOCK HOLMES
                                    / Lady with an Ermine
    created by Bob Kane          -> Dick Grayson / SALVATOR MUNDI (PAINTING)
                                    / Batman / Catwoman
    created by J. R. R. Tolkien  -> Gandalf / HULK / Elrond / Arwen

A player solves those without knowing a single fact about who created what,
which is the mode defeated rather than merely blemished.

The repair DROPS the incoherent sets rather than regenerating the file:
`gen_oddoneout.py` does not merge `tools/corpus/authored/`, and running it would
silently delete hand-authored rounds (that has happened here before — see the
`generated-files-hide-authored-content` note). 930 rows minus these leaves the
mode well covered.

    python3 tools/corpus/fix_oddoneout_coherence.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from quality_gate import kind_map                                  # noqa: E402


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


CORPUS = ROOT / "assets" / "corpus.json"
ODDONEOUT = ROOT / "assets" / "oddoneout.json"

# A fictional character is a kind of its own, and the corpus states it plainly in
# prose even when the description slot holds something else (Ross Geller's holds
# the actor's name). Read the whole explanation for this one signal.
CHARACTER = re.compile(r"\bis a fictional\b|\bfictional character\b"
                       r"|\bmain characters? of\b|\bis a character\b"
                       r"|\btitular character\b", re.I)


def option_kind(name, km, raw):
    name = str(name)
    if CHARACTER.search(raw.get(name, "")):
        return "character"
    return km.get(name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    rows = json.loads(CORPUS.read_text())["questions"]
    km = kind_map(rows)
    raw = {}
    for q in rows:
        if q[7] and q[6]:
            raw.setdefault(q[7], q[6])

    data = json.loads(ODDONEOUT.read_text())
    sets = data["questions"]

    drop, examples = [], []
    by_cat = collections.Counter()
    for r in sets:
        opts = r[2] or []
        kinds = {option_kind(o, km, raw) for o in opts}
        kinds.discard(None)
        if len(kinds) > 1:
            drop.append(r[0])
            by_cat[r[4]] += 1
            if len(examples) < 8:
                marked = [f"{o} [{option_kind(o, km, raw) or '?'}]" for o in opts]
                examples.append((r[1][:56], marked, str(opts[r[3]])))

    print(f"incoherent odd-one-out sets: {len(drop)} of {len(sets)}")
    print(f"remaining after the drop:    {len(sets) - len(drop)}")
    if by_cat:
        print("   by category:", dict(by_cat.most_common()))
    for prompt, marked, ans in examples:
        print(f"\n   {prompt}...\n     {marked}\n     answer: {ans}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    keep = [r for r in sets if r[0] not in set(drop)]
    body = json.dumps(keep, ensure_ascii=False, separators=(",", ":"))
    ODDONEOUT.write_text(
        f'{{"version":"{corpus_version(body)}","count":{len(keep)},"questions":{body}}}')
    print(f"\n{len(sets)} -> {len(keep)} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
