#!/usr/bin/env python3
"""Make every option the same KIND of thing as the answer.

Found by rendering the highest layout-risk question and looking at it. The clue
described "a shrub of the dogbane family"; the options were Myrtle, Nerium, Date
palm — and European hornet. An insect among three plants.

Across the corpus, 966 questions offer a distractor of a different kind
entirely: a giraffe among plants for "the last survivor of an order that first
appeared over 290 million years ago", a soursop among decapod crustaceans. The
player does not need the fact; they need to notice one of these is an animal.

The repair keeps the answer where it is and redraws the offending distractors
from subjects of the SAME kind, using the corpus's own one-line descriptions
(plant / animal / person / place / work / org / event / chemical / disease). It
refuses rather than half-fixing: a question with too few same-kind neighbours is
left alone and reported, because a wrong distractor is worse than a mismatched
one.

    python3 tools/corpus/fix_kind_distractors.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import json
import pathlib
import random
import re
import sys
import unicodedata

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
RNG = random.Random(20260801)      # deterministic; three mirrors must agree

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for", "de",
        "la", "le", "el", "s", "is", "was", "or"}



def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


def descriptions(rows):
    out = {}
    for q in rows:
        e = q[6] or ""
        if ":" in e and "→" not in e:
            _, d = e.split(":", 1)
            d = d.strip()
            if d and len(d) > 8 and not d[0].isdigit():
                out.setdefault(q[7], d)
    return out


# The type classifier lives in quality_gate.py and is imported, not copied. Two
# copies is what let this file keep matching a noun anywhere in the description
# for a full session after the gate had been fixed. The gate is the source of
# truth because it is the thing that blocks a ship.
from quality_gate import readable_description, _KINDS   # noqa: E402


# kind_map is imported, not redefined. This file kept its own copy for one
# session after the gate's was fixed, and the two silently disagreed.
from quality_gate import kind_map                                  # noqa: E402,F401


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    kind = kind_map(rows)
    # Birth years, so a kind repair cannot undo the era repair. The first run of
    # this script paired Ramon Llull with someone 620 years away and the quality
    # gate failed the build — which is what the gate is for, but the two repairs
    # have to agree rather than take turns.
    years = {}
    ents = json.loads((ROOT / "assets" / "enrich.json").read_text())["entities"]
    for t, e in ents.items():
        b = e.get("numbers", {}).get("birth_year")
        if b and -3500 < int(b["value"]) <= 2025:
            years[t.replace("_", " ")] = int(b["value"])

    # Candidate options per (kind, category) — a plant distractor for a science
    # question should still be a science plant.
    pool = collections.defaultdict(set)
    for q in rows:
        for o in (q[2] or []):
            k = kind.get(str(o))
            if k:
                pool[(k, q[4])].add(str(o))
        for o in (q[2] or []):
            k = kind.get(str(o))
            if k:
                pool[(k, "*")].add(str(o))
    pool = {k: sorted(v) for k, v in pool.items()}

    fixed = refused = 0
    examples, refusals = [], []
    by_reason = collections.Counter()
    for q in rows:
        opts, ci = q[2], q[3]
        if not opts or len(opts) < 4 or not (0 <= ci < len(opts)):
            continue
        answer = str(opts[ci])
        want = kind.get(answer)
        if not want:
            continue
        wrong = [i for i, o in enumerate(opts)
                 if i != ci and kind.get(str(o)) and kind.get(str(o)) != want]
        if not wrong:
            continue

        banned = {fold(o) for o in opts}
        prompt_words = sig(q[1])
        ya = years.get(answer)
        cands = [n for n in (pool.get((want, q[4])) or pool.get((want, "*")) or [])
                 if fold(n) not in banned and not (sig(n) & prompt_words)
                 and not (ya and years.get(n) and abs(years[n] - ya) > 350)]
        if len(cands) < len(wrong):
            refused += 1
            by_reason[want] += 1
            if len(refusals) < 6:
                refusals.append(f"{q[0]}: {answer} ({want}) — too few same-kind {q[4]} options")
            continue

        before = list(opts)
        picks = RNG.sample(cands, len(wrong))
        for slot, name in zip(wrong, picks):
            opts[slot] = name
        fixed += 1
        if len(examples) < 5:
            examples.append((q[1][:56], before, list(opts), answer))

    print(f"questions with a wrong-kind distractor repaired: {fixed}")
    print(f"refused (left alone rather than half-fixed): {refused}")
    if by_reason:
        print("   refusals by the answer's kind:", dict(by_reason.most_common(6)))
    for p, b, n, ans in examples:
        print(f"\n   {p}...\n     was: {b}\n     now: {n}   (answer {ans})")
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
