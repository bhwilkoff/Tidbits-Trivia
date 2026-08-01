#!/usr/bin/env python3
"""Strip Wikipedia disambiguators that leaked into templated MCQ prompts.

`fix_match_giveaways.py` fixed exactly this for Match-Up rounds after play-testing
found "Magnificat (Bach) -> Johann Sebastian Bach" as a free pair. The MCQ template
families have the same disease and were never swept — found again while
play-testing Create over the 1,000 most-viewed Wikipedia articles:

    Who composed Magnificat (Bach)?              -> Johann Sebastian Bach
    Who wrote The History of Rome (Mommsen)?     -> Theodor Mommsen
    Who composed Symphony No. 3 (Górecki)?       -> Henryk Górecki
    On which continent is Iskar (river)?         -> Europe
    Who wrote You Can't Take It with You (play)? -> George S. Kaufman

Two distinct faults, measured across the shipping corpus:

  * 32 rows where the parenthetical NAMES THE ANSWER. The player is handed a free
    point, and there is no repair: these are all generic work titles whose
    parenthetical is the only thing identifying them, so "Who composed Symphony
    No. 3?" is ambiguous by nature. They are dropped.
  * ~8,300 rows where it is merely machine noise: "(river)", "(play)", "(novel)",
    "(1927 song)". The question is sound; it just does not read like something a
    human wrote. These get the parenthetical stripped from the PROMPT only.

`source_title` is deliberately left untouched: it is what saved-quiz refs and the
relevance ranker resolve against (docs/QUIZ-CONTRACT.md), and the disambiguator is
doing real work there.

A strip that would collide with another row's prompt in the same template family,
with a different answer, is refused — the parenthetical exists to disambiguate, and
collapsing two questions into one wording makes both unanswerable. Anything that
cannot be fixed safely is reported and left alone, never half-repaired.

    python3 tools/corpus/fix_prompt_disambiguators.py [--check]

`--check` exits non-zero if any leaking prompt remains (CI guard).
Run tools/corpus/resync_corpus.sh afterwards to propagate to every platform.
"""
import json
import pathlib
import re
import sys
import unicodedata
import collections

CORPUS = pathlib.Path("assets/corpus.json")
PAREN = re.compile(r"\s*\([^()]*\)")


def fold(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s or "")
                   if not unicodedata.combining(c)).lower()


def strip_parens(s):
    out, prev = s, None
    while out != prev:
        prev = out
        out = PAREN.sub("", out)
    return out.strip()


def leaks_answer(title, answer):
    """Does the disambiguator name (part of) the answer?"""
    inner = " ".join(re.findall(r"\(([^)]*)\)", title))
    fi = fold(inner)
    words = [w for w in re.split(r"[^a-z0-9]+", fold(answer)) if len(w) >= 4]
    return bool(words) and any(w in fi for w in words)


def family(qid):
    parts = qid.split(":")
    return ":".join(parts[:2]) if len(parts) > 1 else qid


def main():
    check = "--check" in sys.argv
    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    # Row shape: [id, prompt, options, correct, category, difficulty, explanation,
    # source_title, source_url, ...]. Read positionally like the other tools do.
    def get(r, i):
        return r[i] if len(r) > i else None

    # What prompts already exist per family, so a strip cannot collide.
    by_family = collections.defaultdict(lambda: collections.defaultdict(set))
    for r in rows:
        qid, prompt = get(r, 0), get(r, 1)
        opts, ci = get(r, 2) or [], get(r, 3) or 0
        answer = opts[ci] if ci < len(opts) else ""
        by_family[family(qid)][prompt].add(answer)

    stripped = dropped = refused = 0
    examples = {"stripped": [], "dropped": [], "refused": []}
    keep = []
    for r in rows:
        qid, prompt, title = get(r, 0), get(r, 1), get(r, 7)
        opts, ci = get(r, 2) or [], get(r, 3) or 0
        answer = opts[ci] if ci < len(opts) else ""
        if not title or "(" not in title or not prompt or title not in prompt:
            keep.append(r)
            continue
        bare = strip_parens(title)
        new_prompt = prompt.replace(title, bare)

        if leaks_answer(title, answer):
            # A free point, and unrepairable: these are all generic work titles
            # ("Magnificat", "Symphony No. 3", "String Quintet") whose parenthetical
            # is the only thing making them identifiable. With it the answer is
            # printed in the question; without it the question is ambiguous by
            # nature, even where the bare title happens to be unique in THIS corpus.
            # Dropping is the honest call — it is 32 rows out of 128,670.
            dropped += 1
            if len(examples["dropped"]) < 5:
                examples["dropped"].append(f"{prompt}  ->  {answer}")
            continue

        others = by_family[family(qid)].get(new_prompt)
        if others and others - {answer}:
            refused += 1
            if len(examples["refused"]) < 5:
                examples["refused"].append(f"{prompt}  (would collide)")
            keep.append(r)
            continue

        r[1] = new_prompt
        stripped += 1
        if len(examples["stripped"]) < 5:
            examples["stripped"].append(f"{prompt}  ->  {new_prompt}")
        keep.append(r)

    print(f"stripped={stripped}  dropped={dropped}  refused={refused}  "
          f"kept={len(keep)} of {len(rows)}")
    for label, items in examples.items():
        for e in items:
            print(f"   {label:9} {e[:110]}")

    if check:
        sys.exit(1 if (stripped or dropped) else 0)
    if not stripped and not dropped:
        print("nothing to do")
        return
    data["questions"] = keep
    CORPUS.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {CORPUS} — now run tools/corpus/resync_corpus.sh")


if __name__ == "__main__":
    main()
