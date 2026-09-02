"""Re-derive superlative answers from the REFRESHED population and area data.

`refresh_population_facts.py` replaced 2,275 stale values in the source DB and
converted 58 square-metre areas, but it does not touch the corpus: every
`sup:P1082` / `sup:P2046` question stored an answer index computed from the OLD
numbers. Fixing the data without re-deriving the answers leaves the corpus
disagreeing with its own source -- the United States now correctly holds
340,110,988 people while a question still says Ming dynasty is more populous.

This is the repair that `audit_stale_population_answers.py` refused to make from
a regex over Wikipedia prose, and it is safe now for the reason that one was not:
the numbers are Wikidata's own current statements, fetched with the latest
point-in-time qualifier, not a figure scraped out of whichever sentence happened
to mention a population. The audit's failures are the argument for this tool --
it read Indiana as 2,000,000 from a sentence about Indianapolis; the refresh has
Indiana at 6,785,528.

Ties are left alone: if two options hold the same value the question has two
correct answers and repointing would be arbitrary.
"""
import json
from hashlib import md5
from pathlib import Path
import sqlite3

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
PROPS = ("P1082", "P2046", "P2044", "P2043")
MIN_WORDS = ("smallest", "fewest", "least", "lowest", "shortest", "tiniest")


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    q2t = {q: t for q, t in con.execute("select qid, title from subject")}
    val = {}
    for qid, prop, v in con.execute(
            "select qid, prop, value from fact where kind='num'"):
        t = q2t.get(qid)
        if t and v is not None:
            val.setdefault((t, prop), float(v))

    fixed, tied = [], 0
    for q in qs:
        fam = q[0].split(":")[0]
        prop = q[0].split(":")[1] if ":" in q[0] else ""
        if fam != "sup" or prop not in PROPS:
            continue
        vals = [val.get((o, prop)) for o in q[2]]
        if any(v is None for v in vals):
            continue
        want_min = any(w in q[1].lower() for w in MIN_WORDS)
        best = min(range(4), key=lambda i: vals[i]) if want_min \
            else max(range(4), key=lambda i: vals[i])
        if vals.count(vals[best]) > 1:
            tied += 1
            continue
        if vals[q[3]] != vals[best]:
            fixed.append((q[1], q[2][q[3]], vals[q[3]], q[2][best], vals[best]))
            q[3] = best

    print(f"answers re-derived from refreshed data: {len(fixed)}")
    for p, was, wv, now, nv in fixed[:14]:
        print(f"    {p[:40]:42} {was} ({wv:,.0f})  ->  {now} ({nv:,.0f})")
    print(f"\nleft alone -- two options tie: {tied}")
    if not fixed:
        print("nothing to do")
        return
    doc["count"] = len(qs)
    doc["version"] = md5(json.dumps(
        qs, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\nversion {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
