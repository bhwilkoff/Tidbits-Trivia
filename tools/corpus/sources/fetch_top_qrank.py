#!/usr/bin/env python3
"""Expansion — add the top-popularity Wikipedia subjects beyond Vital Articles
(Decision 032). The top Qrank entities ARE the most-searched topics, so this is
what makes "any top Wikipedia search" usable in Tidbits. Walks Qrank top→down,
skips subjects we already have, and enriches each new one exactly like
enrich_subjects.py (facts/dates/relations/image/aliases/gender/P31 + category +
appropriateness gate). Bounded by --add (default 12000) NEW subjects.

Requires an enwiki sitelink (so the article exists for prose/questions) and
applies the same adult-content + dedup gates. New rows get va_class='qrank'.

Usage: python3 fetch_top_qrank.py [--add 12000]
"""
import argparse, os, sqlite3, sys, time, json, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import enrich_subjects as E
from fetch_qrank import load_qrank

WD = "https://www.wikidata.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
BLOCK_TITLE = E.BLOCK_TITLE_SUBSTR

_last = [0.0]
def _throttle(mi=0.12):
    w = mi - (time.monotonic() - _last[0])
    if w > 0: time.sleep(w)
    _last[0] = time.monotonic()

def wd(qids, retries=6):
    p = {"action": "wbgetentities", "ids": "|".join(qids), "format": "json",
         "props": "labels|aliases|claims|sitelinks/urls", "languages": "en",
         "sitefilter": "enwiki", "maxlag": "5"}
    url = WD + "?" + urllib.parse.urlencode(p)
    for a in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return json.load(urllib.request.urlopen(req, timeout=50)).get("entities", {})
        except Exception:
            if a == retries - 1: raise
            time.sleep(2 ** a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--add", type=int, default=12000)
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    have = {r[0] for r in con.execute("SELECT qid FROM subject")}
    qrank = load_qrank()
    # candidate QIDs = Qrank top→down, not already a subject
    cand = [q for q, _ in sorted(qrank.items(), key=lambda kv: -kv[1]) if q not in have]
    print(f"have {len(have):,} subjects; {len(cand):,} Qrank candidates not yet held")

    cols = {r[1] for r in con.execute("PRAGMA table_info(subject)")}
    added = facts = rels = 0
    i = 0
    while added < args.add and i < len(cand):
        batch = cand[i:i + 50]; i += 50
        ent = wd(batch)
        for qid in batch:
            e = ent.get(qid)
            if not e:
                continue
            sl = e.get("sitelinks", {}).get("enwiki")
            if not sl or not sl.get("title"):
                continue                      # no English article → can't ask about it
            title = sl["title"]
            if ":" in title.split(" ")[0] and title.split(":")[0] in ("Category", "Template", "Wikipedia", "Portal", "List"):
                continue
            claims = e.get("claims", {})
            keep = 0 if any(s in title.lower() for s in BLOCK_TITLE) else 1
            p31 = [q for q in (E._mainsnak_qid(c) for c in claims.get("P31", [])) if q]
            p106 = [q for q in (E._mainsnak_qid(c) for c in claims.get("P106", [])) if q]
            cat = E.categorize(p31, p106)
            sitelinks = len(e.get("sitelinks", {}))
            aliases = [a.get("value") for a in e.get("aliases", {}).get("en", []) if a.get("value")]
            image = None
            for c in claims.get("P18", [])[:1]:
                image = E._mainsnak_image(c)
            g = None
            for c in claims.get("P21", [])[:1]:
                tq = E._mainsnak_qid(c); g = {"Q6581072": "f", "Q6581097": "m"}.get(tq)
            con.execute("""INSERT OR IGNORE INTO subject
                (qid,title,va_class,qrank,category,sitelinks,keep,p31,p106,image,aliases,gender)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                (qid, title, "qrank", qrank.get(qid, 0), cat, sitelinks, keep,
                 ",".join(p31[:6]), ",".join(p106[:6]), image,
                 json.dumps(aliases[:12], ensure_ascii=False), g))
            # facts + relations (reuse the same property maps)
            for p, (lbl, unit) in E.NUMERIC.items():
                for c in claims.get(p, [])[:1]:
                    v = E._mainsnak_quantity(c)
                    if v is not None:
                        con.execute("INSERT INTO fact VALUES (?,?,?,?,?,?)", (qid, p, lbl, v, unit, "num")); facts += 1
            for p, lbl in E.DATES.items():
                for c in claims.get(p, [])[:1]:
                    y = E._mainsnak_time(c)
                    if y is not None:
                        con.execute("INSERT INTO fact VALUES (?,?,?,?,?,?)", (qid, p, lbl, float(y), "year", "date")); facts += 1
            for p, lbl in E.RELATIONS.items():
                for c in claims.get(p, [])[:1]:
                    tq = E._mainsnak_qid(c)
                    if tq:
                        con.execute("INSERT INTO relation (qid,prop,label,target_qid) VALUES (?,?,?,?)", (qid, p, lbl, tq)); rels += 1
            added += 1
        con.commit()
        if (i // 50) % 20 == 0:
            print(f"  …scanned {i}, added {added}/{args.add}")

    print(f"\n=== EXPANSION ===\n  added {added:,} new subjects (va_class='qrank'); facts +{facts:,}, relations +{rels:,}")
    tot = con.execute("SELECT COUNT(*) FROM subject WHERE keep=1").fetchone()[0]
    print(f"  total kept subjects now: {tot:,}")
    con.close()


if __name__ == "__main__":
    main()
