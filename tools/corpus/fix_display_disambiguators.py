#!/usr/bin/env python3
"""Put back the disambiguator that makes an ordering/comparison name answerable.

Found by reading a rendered Ordering round in the iOS QA sweep: "Put these people in
order of birth" listed **Bill O'Reilly (1905)** among baseball figures. That is
`Bill_O'Reilly_(cricketer)`, born 1905 — but the generators' `display_name()` strips
every parenthetical, so the card says "Bill O'Reilly", and a player who knows the
broadcaster (born 1949) orders him last and is marked wrong. Knowing more makes you
*less* likely to get it right, which is the worst thing a trivia question can do.

Measured across the shipped artifacts: **132 of 718 Ordering rows and 173 of 1,461
This-or-That rows** display a name whose Wikipedia title carried a disambiguator.
Wikipedia only adds one when the bare title is genuinely ambiguous, so its presence IS
the signal — this restores it rather than guessing.

Two carve-outs, both load-bearing:

  * A parenthetical containing a DIGIT is never restored. "Pinocchio (1940 film)" in a
    "which came first?" pair hands over the answer, which is the same defect in the
    other direction — and it is exactly why Odd One Out had its brackets removed
    (commit a3eb5b0). Brackets leak there; their absence misleads here.
  * A name is only rewritten when exactly ONE enriched title maps to it. Two titles
    collapsing to one display name is a different bug (a duplicate option), and
    picking one of them here would hide it.

Usage: python3 fix_display_disambiguators.py [--dry-run]
"""
import argparse
import hashlib
import json
import pathlib
import re
import urllib.parse
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIRRORS = {
    "order.json": [ROOT / "assets" / "order.json",
                   ROOT / "TidbitsTrivia" / "Resources" / "order.json",
                   ROOT / "android" / "app" / "src" / "main" / "assets" / "order.json"],
    "thisorthat.json": [ROOT / "assets" / "thisorthat.json",
                        ROOT / "TidbitsTrivia" / "Resources" / "thisorthat.json",
                        ROOT / "android" / "app" / "src" / "main" / "assets" / "thisorthat.json"],
}
NAME_INDEX = 2   # both shapes hold their displayed names at index 2
EXPL_INDEX = {"order.json": 5, "thisorthat.json": 6}


def bare(title):
    s = urllib.parse.unquote(title).replace("_", " ")
    s = re.sub(r"\s*\([^)]*\)", "", s)
    return s.split(",")[0].strip()


def qualifier(title):
    """The parenthetical, when it is safe to show. None if absent or numeric."""
    m = re.search(r"\(([^)]*)\)", urllib.parse.unquote(title).replace("_", " "))
    if not m:
        return None
    q = m.group(1).strip()
    return None if (not q or re.search(r"\d", q)) else q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    entities = json.load(open(ROOT / "assets" / "enrich.json"))["entities"]
    titles_for = defaultdict(set)
    for t in entities:
        titles_for[bare(t)].add(t)

    # bare name -> "Name (qualifier)", only where it is unambiguous and safe
    rename = {}
    for name, titles in titles_for.items():
        if len(titles) != 1:
            continue
        q = qualifier(next(iter(titles)))
        if q:
            rename[name] = f"{name} ({q})"

    for shape, paths in MIRRORS.items():
        src = json.load(open(paths[0]))
        changed = {}
        for r in src["questions"]:
            names = r[NAME_INDEX]
            if not isinstance(names, list):
                continue
            new_names = [rename.get(n, n) for n in names]
            if new_names == names:
                continue
            expl = r[EXPL_INDEX[shape]]
            # The reveal is left alone where the name is already followed by "(" — that
            # is its year, and "Sulpicia (satirist) (100)" reads worse than it reads
            # ambiguously. The CARD is where the ambiguity has to be resolved, because
            # that is where the player answers; by the reveal they have already been
            # told which Sulpicia this is. Elsewhere in the prose it IS rewritten,
            # longest-first so "Michael Kelly" inside a longer name is never half-replaced.
            for old in sorted({n for n in names if n in rename}, key=len, reverse=True):
                expl = re.sub(rf"(?<![\w(]){re.escape(old)}(?!\s*\()", rename[old], expl)
            changed[r[0]] = (new_names, expl)

        print(f"  {shape}: {len(changed):,} of {len(src['questions']):,} rows renamed")
        for rid, (n, _) in list(changed.items())[:4]:
            print(f"    {rid} -> {n}")
        if args.dry_run or not changed:
            continue

        for path in paths:
            d = json.load(open(path))
            for r in d["questions"]:
                if r[0] in changed:
                    r[NAME_INDEX], r[EXPL_INDEX[shape]] = changed[r[0]]
            body = json.dumps(d["questions"], ensure_ascii=False, separators=(",", ":"))
            version = hashlib.md5(body.encode()).hexdigest()[:12]
            path.write_text(f'{{"version":"{version}","count":{len(d["questions"])},'
                            f'"questions":{body}}}')
            print(f"    wrote {path.relative_to(ROOT)} (version {version})")


if __name__ == "__main__":
    main()
