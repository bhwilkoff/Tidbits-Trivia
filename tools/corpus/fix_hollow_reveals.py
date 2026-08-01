#!/usr/bin/env python3
"""Give the reveal something to say that the question did not already say it.

`content_audit.py` scores 63,104 of 128,554 questions (49.1%) as HOLLOW: the
"Now you know" panel adds nothing. "Caused by the spiral bacterium Treponema
pallidum, this infection..." reveals "Syphilis is an infection caused by the
bacterium Treponema pallidum."

The cause is structural rather than careless. The reveal is Wikidata's one-line
description, and the delight pass rewrote the PROMPTS out of that same
description — so once the clue is good, the reveal is a rerun. In an app whose
stated purpose is that the reveal turns a miss into a curiosity door, half the
corpus closes the door.

This takes a sentence from the subject's cached Wikipedia lead that the prompt
has NOT already used, and appends it. It only reaches what is cached:

    3,016 of 63,104 hollow questions (4.8%), across 1,297 subjects.

The other ~60,000 need lead paragraphs fetched for ~31,000 subjects, which
`tools/corpus/sources/fetch_prose.py` already knows how to do. Doing the reachable
part first is deliberate — it proves the shape of the repair end to end before
anyone spends a long network run on the rest.

    python3 tools/corpus/fix_hollow_reveals.py [--apply]
"""
import argparse
import collections
import glob
import json
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
CACHE = ROOT / "tools" / "corpus" / "cache" / "articles"

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for", "de", "la",
        "le", "el", "s", "is", "was", "were", "are", "by", "with", "from", "as",
        "that", "this", "it", "its", "his", "her", "their", "which", "who"}

MIN_NEW_WORDS = 4        # a sentence has to earn its place
MAX_CHARS = 165          # the reveal panel is a paragraph, not an essay


def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


def leads():
    """title -> [sentences] from the cached article lead."""
    out = {}
    for p in glob.glob(str(CACHE / "*.json")):
        try:
            d = json.load(open(p))
        except Exception:
            continue
        title, extract = d.get("title"), d.get("extract")
        if not title or not extract:
            continue
        # Split on sentence ends, keeping abbreviations intact well enough.
        parts = re.split(r"(?<=[.!?])\s+(?=[A-Z])", extract)
        out[title] = [s.strip() for s in parts if 40 <= len(s.strip()) <= MAX_CHARS]
    return out


# A lead sentence is written to follow the one before it. Lifted out on its own,
# "Many francophone black writers ... were ALSO influenced" has nothing to be
# also-influenced by, and "However, ..." contradicts a sentence the player never
# saw. The reveal has to stand alone, so a sentence only qualifies if its subject
# is recoverable: it names the subject, or opens with "It"/"Its"/"The".
DANGLING = re.compile(r"^(also|however|moreover|furthermore|in addition|these|those|"
                      r"they|he|she|his|her|many|most|some|other|another|such|"
                      r"by contrast|meanwhile|nevertheless|nonetheless|instead)\b", re.I)


def pick(sentences, prompt, answer, existing, subject):
    """The first sentence that tells the player something new AND stands alone."""
    known = sig(prompt) | sig(answer) | sig(existing)
    subj_words = sig(subject)
    for s in sentences:
        if DANGLING.match(s.strip()):
            continue
        stands_alone = bool(sig(s) & subj_words) or re.match(r"^(It|Its|The)\b", s.strip())
        if not stands_alone:
            continue
        new = sig(s) - known
        if len(new) >= MIN_NEW_WORDS:
            return s
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    lead = leads()
    print(f"cached leads: {len(lead)} subjects")

    sys.path.insert(0, str(ROOT / "tools" / "play"))
    import content_audit as ca

    filled = skipped = 0
    examples = []
    for q in rows:
        if q[7] not in lead or not ca.hollow(q):
            continue
        answer = q[2][q[3]] if q[2] and 0 <= q[3] < len(q[2]) else ""
        s = pick(lead[q[7]], q[1] or "", answer, q[6] or "", q[7] or "")
        if not s:
            skipped += 1
            continue
        base = (q[6] or "").strip()
        # The base must END a sentence before the new one starts. Wikidata's
        # short descriptions mostly do not ("Sculpture by Anish Kapoor in
        # Chicago"), so appending ran the two together and every tool that reads
        # the first sentence as the subject's TYPE then read the prose as well.
        if base and base[-1] not in ".!?":
            base += "."
        q[6] = f"{base} {s}".strip() if base else s
        filled += 1
        if len(examples) < 5:
            examples.append((q[1][:58], base, s))

    print(f"reveals given a new fact: {filled}")
    print(f"skipped (cached lead said nothing new): {skipped}")
    for p, before, after in examples:
        print(f"\n   {p}...\n     was: {before[:70]}\n     now: + {after[:110]}")
    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
