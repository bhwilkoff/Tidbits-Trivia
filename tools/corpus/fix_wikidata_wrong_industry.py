"""Two industry answers that are wrong IN WIKIDATA, and four unverifiable class rows.

WHAT THE P452 FETCH ACTUALLY SETTLED. `biz:industry` had no local ground truth at
all (the relation table held 0 industry rows), so every check over it returned a
meaningless clean. `fetch_industry.py` fixed that: 169 of the 236 rows are now
verifiable, and against Wikidata only 6 answers mismatch -- all six being LABEL
VARIANTS ("telecommunications" vs "telecommunications industry", "financial
services" vs "financial service activities, except insurance..."). By that
measure the family is faithful, and the 2-in-16 rate I saw by eye is NOT the real
rate. Measuring beat extrapolating, which is why the sample was never projected.

BUT FETCHING A SOURCE CANNOT FIX AN ERROR THAT IS IN THE SOURCE. The two rows I
found by reading are faithful reproductions of Wikidata, and Wikidata is wrong:

    Which industry does Gainax belong to?  -> "copyright collective"
        Wikidata's P452 for Gainax (Q834328) literally is "copyright collective".
        Gainax is an ANIME STUDIO, and "anime industry" appears as a distractor
        elsewhere in this very family.
    What industry is Avianca in?  -> "aircraft industry"
        Wikidata's P452 for Avianca (Q308911) is "aircraft industry". Avianca is
        an AIRLINE; "air transport" is used correctly for Aegean Airlines and EL
        AL two rows away. An aircraft industry builds planes; an airline flies
        them.

A PROSE CROSS-CHECK WAS TRIED AND REJECTED as too noisy to automate: requiring
the answer's key word to appear in the company's own lead flags 50 rows, and
roughly 48 are synonym mismatches, not errors -- "Ferrari -> automotive industry"
against a lead that says "sports car manufacturer", "ExxonMobil -> petroleum
industry" against "oil and gas", "Stanford -> higher education" against "research
university". Same verdict as the prose population extractor: ship the reading,
not the regex. So these two rows are fixed BY NAME, as the individual defects
they are, and no sweep is built around them.

ALSO: four `class:*` rows whose marked answer is not in its own asserted class
(Charles Perkins as a professional footballer, Stephen Gray as an astronomer,
William Walker as a journalist, Mark Wright as a professional footballer). These
are pre-existing, almost certainly ambiguous names resolving to a different
person, and NONE of the four subjects has a Wikipedia lead in the corpus to
adjudicate with. An answer that cannot be verified as correct is not an answer,
so they are culled rather than guessed at.
"""
import json
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

# subject -> (wrong answer string, correct answer string)
INDUSTRY = {
    "Gainax": ("copyright collective", "anime industry"),
    "Avianca": ("aircraft industry", "air transport"),
}
CULL_CLASS = {
    "class:Q937857:87572012727": "marked answer 'Charles Perkins' is not a professional footballer per p106, and the subject has no lead to verify against",
    "class:Q11063:828099178974": "marked answer 'Stephen Gray' is not an astronomer per p106, and the subject has no lead to verify against",
    "class:Q1930187:243763836648": "marked answer 'William Walker' is not a journalist per p106, and the subject has no lead to verify against",
    "class:Q937857:213395966390": "marked answer 'Mark Wright' is not a professional footballer per p106, and the subject has no lead to verify against",
}


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    present = {q[0] for q in qs}
    missing = [i for i in CULL_CLASS if i not in present]
    if missing:
        print(f"WARNING: class ids absent from the corpus: {missing}")

    fixed, culled = [], []
    keep = []
    for q in qs:
        if q[0] in CULL_CLASS:
            culled.append((q[0], q[1], q[2][q[3]]))
            continue
        s = q[7] if len(q) > 7 else None
        if q[0].startswith("biz:industry") and s in INDUSTRY:
            wrong, right = INDUSTRY[s]
            if wrong in q[2] and right not in q[2]:
                q[2][q[2].index(wrong)] = right
                if q[6]:
                    q[6] = q[6].replace(wrong, right)
                fixed.append((s, q[1], wrong, right))
        keep.append(q)

    print(f"industry answers corrected: {len(fixed)}")
    for s, p, w, r in fixed:
        print(f"    {p[:44]:46} {w!r} -> {r!r}")
    print(f"\nunverifiable class rows culled: {len(culled)}")
    for qid, p, a in culled:
        print(f"    {p[:46]:48} marked={a}")
    if not (fixed or culled):
        print("\nnothing to do")
        return

    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for qid, _, _ in culled:
        tomb[qid] = CULL_CLASS[qid]
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
