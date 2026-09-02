"""The United States has no official language, so the question cannot be asked.

"Which of these is an official language of the United States?" -> English asserts
a federal fact that does not exist. Congress has never designated one; English is
official in many STATES by state statute, which is a different question and a
fair one. The generator built this row from a Wikidata P37 claim without the
distinction.

This is a WRONG row, not a weak one. An earlier pass over the same template left
the 28 US-language rows alone under "a weak question is not a wrong one" -- and
that was right for the states (Arizona, Iowa, Kansas, Nebraska, Utah, Wyoming,
Alabama, Florida, Alaska and California all really do have English official under
state law, and Puerto Rico really does have Spanish). It was wrong for the
federal row, which is the one row in the set that asks about a polity with no
answer. Reviewing a template as a block is what hid it: the 27 correct rows made
the 28th look like more of the same.

Only `rel:P37:Q30` is removed. No sweep: the states are fine, and the same
reasoning does not generalise to any other country in the template.
"""
import json
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
TARGET = "rel:P37:Q30"


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    keep = [q for q in qs if q[0] != TARGET]
    if len(keep) == len(qs):
        print("nothing to do")
        return
    for q in qs:
        if q[0] == TARGET:
            print(f"culled: {q[1]} -> {q[2][q[3]]}")
    doc["questions"] = keep
    doc.setdefault("tombstones", {}).setdefault("corpus", {})[TARGET] = (
        "the United States has no federally designated official language; "
        "English is official in many states, which is a different question")
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"{len(qs)} -> {len(keep)}   version {doc['version']}")


if __name__ == "__main__":
    main()
