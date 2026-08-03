"""When the answer is the only name you don't recognise, the clue is decoration.

Found by playing, on a Sports round:

    A five-star recruit who reclassified to join the G League Ignite instead of
    college, this Congolese forward was picked seventh by the Golden State
    Warriors in 2021 and won a title as a rookie - who is he?

        Michael Jordan / LeBron James / Jonathan Kuminga / Kobe Bryant

Every specific in that clue is wasted. Three of the four options are among the
most famous basketball players who have ever lived and the fourth is a 2021
draft pick, so the answer is identifiable without reading a word of it.

Measured with QRank (the Wikidata popularity score already in
`corpus_source.sqlite`) across the 76,268 rounds where all four options have a
score, the answer is the LEAST famous option **40.3%** of the time against a 25%
baseline — and on `src:` rows, 56.7%.

Most of that skew is imperceptible: trivia asks about less-famous things, so the
answer sits slightly below its distractors and no player can see it. Only 8.6% of
rounds are even 2x dimmer than every distractor. What a player CAN see is the
tail, where the gap is an order of magnitude — Kuminga against Jordan, John
Harvey Kellogg against Einstein/Tesla/Jobs, Cilicia against Israel/Palestine/Gaza
Strip. That is 1,552 rounds and this fixes those.

The replacement distractors are peers by OCCUPATION (Wikidata `p106`), with a
QRank within 5x of the answer's, so no option stands out by fame.

A first version keyed on `p31` + category instead, which is far more coverage
(94% vs 65%) and produced this:

    In 1990 this British sports journalist became the first WOMAN to present...
      was  Priscilla Presley / Sofia Vergara / Elliot Page
      now  Alfred Lunt / William Kempe / Lynn Fontanne      <- two of them men

    One of the largest parasitoid wasps, this creature paralyzes its prey...
      now  Africanized bee / Ibex / Early modern human

`p31` for a person is "human" and for a wasp is "taxon", so the pool was every
human in the category and every organism in the corpus. That trades a fame tell
for a plausibility collapse, which is worse: a distractor a player can rule out
on sight removes a real option from the round. So this fixes only what it can fix
WELL — people with a known occupation — and leaves the rest for the gate to
report rather than damaging them.

Gender is matched whenever the prompt turns on it ("the first woman to..."), for
the same reason: an option that cannot be the answer is not a distractor. A
candidate named anywhere in the prompt or the reveal is never used, and the
answer keeps its position so nothing downstream shifts.

    python3 tools/corpus/fix_fame_tell.py [--apply] [--threshold 10]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import json
import pathlib
import re
import sqlite3
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import quality_gate as qg                                          # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SOURCE_DB = ROOT / "tools" / "corpus" / "corpus_source.sqlite"


# The prompt turns on the subject's gender, so an option of the wrong gender is
# eliminable on sight and is not a distractor at all.
GENDERED = re.compile(r"\b(woman|women|she|her|actress|female|"
                      r"man|men|he|his|actor|male)\b", re.I)


def load_pool():
    db = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    sub = {t: (q, p106 or "", g or "")
           for t, q, p106, g in db.execute(
               "select title, qrank, p106, gender from subject "
               "where qrank is not null")}
    db.close()
    return sub


def pick(cands, want, ideal):
    """Most specific shared occupation first, then closest in fame.

    A person carries several `p106` values and they are not equally informative.
    Rita Levi-Montalcini is a neuroscientist, a writer and a senator, so drawing
    from all three equally offered Diana Gabaldon and Martha Washington against an
    Italian Nobel neurobiologist. Ranking by how RARE the shared occupation is
    puts the neuroscientists first: "neuroscientist" describes few people,
    "writer" describes tens of thousands, and the rare one is the one that makes a
    distractor plausible.

    Ties break on title so a re-run picks the same three.
    """
    cands.sort(key=lambda c: (c[2], abs(c[0] / ideal - 1), c[1]))
    return [t for _, t, _ in cands[:want]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--threshold", type=float, default=10.0,
                    help="flag when every distractor is this many times more famous")
    ap.add_argument("--drop", action="store_true",
                    help="delete the flagged rounds that have no peer pool")
    a = ap.parse_args()

    sub = load_pool()
    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    # The gate's OWN era and nationality data, not a second copy of it. A first
    # run of this repair used neither and the gate rejected the result: 85 rounds
    # newly spanned 400+ years (Luther Burbank against Avempace, 855 years) and 3
    # newly had a nationality-unique answer, which is the same tell in another
    # form. Reading the gate's maps is what keeps the repair and the check from
    # drifting apart.
    years = qg.birth_years()
    nationality = {}
    for r in rows:
        d = qg.readable_description(r[6] or "", r[7])
        if d and d != "PERSON-BY-DATES":
            m = qg.NAT_IN_DESC.match(d)
            if m:
                nationality.setdefault(r[7], qg._nat_family(m.group(1)))

    by_occ = collections.defaultdict(list)
    for t, (q, p106, g) in sub.items():
        for occ in p106.split(","):
            if occ:
                by_occ[occ].append((q, t, g))

    fixed = skipped = 0
    examples = []
    unrepairable = []
    for r in rows:
        opts = r[2]
        if not isinstance(opts, list) or len(opts) != 4:
            continue
        ranks = [sub.get(str(o), (None,))[0] for o in opts]
        if any(x is None for x in ranks) or not ranks[r[3]]:
            continue
        ideal = ranks[r[3]]
        if min(ranks[i] for i in range(4) if i != r[3]) / ideal < a.threshold:
            continue

        ans = str(opts[r[3]])
        _, p106, gender = sub[ans]
        text = f"{r[1]}\n{r[6] or ''}"
        want_gender = gender if (gender and GENDERED.search(r[1])) else None

        # Keep the round inside the 400-year span the gate allows, anchored on
        # the ANSWER alone and banded at +/-200 so any two candidates are at most
        # 400 apart. A first version anchored on the spread of the EXISTING
        # options -- the very distractors being discarded -- so a round that was
        # already wide stayed wide, and 14 rounds survived the repair still
        # flagged (Constantine V at 552 years).
        anchor = years.get(str(ans))
        want_nat = nationality.get(ans)

        got = {}
        for occ in p106.split(","):
            if not occ:
                continue
            rarity = len(by_occ[occ])
            for q, t, g in by_occ[occ]:
                if t == ans or not (ideal / 5 <= q <= ideal * 5) or t in text:
                    continue
                if want_gender and g != want_gender:
                    continue
                # A nationality the answer does not share is the fame tell again,
                # wearing a passport.
                if want_nat and nationality.get(t) and nationality[t] != want_nat:
                    continue
                if anchor is not None:
                    y = years.get(t)
                    if y is None or abs(y - anchor) > 200:
                        continue
                if t not in got or rarity < got[t][1]:
                    got[t] = (q, rarity)
        if len(got) < 3:
            skipped += 1
            unrepairable.append(r[0])
            continue

        new = pick([(q, t, rare) for t, (q, rare) in got.items()], 3, ideal)
        before = list(opts)
        it = iter(new)
        r[2] = [opts[i] if i == r[3] else next(it) for i in range(4)]
        fixed += 1
        if len(examples) < 6:
            examples.append((r[1][:66], ans, before, r[2]))

    print(f"rounds where every distractor is >={a.threshold:g}x more famous "
          f"than the answer: {fixed + skipped:,}")
    print(f"  distractors replaced with peers: {fixed:,}")
    print(f"  left alone (no occupation peers): {skipped:,}")
    for prompt, ans, before, after in examples:
        print(f"\n   {prompt}...\n     answer  {ans}"
              f"\n     was     {[o for o in before if o != ans]}"
              f"\n     now     {[o for o in after if o != ans]}")

    if a.drop and unrepairable:
        dead = set(unrepairable)
        rows = [r for r in rows if r[0] not in dead]
        print(f"  DROPPED the {len(dead):,} with no peer pool "
              f"({len(data['questions']):,} -> {len(rows):,})")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
