#!/usr/bin/env python3
"""Stop showing the player Wikipedia's disambiguator.

Rendered a Match Up round: "Match each organization to its founder" over SpaceX,
Alibaba Group, Apple Inc. — and "Amazon (company)". The parenthetical is
Wikipedia's way of separating two articles with one name. It is not part of the
thing's name, and on a card that already says ORGANIZATION it is noise the player
has to read past. 9,745 questions show one.

Stripping them all would be wrong, which is why this measures first. "Michael
Jordan (footballer)" needs its parenthetical or the option is misleading; so do
"Evita (musical)", "Symphony No. 9 (Dvorak)" and "Andromeda (constellation)",
each of which shares a bare name with another subject in this corpus.

A cell is simplified only when both hold:
  * exactly ONE subject in the whole corpus claims that bare name, so the
    parenthetical distinguishes it from nothing, and
  * no sibling option in the same set collapses onto it, so no round can end up
    with two identical cards.

    python3 tools/corpus/fix_option_disambiguators.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
PAREN = re.compile(r"^(.*?)\s\(([^)]{2,28})\)$")

# The shape sources render options too; a Match Up value cell is as player-facing
# as a multiple-choice option.
SHAPE_FILES = ["oddoneout.json", "match.json", "order.json", "thisorthat.json",
               "picture.json", "typeanswer.json", "closest.json", "enumerate.json"]


def bare(name):
    m = PAREN.match(str(name))
    return m.group(1) if m else str(name)


def claim_map(rows):
    """bare name -> the set of subject titles claiming it."""
    claims = collections.defaultdict(set)
    for t in {q[7] for q in rows if q[7]}:
        claims[bare(t)].add(t)
    return claims


def simplify(options, claims):
    """Return options with the noise-only parentheticals removed."""
    names = [str(o) for o in options]
    out = list(names)
    for i, o in enumerate(names):
        m = PAREN.match(o)
        if not m:
            continue
        b = m.group(1)
        if len(claims.get(b, ())) != 1:
            continue                       # the parenthetical is doing real work
        # A very short bare name is not a name. "C (programming language)" -> "C"
        # reads as a typo beside "C++", and the duplicate detector folds the two
        # together. The gate caught this on the first run; the parenthetical is
        # the only thing making the card legible.
        if len(b) < 4:
            continue
        if any(bare(x) == b for j, x in enumerate(names) if j != i):
            continue                       # would collide with a sibling card
        out[i] = b
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    claims = claim_map(rows)

    changed = cells = 0
    examples = []
    for q in rows:
        if not q[2]:
            continue
        new = simplify(q[2], claims)
        if new != [str(o) for o in q[2]]:
            for b, n in zip(q[2], new):
                if str(b) != n:
                    cells += 1
                    if len(examples) < 8:
                        examples.append(f"{b}  ->  {n}")
            q[2] = new
            changed += 1

    shape_changed = 0
    shapes = {}
    for name in SHAPE_FILES:
        path = ROOT / "assets" / name
        if not path.exists():
            continue
        d = json.loads(path.read_text())
        srows = d["questions"] if isinstance(d, dict) else d
        touched = 0
        for r in srows:
            if len(r) > 2 and isinstance(r[2], list) and r[2]:
                new = simplify(r[2], claims)
                if new != [str(o) for o in r[2]]:
                    r[2] = new
                    touched += 1
        if touched:
            shapes[name] = (d, srows, touched)
            shape_changed += touched

    print(f"questions simplified: {changed}  ({cells} option cells)")
    print(f"shape-source rows simplified: {shape_changed}")
    for e in examples:
        print("   ", e)

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    for name, (d, srows, _) in shapes.items():
        path = ROOT / "assets" / name
        b = json.dumps(srows, ensure_ascii=False, separators=(",", ":"))
        path.write_text(
            f'{{"version":"{d["version"]}","count":{len(srows)},"questions":{b}}}')
    print(f"\nwrote {CORPUS} and {len(shapes)} shape sources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
