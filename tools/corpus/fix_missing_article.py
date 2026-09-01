"""Put the "the" back into "On which continent is Peace River?".

Rendered ten games on the pruned corpus and read the prompts: "Approximately
what is the elevation of Appalachian Mountains?". A template dropped a subject
title into a slot, and titles like "Appalachian Mountains", "Peace River" and
"Phoenix Islands" do not stand alone after a preposition — English wants the
article. 647 prompts read like that, from three generators.

The list of names that take "the" is deliberately conservative, because the
alternative is worse than the defect. A first pass matched every "Sudan",
"Congo", "Gambia" and "Valley" and would have produced "the Sudan" (archaic) and
"the Death Valley" (simply wrong). Only patterns that take the article in every
ordinary use are listed: plural ranges and island groups, and the head nouns
Sea / Ocean / Gulf / Strait / Channel / River / Desert / Range / Peninsula /
Archipelago / Delta / Basin / Empire / Republic / Federation / Union.

    python3 tools/corpus/fix_missing_article.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
import json
import pathlib
import re
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

# A title reads wrong after a preposition without "the" when it ends in one of
# these. Country names are NOT here: "the Sudan" and "the Ukraine" are exactly
# the mistake this script would otherwise introduce.
TAKES_THE = re.compile(
    r"(?:^|\s)(?:Mountains|Islands|Alps|Andes|Himalayas|Rockies|Pyrenees|"
    r"Balkans|Highlands|Everglades|Badlands|Netherlands|Philippines|Bahamas|"
    r"Maldives|Seychelles|United States|United Kingdom|Soviet Union)$"
    r"|\b(?:Sea|Ocean|Gulf|Strait|Channel|River|Desert|Range|Peninsula|"
    r"Archipelago|Delta|Basin|Empire|Republic|Federation|Union)$")

PREPOSITION = r"\b(of|in|is|to|for|from|across|near|along|around|through)\s+"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    fixed = 0
    examples = []
    by_gen = collections.Counter()
    for q in rows:
        subj, prompt = (q[7] or ""), (q[1] or "")
        if not subj or not TAKES_THE.search(subj):
            continue
        if re.search(r"\bthe\s+" + re.escape(subj) + r"\b", prompt, re.I):
            continue
        new = re.sub(PREPOSITION + re.escape(subj) + r"\b",
                     lambda m: f"{m.group(1)} the {subj}", prompt, count=1)
        if new == prompt:
            continue
        if len(examples) < 8:
            examples.append((prompt[:66], new[:70]))
        q[1] = new
        by_gen[q[0].split(":")[0]] += 1
        fixed += 1

    print(f"prompts given their definite article: {fixed}")
    print("   by generator:", dict(by_gen.most_common()))
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
