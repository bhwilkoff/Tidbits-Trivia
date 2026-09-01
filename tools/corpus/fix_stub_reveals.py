#!/usr/bin/env python3
"""Stop the reveal from introducing a subject with a bare number.

Rendered a Sweep round and read the reveal: "Brandon Spikes: 1987. Brandon Spikes
(born September 3, 1987) is an American former professional football linebacker."
The panel that is supposed to tell you who someone is opens by telling you a year
and nothing else.

29,020 reveals do this — 22.6% of the corpus — and for 2,425 of them the number IS
the whole reveal: the player answers, and the payoff reads "Matthew Perry: 1969."

The cause is mechanical. These rows were generated from a numeric fact (birth
year, death year, founding year), and the generator wrote the FACT into the
description slot, which is meant to hold "American and Canadian actor". Every
tool in this directory then skipped them, because they all guard with
`not d[0].isdigit()` — so the defect was invisible to the machine and loud to the
player. A field that classifiers refuse to read is exactly where rot collects.

Two repairs:
  * a sentence already follows the number -> drop the number, keep the sentence
  * nothing follows -> take a lead sentence from Stage C prose, as
    fix_hollow_reveals.py does; refuse if there is none

Refusing leaves the row for the STUB-REVEAL gate rule to count, which is the
point: a budget that shrinks is a record of what is left, and a rule that cannot
be satisfied is better than a repair that invents.

    python3 tools/corpus/fix_stub_reveals.py [--apply]

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

# "1987." / "c. 1450" / "-44" / "1969 BCE" — a year standing in for a description.
STUB = re.compile(r"^\s*(?:c\.\s*)?-?\d{1,4}(?:\s*(?:BCE?|AD|CE))?\s*[.,;]?\s*$", re.I)
MAX_CHARS = 165


def split_desc(expl):
    """-> (subject, description) for the "Subject: description" reveal shape."""
    if not expl or ":" not in expl or "→" in expl:
        return None, None
    s, d = expl.split(":", 1)
    return s.strip(), d.strip()


def first_sentence(d):
    return re.split(r"(?<=[.!?])\s", d, maxsplit=1)[0].strip()


def leads():
    out = {}
    if not SOURCE_DB.exists():
        return out
    db = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    for title, text in db.execute(
            "select title, lead from prose where lead is not null and length(lead) > 80"):
        parts = re.split(r"(?<=[.!?])\s+(?=[A-Z])", text)
        keep = [x.strip() for x in parts if 40 <= len(x.strip()) <= MAX_CHARS]
        if keep:
            out[title] = keep
    db.close()
    return out


def repair_shape_sources(apply):
    """The same defect, in the files corpus.json does not own.

    The first version of this script walked corpus.json alone and the gate went
    green, so "Whitney Houston: 2012." kept rendering in Closest Call — that mode
    carries its OWN explanation cell. A rule that names one file checks one file.
    Every subject here already has a real description in corpus.json; borrow it.
    """
    rows = json.loads(CORPUS.read_text())["questions"]
    good = {}
    for q in rows:
        subj, d = split_desc(q[6] or "")
        if subj and d and not STUB.match(first_sentence(d)):
            good.setdefault(subj, d)

    total = 0
    for name in ("closest.json", "oddoneout.json", "match.json", "order.json",
                 "thisorthat.json", "picture.json", "typeanswer.json",
                 "enumerate.json"):
        path = ROOT / "assets" / name
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        srows = data["questions"]
        touched = 0
        for r in srows:
            for i, cell in enumerate(r):
                if not isinstance(cell, str) or ":" not in cell or "\u2192" in cell:
                    continue
                subj, d = split_desc(cell)
                if d is None or not STUB.match(first_sentence(d)):
                    continue
                rest = d[len(first_sentence(d)):].strip()
                # A real sentence already follows; or corpus.json knows this
                # subject; or say nothing rather than say a year.
                r[i] = (f"{subj}: {rest}" if rest
                        else f"{subj}: {good[subj]}" if subj in good else "")
                touched += 1
        if touched and apply:
            b = json.dumps(srows, ensure_ascii=False, separators=(",", ":"))
            path.write_text(
                f'{{"version":"{corpus_version(b)}","count":{len(srows)},"questions":{b}}}')
        if touched:
            print(f"   {name}: {touched} bare-number reveals repaired")
        total += touched
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    lead = leads()

    trimmed = filled = refused = 0
    by_cat = collections.Counter()
    examples = []
    for q in rows:
        subj, d = split_desc(q[6] or "")
        if d is None:
            continue
        head = first_sentence(d)
        if not STUB.match(head):
            continue
        rest = d[len(head):].strip()
        before = q[6]
        if rest:
            q[6] = f"{subj}: {rest}"
            trimmed += 1
        else:
            # Same standalone test as fix_hollow_reveals: a lead sentence only
            # works out of context if its subject is recoverable.
            pick = None
            for s in lead.get(q[7], []):
                if re.match(r"^(also|however|moreover|these|they|he|she|his|her)\b", s, re.I):
                    continue
                if q[7] and q[7].split()[0].lower() in s.lower() or re.match(r"^(It|Its|The)\b", s):
                    pick = s
                    break
            if not pick:
                # Nothing true to say. Clearing the field is not a loss: the web
                # renders "No story recorded for this one." and iOS renders
                # nothing, both of which are honest, where "Matthew Perry: 1969."
                # is the app claiming to explain and then naming a number. The
                # row stays playable and content_audit counts it hollow, which is
                # what it is.
                q[6] = ""
                refused += 1
                by_cat[q[4]] += 1
                continue
            q[6] = f"{subj}: {pick}"
            filled += 1
        if len(examples) < 6:
            examples.append((before[:96], q[6][:96]))

    print(f"bare-number descriptions dropped (a real sentence followed): {trimmed}")
    print(f"bare-number descriptions replaced from Stage C prose:        {filled}")
    print(f"refused (no prose to say who this is):                       {refused}")
    if by_cat:
        print("   refusals by category:", dict(by_cat.most_common()))
    for b, n in examples:
        print(f"\n   was: {b}\n   now: {n}")

    print("shape sources:")
    shaped = repair_shape_sources(a.apply)
    print(f"   total in shape sources: {shaped}")

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
