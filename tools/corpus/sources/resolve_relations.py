#!/usr/bin/env python3
"""Stage B.2 — resolve relation target QIDs to English labels (Decision 032).

enrich_subjects.py stored 1:1 relations as (qid, prop, label, target_qid) — the
target is a bare QID (e.g. France's P36 capital = Q90). To turn these into Matching
rows (and real "what is the capital of X?" MCQs) we need the target's name. This
batch-resolves every distinct target QID once and writes relation.target_label,
so build_corpus.py can regenerate the wd:capital / wd:currency / wd:author rows
from the new source instead of carrying the old ones forward.

Usage: python3 resolve_relations.py
"""
import os, sqlite3, sys, time, json, urllib.parse, urllib.request

WD = "https://www.wikidata.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))

_last = [0.0]
def _throttle(mi=0.12):
    w = mi - (time.monotonic() - _last[0])
    if w > 0: time.sleep(w)
    _last[0] = time.monotonic()

def labels(qids, retries=6):
    p = {"action": "wbgetentities", "ids": "|".join(qids), "format": "json",
         "props": "labels", "languages": "en", "maxlag": "5"}
    url = WD + "?" + urllib.parse.urlencode(p)
    for attempt in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            ent = json.load(urllib.request.urlopen(req, timeout=45)).get("entities", {})
            return {q: e.get("labels", {}).get("en", {}).get("value") for q, e in ent.items()}
        except Exception:
            if attempt == retries - 1: raise
            time.sleep(2 ** attempt)


def main():
    con = sqlite3.connect(DB)
    if not any(r[1] == "target_label" for r in con.execute("PRAGMA table_info(relation)")):
        con.execute("ALTER TABLE relation ADD COLUMN target_label TEXT")
    targets = [r[0] for r in con.execute(
        "SELECT DISTINCT target_qid FROM relation WHERE target_qid IS NOT NULL AND target_label IS NULL")]
    print(f"resolving {len(targets):,} distinct relation targets…")
    done = 0
    for i in range(0, len(targets), 50):
        batch = targets[i:i + 50]
        lbl = labels(batch)
        for qid, name in lbl.items():
            if name:
                con.execute("UPDATE relation SET target_label=? WHERE target_qid=?", (name, qid))
        con.commit()
        done += len(batch)
        if (i // 50) % 10 == 0:
            print(f"  …{done}/{len(targets)}")
    have = con.execute("SELECT COUNT(*) FROM relation WHERE target_label IS NOT NULL").fetchone()[0]
    tot = con.execute("SELECT COUNT(*) FROM relation").fetchone()[0]
    print(f"\nresolved labels on {have:,}/{tot:,} relations")
    for prop, lbl, n in con.execute(
            "SELECT prop, label, COUNT(*) FROM relation WHERE target_label IS NOT NULL GROUP BY label ORDER BY 3 DESC LIMIT 10"):
        print(f"  {lbl:18} {n}")
    con.close()


if __name__ == "__main__":
    main()
