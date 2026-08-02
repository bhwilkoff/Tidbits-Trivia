"""Fetch lead paragraphs for the subjects whose reveal still says nothing.

The reveal is the app's stated purpose — it turns a miss into a curiosity door.
After `fix_hollow_reveals.py` has used every lead the Stage C pipeline already
holds, 2,241 rows still restate their own prompt:

    prompt  Stalked ones anchored to the seafloor are nicknamed 'sea lilies'...
    reveal  Crinoid: Class of echinoderms.

Those split two ways. ~1,500 rows belong to subjects whose cached lead exists but
offers no sentence that stands alone AND adds four new words. The rest — 664
subjects — have no prose at all, because Stage C never fetched them.

This fetches those, from the Wikipedia REST summary endpoint, and writes them
into the same `prose` table the rest of the pipeline reads, so
`fix_hollow_reveals.py` can then do its ordinary job. It does NOT write questions
itself: one script fetches, another decides what the player reads.

    python3 tools/corpus/fetch_hollow_prose.py --fetch [--limit N]
    python3 tools/corpus/fix_hollow_reveals.py --apply

Polite by construction: one request at a time with a delay, a descriptive
User-Agent, and everything cached so a re-run costs nothing.
"""
import argparse
import json
import pathlib
import sqlite3
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SOURCE_DB = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
API = "https://en.wikipedia.org/api/rest_v1/page/summary/"
UA = ("TidbitsTrivia/1.0 (trivia app corpus enrichment; "
      "contact ben@learningischange.com)")


def hollow_subjects():
    sys.path.insert(0, str(ROOT / "tools" / "play"))
    import content_audit as ca
    rows = json.loads(CORPUS.read_text())["questions"]
    subs = {q[7] for q in rows if q[7] and ca.hollow(q)}

    db = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    have = {t for (t,) in db.execute(
        "select title from prose where lead is not null and length(lead) > 120")}
    db.close()
    return sorted(subs - have)


def fetch_one(title):
    url = API + urllib.parse.quote(title.replace(" ", "_"), safe="")
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.loads(r.read().decode())
    # `extract` is the lead paragraph. A disambiguation page has no facts in it.
    if d.get("type") == "disambiguation":
        return None
    text = (d.get("extract") or "").strip()
    return text if len(text) > 120 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--delay", type=float, default=0.2)
    a = ap.parse_args()

    todo = hollow_subjects()
    if a.limit:
        todo = todo[:a.limit]
    print(f"subjects whose reveal says nothing and have no cached prose: {len(todo):,}")
    if not a.fetch:
        print("   e.g.", todo[:6])
        print("\n(pass --fetch to retrieve them)")
        return 0

    db = sqlite3.connect(SOURCE_DB)
    got = missed = 0
    for i, title in enumerate(todo, 1):
        try:
            text = fetch_one(title)
        except Exception as e:
            text = None
            if missed < 3:
                print(f"   {title}: {e}")
        if text:
            db.execute("INSERT OR REPLACE INTO prose (title, lead) VALUES (?,?)",
                       (title, text))
            got += 1
        else:
            missed += 1
        if i % 100 == 0:
            db.commit()
            print(f"   {i}/{len(todo)} — {got} fetched, {missed} without usable prose")
        time.sleep(a.delay)
    db.commit()
    db.close()
    print(f"\nfetched {got:,} leads; {missed:,} had none usable "
          f"(disambiguation pages, stubs, redirects)")
    print("now run: python3 tools/corpus/fix_hollow_reveals.py --apply")
    return 0


if __name__ == "__main__":
    sys.exit(main())
