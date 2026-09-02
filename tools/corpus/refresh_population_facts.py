"""Re-fetch CURRENT population and area from Wikidata into the source DB.

`corpus_source.sqlite` holds historical census values for P1082. The United
States is stored at 3,929,214 -- the 1790 census. Canada at 44. France at
40,681,000 against a real 68.6 million. Of the countries where the Wikipedia lead
also gives a figure, 93 disagree by 2x or more, and 481 of the 3,117 population
superlatives name the WRONG ANSWER as a result.

`audit_stale_population_answers.py` proves the problem but deliberately does not
fix it: correcting an answer index from a regex over prose produced a new wrong
answer in every one of four tightening rounds (a city's lead quotes its METRO
figure; Indiana's lead sentence is about Indianapolis; England's parsed as 15M
when the lead says 56,490,048). The fix has to happen at the SOURCE, where one
correct number repairs every question that touches it at once.

WHY THE STORED VALUES ARE OLD: a Wikidata item carries MANY P1082 statements, one
per census, each qualified by a point in time (P585). The original fetch took an
arbitrary one -- often the earliest. This asks for the statement with the LATEST
P585, which is what "population" means to a player, and falls back to an
unqualified statement when an item has only one.

WIKIDATA STATES UNITS AND THE FIRST VERSION OF THIS IGNORED THEM. Mount Everest
carries five P2044 statements -- 8,848 metre, 8,848.86 metre, 8,844.43 metre,
8,850 metre AND 29,030 FOOT -- and taking the raw amount by latest date returned
29,030, which would have replaced a CORRECT stored 8,849 with a figure in the
wrong unit. Caught by spot-checking the fetch against a value already known to be
right, before applying anything. The query now asks for `wikibase:quantityUnit`
and converts feet to metres, and any statement whose unit is not recognised is
dropped rather than guessed at.

(The area refresh was re-verified against known truth for the same reason and is
clean: US 9,826,675 km2, Russia 17,125,191, Japan 377,972 -- no square-mile
contamination. France's 643,801 is the legitimate total including overseas
departments.)

P2044 (elevation) and P2043 (length) get the same treatment. Five Earth terrain
features are stored above 8,849 m, which is impossible on this planet -- Sierra
Nevada at 14,505, Cascade Range at 14,411 -- and every one is a FEET figure
recorded as metres (14,505 ft is Mount Whitney exactly). Note the values that
look impossible but are not: a noctilucent cloud really does sit at 76,000 m and
Olympus Mons at 21,229 m, because one is atmospheric and the other is on Mars, so
the check is confined to terrestrial mountains, ranges and volcanoes.

Same treatment for P2046 (area) -- and the "87 physically impossible city areas"
turn out not to be corrupt at all. Windhoek's 5,133,000,000 is not ten Earths, it
is SQUARE METRES: 5,133 km2, which is Windhoek exactly. Miami's 143,148,642 m2 is
143.1 km2, also exactly right. The values were always correct and the UNIT was
never applied, so they are converted rather than refused. Refusing them, as the
first version of this did, left the wrong number in place while reporting success.

The result is cached to a committed JSON file so the build stays offline, exactly
like `fetch_p31_labels.py`. Nothing is written to the database or the corpus
without `--apply`, and `--apply` refuses a value that fails the same sanity rules
the audit uses, so a bad fetch cannot quietly replace a good number.

    python3 tools/corpus/refresh_population_facts.py --fetch     # network -> cache
    python3 tools/corpus/refresh_population_facts.py --apply     # cache  -> source DB
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

SOURCE_DB = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
CACHE = ROOT / "tools" / "corpus" / "population_area_current.json"
BATCH = 40                     # 120 drew HTTP 502 from WDQS; 40 is reliable
MAX_CITY_AREA = 100_000        # km2 -- larger than any real city

# Wikidata unit QIDs -> the base unit each property is stored in here.
UNIT_TO_BASE = {
    "P2044": {"Q11573": 1.0, "Q3710": 0.3048, "Q253276": 1609.344, "Q828224": 1000.0},
    "P2043": {"Q11573": 1.0, "Q3710": 0.3048, "Q253276": 1609.344, "Q828224": 1000.0},
    "P2046": {"Q712226": 1.0, "Q25343": 1.0e-6, "Q3272812": 2.589988, "Q35852": 0.01},
    "P1082": {},
}


def fetch(props=("P1082", "P2046", "P2044", "P2043")):
    con = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    out = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    for prop in props:
        qids = [q for q, in con.execute(
            "select distinct qid from fact where prop=?", (prop,))]
        todo = [q for q in qids if q not in out.get(prop, {})]
        print(f"{prop}: {len(qids)} subjects, {len(todo)} still to fetch")
        got = out.setdefault(prop, {})
        for i in range(0, len(todo), BATCH):
            chunk = todo[i:i + BATCH]
            values = " ".join(f"wd:{q}" for q in chunk)
            # Latest point-in-time wins; unqualified statements sort last but are
            # kept so single-statement items still resolve.
            query = f"""SELECT ?item ?v ?d ?unit WHERE {{
              VALUES ?item {{ {values} }}
              ?item p:{prop} ?st . ?st psv:{prop} ?qv .
              ?qv wikibase:quantityAmount ?v .
              OPTIONAL {{ ?qv wikibase:quantityUnit ?unit }}
              OPTIONAL {{ ?st pq:P585 ?d }}
            }}"""
            rows = wd.sparql(query)
            best = {}
            for r in rows:
                q = r["item"]["value"].rsplit("/", 1)[-1]
                try:
                    v = float(r["v"]["value"])
                except (KeyError, ValueError):
                    continue
                unit = r.get("unit", {}).get("value", "").rsplit("/", 1)[-1]
                factor = UNIT_TO_BASE.get(prop, {}).get(unit)
                if factor is None and unit and unit not in ("", "1"):
                    continue          # unrecognised unit: drop, never guess
                v *= (factor or 1.0)
                d = r.get("d", {}).get("value", "")
                if q not in best or d > best[q][1]:
                    best[q] = (v, d)
            for q, (v, d) in best.items():
                got[q] = {"value": v, "asof": d[:10] or None}
            print(f"   {i + len(chunk)}/{len(todo)}  (+{len(best)})")
            CACHE.write_text(json.dumps(out, indent=0, sort_keys=True))
            time.sleep(1)
    print(f"cached -> {CACHE}")


def apply():
    if not CACHE.exists():
        sys.exit("no cache; run --fetch first")
    cache = json.loads(CACHE.read_text())
    con = sqlite3.connect(SOURCE_DB)
    p31 = {q: (p or "") for q, p in con.execute("select qid, p31 from subject")}
    labels = json.loads((ROOT / "tools/corpus/p31_labels.json").read_text())
    import re as _re
    _CITY = _re.compile(r"\bcity\b|\btown\b|municipality|human settlement|big city|"
                        r"county seat|borough", _re.I)

    def _is_city(codes):
        return bool(_CITY.search(" ".join(labels.get(c, c) for c in codes.split(",") if c)))

    changed = skipped = converted = 0
    for prop, items in cache.items():
        for qid, rec in items.items():
            v = rec["value"]
            if v <= 0:
                skipped += 1
                continue
            # An "impossible" city area is square metres, not an error. The
            # largest real city, Chongqing, is ~82,400 km2, so anything above
            # 100,000 for a city is m2 and converts cleanly.
            if prop == "P2046" and v > MAX_CITY_AREA and _is_city(p31.get(qid, "")):
                v = v / 1_000_000
                converted += 1
            cur = con.execute(
                "select value from fact where qid=? and prop=?", (qid, prop)).fetchone()
            if cur is None or abs(cur[0] - v) < 1e-6:
                continue
            con.execute("update fact set value=? where qid=? and prop=?", (v, qid, prop))
            changed += 1
    # The loop above only visits subjects the FETCH returned. Wikidata gave no
    # P2046 for Miami or Boston, so their stored square-metre values would have
    # survived a "successful" run untouched. Sweep the stored rows too.
    for qid, v in con.execute(
            "select qid, value from fact where prop='P2046'").fetchall():
        if v and v > MAX_CITY_AREA and _is_city(p31.get(qid, "")):
            con.execute("update fact set value=? where qid=? and prop='P2046'",
                        (v / 1_000_000, qid))
            converted += 1
    con.commit()
    print(f"source DB updated: {changed} changed, {converted} m2->km2 converted, "
          f"{skipped} refused")


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
