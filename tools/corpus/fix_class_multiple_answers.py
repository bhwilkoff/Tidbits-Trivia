"""Classification questions with more than one correct answer.

    Pick the painter from these four.
      Zainul Abedin / Francis Bacon / Tarsila do Amaral / Viktor Vasnetsov

All four are painters. The question has four right answers and marks one, so
three players in four are told they are wrong for being right. That is the
purest form of the ambiguity the owner asked to be removed -- not a matter of
taste or difficulty, just a broken question.

41 of the 635 `class:*` rows are like this.

THE FIRST SWEEP FOUND ZERO, and the zero was my own blindness: I checked
membership against `p31`, but an occupation lives in `p106`. Of the 635 rows the
marked answer carries its class in p106 631 times and in p31 exactly 0 times, so
the check could not have fired for any row. Confirming which field actually
carries the signal, BEFORE believing a clean result, is what turned 0 into 41.

REPAIRED, not culled: each surplus member is swapped for a subject of comparable
FAME that is NOT in the class, drawn from the pool the corpus already uses, so
one option is a painter and three are not. A row is culled only if no clean
replacement exists.

A REPLACEMENT MUST BE THE SAME KIND OF THING. The first run drew from "any
subject the corpus asks about" and produced

    Which one below is best known as a physicist?
      Leslie Lamport / Luis Walter Alvarez / Shrek the Third / Al-Ahli Saudi FC

    Pick the painter from these four.
      Dutch colonial empire / On Her Majesty's Secret Service / Tarsila do Amaral / Nuuk

-- a film and a football club offered as candidate physicists. That is a worse
question than the ambiguity it replaced: the answer becomes obvious by kind
alone. The pool is now restricted to PEOPLE (anyone carrying an occupation, or
typed human), so the three wrong options are real people who simply are not
painters.

The quality gate is the backstop for the swap -- it independently checks
fame-tell and kind-mismatch on every option set rewritten here.
"""
import json
import random
import sqlite3
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
FAME_BAND = 8


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    p106, p31, fame = {}, {}, {}
    for t, a, b, r in con.execute(
            "select title, p106, p31, qrank from subject"):
        p106[t] = set(c for c in (a or "").split(",") if c)
        p31[t] = set(c for c in (b or "").split(",") if c)
        try:
            fame[t] = int(r or 0)
        except (TypeError, ValueError):
            fame[t] = 0

    def in_class(t, k):
        return k in p106.get(t, set()) or k in p31.get(t, set())

    # PEOPLE ONLY. An occupation question needs human distractors; see docstring.
    HUMAN = "Q5"
    pool = sorted({q[7] for q in qs if len(q) > 7 and q[7] and q[7] in fame
                   and (p106.get(q[7]) or HUMAN in p31.get(q[7], set()))})

    fixed, culled = [], []
    keep = []
    for q in qs:
        if not q[0].startswith("class:"):
            keep.append(q)
            continue
        k = q[0].split(":")[1]
        members = [i for i, o in enumerate(q[2]) if in_class(o, k)]
        if len(members) <= 1:
            keep.append(q)
            continue
        ans_fame = max(fame.get(q[2][q[3]], 0), 1)
        used = set(q[2])
        ok = True
        for i in members:
            if i == q[3]:
                continue                      # the intended answer stays
            cands = [t for t in pool
                     if t not in used and not in_class(t, k)
                     and ans_fame / FAME_BAND <= max(fame.get(t, 0), 1) <= ans_fame * FAME_BAND]
            if not cands:
                ok = False
                break
            pick = cands[random.Random(q[0] + q[2][i]).randrange(len(cands))]
            q[2][i] = pick
            used.add(pick)
        if not ok:
            culled.append((q[0], q[1]))
            continue
        fixed.append((q[1], q[2], q[2][q[3]]))
        keep.append(q)

    print(f"repaired (surplus class members swapped out): {len(fixed)}")
    for p, opts, ans in fixed[:12]:
        print(f"    {p[:40]:42} {opts}  -> {ans}")
    print(f"\nculled (no clean replacement): {len(culled)}")
    if not (fixed or culled):
        print("nothing to do")
        return
    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for qid, p in culled:
        tomb[qid] = "more than one option belonged to the asserted class; no clean replacement"
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
