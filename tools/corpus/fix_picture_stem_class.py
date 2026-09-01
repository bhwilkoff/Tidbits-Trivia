"""Give picture rows a stem that matches what the picture shows (F-012).

Probe P1 served "Which war is this?" over a PORTRAIT of Werner M\u00f6lders with
people as options. The stem-assignment keyed off subject CATEGORY (war,
business, city), so humans filed under those categories got class-asserting
stems — and vice versa ("Who is this?" over Buckingham Palace).

Detection uses the definitive signal: the subject's p31 in
corpus_source.sqlite. Exact-token Q5 = human (substring matching would hit
Q515, city — the audit's first false alarm). Humans under non-person stems
get "Who is this?"; non-humans under person stems get "Can you identify
this?".

    python3 tools/corpus/fix_picture_stem_class.py [--apply]

Then run tools/corpus/resync_corpus.sh and bump sw.js CACHE.
"""
import argparse
import hashlib
import json
import pathlib
import re
import sqlite3
import sys


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


ROOT = pathlib.Path(__file__).resolve().parents[2]
PICTURE = ROOT / "assets" / "picture.json"
SOURCE = ROOT / "tools" / "corpus" / "corpus_source.sqlite"

NON_PERSON_STEMS = (
    "Which war is this?", "What city is this?", "Name this city.",
    "Which city is shown here?", "Which company is this?",
    "What historical event is this?",
)
PERSON_STEMS = (
    "Who is this?", "Who is this person?", "Can you name this person?",
    "Name this American actress.",
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    con = sqlite3.connect(SOURCE)
    p31 = {t: set(re.findall(r"Q\d+", p or "")) for t, p in
           con.execute("select title, p31 from subject")}

    data = json.loads(PICTURE.read_text())
    rows = data["questions"] if isinstance(data, dict) else data

    to_person, to_neutral = [], []
    for q in rows:
        if not isinstance(q, list):
            continue
        title = q[0].split(":")[-1].replace("_", " ")
        toks = p31.get(title)
        if toks is None:
            continue
        human = "Q5" in toks
        if q[1] in NON_PERSON_STEMS and human:
            to_person.append((q[0], q[1])); q[1] = "Who is this?"
        elif q[1] in PERSON_STEMS and not human:
            to_neutral.append((q[0], q[1])); q[1] = "Can you identify this?"

    print(f"humans given 'Who is this?': {len(to_person)}")
    for i, s in to_person: print(f"   {i}  (was: {s})")
    print(f"non-humans given 'Can you identify this?': {len(to_neutral)}")
    for i, s in to_neutral[:10]: print(f"   {i}  (was: {s})")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then resync + CACHE bump)")
        return 0
    if isinstance(data, dict):
        body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
        PICTURE.write_text(
            f'{{"version":"{corpus_version(body)}","count":{len(rows)},"questions":{body}}}')
    else:
        PICTURE.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    print(f"\nwrote {PICTURE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
