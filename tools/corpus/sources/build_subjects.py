#!/usr/bin/env python3
"""Build the SELECTION layer of the corpus source index (Decision 032, Phase 0).

Subject universe = Wikipedia **Vital Articles Level 5** gated to **quality > C**
(keep B / GA / A / FA), each resolved to a Wikidata QID and ranked by **Qrank**.
This replaces the old seed-search candidate selection: a curated, recognizable,
quality-filtered, popularity-ranked set instead of "whatever matched 70 seeds".

The L5 ∩ >C set comes straight from the per-class tracking categories
(`Category:<CLASS>-Class level-5 vital articles`), whose members are the article
talk pages — so the quality gate is free and exact.

Output: tools/corpus/corpus_source.sqlite, table `subject`
        (qid PK, title, va_class, qrank, category) — build-time only, not shipped.

Usage: python3 build_subjects.py [--refresh-qrank] [--limit N]
"""
import argparse, os, sqlite3, sys, time, urllib.parse, urllib.request, json

sys.path.insert(0, os.path.dirname(__file__))
from fetch_qrank import load_qrank

API = "https://en.wikipedia.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))

# Quality classes strictly above C (the gate). Ordered best→worst for dedup.
KEEP_CLASSES = ["FA", "A", "GA", "B"]
CLASS_RANK = {c: i for i, c in enumerate(KEEP_CLASSES)}  # lower = better

_last = [0.0]
def _throttle(min_interval=0.18):
    wait = min_interval - (time.monotonic() - _last[0])
    if wait > 0:
        time.sleep(wait)
    _last[0] = time.monotonic()

def api(params, retries=6):
    params = {**params, "format": "json", "maxlag": "5"}
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return json.load(urllib.request.urlopen(req, timeout=40))
        except Exception as e:
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)


def fetch_class_members(cls):
    """All article titles in Category:<cls>-Class level-5 vital articles (talk→article)."""
    cat = f"Category:{cls}-Class level-5 vital articles"
    titles, cont = [], None
    while True:
        p = {"action": "query", "list": "categorymembers", "cmtitle": cat,
             "cmlimit": "500", "cmtype": "page"}
        if cont:
            p["cmcontinue"] = cont
        d = api(p)
        for m in d.get("query", {}).get("categorymembers", []):
            t = m["title"]
            if t.startswith("Talk:"):
                titles.append(t[5:])
        cont = d.get("continue", {}).get("cmcontinue")
        if not cont:
            break
    return titles


def resolve_qids(titles):
    """title -> QID via pageprops (redirects normalized). Batched 50/call."""
    out = {}
    for i in range(0, len(titles), 50):
        batch = titles[i:i + 50]
        d = api({"action": "query", "titles": "|".join(batch),
                 "prop": "pageprops", "ppprop": "wikibase_item", "redirects": "1"})
        q = d.get("query", {})
        # follow redirects: map requested title via normalized/redirects to final page
        for page in q.get("pages", {}).values():
            qid = page.get("pageprops", {}).get("wikibase_item")
            if qid and page.get("title"):
                out[page["title"]] = qid
        if (i // 50) % 20 == 0:
            print(f"  …resolved {min(i+50, len(titles))}/{len(titles)} titles")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh-qrank", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="cap subjects (0 = keep all)")
    args = ap.parse_args()

    # 1) L5 ∩ >C: gather titles per class, keep best class on dup.
    best_class = {}
    for cls in KEEP_CLASSES:
        ts = fetch_class_members(cls)
        print(f"[VA L5] {cls}-Class: {len(ts)} articles")
        for t in ts:
            if t not in best_class or CLASS_RANK[cls] < CLASS_RANK[best_class[t]]:
                best_class[t] = cls
    titles = sorted(best_class)
    print(f"[VA L5] {len(titles)} distinct articles (quality > C)")

    # 2) resolve QIDs
    title_qid = resolve_qids(titles)
    print(f"[resolve] {len(title_qid)} of {len(titles)} titles have a QID")

    # 3) join Qrank
    qrank = load_qrank(refresh=args.refresh_qrank)

    # 4) build rows, dedup by QID (keep best class, then highest qrank)
    by_qid = {}
    for t in titles:
        qid = title_qid.get(t)
        if not qid:
            continue
        row = {"qid": qid, "title": t, "va_class": best_class[t], "qrank": qrank.get(qid, 0)}
        prev = by_qid.get(qid)
        if (prev is None
                or CLASS_RANK[row["va_class"]] < CLASS_RANK[prev["va_class"]]
                or (row["va_class"] == prev["va_class"] and row["qrank"] > prev["qrank"])):
            by_qid[qid] = row
    rows = sorted(by_qid.values(), key=lambda r: r["qrank"], reverse=True)
    if args.limit:
        rows = rows[:args.limit]

    # 5) write sqlite
    con = sqlite3.connect(DB)
    con.execute("DROP TABLE IF EXISTS subject")
    con.execute("""CREATE TABLE subject (
        qid TEXT PRIMARY KEY, title TEXT, va_class TEXT, qrank INTEGER, category TEXT)""")
    con.executemany("INSERT OR REPLACE INTO subject VALUES (?,?,?,?,?)",
                    [(r["qid"], r["title"], r["va_class"], r["qrank"], None) for r in rows])
    con.commit()

    # 6) report
    have_rank = sum(1 for r in rows if r["qrank"] > 0)
    by_cls = {}
    for r in rows:
        by_cls[r["va_class"]] = by_cls.get(r["va_class"], 0) + 1
    print("\n=== SUBJECT INDEX BUILT ===")
    print(f"  total subjects:   {len(rows):,}")
    print(f"  with a Qrank:     {have_rank:,} ({100*have_rank//max(1,len(rows))}%)")
    print(f"  by class:         {by_cls}")
    print(f"  db:               {DB}")
    print("  top 25 by Qrank:")
    for r in rows[:25]:
        print(f"    {r['qrank']:>12,}  {r['va_class']:>2}  {r['title']}")
    con.close()


if __name__ == "__main__":
    main()
