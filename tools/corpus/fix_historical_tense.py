"""Ask historical subjects about the past, not the present.

Rendered a geography round and read it: "What currency is used in the Songhai
Empire?" The Songhai Empire fell in 1591. 528 prompts do this — five templates
that were written for present-day places and then applied to every polity the
corpus knows, including the medieval kingdom of Alodia and the Duchy of Brittany.

    On which continent is Indore State?          -> was
    What is the capital of Alodia?               -> was
    What currency is used in the Songhai Empire? -> was used

The subject is treated as historical only when the corpus itself says so: its
description carries "former"/"historical"/"defunct", a closed date range, or a
"was a" clause. Guessing from the NAME would be wrong — plenty of live places are
called a Kingdom, and Indore State is historical while Washington State is not.

Also completes the article list from fix_missing_article.py: a title that OPENS
with "Kingdom of" / "Duchy of" / "Sultanate of" / "Empire of" takes "the", which
that script's suffix-matching missed ("On which continent is Kingdom of
Gwynedd?"). "Baroda State" and "Indore State" correctly take none.

    python3 tools/corpus/fix_historical_tense.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
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
CORPUS = ROOT / "assets" / "corpus.json"
SOURCE_DB = ROOT / "tools" / "corpus" / "corpus_source.sqlite"

# Wikidata Q3024240 is "historical country". It is on the Kingdom of Navarre, the
# First French Empire and the Mataram Sultanate, and NOT on France or Japan —
# which is exactly the distinction the description-sniffing below keeps missing,
# stated as data instead of guessed from prose.
HISTORICAL_CLASS = "Q3024240"


def historical_titles():
    if not SOURCE_DB.exists():
        return set()
    db = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    out = {t for t, p31 in db.execute("select title, p31 from subject")
           if p31 and HISTORICAL_CLASS in p31}
    db.close()
    return out

HISTORICAL = re.compile(
    r"\b(former|historical|defunct|extinct|dissolved|abolished)\b"
    r"|\(\s*c?\.?\s*\d{3,4}\s*[-–]\s*\d{3,4}\s*\)"
    r"|\bwas a\b|\bwere a\b", re.I)

# present form -> past form, applied only at the START of the prompt.
TENSE = [
    ("What currency is used in ", "What currency was used in "),
    ("In which country is ", "In which country was "),
    ("What is the capital of ", "What was the capital of "),
    ("What is the official language of ", "What was the official language of "),
    ("Which of these is an official language of ",
     "Which of these was an official language of "),
    ("On which continent is ", "On which continent was "),
]

# Titles whose HEAD noun takes the article — the suffix list in
# fix_missing_article.py only sees the end of the name.
LEADING_THE = re.compile(r"^(Kingdom|Duchy|Sultanate|Empire|Principality|"
                         r"County|Emirate|Khanate|Caliphate|Commonwealth)\s+of\s",
                         re.I)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    by_class = historical_titles()
    print(f"subjects Wikidata calls a historical country: {len(by_class):,}")
    described = {}
    for q in rows:
        if q[7] and q[6]:
            described.setdefault(q[7], q[6])

    tensed = articled = 0
    examples = []
    by_template = collections.Counter()
    for q in rows:
        prompt, subj = (q[1] or ""), (q[7] or "")
        if not subj:
            continue
        before = prompt

        if subj in by_class or HISTORICAL.search(described.get(subj, "")):
            for present, past in TENSE:
                if prompt.startswith(present):
                    prompt = past + prompt[len(present):]
                    by_template[present.strip()] += 1
                    tensed += 1
                    break

        if LEADING_THE.match(subj) and not re.search(
                r"\bthe\s+" + re.escape(subj), prompt, re.I):
            new = re.sub(r"\b(of|in|is|was|to|for|from)\s+" + re.escape(subj) + r"\b",
                         lambda m: f"{m.group(1)} the {subj}", prompt, count=1)
            if new != prompt:
                prompt = new
                articled += 1

        if prompt != before:
            q[1] = prompt
            if len(examples) < 8:
                examples.append((before[:64], prompt[:68]))

    print(f"prompts put into the past tense: {tensed}")
    print("   by template:", dict(by_template.most_common()))
    print(f"titles given a leading article: {articled}")
    for b, n in examples:
        print(f"\n   was: {b}\n   now: {n}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{corpus_version(body)}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
