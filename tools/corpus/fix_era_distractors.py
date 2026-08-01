#!/usr/bin/env python3
"""Give person questions distractors from the same WALK OF LIFE, and era.

Found by rendering the corpus's longest prompt on the simulator rather than by
counting anything: a clue describing a living Russian-British activist and
filmmaker sat beside Amin al-Husseini, Lazarus of Bethany and Titus. The era in
the clue eliminates three options before the player knows a thing.

Measured across the corpus, 445 MCQs whose four options are ALL dated people
span more than 400 years — the worst by 4,314 (an Egyptian pharaoh beside a
19th-century Canadian politician). That is the last rule in
`tools/corpus/quality_gate.py` still carrying a budget.

Matching on era ALONE is not enough, and the first version of this script proved
it on screen: it rebuilt a ski-jumper question as Matti Nykanen beside Roman
Abramovich, Ben Ali and Boris Johnson. All four are 20th-century, the gate rule
passed, and a player who reads the words "ski jumper" still eliminates three
options without knowing anything. The corpus already held the right answer in the
next row over — the same subject's `describe` question offers Eddie Edwards,
Simon Ammann and Jens Weissflog, all ski jumpers.

So the draw is by OCCUPATION first, taken from the one-line description
("Finnish ski jumper (1963-2019)"), and only then by era. It refuses rather than
half-fixes: a question it cannot fill from the answer's own walk of life inside
the era window is left alone and reported, because a wrong distractor is worse
than a wide one.

    python3 tools/corpus/fix_era_distractors.py [--apply]

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

MAX_SPAN = 400          # what the gate calls acceptable
WINDOWS = [60, 100, 150, 200]   # half-widths tried in order; 200 keeps span <= 400
RNG = random.Random(20260801)   # deterministic — three platform copies must agree

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for", "de",
        "la", "le", "el", "s", "is", "was", "or"}

OCCUPATION = re.compile(
    r"\b(ski jumper|footballer|football player|basketball player|baseball player|"
    r"tennis player|golfer|boxer|sprinter|swimmer|cyclist|athlete|racing driver|"
    r"actor|actress|singer|musician|composer|rapper|guitarist|pianist|conductor|"
    r"novelist|poet|writer|author|playwright|philosopher|painter|sculptor|architect|"
    r"physicist|chemist|biologist|mathematician|astronomer|engineer|inventor|economist|"
    r"politician|president|prime minister|king|queen|emperor|monarch|general|"
    r"film director|filmmaker|screenwriter|journalist|businessman|entrepreneur)\b", re.I)

# Occupations that read as the same walk of life, so a round can mix them.
KIN = {}
for _group in (
    {"actor", "actress"}, {"singer", "musician", "rapper", "guitarist", "pianist"},
    {"novelist", "poet", "writer", "author", "playwright"},
    {"physicist", "chemist", "biologist", "mathematician", "astronomer"},
    {"politician", "president", "prime minister"}, {"king", "queen", "emperor", "monarch"},
    {"film director", "filmmaker", "screenwriter"},
):
    for _o in _group:
        KIN[_o] = _group


def occupations(rows):
    """subject -> its occupation word, from the corpus's own description."""
    desc, out = {}, {}
    for q in rows:
        e = q[6] or ""
        if ":" in e and "\u2192" not in e and "->" not in e:
            _, d = e.split(":", 1)
            d = d.strip()
            if d and not d[0].isdigit() and len(d) > 8:
                desc.setdefault(q[7], d)
    for name, d in desc.items():
        m = OCCUPATION.search(d)
        if m:
            out[name] = m.group(1).lower()
    return out


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
        if b:
            y = int(b["value"])
            # A "screen" person born in 2230 is bad data, not a distractor.
            if -3500 < y <= 2025:
                out[t.replace("_", " ")] = y
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    years = birth_years()
    occ = occupations(rows)

    # Candidate distractors per category, sorted by year so a window is a slice.
    pool = collections.defaultdict(set)
    for q in rows:
        for o in (q[2] or []):
            if str(o) in years:
                pool[q[4]].add(str(o))
    by_cat = {c: sorted(v, key=lambda n: years[n]) for c, v in pool.items()}
    cat_years = {c: [years[n] for n in v] for c, v in by_cat.items()}
    # When the occupation is known it is the constraint that matters, and it does
    # not respect the corpus's category buckets: Matti Nykanen's row is filed
    # under `history`, so a per-category search found him no ski-jumper
    # contemporaries — while the very next row about him offers three, because
    # they sit under `sports`. Occupation-matched draws search everyone.
    everyone = sorted({n for v in pool.values() for n in v}, key=lambda n: years[n])
    all_years = [years[n] for n in everyone]

    fixed = refused = 0
    examples, refusals = [], []
    by_reason = collections.Counter()
    drop = set()
    for q in rows:
        opts, ci = q[2], q[3]
        if not opts or len(opts) < 4 or not (0 <= ci < len(opts)):
            continue
        if not all(str(o) in years for o in opts):
            continue
        ys = [years[str(o)] for o in opts]
        if max(ys) - min(ys) <= MAX_SPAN:
            continue

        answer = str(opts[ci])
        target = years[answer]
        # (chosen below, once we know whether an occupation is available)
        # Never reuse the answer, anything already on screen, or a name the
        # prompt hands the player.
        banned = {fold(o) for o in opts}
        prompt_words = sig(q[1])

        # Same walk of life is the requirement; era is the tie-break. A round of
        # four ski jumpers born decades apart is a real question. A round of four
        # contemporaries drawn from unrelated trades is not, however narrow the
        # date range — that is what the first version of this shipped.
        want = occ.get(answer)
        kin = KIN.get(want, {want}) if want else None
        names, yrs = ((everyone, all_years) if kin
                      else (by_cat.get(q[4], []), cat_years.get(q[4], [])))
        chosen = None
        for w in WINDOWS:
            lo = bisect.bisect_left(yrs, target - w)
            hi = bisect.bisect_right(yrs, target + w)
            cands = [n for n in names[lo:hi]
                     if fold(n) not in banned and not (sig(n) & prompt_words)
                     and (kin is None or occ.get(n) in kin)]
            if len(cands) >= 3:
                chosen = RNG.sample(cands, 3)
                break
        if not chosen:
            # Cannot be repaired, and shipping it means three of four options are
            # eliminable from the clue's era alone. 44 rows out of 128,632 is a
            # cheaper price than a question that plays itself — and most have a
            # sibling row about the same subject that survives.
            drop.add(q[0])
            refused += 1
            by_reason[("no occupation" if want is None else want)] += 1
            if len(refusals) < 6:
                refusals.append(
                    f"{q[0]}: {answer} ({target}, {want or 'occupation unknown'}) — "
                    f"too few {q[4]} contemporaries in the same line of work")
            continue

        before = list(opts)
        new = list(chosen)
        new.insert(ci, answer)          # the answer keeps its position
        q[2] = new[:4] if len(new) > 4 else new
        fixed += 1
        if len(examples) < 4:
            examples.append((q[1][:60], before, q[2], answer))

    print(f"era-spread violations repaired: {fixed}")
    print(f"refused (left alone rather than half-fixed): {refused}")
    for p, b, n, ans in examples:
        print(f"\n   {p}...\n     was: {b}\n     now: {n}   (answer {ans})")
    for r in refusals:
        print(f"   REFUSED {r}")
    if by_reason:
        print("\n   refusals by the answer's line of work:",
              dict(by_reason.most_common(8)))

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    kept = [q for q in rows if q[0] not in drop]
    body = json.dumps(kept, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(f'{{"version":"{data["version"]}","count":{len(kept)},"questions":{body}}}')
    print(f"dropped {len(rows) - len(kept)} unrepairable rows")
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
