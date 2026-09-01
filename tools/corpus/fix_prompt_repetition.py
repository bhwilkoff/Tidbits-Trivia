"""Stop a round showing the same sentence twice.

Measured 2026-08-02: a ten-question round contains the SAME prompt text verbatim
7.4% of the time. The cause is that comparison questions come from a handful of
templates used ~1,900 times each:

    1,941  Which one below was established earliest?
    1,920  Which of these four was founded earliest?
    1,891  Which of these was founded earliest?
    1,774  Which of these four came first?

Four phrasings of ONE question, which is variety — but at 1,900 uses apiece the
birthday problem does the rest, and seeing "Which of these four is the longest?"
twice in a round reads as a bug rather than as two questions.

The repair keeps every phrasing already in use, adds a few more per class, and
distributes them by a stable hash of the row id so the assignment is
deterministic and identical on every platform. Nothing about the question
changes — only which of several true ways of asking it this row uses.

    python3 tools/corpus/fix_prompt_repetition.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import hashlib
import json
import pathlib
import random
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

# Every phrasing must be true of every row in its class, because assignment is by
# hash and no row gets to opt out.
VARIANTS = {
    "chron:P571": [
        "Which of these four was founded earliest?",
        "Which one below was established earliest?",
        "Which of these was founded earliest?",
        "Which of these four came first?",
        "Which of these four is the oldest?",
        "Which of these four dates back furthest?",
        "Which of these four has been around longest?",
        "Which one below started first?",
        "Which of these four began earliest?",
    ],
    "chron:P569": [
        "Which of these four was born earliest?",
        "Which one below was born first?",
        "Who among these four was born earliest?",
        "Which of these four is the eldest?",
    ],
    "chron:P577": [
        "Which of these four was released earliest?",
        "Which one below came out first?",
        "Which of these four is the oldest release?",
        "Which of these four appeared first?",
    ],
    "sup:P1082": [
        "Which of these four has the largest population?",
        "Which one below has the most people?",
        "Which of these four is the most populous?",
        "Which of these has the biggest population?",
    ],
    "sup:P2046": [
        "Which of these four is biggest by area?",
        "Which one below has the greatest area?",
        "Which of these covers the most land?",
        "Which of these four is the largest by area?",
        "Which one below is largest in area?",
        "Which of these four spans the most territory?",
    ],
    "sup:P2043": [
        "Which of these four is the longest?",
        "Which one below has the greatest length?",
        "Which of these four measures longest?",
    ],
    "sup:P2048": [
        "Which of these four is the tallest?",
        "Which one below has the greatest height?",
        "Which of these four stands tallest?",
    ],
}


def variant_for(row_id, choices):
    h = int(hashlib.sha1(row_id.encode()).hexdigest()[:8], 16)
    return choices[h % len(choices)]


def repeat_rate(prompts, seed=3, trials=20000):
    r = random.Random(seed)
    hit = sum(1 for _ in range(trials) if len(set(r.sample(prompts, 10))) < 10)
    return hit / trials


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    before = repeat_rate([q[1] or "" for q in rows])

    changed = 0
    per_class = collections.Counter()
    for q in rows:
        key = ":".join(q[0].split(":")[:2])
        choices = VARIANTS.get(key)
        if not choices or (q[1] or "") not in choices:
            continue                      # not a comparison row, or worded some other way
        new = variant_for(q[0], choices)
        if new != q[1]:
            q[1] = new
            changed += 1
        per_class[key] += 1

    after = repeat_rate([q[1] or "" for q in rows])
    print(f"comparison rows redistributed: {changed:,} across {len(per_class)} classes")
    print("   per class:", dict(per_class.most_common()))
    print(f"\nchance a 10-question round repeats a prompt verbatim: "
          f"{before:.1%} -> {after:.1%}")
    top = collections.Counter(q[1] or "" for q in rows).most_common(4)
    print("   most repeated prompt now:")
    for p, n in top:
        print(f"      {n:6}  {p[:58]}")

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
