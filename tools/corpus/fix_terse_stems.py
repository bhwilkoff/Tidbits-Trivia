"""Say what is being compared, in a sentence.

Rendered science, music, arts and sports rounds and read the prompts aloud:

    Most people of the four — which one?      (not English)
    Longest of the four — which one?          (longest WHAT?)
    Earliest of the four — which one?         (earliest by what measure?)
    On the periodic table, promethium is which symbol?

3,670 comparison questions use a headline fragment where the app has a perfectly
good sentence form for the same shape elsewhere in the corpus — "Which of these
was founded earliest?", "Which one below has the most people?". The generator
emitted two phrasings for one question type and only one of them reads.

The dimension is not guessed from the fragment; it comes from the Wikidata
property in the row id, which is also what the reveal already states out loud
("has the greatest population of the four (23.9 million)"). A prompt that says
less than its own answer panel is the defect.

    chron:P571  founded          chron:P569  born
    chron:P577  released         sup:P1082   population
    sup:P2043   length           sup:P2048   height

Also rewrites 22 "<element> is which symbol?" prompts into "Which symbol
represents <element>?", which is the form the other 19 already use.

    python3 tools/corpus/fix_terse_stems.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

TERSE = re.compile(r"of the four — which one\?$")

# row-id property -> the sentence the reveal already implies
BY_PROPERTY = {
    "chron:P571": "Which of these four was founded earliest?",
    "chron:P569": "Which of these four was born earliest?",
    "chron:P577": "Which of these four was released earliest?",
    "sup:P1082": "Which of these four has the largest population?",
    "sup:P2043": "Which of these four is the longest?",
    "sup:P2048": "Which of these four is the tallest?",
}

SYMBOL = re.compile(r"^On the periodic table, (.+?) is which symbol\?$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    rewritten = 0
    skipped = collections.Counter()
    examples = []
    for q in rows:
        prompt = q[1] or ""
        new = None

        if TERSE.search(prompt):
            key = ":".join(q[0].split(":")[:2])
            new = BY_PROPERTY.get(key)
            if not new:
                # An unknown property would get a sentence that claims the wrong
                # dimension. Leave it and report it rather than guess.
                skipped[key] += 1
                continue
        else:
            m = SYMBOL.match(prompt)
            if m:
                new = f"Which symbol represents {m.group(1)}?"

        if new and new != prompt:
            if len(examples) < 8:
                examples.append((prompt[:56], new[:58]))
            q[1] = new
            rewritten += 1

    print(f"terse comparison stems rewritten: {rewritten}")
    if skipped:
        print(f"   left alone (property not mapped): {dict(skipped)}")
    for b, n in examples:
        print(f"\n   was: {b}\n   now: {n}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
