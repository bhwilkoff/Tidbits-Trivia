"""Chronology comparisons where the answer is obvious without any knowledge.

    Which of these four was founded earliest?
      The Wonderful Wizard of Oz (1900) / Mein Kampf (1924) / Animal Farm (1945)
      / the Quran (631)

    Who among these four was born earliest?
      Sheikh Hasina (1947) / Vyacheslav Volodin (1964) / Katalin Novak (1977)
      / John the Evangelist (10)

Nobody needs to know anything to answer these. The question LOOKS like a
comparison and is not one, which is the "feels false" shape the owner asked to
be removed -- and it wastes one of the four slots a good chronology question has.

THE RAW DATE GAP IS NOT THE DEFECT, and measuring it that way would have culled
some of the best questions in the family. Reading both sides of the boundary
first: at a 400-600 year gap sit "Kabul (1200) / Tripoli (601) / Luanda (1575) /
Taipei (1709)" and "Oxford (1000) / Edinburgh (601) / Iasi (1408) / Darmstadt
(1330)" -- genuinely hard, genuinely good. At a 40-80 year gap sits "Finnegans
Wake (1923) / The Count of Monte Cristo (1844) / The Outsiders (1967)", also
good. 2,706 rows have a gap over a century and nearly all of them are fine.

What actually breaks a row is ERA INCONGRUITY: the answer is ancient and EVERY
other option is modern, so the outlier is recognisable on sight. Measured as
answer < 1000 AD while every distractor is > 1700: 288 rows.

REPAIRED, NOT CULLED, wherever a same-era pool exists. The three modern
distractors are replaced with subjects of the SAME corpus category whose dates
fall between the answer's year and 800 years later -- so the answer is still
correct, still earliest, and the comparison is now real. Selection is seeded by
the question id so a rerun is a no-op rather than a reshuffle.

Where the pool cannot support it the row is CULLED instead: there are essentially
no pre-1500 subjects in `screen`, `music`, `sports` or `business` (2 to 7 each,
against 479 in history and 362 in geography), so inventing a comparison there
would mean reaching for subjects nobody recognises -- trading one bad question
for another.

A SECOND, WORSE DEFECT SURFACED ONCE BC DATES PARSED CORRECTLY: 62 chronology
rows whose MARKED ANSWER IS NOT THE EARLIEST by the corpus's own dates.

    Which of these came out first?   marked "Mario" (1981)   vs FIFA (1904)
    Which of these four is the oldest?  marked "Alice" (1865) vs Sherlock Holmes (1854)
    Which of these four appeared earliest?  marked "Constitution of India" (1949)
                                            vs the New Testament (100)

They are a mix of true ordering errors, incoherent comparisons (a video-game
character against a football federation; a company's founding against a person's
birth) and bad source dates (Sherlock Holmes's date is his FICTIONAL birth year,
not a publication date). Which of the three it is does not change what to do: a
question whose marked answer contradicts the very dataset it was generated from
cannot be trusted, and there is no repair that is safe to apply blind. Those rows
are CULLED, along with one row where two options tie for earliest and the
question therefore has two correct answers.

The 40-rule quality gate is the backstop, and it EARNED that role: the first
version of this repair matched only on category and era, and the gate rejected
the result with 9 FAME-TELL and 7 KIND-MISMATCH hits. Matching on category is not
enough, because "history" holds people, kingdoms and buildings at every level of
fame:

    ['Johann Pachelbel', 'Antonio Vivaldi', 'Handel', 'Gregorian chant']
        -- a musical tradition among three composers
    ['Edward I', 'Kingdom of France', 'Kingdom of Hungary', 'Stephen Bathory']
        -- two people among two kingdoms
    ['Haarlem', 'Brihadisvara Temple', 'Denmark', 'Bastille']
        -- a whole country, 10x more famous than anything beside it

So a distractor must now also match the answer's KIND (person / place / work /
organisation / other, read from p31) and sit within a fame BAND of it, so no
option stands out by recognition alone. Trading one guessable question for a
differently guessable question is not a repair.
"""
import json
import random
import re
import sqlite3
from collections import defaultdict
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"

ANCIENT, MODERN = 1000, 1700   # answer below / every distractor above
WINDOW = 800                   # distractors may be up to this much later
FAME_FLOOR = 300_000           # a distractor nobody knows is not a fair option
FAME_BAND = 6                  # distractor fame must be within this factor of the answer's

KIND_RX = (
    ("person", r"\bhuman\b|\bperson\b"),
    ("work", r"\bfilm\b|\balbum\b|\bsong\b|\bnovel\b|\bbook\b|\bpainting\b|"
             r"\bsymphony\b|\bcomposition\b|\bsculpture\b|\bpoem\b|\bplay\b|"
             r"\bwritten work\b|\bliterary work\b|\bmanuscript\b"),
    ("org", r"\bbusiness\b|\bcompany\b|\benterprise\b|\borganization\b|\bband\b|"
            r"\bclub\b|\bteam\b|\buniversity\b|\bparty\b|\bbank\b|\bdynasty\b|"
            r"\border\b|\binstitution\b"),
    ("place", r"\bcity\b|\bcountry\b|\bstate\b|\btown\b|\bregion\b|\bsettlement\b|"
              r"\bisland\b|\bkingdom\b|\bempire\b|\bvillage\b|\bmunicipality\b|"
              r"\bbuilding\b|\btemple\b|\bchurch\b|\bcastle\b|\bmonument\b"),
)


def kind_of(title, p31, labels):
    names = " ".join(labels.get(c, c) for c in p31.get(title, set())).lower()
    for k, rx in KIND_RX:
        if re.search(rx, names):
            return k
    return "other"



def gate_kind_map(rows):
    """The QUALITY GATE's own notion of kind, not a private one.

    An earlier version of this repair classified subjects with its own regex over
    p31 labels, and the gate then rejected the result: my classifier and its
    classifier disagreed, so a "same-kind" swap produced 'Metamorphoses' among
    what the gate reads as places. Two classifiers is one too many -- ask the
    component that will judge the answer.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "quality_gate", str(Path(__file__).resolve().parent / "quality_gate.py"))
    qg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qg)
    return qg.kind_map(rows)


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    labels = json.loads((ROOT / "tools/corpus/p31_labels.json").read_text())
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    p31 = {t: set(c for c in (pp or "").split(",") if c)
           for t, pp in con.execute("select title, p31 from subject")}
    q2t, fame = {}, {}
    for q, t, r in con.execute("select qid, title, qrank from subject"):
        q2t[q] = t
        try:
            fame[t] = int(r or 0)
        except (TypeError, ValueError):
            fame[t] = 0
    year = {}
    for qid, prop, val in con.execute(
            "select qid, prop, value from fact where prop in ('P571','P577','P569')"):
        t = q2t.get(qid)
        if not t or not val:
            continue
        # BC dates are stored as NEGATIVE FLOATS (-1274.0 for Abu Simbel). An
        # earlier version of this matched "-1274" with the regex AND THEN negated
        # it again for the leading minus, turning every BC date into the same AD
        # year. That is not a cosmetic bug: it put Abu Simbel (1274 BC) into an
        # option set as 1274 AD, which would have shipped "which dates back
        # furthest?" with Hagia Sophia (537 AD) marked correct over it.
        try:
            y = int(float(val))
        except (TypeError, ValueError):
            continue
        year.setdefault(t, y)

    cat = {}
    for q in qs:
        s = q[7] if len(q) > 7 else None
        if s and s not in cat:
            cat[s] = q[4]
    pool = defaultdict(list)
    for t, y in year.items():
        if fame.get(t, 0) >= FAME_FLOOR and t in cat:
            pool[cat[t]].append((y, t))

    gkind = gate_kind_map(qs)
    repaired, culled, unordered, tied = [], [], [], []
    keep = []
    for q in qs:
        if not q[0].startswith("chron:"):
            keep.append(q)
            continue
        ys = [year.get(o) for o in q[2]]
        if any(y is None for y in ys):
            keep.append(q)
            continue
        ans_t, ans_y = q[2][q[3]], ys[q[3]]
        others = [y for i, y in enumerate(ys) if i != q[3]]
        # The marked answer must actually be the earliest, and uniquely so.
        if min(others) < ans_y:
            unordered.append((q[0], q[1], ans_t, ans_y,
                              q[2][min(range(4), key=lambda i: ys[i])], min(ys)))
            continue
        if min(others) == ans_y:
            tied.append((q[0], q[1], ans_t, ans_y))
            continue
        if not (ans_y < ANCIENT and min(others) > MODERN):
            keep.append(q)
            continue

        ans_kind = kind_of(ans_t, p31, labels)
        ans_fame = max(fame.get(ans_t, 0), 1)
        cands = [t for y, t in pool.get(q[4], [])
                 if ans_y < y <= ans_y + WINDOW and t != ans_t
                 and kind_of(t, p31, labels) == ans_kind
                 and (gkind.get(t) is None or gkind.get(ans_t) is None
                      or gkind.get(t) == gkind.get(ans_t))
                 and ans_fame / FAME_BAND <= max(fame.get(t, 0), 1) <= ans_fame * FAME_BAND]
        if len(cands) < 3:
            culled.append((q[0], q[1], ans_t, ans_y, q[4]))
            continue
        rng = random.Random(q[0])
        picks = rng.sample(sorted(cands), 3)
        opts = [ans_t] + picks
        rng.shuffle(opts)
        before = list(q[2])
        q[2] = opts
        q[3] = opts.index(ans_t)
        repaired.append((q[0], q[1][:38], before, [(o, year.get(o)) for o in opts]))
        keep.append(q)

    print(f"REPAIRED (same-era distractors): {len(repaired)}")
    for qid, p, before, after in repaired[:10]:
        print(f"    {p}\n       was {[(o, year.get(o)) for o in before]}\n       now {after}")
    print(f"\nCULLED: answer is NOT the earliest by the corpus's own dates: {len(unordered)}")
    for qid, p, t, y, tt, ty in unordered[:10]:
        print(f"    {p[:34]:36} marked={t} ({y})  TRUE={tt} ({ty})")
    print(f"\nCULLED: two options tie for earliest: {len(tied)}")
    for qid, p, t, y in tied:
        print(f"    {p[:34]:36} {t} ({y})")
    print(f"\nCULLED (no same-era pool in that category): {len(culled)}")
    for qid, p, t, y, c in culled[:10]:
        print(f"    [{c}] {p[:40]:42} answer={t} ({y})")

    if not (repaired or culled or unordered or tied):
        print("\nnothing to do")
        return
    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for qid, p, t, y, tt, ty in unordered:
        tomb[qid] = (f"chronology answer '{t}' ({y}) is not the earliest: "
                     f"'{tt}' ({ty}) predates it by the corpus's own dates")
    for qid, p, t, y in tied:
        tomb[qid] = f"two options tie for earliest ({y}), so the question has two answers"
    for qid, p, t, y, c in culled:
        tomb[qid] = (f"era-incongruous chronology: answer '{t}' ({y}) against all-modern "
                     f"options, and category '{c}' has no same-era pool to repair with")
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
