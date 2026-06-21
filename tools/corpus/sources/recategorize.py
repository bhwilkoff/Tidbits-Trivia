#!/usr/bin/env python3
"""Re-categorize subjects OFFLINE from stored P31/P106 (Decision 032).

Because enrich_subjects.py banks each subject's P31/P106 type QIDs in the DB, the
category map can be iterated to high coverage WITHOUT re-fetching Wikidata: edit
the maps in enrich_subjects.py, run this, inspect the top remaining unmapped
types, repeat. Resolves labels for only the top-N unmapped types (one small call).

Usage: python3 recategorize.py
"""
import os, sqlite3, sys, json, urllib.parse, urllib.request
from collections import Counter

sys.path.insert(0, os.path.dirname(__file__))
from enrich_subjects import categorize

DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
WD = "https://www.wikidata.org/w/api.php"; UA = "TidbitsTrivia/1.0 (ben@learningischange.com)"


def labels(qids):
    if not qids:
        return {}
    p = {"action": "wbgetentities", "ids": "|".join(qids), "format": "json",
         "props": "labels", "languages": "en"}
    req = urllib.request.Request(WD + "?" + urllib.parse.urlencode(p), headers={"User-Agent": UA})
    ent = json.load(urllib.request.urlopen(req, timeout=40)).get("entities", {})
    return {q: e.get("labels", {}).get("en", {}).get("value", "?") for q, e in ent.items()}


def main():
    con = sqlite3.connect(DB)
    rows = con.execute("SELECT qid, title, p31, p106 FROM subject WHERE keep=1").fetchall()
    dist = Counter()
    unmapped_type = Counter(); ex = {}
    for qid, title, p31s, p106s in rows:
        p31 = (p31s or "").split(",") if p31s else []
        p106 = (p106s or "").split(",") if p106s else []
        p31 = [x for x in p31 if x]; p106 = [x for x in p106 if x]
        cat = categorize(p31, p106)
        con.execute("UPDATE subject SET category=? WHERE qid=?", (cat, qid))
        dist[cat or "mixed"] += 1
        if cat is None:
            # blame the most specific available type
            for t in (p106 + p31):
                unmapped_type[t] += 1
                ex.setdefault(t, []).append(title)
                break
    con.commit()

    print("category distribution:", dict(sorted(dist.items(), key=lambda x: -x[1])))
    mixed = dist.get("mixed", 0)
    print(f"mixed: {mixed:,} / {len(rows):,} ({100*mixed//max(1,len(rows))}%)")
    top = [t for t, _ in unmapped_type.most_common(25)]
    lbl = labels(top)
    print("top unmapped types (add to OCCUPATION/INSTANCE to reduce 'mixed'):")
    for t, c in unmapped_type.most_common(25):
        print(f"  {c:>4}  {t} {lbl.get(t,'?')[:28]:28} e.g. {ex[t][:2]}")
    con.close()


if __name__ == "__main__":
    main()
