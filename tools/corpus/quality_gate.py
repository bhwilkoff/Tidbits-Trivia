#!/usr/bin/env python3
"""Fail the build when the corpus contains a question that should never ship.

    python3 tools/corpus/quality_gate.py            # exits non-zero on a violation
    python3 tools/corpus/quality_gate.py --report   # list everything, exit 0

Every quality fix this session was REACTIVE: play, notice something bad, fix that
instance. That is unbounded work, because nothing stopped the next bad question
from appearing — the audit reported, and reporting is not a gate. This is the
gate. It runs over the shipped data files, not a sample of gameplay, so a defect
cannot slip through by not being drawn during a sweep.

Each rule below is here because a real question in this app hit it:

  READ-OFF        "Cædmon's Hymn -> Cædmon", "Singapore -> Singapore dollar" —
                  the answer is inside the question.
  ANSWER-IN-PROMPT "Headquartered in Dallas's Whitacre Tower ... AT&T".
  DUP-OPTION      the same option twice in one set of four.
  BROKEN-SHAPE    a mode's question with no shape payload, so Closest Call
                  silently renders as a plain MCQ.
  PLACEHOLDER     unresolved %@ / nil / Optional( in a prompt.
  ERA-SPREAD      four dated people spanning 400+ years, so the era in the clue
                  eliminates three options before any knowledge is applied.
  MACHINE-STEM    "In what year was Sir Gawain and the Green Knight founded or
                  created?" — a Wikidata property name left in the prose.
  THIN-COVERAGE   a mode x category the bundle cannot fill, which silently
                  serves a different category and says nothing.

Thresholds are the count that ships TODAY, so the gate locks in progress and
fails on regression. Lower them as content improves; never raise one to make a
build pass.
"""
import argparse
import collections
import json
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
A = ROOT / "assets"

# rule -> how many known instances are tolerated. Every one of these should be
# trending to zero; a PR that raises a number is doing the wrong thing.
BUDGET = {
    "READ-OFF": 0,
    "ANSWER-IN-PROMPT": 0,      # the 6 that existed were dropped, not budgeted
    "DUP-OPTION": 0,
    "BROKEN-SHAPE": 0,
    "PLACEHOLDER": 0,
    "ERA-SPREAD": 0,            # 401 repaired by occupation+era; 44 unrepairable, dropped
    "MACHINE-STEM": 0,
    "THIN-COVERAGE": 0,
}

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for",
        "de", "la", "le", "el", "s", "is", "was", "or"}

# Wikidata property names and template scaffolding that must never reach a
# player. "founded or created" shipped on 451 rows, including Auschwitz.
# Narrowed after its first run reported 16 violations of which 16 were mine:
# `\binception\b` matched twelve references to the FILM Inception, and
# "instance of" matched a sentence of ordinary English. A gate that cries wolf
# gets its budget raised, which is the failure mode this file exists to prevent.
# Only phrases that are never natural prose survive.
MACHINE = re.compile(
    r"founded or created|\bwikidata\b|\bqid\b|\bQ\d{4,}\b|"
    r"significant event|subclass of|\bP\d{2,4}:", re.I)
PLACEHOLDER = re.compile(r"%@|%\d*\$?[sd]|\{\}|\bnil\b|Optional\(|\bNaN\b|\bundefined\b")

SHAPE_FILES = {
    "picture.json":    ("pictureId", 10, 4, 9),    # (mode, per-round, cat idx, shape idx)
    "thisorthat.json": ("thisOrThat", 10, 4, None),
    "closest.json":    ("closestCall", 8, 8, None),
    "order.json":      ("ordering", 6, 4, None),
    "match.json":      ("matching", 6, 4, None),
    "typeanswer.json": ("typeAnswer", 8, 4, None),
    "oddoneout.json":  ("oddOneOut", 8, 4, None),
    "enumerate.json":  ("enumerate", 3, 3, None),
}
CATEGORIES = ["history", "science", "geography", "arts", "screen", "music",
              "sports", "business"]


def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


def reads_off(a, b):
    """Can one side be read off the other, with no knowledge?"""
    aw, bw = sig(a), sig(b)
    if not aw or not bw:
        return False
    if aw & bw or aw.issubset(bw) or bw.issubset(aw):
        return True
    # The adjectival form: Russia/Russian, India/Indian.
    return any(len(x) >= 4 and len(y) >= 4 and (x.startswith(y) or y.startswith(x))
               for x in aw for y in bw)


def load(name):
    p = A / name
    return json.loads(p.read_text())["questions"] if p.exists() else []


def birth_years():
    out = {}
    ents = json.loads((A / "enrich.json").read_text())["entities"]
    for t, e in ents.items():
        b = e.get("numbers", {}).get("birth_year")
        if b:
            out[t.replace("_", " ")] = int(b["value"])
    return out


def check():
    """rule -> list of human-readable violations."""
    bad = collections.defaultdict(list)
    years = birth_years()

    # ---- the corpus itself -------------------------------------------------
    for q in load("corpus.json"):
        prompt, opts, ci = q[1], q[2], q[3]
        if PLACEHOLDER.search(prompt or ""):
            bad["PLACEHOLDER"].append(f"{q[0]}: {prompt[:70]}")
        if MACHINE.search(prompt or ""):
            bad["MACHINE-STEM"].append(f"{q[0]}: {prompt[:70]}")
        if not opts or not (0 <= ci < len(opts)):
            continue
        folded = [fold(o) for o in opts]
        if len(set(folded)) < len(folded):
            bad["DUP-OPTION"].append(f"{q[0]}: {opts}")
        # The answer spelled out in its own prompt. Interrogatives are excluded:
        # "The Who" matched "Who composed the score for CSI?" because the answer's
        # only significant word is the question word.
        aw = sig(opts[ci]) - {"who", "what", "when", "where", "which", "why", "how"}
        if aw and aw.issubset(sig(prompt)) and len(fold(opts[ci])) > 3:
            bad["ANSWER-IN-PROMPT"].append(f"{q[0]}: '{opts[ci]}' in {prompt[:60]}")
        ys = [years.get(str(o)) for o in opts]
        if len(opts) >= 4 and all(ys) and max(ys) - min(ys) > 400:
            bad["ERA-SPREAD"].append(f"{q[0]}: {max(ys) - min(ys)}y {opts}")

    # ---- the shape sources -------------------------------------------------
    for name, (mode, per_round, cat_i, shape_i) in SHAPE_FILES.items():
        rows = load(name)
        if not rows:
            bad["BROKEN-SHAPE"].append(f"{name} is missing or empty")
            continue
        counts = collections.Counter()
        for r in rows:
            if len(r) > cat_i and isinstance(r[cat_i], str):
                counts[r[cat_i]] += 1
            if PLACEHOLDER.search(str(r[1])):
                bad["PLACEHOLDER"].append(f"{r[0]}: {str(r[1])[:70]}")
            if MACHINE.search(str(r[1])):
                bad["MACHINE-STEM"].append(f"{r[0]}: {str(r[1])[:70]}")
            if shape_i is not None and (len(r) <= shape_i or not r[shape_i]):
                bad["BROKEN-SHAPE"].append(f"{r[0]}: {mode} row has no shape payload")
        # Match Up: neither side may give the other away.
        if name == "match.json":
            for r in rows:
                for k, v in zip(r[2], r[3]):
                    if reads_off(k, v):
                        bad["READ-OFF"].append(f"{r[0]}: {k} -> {v}")
        # Every category must hold at least one round's worth.
        for c in CATEGORIES:
            if counts.get(c, 0) < per_round:
                bad["THIN-COVERAGE"].append(
                    f"{mode} x {c}: {counts.get(c, 0)} rows, a round needs {per_round}")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="list and exit 0")
    ap.add_argument("--full", action="store_true")
    a = ap.parse_args()

    bad = check()
    failed = False
    print(f"{'rule':18}{'found':>7}{'budget':>8}   status")
    for rule in sorted(BUDGET):
        n, cap = len(bad.get(rule, [])), BUDGET[rule]
        ok = n <= cap
        failed |= not ok
        print(f"{rule:18}{n:>7}{cap:>8}   {'ok' if ok else 'FAIL'}")
        if not ok or a.full:
            for v in bad.get(rule, [])[: (None if a.full else 5)]:
                print(f"      {v}")
    unknown = set(bad) - set(BUDGET)
    for rule in sorted(unknown):
        failed = True
        print(f"{rule:18}{len(bad[rule]):>7}{'—':>8}   FAIL (no budget defined)")

    if a.report:
        return 0
    if failed:
        print("\nA question that should never ship is in the data. Fix the content, "
              "or the generator that produced it — do not raise a budget.")
        return 1
    print("\nquality gate passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
