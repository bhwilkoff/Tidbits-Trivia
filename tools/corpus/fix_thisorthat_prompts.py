#!/usr/bin/env python3
"""Name the dimension on the This-or-That rows the generator no longer emits.

`gen_thisorthat.py --regenerate` replaced "Which came first?" with "Who was born
first?" / "Which began first?" on the 857 rows it still produces. It could not
touch the 314 rows genguard keeps because the generator stopped producing them
(the per-bucket cap moves as the corpus grows), and those carry the original
defect: "Which came first? Zeami Motokiyo / William Kempe", asked of two people.

The row itself does not record which metric built it, so the metric is recovered
the same way the generator chose it — from `enrich.json`, keyed on the wiki
titles already embedded in the id.

The 37 `biztot:` rows from `gen_business_shapes.py` carried a second defect the
same reading found: their reveal states two years and no claim —

    3M (1902) and AMD (1969).

which tells a player who got it wrong nothing at all. Fixed here for the shipped
rows and in the generator for future ones.

Usage: python3 fix_thisorthat_prompts.py [--dry-run]
"""
import argparse
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIRRORS = [
    ROOT / "assets" / "thisorthat.json",
    ROOT / "TidbitsTrivia" / "Resources" / "thisorthat.json",
    ROOT / "android" / "app" / "src" / "main" / "assets" / "thisorthat.json",
]

BORN = ("Who was born first?", "was born before")
BEGAN = ("Which began first?", "came before")


def metric_for(entities, a, b):
    """birth_year only if BOTH carry it, inception only if both carry that."""
    for metric in ("birth_year", "inception"):
        ea = entities.get(a, {}).get("numbers", {})
        eb = entities.get(b, {}).get("numbers", {})
        if metric in ea and metric in eb:
            return metric
    return None


def dated_pair(entities, row):
    a, _, b = row[0][len("tot:first:"):].partition("|")
    metric = metric_for(entities, a, b)
    if metric is None:
        return None
    prompt, verb = BORN if metric == "birth_year" else BEGAN
    return prompt, row[6].replace(" came before ", f" {verb} ")


def business(row):
    """A company pair: name the dimension, and make the reveal state the claim."""
    years = re.findall(r"\((\d{3,4})\)", row[6])
    if len(years) != 2:
        return None
    names, first = row[2], row[3]
    other = 1 - first
    return ("Which company was founded first?",
            f"{names[first]} ({years[first]}) was founded before "
            f"{names[other]} ({years[other]}).")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    entities = json.load(open(ROOT / "assets" / "enrich.json"))["entities"]

    src = json.load(open(MIRRORS[0]))
    fixed = {}
    unknown = []
    for r in list(src["questions"]):
        if r[1] != "Which came first?":
            continue
        if r[0].startswith("biztot:"):
            fix = business(r)
        elif r[0].startswith("tot:first:"):
            fix = dated_pair(entities, r)
        else:
            fix = None
        if fix is None:
            unknown.append(r[0])
            continue
        fixed[r[0]] = fix

    print(f"  rewrote {len(fixed):,} rows; {len(unknown):,} unresolved")
    for i in unknown[:5]:
        print(f"    unresolved {i}")
    if args.dry_run or not fixed:
        return

    # Apply the same edit to every mirror by id, so the three stay byte-identical
    # even if a mirror is momentarily behind. The version is the body's hash — the
    # clients key their cache on it, so leaving it stale would ship the fix to a
    # player who never re-reads the file.
    for path in MIRRORS:
        d = json.load(open(path))
        for r in d["questions"]:
            if r[0] in fixed:
                r[1], r[6] = fixed[r[0]]
        body = json.dumps(d["questions"], ensure_ascii=False, separators=(",", ":"))
        version = hashlib.md5(body.encode()).hexdigest()[:12]
        path.write_text(f'{{"version":"{version}","count":{len(d["questions"])},'
                        f'"questions":{body}}}')
        print(f"  wrote {path.relative_to(ROOT)} (version {version})")


if __name__ == "__main__":
    main()
