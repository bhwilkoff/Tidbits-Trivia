"""Tidy the text the player reads after answering.

Scanned all 110,140 reveals for things that are wrong as TYPESETTING rather than
as facts, after reading 220 served prompts and realising the payoff panel had
never had the same treatment.

    Arkansas ( , AR-kən-saw) is a landlocked state...
    Delaware (  DEL-ə-wair) is a state in the Mid-Atlantic...
    Nevada ( , nə-VAD-ə; Spanish: [ne.ˈβa.ða] ) is a landlocked...

An IPA transcription was stripped out of the Wikipedia lead and left its
delimiters behind, so the reveal shows an empty slot, a doubled space, or a space
before a comma. 1,571 doubled spaces and 647 spaces before punctuation.

Separately, 11,929 reveals end without a full stop — "Mannitol: Chemical
compound" — because a Wikidata one-liner is a label, not a sentence. In a panel
that also carries prose sentences, the missing stop reads as truncation.

None of this changes a single fact. It is the difference between a payoff that
looks written and one that looks scraped.

    python3 tools/corpus/fix_reveal_hygiene.py [--apply]

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
SHAPES = ["closest.json", "oddoneout.json", "match.json", "order.json",
          "thisorthat.json", "picture.json", "typeanswer.json", "enumerate.json"]


def tidy(text, add_stop=True):
    """Typesetting only — never touches a word.

    `add_stop` is False for the shape sources, whose cells include OPTION text.
    A period appended to "Yesterday (song)" on an answer card would be a defect
    introduced by a script that exists to remove them.
    """
    # Iterate to a fixed point. These substitutions feed each other — collapsing
    # "(; " can expose a space-before-punctuation that the earlier rule already
    # passed — so a single pass left 8 rows still dirty and the gate caught them.
    # The same non-idempotence shipped "based based based based" once already.
    s = text
    for _ in range(4):
        after = _tidy_once(s)
        if after == s:
            break
        s = after
    if add_stop and s and s[-1] not in ".!?)]\"'”’":
        s += "."
    return s


def _tidy_once(text):
    s = text
    # "( , AR-kən-saw)" and "(  DEL-ə-wair)" — an emptied leading element.
    s = re.sub(r"\(\s*[,;]\s*", "(", s)
    s = re.sub(r"\(\s{2,}", "(", s)
    # " )" and " ]" left by the same stripping.
    s = re.sub(r"\s+([)\]])", r"\1", s)
    # A parenthetical that lost everything.
    s = re.sub(r"\s*\(\s*\)", "", s)
    s = re.sub(r"\s*\[\s*\]", "", s)
    # Space before punctuation, then runs of whitespace.
    s = re.sub(r"\s+([,.;:!?])", r"\1", s)
    return re.sub(r"[ \t]{2,}", " ", s).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    changed = 0
    why = collections.Counter()
    examples = []
    for q in rows:
        before = (q[6] or "").strip()
        if not before:
            continue
        after = tidy(before)
        if after == before:
            continue
        if re.search(r"\s{2,}", before):
            why["doubled space"] += 1
        elif re.search(r"\s+[,.;:]", before) or re.search(r"\(\s*[,;]", before):
            why["stripped pronunciation left its delimiters"] += 1
        else:
            why["no end punctuation"] += 1
        if len(examples) < 6 and len(before) > 40:
            examples.append((before[:72], after[:72]))
        q[6] = after
        changed += 1

    shaped = 0
    shape_data = {}
    for name in SHAPES:
        path = ROOT / "assets" / name
        if not path.exists():
            continue
        d = json.loads(path.read_text())
        srows = d["questions"]
        touched = 0
        for r in srows:
            for i, cell in enumerate(r):
                if isinstance(cell, str) and len(cell) > 24 and ("." in cell or "(" in cell):
                    new = tidy(cell, add_stop=False)
                    if new != cell:
                        r[i] = new
                        touched += 1
        if touched:
            shape_data[name] = (d, srows)
            shaped += touched

    print(f"reveals tidied: {changed:,}   {dict(why)}")
    print(f"shape-source cells tidied: {shaped:,}")
    for b, n in examples:
        print(f"\n   was: {b}\n   now: {n}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    for name, (d, srows) in shape_data.items():
        b = json.dumps(srows, ensure_ascii=False, separators=(",", ":"))
        (ROOT / "assets" / name).write_text(
            f'{{"version":"{d["version"]}","count":{len(srows)},"questions":{b}}}')
    print(f"\nwrote {CORPUS} and {len(shape_data)} shape sources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
