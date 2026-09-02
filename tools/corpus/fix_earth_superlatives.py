"""Superlatives that include Earth itself as an option.

    Which of these four has the most people?
      Western Europe / Nepal / Earth / North India      -> Earth

Earth is not a comparable place; it is the sum of every other option. The
question looks like a comparison and cannot be one, which is the "feels false"
shape the owner asked to remove -- and unlike a merely easy question it teaches
nothing and wastes all four slots.

SCOPE, deliberately narrow. A sweep for "the answer is a wholly larger KIND than
every distractor" returns 65 rows, but reading them shows most are fine: "most
populous: Africa / Eastern Europe / Siberia / Central Asia" and "largest by area:
Europe / Holland / Gaza Strip / Bengal" are easy, and easy is not the complaint.
The owner objected to ambiguity and gotchas. Only Earth is categorically not a
peer of its options, so only Earth is acted on.

(That 65-row sweep also had to be rewritten once: the first scale classifier put
subdivisions before cities and matched \\bcounty\\b against "county seat", filing
San Francisco, Houston and Hamburg as subdivisions -- 170 false positives. And it
returned 0 at first because "Western Europe" and "North India" are typed as a
bare `region`, which the scale did not cover, so the rows were skipped as
unclassifiable rather than flagged.)

Earth is REPLACED, not the row deleted: a same-kind option of comparable scale
keeps the question, so "most people: Western Europe / Nepal / North India /
South America" is a real comparison.
"""
import json
import random
import re
import sqlite3
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
LABELS = ROOT / "tools" / "corpus" / "p31_labels.json"
EARTH = "Earth"
PEER_RX = re.compile(r"\bcontinent\b|subcontinent|\bregion\b", re.I)


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    labels = json.loads(LABELS.read_text())
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    p31, q2t = {}, {}
    for q, t, pp in con.execute("select qid, title, p31 from subject"):
        q2t[q] = t
        p31[t] = set(c for c in (pp or "").split(",") if c)
    val = {}
    for qid, prop, v in con.execute(
            "select qid, prop, value from fact where kind='num'"):
        t = q2t.get(qid)
        if t and v is not None:
            val.setdefault((t, prop), float(v))

    def is_peer(t):
        return bool(PEER_RX.search(" ".join(labels.get(c, c) for c in p31.get(t, set()))))

    rows = [q for q in qs if q[0].startswith("sup:") and EARTH in q[2]]
    fixed, culled = [], []
    keep = []
    for q in qs:
        if q not in rows:
            keep.append(q)
            continue
        prop = q[0].split(":")[1]
        # The replacement must be a real peer AND must not beat the intended
        # answer, or swapping Earth out would silently change who wins.
        others = [o for o in q[2] if o != EARTH]
        best_other = max(others, key=lambda o: val.get((o, prop), 0))
        ceiling = val.get((best_other, prop), 0)
        cands = [t for (t, p), v in val.items()
                 if p == prop and t not in q[2] and is_peer(t) and 0 < v < ceiling]
        if not cands:
            culled.append(q)
            continue
        pick = sorted(cands)[random.Random(q[0]).randrange(len(cands))]
        i = q[2].index(EARTH)
        q[2][i] = pick
        q[3] = q[2].index(best_other)
        fixed.append((q[1], q[2], q[2][q[3]]))
        keep.append(q)

    print(f"rows containing Earth: {len(rows)}   repaired: {len(fixed)}   culled: {len(culled)}")
    for p, opts, ans in fixed:
        print(f"    {p[:40]:42} {opts}  -> {ans}")
    if not (fixed or culled):
        print("nothing to do")
        return
    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for q in culled:
        tomb[q[0]] = "compared Earth itself against places; no peer replacement available"
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
