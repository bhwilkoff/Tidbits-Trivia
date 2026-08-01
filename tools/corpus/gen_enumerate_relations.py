#!/usr/bin/env python3
"""Build Name as Many puzzles from the corpus's creator relations.

`enumerate.json` was 32 curated puzzles — 2 to 4 per category against a 3-puzzle
round, so the second round in a category fell back to mixed. The corpus holds
128,638 rows and a director / composer / author relation for most creative work
in it, and "name as many films by this director" is exactly the shape this mode
wants.

It only helps where the corpus encodes a COMPLETE set. That is true of a
creator's body of work and of a continent's countries; it is not true of
"the Grand Slam tournaments" or "the noble gases", which have a definite answer
the corpus does not enumerate. So screen / music / arts / geography are derived
here and history / science / sports / business stay curated — a real limit, not
a gap to paper over.

APPENDS; existing ids are never touched and re-runs add nothing.

    python3 tools/corpus/gen_enumerate_relations.py [--apply]
"""
import argparse
import collections
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIRRORS = ("assets", "TidbitsTrivia/Resources", "android/app/src/main/assets")

RELATIONS = {
    "wd:director": "Name as many films directed by {} as you can",
    "wd:composer": "Name as many works composed by {} as you can",
    "wd:author":   "Name as many works written by {} as you can",
    "rel:P170":    "Name as many things created by {} as you can",
    "rel:P175":    "Name as many songs performed by {} as you can",
}
MIN_ITEMS, MAX_ITEMS = 5, 14      # enough to be a game, few enough to be finishable
PER_CATEGORY = 60


def build(rows, difficulty):
    groups = collections.defaultdict(lambda: collections.defaultdict(set))
    diff_of, url_of = {}, {}
    for q in rows:
        rel = ":".join(q[0].split(":")[:2])
        if rel not in RELATIONS or not q[7] or not q[2] or not (0 <= q[3] < len(q[2])):
            continue
        groups[(q[4], rel)][q[2][q[3]]].add(q[7])
        diff_of[q[7]] = q[5]
        url_of[q[7]] = q[8]

    def rank(s):
        return (diff_of.get(s, 5), difficulty.get((url_of.get(s) or "").split("/wiki/")[-1], 5))

    out, per_cat = [], collections.Counter()
    for (cat, rel), byval in sorted(groups.items()):
        # Most recognizable creators first, so the puzzle is one a player can
        # actually make progress on.
        for value in sorted(byval, key=lambda v: (rank(sorted(byval[v], key=rank)[0]), v)):
            if per_cat[cat] >= PER_CATEGORY:
                break
            items = sorted(byval[value], key=rank)
            if not (MIN_ITEMS <= len(items)):
                continue
            items = items[:MAX_ITEMS]
            # Titles carry disambiguators — "Penguin (character)", "Leonardo
            # (Teenage Mutant Ninja Turtles)". The engine's normalizer strips
            # punctuation but keeps the words, so a player typing "Penguin" would
            # be told they are wrong. Accept the bare name AND the full title, and
            # show the bare one.
            groups, bares = [], set()
            for i in items:
                bare = re.sub(r"\s*\([^)]*\)", "", i).strip()
                if not bare or bare.lower() in bares:
                    groups = []          # two items collapse to the same answer
                    break
                bares.add(bare.lower())
                groups.append([bare, i] if bare != i else [i])
            if len(groups) < MIN_ITEMS:
                continue
            prompt = RELATIONS[rel].format(value)
            out.append([
                f"enumrel:{hashlib.sha1(f'{rel}|{value}'.encode()).hexdigest()[:14]}",
                prompt, groups, cat, 60, "",
            ])
            per_cat[cat] += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    rows = json.load(open(ROOT / "assets" / "corpus.json"))["questions"]
    difficulty = json.load(open(ROOT / "assets" / "difficulty.json"))["difficulty"]
    built = build(rows, difficulty)
    print(f"built {len(built)} relation-derived Name as Many puzzles")
    print("by category:", dict(collections.Counter(r[3] for r in built).most_common()))
    for r in built[:4]:
        print(f"   {r[1]}  ({len(r[2])} items: {', '.join(x[0] for x in r[2][:4])}…)")
    if not args.apply:
        print("\n(dry run — pass --apply to append)")
        return
    base = json.load(open(ROOT / "assets" / "enumerate.json"))
    have = {r[0] for r in base["questions"]}
    added = [r for r in built if r[0] not in have]
    all_rows = base["questions"] + added
    body = json.dumps(all_rows, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(all_rows)},"questions":{body}}}'
    for m in MIRRORS:
        p = ROOT / m / "enumerate.json"
        if p.exists():
            p.write_text(payload)
    print(f"\nappended {len(added)}; enumerate.json now {len(all_rows)} rows")


if __name__ == "__main__":
    main()
