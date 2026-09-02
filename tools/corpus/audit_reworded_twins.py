"""The same fact asked twice, reworded.

    src:describe:Will_Rogers  "A vaudeville-trained humorist born a citizen of the
                               Cherokee Nation ... who was he?"
    src:cloze:Will_Rogers     "Born a citizen of the Cherokee Nation, this
                               'Oklahoma's Favorite Son' ... who was he?"

Two generators ran over the same subject and produced the same question in
different words. It is redundancy, not variety: across sessions a player meets
the identical fact twice, and the corpus count overstates how much is really in
there.

WHAT COUNTS AS A TWIN, and why each part is needed --- every looser key was tried
and merged genuinely different questions:

  * same SUBJECT, same ANSWER, same OPTION SET. On its own this is not enough:
    "Of which country is Scone the capital?", "Which country uses the pound
    Scots?" and "Of which country is Scottish Gaelic an official language?" all
    share those three and are three different facts.
  * plus a prompt SIMILARITY >= 0.78 (difflib over letters-and-digits). That is
    what separates a rewording from a different fact about the same subject.
  * BARE comparison prompts are excluded --- they are handled by
    audit_unanswerable_people.py and their identity is the option set, not the
    wording.

WHICH ONE SURVIVES: the prompt naming MORE CONCRETE FACTS --- proper nouns and
years --- not the longer one. Length was the first rule and it was backwards. In
513 of 976 pairs the longer prompt is longer precisely BECAUSE it paraphrases a
name away:

    keep-by-length:  "...played Dr. Jo Wilson on a long-running medical drama"
    the one it drops: "...played Dr. Jo Wilson on Grey's Anatomy"

    keep-by-length:  "...playing basketball star Nathan Scott on a CW teen drama"
    the one it drops: "...playing Nathan Scott on The WB/CW drama series
                       'One Tree Hill'"

Naming the show is the better question by the interest bar --- a player who
watched Grey's Anatomy can play; "a long-running medical drama" tells them
nothing. Choosing by generator is also wrong: describe wins 376 pairs and cloze
the rest. Ties break on length, then on the lower id, so the result is
deterministic.

    python3 tools/corpus/audit_reworded_twins.py            # report
    python3 tools/corpus/audit_reworded_twins.py --write    # write tombstones
"""
import argparse
import collections
import difflib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS_JSON = ROOT / "assets/corpus.json"
TOMBSTONES = ROOT / "tools/corpus/tombstones.json"

SIMILARITY = 0.78
BARE = re.compile(r"^(which|who|what)[^?]{0,70}\?$", re.I)


def _pure_comparison(p: str) -> bool:
    if not BARE.match(p.strip()):
        return False
    return not any(w[:1].isupper() for w in p.strip().rstrip("?").split()[1:])


def _facts(p: str) -> int:
    """Concrete things a player can recognise: proper nouns and years. This is the
    clue count that matters, and it is NOT correlated with prompt length --- the
    wordier twin is usually the one that replaced a title with a description."""
    return len(set(re.findall(r"\b[A-Z][a-zA-Z\u2019'\-]+\b|\b\d{3,4}\b", p)))


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9 ]", "", s.lower())


def twins():
    rows = json.loads(CORPUS_JSON.read_text())["questions"]
    groups = collections.defaultdict(list)
    for r in rows:
        if _pure_comparison(r[1]):
            continue
        subj = r[7] if len(r) > 7 else None
        opts = r[2]
        if not subj or not isinstance(opts, list) or len(opts) < 2:
            continue
        if not (isinstance(r[3], int) and 0 <= r[3] < len(opts)):
            continue
        groups[(subj, opts[r[3]], frozenset(opts))].append(r)

    out = []
    for v in groups.values():
        for i in range(len(v)):
            for j in range(i + 1, len(v)):
                ratio = difflib.SequenceMatcher(None, _norm(v[i][1]), _norm(v[j][1])).ratio()
                if ratio < SIMILARITY:
                    continue
                a, b = v[i], v[j]
                ka, kb = (_facts(a[1]), len(a[1])), (_facts(b[1]), len(b[1]))
                if (ka, b[0]) >= (kb, a[0]):
                    keep, drop = a, b
                else:
                    keep, drop = b, a
                out.append((ratio, keep, drop))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--show", type=int, default=6)
    a = ap.parse_args()

    pairs = twins()
    for ratio, keep, drop in pairs[: a.show]:
        print(f"ratio {ratio:.2f}")
        print(f"  KEEP [{keep[0][:34]:36}] {keep[1][:96]}")
        print(f"  DROP [{drop[0][:34]:36}] {drop[1][:96]}")
    print(f"\n{len(pairs)} reworded twins (similarity >= {SIMILARITY})")

    if a.write and pairs:
        doc = json.loads(TOMBSTONES.read_text()) if TOMBSTONES.exists() else {}
        bucket = doc.setdefault("corpus", {})   # shape-keyed; a flat write wipes every guard
        for _ratio, _keep, drop in pairs:
            bucket[drop[0]] = "reworded twin: same subject, answer and options, prompt reworded"
        TOMBSTONES.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {len(pairs)} tombstones into the `corpus` bucket")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
