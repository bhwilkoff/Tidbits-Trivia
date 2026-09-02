"""'In which country is X?' asked of something that is not IN one country.

Two rules, and they are not the same kind of wrong.

A. A SEA IS NOT IN A COUNTRY. Every one of these is malformed by construction,
   whichever country the generator picked:

       In which country is the North Sea?        -> Norway
       In which country is the Caribbean Sea?    -> Mexico

   And several land on live disputes, the same "stops the night" failure as the
   present-tense defunct-country class: the Sea of Azov answered "Russia", the
   South China Sea "Vietnam", the English Channel "United Kingdom", the Persian
   Gulf "Saudi Arabia". No rewrite saves these; the question itself is the error.

B. A LANDFORM THAT GENUINELY CROSSES BORDERS, curated. The Nile answered "Sudan"
   and the Amazon "Peru" are not just arbitrary — they mark the answer most of
   the room WOULD give (Egypt, Brazil) wrong. Same for the Danube through ten
   countries answered "Germany", Everest answered "Nepal" when it is equally in
   China, and Niagara Falls answered "United States".

   Curated rather than derived, because the DATA CANNOT ANSWER IT: the subject
   table stores exactly ONE P17 per subject — 0 of 12,902 have more than one — so
   the fetch discarded the very fact that a river crosses borders. The generator
   never had a way to know. That is the upstream bug; this is the cleanup.

C. A CITY HAS NO CAPITAL. The same generator followed Wikidata P36 out of a city
   and landed on its seat-of-government district:

       What is the capital of Beijing?  -> Tongzhou District
       What is the capital of Kyoto?    -> Nakagyo Ward

   Nobody in a pub knows this, and the question does not parse even if they did.
   Wrong by construction, like the seas.

Landforms that really do sit in one country keep their questions: the Po is in
Italy, Loch Ness in the United Kingdom, Mount Ararat in Turkey, the Ozarks in the
United States. This is not a cull of the type.

Deliberately NOT culled, having been measured: "Which of these is an official
language of <a US state>?" answered "English" (28 rows). Many states really do
have official-English statutes, so the answers are mostly right — a weak question
is not a wrong one, and no rule here should pretend otherwise.

    python3 tools/corpus/audit_landform_country.py           # report
    python3 tools/corpus/audit_landform_country.py --write   # tombstones
"""
import argparse
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS_JSON = ROOT / "assets/corpus.json"
SOURCE_DB = ROOT / "tools/corpus/corpus_source.sqlite"
TOMBSTONES = ROOT / "tools/corpus/tombstones.json"

SEA_P31 = "Q165"
STEM = "In which country is "
CAPITAL_STEM = "What is the capital of "

# Verified by eye: each of these lies in several countries, and the answer the
# corpus gives is one arbitrary pick — often not the one a room would name.
TRANSBOUNDARY = {
    "Nile", "Danube", "Amazon River", "Rhine", "Euphrates", "Tigris", "Mekong",
    "Congo River", "Zambezi", "Sava", "Rio Grande", "Jordan River", "Indus",
    "Sahara", "Andes", "Alps", "Himalayas", "Pyrenees", "Carpathian Mountains",
    "Mount Everest", "Matterhorn", "Mont Blanc", "Niagara Falls",
    "Lake Victoria", "Lake Geneva", "Dead Sea", "Lake Tanganyika", "Lake Constance",
}


def offenders():
    con = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    p31 = {t: (p or "") for t, p in con.execute("select title, p31 from subject")}
    con.close()

    labels = json.loads((ROOT / "tools/corpus/p31_labels.json").read_text())
    city_codes = {c for c, n in labels.items() if "city" in n.lower() or "town" in n.lower()}

    rows = json.loads(CORPUS_JSON.read_text())["questions"]
    out = []
    for r in rows:
        # C. a city has no capital
        if r[1].startswith(CAPITAL_STEM):
            subj = r[1][len(CAPITAL_STEM):].rstrip("?").strip()
            if set(p31.get(subj, "").split(",")) & city_codes:
                opts = r[2]
                ans = opts[r[3]] if isinstance(opts, list) and isinstance(r[3], int) and 0 <= r[3] < len(opts) else "?"
                out.append((r[0], subj, ans, "a city has no capital"))
            continue
        if not r[1].startswith(STEM):
            continue
        subj = r[7] if len(r) > 7 else ""
        opts = r[2]
        if not (isinstance(opts, list) and isinstance(r[3], int) and 0 <= r[3] < len(opts)):
            continue
        answer = opts[r[3]]
        if SEA_P31 in p31.get(subj, "").split(","):
            out.append((r[0], subj, answer, "a sea is not in a country"))
        elif subj in TRANSBOUNDARY:
            out.append((r[0], subj, answer, "crosses borders; the answer is one arbitrary pick"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    hits = offenders()
    for qid, subj, answer, why in hits:
        print(f"{subj:24} -> {answer:28} {why}")
    print(f"\n{len(hits)} question(s) whose subject has no single answer of that kind")

    if a.write and hits:
        doc = json.loads(TOMBSTONES.read_text()) if TOMBSTONES.exists() else {}
        bucket = doc.setdefault("corpus", {})   # shape-keyed; a flat write wipes every guard
        for qid, _s, _a, why in hits:
            bucket[qid] = f"landform has no single country: {why}"
        TOMBSTONES.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {len(hits)} tombstones into the `corpus` bucket")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
