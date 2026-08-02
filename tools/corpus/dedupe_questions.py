"""Drop questions the corpus already asks somewhere else.

7,800 rows across 5,070 groups share a normalised prompt AND the same answer.
The player can draw two of them in one round and be asked the same thing twice.

Two generators account for most of it. `src:describe:X` and `src:cloze:X` were
each given the same subject and wrote the same sentence:

    This English poet and novelist is best remembered for his 1947 novel...
      src:describe:Malcolm_Lowry
      src:cloze:Malcolm_Lowry

The rest are one fact reached by two Wikidata paths — "What is the capital of
Malta?" exists under both the country's QID and the capital's.

Prompt+answer is NOT the key for every shape. The comparison generators (`sup:`,
`chron:`) write a deliberately generic stem — "Which one below has the biggest
population?" — where the OPTION SET is the question:

    Which one below has the biggest population?
      sup:P1082:41389925541    Tibet / West Bank / Gibraltar / Azad Kashmir
      sup:P1082:397081799445   Donetsk PR / Azad Kashmir / Guayana Esequiba / Abkhazia

Both answer Azad Kashmir and they are different questions. A first version of
this script keyed on prompt+answer alone and would have deleted 7,274 perfectly
good comparison rows. For those generators the option set is part of the key.

Which one survives, in order:
  1. a reveal that STATES A TYPE ("American writer") over one that does not
  2. the richer reveal — the payoff is the point
  3. a real Wikipedia source URL over none
  4. the lexicographically smallest id, so the choice is stable across runs

Rule 1 is not cosmetic. A first version scored on length alone, which prefers
prose over a terse Wikidata description — and the terse one is what every
classifier in this directory reads to type a subject. It dropped Susan Sontag's
"American writer" in favour of a longer paragraph, leaving her untypeable, and
NATIONALITY-FREE went BLIND in the gate self-test because a planted defect needs
her nationality to be known. Keeping the longest text can cost the corpus its
only statement of what a subject IS.

    python3 tools/corpus/dedupe_questions.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from quality_gate import readable_description                     # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"


def norm(s):
    return re.sub(r"\W+", " ", (s or "").lower()).strip()


def answer_of(r):
    opts = r[2] or []
    return str(opts[r[3]]) if 0 <= r[3] < len(opts) else ""


# Generators whose prompt is generic BY DESIGN: the option set is the question.
# For these, two rows are the same only when they offer the same four things.
GENERIC_STEM = ("sup", "chron")


def dedupe_key(r):
    prefix = r[0].split(":")[0]
    base = (norm(r[1]), norm(answer_of(r)))
    if prefix in GENERIC_STEM:
        return base + (tuple(sorted(str(o) for o in (r[2] or []))),)
    return base


def score(r):
    """Higher is better. A type-stating reveal wins outright; length breaks ties."""
    reveal = (r[6] or "").strip()
    typed = 1 if readable_description(reveal, r[7]) else 0
    has_url = 1 if str(r[8] or "").startswith("http") else 0
    return (typed, len(reveal), has_url)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    groups = collections.defaultdict(list)
    for r in rows:
        groups[dedupe_key(r)].append(r)

    drop = set()
    by_prefix = collections.Counter()
    examples = []
    for key, members in groups.items():
        if len(members) < 2:
            continue
        members = sorted(members, key=lambda r: (-score(r)[0], -score(r)[1],
                                                 -score(r)[2], r[0]))
        keep, rest = members[0], members[1:]
        for r in rest:
            drop.add(r[0])
            by_prefix[r[0].split(":")[0]] += 1
        if len(examples) < 5:
            examples.append((keep[1][:58], keep[0], [r[0] for r in rest]))

    kept = [r for r in rows if r[0] not in drop]
    print(f"duplicate groups: {sum(1 for v in groups.values() if len(v) > 1):,}")
    print(f"rows dropped:     {len(drop):,}   by generator: {dict(by_prefix.most_common(6))}")
    print(f"corpus:           {len(rows):,} -> {len(kept):,}")
    for prompt, keep_id, dropped in examples:
        print(f"\n   {prompt}...\n     keep {keep_id}\n     drop {dropped}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(kept, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(kept)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
