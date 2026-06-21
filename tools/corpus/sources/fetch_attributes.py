#!/usr/bin/env python3
"""Stage B.3 — sex-or-gender (P21) per subject (Decision 032).

Enables GENDER-matched distractors: a clue like "American actress (born 1958)"
must have actress distractors, else the answer is guessable by elimination
(Sharon Stone was the only woman among 3 men). Targeted batched fetch.

Writes subject.gender ('f' / 'm' / None). Run after enrich_subjects.py.

Usage: python3 fetch_attributes.py
"""
import os, sqlite3, sys, time, json, urllib.parse, urllib.request

WD = "https://www.wikidata.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
GENDER = {"Q6581072": "f", "Q6581097": "m"}   # female / male (others left None)

_last = [0.0]
def _throttle(mi=0.12):
    w = mi - (time.monotonic() - _last[0])
    if w > 0: time.sleep(w)
    _last[0] = time.monotonic()

def wd(qids, retries=6):
    p = {"action": "wbgetentities", "ids": "|".join(qids), "format": "json",
         "props": "claims", "languages": "en", "maxlag": "5"}
    url = WD + "?" + urllib.parse.urlencode(p)
    for attempt in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return json.load(urllib.request.urlopen(req, timeout=45)).get("entities", {})
        except Exception:
            if attempt == retries - 1: raise
            time.sleep(2 ** attempt)


def main():
    con = sqlite3.connect(DB)
    if not any(r[1] == "gender" for r in con.execute("PRAGMA table_info(subject)")):
        con.execute("ALTER TABLE subject ADD COLUMN gender TEXT")
    qids = [r[0] for r in con.execute("SELECT qid FROM subject WHERE keep=1")]
    print(f"fetching P21 for {len(qids):,} subjects…")
    done = 0
    for i in range(0, len(qids), 50):
        batch = qids[i:i + 50]
        ent = wd(batch)
        for qid in batch:
            claims = ent.get(qid, {}).get("claims", {})
            g = None
            for c in claims.get("P21", [])[:1]:
                tq = c.get("mainsnak", {}).get("datavalue", {}).get("value", {}).get("id")
                g = GENDER.get(tq)
            if g:
                con.execute("UPDATE subject SET gender=? WHERE qid=?", (g, qid))
        con.commit()
        done += len(batch)
        if (i // 50) % 20 == 0:
            print(f"  …{done}/{len(qids)}")
    f = con.execute("SELECT COUNT(*) FROM subject WHERE gender='f'").fetchone()[0]
    m = con.execute("SELECT COUNT(*) FROM subject WHERE gender='m'").fetchone()[0]
    print(f"\ngender: {f:,} female / {m:,} male / {len(qids)-f-m:,} none (non-people or unset)")
    con.close()


if __name__ == "__main__":
    main()
