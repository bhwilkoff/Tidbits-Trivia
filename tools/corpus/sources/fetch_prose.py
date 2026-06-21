#!/usr/bin/env python3
"""Stage C — lead prose + short description for each subject (Decision 032).

For every subject QID/title in corpus_source.sqlite, fetch the Wikipedia lead
extract (clean intro, plain text) and the short description. These feed the main
MCQ stems ("What is …?" / "Which … is described as …?") and the Type-the-answer
clue. Targeted batched fetch (the curated set is ~12k, not millions) — no dump.

Writes table: prose(qid, title, lead, description). Run AFTER enrich_subjects.py
(separate table, but same SQLite file — don't run them concurrently).

Usage: python3 fetch_prose.py [--limit N]
"""
import argparse, os, sqlite3, sys, time, json, urllib.parse, urllib.request

API = "https://en.wikipedia.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))

_last = [0.0]
def _throttle(mi=0.12):
    w = mi - (time.monotonic() - _last[0])
    if w > 0: time.sleep(w)
    _last[0] = time.monotonic()

def api(params, retries=6):
    params = {**params, "format": "json", "formatversion": "2", "maxlag": "5"}
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return json.load(urllib.request.urlopen(req, timeout=45))
        except Exception:
            if attempt == retries - 1: raise
            time.sleep(2 ** attempt)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    con.execute("CREATE TABLE IF NOT EXISTS prose (qid TEXT PRIMARY KEY, title TEXT, lead TEXT, description TEXT)")
    con.execute("DELETE FROM prose")
    con.commit()

    rows = con.execute("SELECT qid, title FROM subject WHERE keep=1 ORDER BY qrank DESC").fetchall()
    if args.limit: rows = rows[:args.limit]
    qid_of = {}
    titles = []
    for qid, title in rows:
        qid_of[title] = qid
        titles.append(title)

    got = 0
    # extracts with exintro is capped at 20 titles/request
    for i in range(0, len(titles), 20):
        batch = titles[i:i+20]
        d = api({"action": "query", "titles": "|".join(batch),
                 "prop": "extracts|description", "exintro": "1", "explaintext": "1",
                 "redirects": "1"})
        pages = d.get("query", {}).get("pages", [])
        # formatversion=2 → pages is a list; map by normalized title
        norm = {}
        for n in d.get("query", {}).get("normalized", []):
            norm[n["to"]] = n["from"]
        for p in pages:
            title = p.get("title", "")
            src_title = norm.get(title, title)
            qid = qid_of.get(src_title) or qid_of.get(title)
            if not qid:
                continue
            lead = (p.get("extract") or "").strip()
            desc = (p.get("description") or "").strip()
            if lead or desc:
                con.execute("INSERT OR REPLACE INTO prose VALUES (?,?,?,?)", (qid, title, lead, desc))
                got += 1
        con.commit()
        if (i // 20) % 25 == 0:
            print(f"  …prose {min(i+20, len(titles))}/{len(titles)}")

    print(f"\n=== STAGE C (prose) ===\n  prose rows: {got:,} / {len(titles):,}")
    con.close()


if __name__ == "__main__":
    main()
