"""Fetch English labels for the Wikidata types the Match Up generator groups by.

`gen_match.py` had four relations whose keys are not one kind of thing. Every other relation says what
its keys ARE — "Match each work to its author", "Match each place to its capital"
— but `rel:P17:` (country-of) shipped as:

    Match each of these to its country.

Read on screen it is worse than vague, because the keys are not one kind of
thing:

    Serie C · Chelsea F.C. · TSG 1899 Hoffenheim · 2017 World Baseball Classic
    Anne of Green Gables · Bauhaus · Naruto · Manneken Pis

304 of the 324 rounds mixed Wikidata types. The generator can group by type
instead — 281 homogeneous rounds are formable, 87% of the current count — but
naming them needs labels, and `corpus_source.sqlite` stores `p31` as bare QIDs.

This fetches those labels once, in batches of 50, and commits them so the build
stays offline. 94 type+category buckets can fill a round; this covers every type
the relation touches so a regrouping never goes unnamed for want of a fetch.

    python3 tools/corpus/fetch_p31_labels.py [--fetch]
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
OUT = ROOT / "tools" / "corpus" / "p31_labels.json"
API = "https://www.wikidata.org/w/api.php"
UA = ("TidbitsTrivia/1.0 (trivia app corpus enrichment; "
      "contact ben@learningischange.com)")


def wanted():
    db = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    p31 = {t: (p or "").split(",")[0] for t, p in
           db.execute("select title, p31 from subject")}
    db.close()
    rows = json.loads(CORPUS.read_text())["questions"]
    # Every relation whose keys are not one kind of thing, not just country-of.
    # "Match each work to its creator" was asked with Skynet as a key (a fictional
    # AI, not a work) and "Match each organization to its founder" with a CITY.
    prefixes = ("rel:P17:", "rel:P170:", "rel:P175:", "rel:P112:")
    return sorted({p31[r[7]] for r in rows
                   if r[0].startswith(prefixes) and r[7] in p31 and p31[r[7]]})


def fetch(qids):
    out = {}
    for i in range(0, len(qids), 50):
        batch = qids[i:i + 50]
        url = API + "?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(batch),
            "props": "labels", "languages": "en", "format": "json"})
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.loads(r.read().decode())
        for q, e in (d.get("entities") or {}).items():
            lab = ((e.get("labels") or {}).get("en") or {}).get("value")
            if lab:
                out[q] = lab
        print(f"   {min(i + 50, len(qids))}/{len(qids)}")
        time.sleep(0.3)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    a = ap.parse_args()

    qids = wanted()
    print(f"Wikidata types used as a key by a typed relation: {len(qids):,}")
    if not a.fetch:
        print("(pass --fetch to retrieve their labels)")
        return 0
    labels = fetch(qids)
    OUT.write_text(json.dumps(labels, ensure_ascii=False, indent=0,
                              sort_keys=True))
    print(f"\nwrote {OUT.relative_to(ROOT)}: {len(labels):,} labels")
    for q in qids[:8]:
        print(f"   {q} = {labels.get(q, '(none)')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
