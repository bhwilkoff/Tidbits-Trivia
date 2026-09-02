"""Fetch P452 (industry) into the relation table, so `biz:industry` can be checked.

`biz:industry` asks "Which industry does X belong to?" for 236 companies, and
NOTHING IN THE LOCAL DATA CAN VERIFY THE ANSWER: the relation table has no
industry property at all (P452 = 0 rows). Every automated check over it therefore
returns a clean result that means nothing -- the same shape of false comfort as
`class:*` returning 0 because occupations live in p106, or the `sup:*` sweep
agreeing with the very table that generated it.

Reading 16 rows by eye found two answers that are simply wrong:

    Which industry does Gainax belong to?  -> "copyright collective"
        Gainax is an anime studio, and "anime industry" sits as a DISTRACTOR on
        another row in the same family.
    What industry is Avianca in?          -> "aircraft industry"
        Avianca is an airline. "air transport" is used correctly for Aegean
        Airlines and EL AL two rows away.

Two in sixteen is a small sample and is NOT projected onto the other 220 rows;
this fetch exists so the real number can be measured instead of guessed.

Unlike population and area, an industry is a RELATION (a target label, not a
quantity), so this writes to `relation` rather than `fact`, and a subject may
legitimately have several -- a conglomerate really does operate in many
industries. All values are kept, which is what makes the multiple-correct-answer
check possible: a question whose options contain two of a company's industries
has two right answers, exactly like the 41 `class:*` rows already repaired.

    python3 tools/corpus/fetch_industry.py --fetch    # network -> cache
    python3 tools/corpus/fetch_industry.py --apply    # cache  -> relation table
"""
import argparse
import json
import pathlib
import sqlite3
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "corpus"))
import wikidata as wd  # noqa: E402

CORPUS = ROOT / "assets" / "corpus.json"
SOURCE_DB = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
CACHE = ROOT / "tools" / "corpus" / "industry_p452.json"
BATCH = 40          # 120 drew HTTP 502 from WDQS during the population fetch


def subjects():
    """Every subject a biz:industry question is about, plus its options."""
    qs = json.loads(CORPUS.read_text())["questions"]
    con = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    t2q = {t: q for q, t in con.execute("select qid, title from subject")}
    want = set()
    for q in qs:
        if q[0].startswith("biz:industry"):
            s = q[7] if len(q) > 7 else None
            if s in t2q:
                want.add(t2q[s])
    return sorted(want)


def fetch():
    todo_all = subjects()
    out = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    todo = [q for q in todo_all if q not in out]
    print(f"{len(todo_all)} biz:industry subjects, {len(todo)} still to fetch")
    for i in range(0, len(todo), BATCH):
        chunk = todo[i:i + BATCH]
        values = " ".join(f"wd:{q}" for q in chunk)
        query = f"""SELECT ?item ?vLabel WHERE {{
          VALUES ?item {{ {values} }}
          ?item wdt:P452 ?v .
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en" }}
        }}"""
        rows = wd.sparql(query)
        got = {}
        for r in rows:
            q = r["item"]["value"].rsplit("/", 1)[-1]
            lab = r.get("vLabel", {}).get("value")
            if lab:
                got.setdefault(q, []).append(lab)
        for q in chunk:                       # record misses too, so we do not refetch
            out[q] = sorted(set(got.get(q, [])))
        print(f"   {i + len(chunk)}/{len(todo)}  (+{len(got)} with data)")
        CACHE.write_text(json.dumps(out, indent=0, sort_keys=True))
        time.sleep(1)
    have = sum(1 for v in out.values() if v)
    print(f"cached {len(out)} subjects, {have} with at least one industry -> {CACHE}")


def apply():
    if not CACHE.exists():
        sys.exit("no cache; run --fetch first")
    cache = json.loads(CACHE.read_text())
    con = sqlite3.connect(SOURCE_DB)
    added = 0
    for qid, labels in cache.items():
        for lab in labels:
            exists = con.execute(
                "select 1 from relation where qid=? and prop='P452' and target_label=?",
                (qid, lab)).fetchone()
            if exists:
                continue
            con.execute(
                "insert into relation (qid, prop, label, target_qid, target_label) "
                "values (?, 'P452', 'industry', '', ?)", (qid, lab))
            added += 1
    con.commit()
    print(f"relation rows added: {added}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    if a.fetch:
        fetch()
    if a.apply:
        apply()
    if not (a.fetch or a.apply):
        ap.print_help()
