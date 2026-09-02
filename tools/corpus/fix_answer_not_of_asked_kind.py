"""Four rows whose correct answer is not the KIND of thing the question asks for.

Found by sweeping two whole templates and finding them almost entirely healthy,
which is the point: measuring first is what keeps a four-row repair from becoming
a four-hundred-row cull.

  `wd:continent:` -- 1,001 rows, and the answer is one of the seven continents in
  998 of them. THREE answer with something that is not a continent at all, so the
  question cannot be answered correctly as asked:

     Which continent is Niue part of?              -> "Insular Oceania"
     Which continent is the Cook Islands part of?  -> "Insular Oceania"
     Which continent is Kashmir Sultanate part of? -> "Indian subcontinent"

  These are CULLED rather than repointed because the right answer is not among
  the options to repoint to: Niue's and the Cook Islands' options contain no
  "Oceania", and Kashmir Sultanate's contain no "Asia". (Both strings also appear
  as DISTRACTORS on 9 further rows. Those are left: an implausible wrong option
  is a weak question, not a wrong one, and the answer there is still a continent.)

  `fact:P571:` -- 993 founded-date rows, and they are fine. Businesses, bands,
  football clubs, cities, empires, republics and dynasties are all founded, so
  the "founded date for something never founded" class this sweep went looking
  for does not exist here. ONE row asks it of a PEOPLE, which is not founded:

     In what year was Xiongnu founded?  -> 300 BC

  One row is not a class. It is fixed, and no sweep is built around it.

A note on the sweep that found the continent rows: an earlier regex flagged 49
"non-founded" subjects that were all false positives, because \\bsea\\b-less
patterns matched inside words -- "sea" in `Hanseatic` and `county seat`, "human"
in `human settlement`, "person" in `personal union`. Every one was a city, and
cities are founded. Word boundaries took it to 12, and reading those took it to 1.
"""
import json
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

CULL = {
    "wd:continent:54125299532558":
        "asks which CONTINENT but answers 'Insular Oceania'; no 'Oceania' option to repoint to",
    "wd:continent:25425376106032":
        "asks which CONTINENT but answers 'Insular Oceania'; no 'Oceania' option to repoint to",
    "wd:continent:61967864409962":
        "asks which CONTINENT but answers 'Indian subcontinent'; no 'Asia' option to repoint to",
    "fact:P571:Q188836":
        "the Xiongnu were a people, and a people is not founded",
}


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    seen = {q[0] for q in qs}
    missing = [i for i in CULL if i not in seen]
    if missing:
        # Loud, because a silent no-op here reads exactly like a clean run.
        print(f"WARNING: {len(missing)} target ids are not in the corpus: {missing}")
    keep = [q for q in qs if q[0] not in CULL]
    if len(keep) == len(qs):
        print("nothing to do")
        return
    for q in qs:
        if q[0] in CULL:
            print(f"culled: {q[1]} -> {q[2][q[3]]}")
    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for qid, why in CULL.items():
        tomb[qid] = why
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
