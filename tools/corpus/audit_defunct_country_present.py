"""Present-tense "In which country is X?" answered with a country that no longer exists.

    In which country is London?     -> Roman Empire
    In which country is Mariupol?   -> Russian Empire
    In which country is Ramallah?   -> Ottoman Empire
    In which country is Easter Bunny? -> Holy Roman Empire

The `rel:P17` generator asked a PRESENT-TENSE template over Wikidata's P17
("country"), which for a historical subject returns the polity of its time. The
result fails both halves of the quality bar at once:

  * COMPREHENSIBILITY. "In which country is London?" has no true answer of the
    form offered; London is in the United Kingdom, and Roman Britain is not a
    thing you can say "is" about. Same for "In which country is Brazil?" ->
    Portuguese Empire, or "In which country is the Easter Bunny?".

  * NOT DRIVING PLAYERS AWAY. This is the serious half. In the present tense
    these read as claims about live territorial disputes: Mariupol, Donetsk,
    Odesa, Bakhmut, Avdiivka and Sevastopol answered "Russian Empire" / "Soviet
    Union"; Jerusalem "Kingdom of Judah"; Ramallah, Hebron, Beersheba and Nablus
    "Ottoman Empire"; Western Sahara "Spanish Empire"; Wales "Kingdom of
    England". Whatever a player believes, being asked this in a pub quiz stops
    the night.

Past tense is FINE and is deliberately not matched: "In which country WAS
Königsberg?" -> Prussia is a good question. The defect is the tense, not the
history, so the rule keys on a present-tense stem.

"Historical" is Wikidata p31 = Q3024240 stated as data, never sniffed from the
name — plenty of live countries have "Kingdom" in the title.

    python3 tools/corpus/audit_defunct_country_present.py           # report
    python3 tools/corpus/audit_defunct_country_present.py --write   # tombstones
"""
import argparse
import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS_JSON = ROOT / "assets/corpus.json"
SOURCE_DB = ROOT / "tools/corpus/corpus_source.sqlite"
TOMBSTONES = ROOT / "tools/corpus/tombstones.json"

HISTORICAL_P31 = "Q3024240"          # Wikidata "historical country"
PRESENT = re.compile(r"\bis\b", re.I)


def offenders():
    con = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    historical = {t for t, p in con.execute("select title, p31 from subject")
                  if p and HISTORICAL_P31 in p}
    con.close()

    rows = json.loads(CORPUS_JSON.read_text())["questions"]
    out = []
    for r in rows:
        if not r[0].startswith("rel:P17:"):
            continue
        opts = r[2]
        if not (isinstance(opts, list) and isinstance(r[3], int) and 0 <= r[3] < len(opts)):
            continue
        answer = opts[r[3]]
        if answer in historical and PRESENT.search(r[1]):
            out.append((r[0], r[1], answer))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    hits = offenders()
    for qid, prompt, answer in hits:
        print(f"{qid[:24]:26} {prompt[:56]:58} -> {answer}")
    print(f"\n{len(hits)} present-tense questions answered with a defunct country")

    if a.write and hits:
        doc = json.loads(TOMBSTONES.read_text()) if TOMBSTONES.exists() else {}
        bucket = doc.setdefault("corpus", {})   # shape-keyed; a flat write wipes every guard
        for qid, _p, _a in hits:
            bucket[qid] = "present tense answered with a defunct country"
        TOMBSTONES.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {len(hits)} tombstones into the `corpus` bucket")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
