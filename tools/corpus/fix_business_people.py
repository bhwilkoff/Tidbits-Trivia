"""The Business category means "companies". Business PEOPLE are filed elsewhere.

Rendered a Type It In round and read the header:

    SCIENCE
    Google's employee No. 20 and its first woman software engineer, she later
    left to run a famous internet company as CEO from 2012 until Verizon bought
    it — who is she?

Marissa Mayer's Wikidata occupation is "computer scientist", so the row was
categorised from the SUBJECT rather than from what the question asks, and a
question about running Yahoo came out as Science.

Measured, that is the whole shape of the Business category:

    corpus rows whose subject is a PERSON      54,214  (48.9%)
    BUSINESS rows whose subject is a person       281  ( 6.8%)

Business is 3.7% of the corpus not because the corpus lacks business, but because
half of it is people and business people are counted as something else. Lee
Iacocca ("American businessman") sits in Science; Larry Ellison in Screen; Bill
Gates in Arts.

The move needs BOTH signals, because either alone repeats the original mistake.

Subject alone is not enough — that IS the bug. A first version moved every row
whose subject leads with a business role, and it took this one with it:

    This South Korean actor-turned-businessman starred in the 2002 drama...

Bae Yong-joon is a businessman; the QUESTION is about his acting, and Screen was
right. Categorising by subject is exactly what filed Marissa Mayer under Science.

Prompt alone is not enough either. "Who composed the score for The Firm?" matched
a commerce vocabulary on a film title, and "sold under the brand name Tamiflu" is
pharmacology.

So a row moves when the subject is a business person AND the clue is asking about
commerce. That is deliberately narrow — the point is to be right, not to inflate
a category.

    python3 tools/corpus/fix_business_people.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
import json
import pathlib
import re


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

# The role must be the FIRST one the description names: "<Nationality>
# businessman and politician", not "engineer and businessman".
PRIMARY_BUSINESS = re.compile(
    r"\b(?:is|was)\s+(?:an?|the)\s+(?:[A-Z][a-z]+(?:[- ][A-Z][a-z]+)?\s+)?"
    r"(businessman|businesswoman|entrepreneur|industrialist|business magnate|"
    r"financier|banker)\b", re.I)

# What the QUESTION is about. Deliberately commerce verbs and roles, not the word
# "brand" (drug brand names) or "corporation" (any institution).
COMMERCE_CLUE = re.compile(
    r"\b(as CEO|as its CEO|chief executive|founded the company|co-founded|"
    r"billionaire|conglomerate|acquired by|went public|stock exchange|"
    r"hostile takeover|venture capital|investment bank|business empire|"
    r"his company|her company|the company he|the company she|"
    r"richest|fortune|tycoon|magnate)\b", re.I)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    primary = {}
    for r in rows:
        s = r[7]
        if s and s not in primary:
            m = PRIMARY_BUSINESS.search(r[6] or "")
            if m:
                primary[s] = m.group(1).lower()

    moved = collections.Counter()
    examples = []
    for r in rows:
        if r[4] == "business" or r[7] not in primary:
            continue
        if not COMMERCE_CLUE.search(str(r[1])):
            continue
        moved[r[4]] += 1
        if len(examples) < 8:
            examples.append((r[7], r[4], primary[r[7]], str(r[1])[:62]))
        r[4] = "business"

    before = sum(1 for r in rows if r[4] == "business") - sum(moved.values())
    print(f"subjects whose prose leads with a business role: {len(primary):,}")
    print(f"rows moved into business: {sum(moved.values()):,}   from {dict(moved.most_common())}")
    print(f"business category: {before:,} -> {before + sum(moved.values()):,} "
          f"({(before + sum(moved.values())) / len(rows) * 100:.1f}% of the corpus)")
    for s, was, role, prompt in examples:
        print(f"   {s} ({role}) — {was} -> business\n      {prompt}...")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{corpus_version(body)}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
