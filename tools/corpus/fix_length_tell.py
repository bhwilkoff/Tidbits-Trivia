#!/usr/bin/env python3
"""Stop the answer being conspicuously longer than every distractor.

"Sir Gawain and the Green Knight" beside The Hobbit, Book of Ruth and
Persuasion. "Jean-Baptiste de Boyer, Marquis d'Argens" beside Les Murray, George
Crabbe and Junpei Gomikawa. The player does not read the clue; they pick the long
one.

Corpus-wide there is NO systematic length bias — the answer is the single longest
option 24.2% of the time against a 25% chance baseline (measured 2026-08-01), so
this is not a pattern anyone can farm. It is a per-question smell, and these are
the questions where it is loud: the answer more than 2.5x the longest distractor
and over 25 characters.

The repair swaps in distractors of comparable LENGTH from the same category, and
keeps every constraint the earlier repairs established — same KIND, same era, no
word shared with the prompt, nothing already on screen. It refuses rather than
half-fixing.

The kind constraint is not optional and the first version proved it: matching on
length alone put "Sir Gawain and the Green Knight" beside Rudolf II, Dina bint
Abdul-Hamid and Peter Townsend — a poem among three people, which is a louder
giveaway than the length ever was. A repair that ignores the other repairs just
moves the defect.

    python3 tools/corpus/fix_length_tell.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import bisect
import collections
import json
import pathlib
import random
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
ENRICH = ROOT / "assets" / "enrich.json"
RNG = random.Random(20260801)

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for", "de",
        "la", "le", "el", "s", "is", "was", "or"}


def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


def birth_years():
    out = {}
    for t, e in json.loads(ENRICH.read_text())["entities"].items():
        b = e.get("numbers", {}).get("birth_year")
        if b and -3500 < int(b["value"]) <= 2025:
            out[t.replace("_", " ")] = int(b["value"])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    years = birth_years()
    sys.path.insert(0, str(ROOT / "tools" / "corpus"))
    from fix_kind_distractors import kind_map
    kind = kind_map(rows)

    # Options by category, sorted by length so a length window is a slice.
    pool = collections.defaultdict(set)
    for q in rows:
        for o in (q[2] or []):
            pool[(q[4], kind.get(str(o)))].add(str(o))
    by_cat = {c: sorted(v, key=len) for c, v in pool.items()}
    cat_lens = {c: [len(n) for n in v] for c, v in by_cat.items()}

    fixed = refused = 0
    examples, refusals = [], []
    for q in rows:
        opts, ci = q[2], q[3]
        if not opts or len(opts) < 4 or not (0 <= ci < len(opts)):
            continue
        answer = str(opts[ci])
        others = [(i, str(o)) for i, o in enumerate(opts) if i != ci]
        longest = max(len(o) for _, o in others)
        if not (len(answer) > 2.5 * longest and len(answer) > 25):
            continue

        banned = {fold(o) for o in opts}
        prompt_words = sig(q[1])
        ya = years.get(answer)
        ka = kind.get(answer)
        if ka is None:
            # No kind for the answer means the only pool available is everything
            # UNCLASSIFIED, which is heterogeneous — that is how "Sir Gawain and
            # the Green Knight" ended up beside the First Council of Nicaea and
            # two priests. A length tell is a smaller sin than a kind tell.
            refused += 1
            continue
        key = (q[4], ka)
        names, lens = by_cat.get(key, []), cat_lens.get(key, [])
        # Within 40% of the answer's length — close enough that nothing stands out.
        lo = bisect.bisect_left(lens, int(len(answer) * 0.6))
        hi = bisect.bisect_right(lens, int(len(answer) * 1.4))
        cands = [n for n in names[lo:hi]
                 if fold(n) not in banned and not (sig(n) & prompt_words)
                 and not (ya and years.get(n) and abs(years[n] - ya) > 350)]
        if len(cands) < len(others):
            refused += 1
            if len(refusals) < 5:
                refusals.append(f"{q[0]}: {answer[:40]} — too few {q[4]} options of its length")
            continue

        before = list(opts)
        picks = RNG.sample(cands, len(others))
        for (slot, _), name in zip(others, picks):
            opts[slot] = name
        fixed += 1
        if len(examples) < 5:
            examples.append((q[1][:50], before, list(opts), answer))

    print(f"length-tell questions repaired: {fixed}")
    print(f"refused (left alone rather than half-fixed): {refused}")
    for p, b, n, ans in examples:
        print(f"\n   {p}...\n     was: {b}\n     now: {n}")
    for r in refusals:
        print(f"   REFUSED {r}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
