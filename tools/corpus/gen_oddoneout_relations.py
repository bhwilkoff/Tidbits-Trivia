#!/usr/bin/env python3
"""Build Odd One Out from the corpus's relations, in every category.

`gen_oddoneout.py` derives rounds from ONE grouping — country-to-continent — so
`oddoneout.json` was 179 generated geography rows plus 67 authored ones covering
everything else, about 11 per category against an 8-question round. That is why
a player's SECOND Odd One Out round in a category silently became a mixed one
(measured: 100% -> 31.2% on-category on the second pass through the modes).

Nothing about that was necessary. The corpus holds 128,638 rows and a dozen 1:1
relations, and every one of them is a grouping: three films by the same director
and one that is not, three works by the same composer and one that is not, three
places in the same country and one that is not. This uses all of them.

    wd:director  wd:composer  wd:author  wd:continent  wd:capital  wd:currency
    rel:P17 (country)  rel:P170 (creator)  rel:P175 (performer)
    rel:P37 (official language)  rel:P112 (founded by)  rel:P61 (discovered by)

APPENDS — the existing 238 rows (including 67 authored and 10 authored Business)
are never touched, and re-runs add nothing new (idempotent by id).

    python3 tools/corpus/gen_oddoneout_relations.py [--apply]
"""
import argparse
import collections
import hashlib
import json
import pathlib
import random
import re
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIRRORS = ("assets", "TidbitsTrivia/Resources", "android/app/src/main/assets")
RNG = random.Random(20260801)   # deterministic: the three mirrors must agree

# relation -> (how the shared property reads, past-tense verb for the prompt).
#
# The property is NAMED in the prompt rather than left for the player to infer.
# A relation groups whatever the corpus has, so a round can hold a manga, an art
# school and a fairy tale at once — and then "which is the odd one out?" has
# several defensible answers (the only manga? the only building?) and the game
# marks three of them wrong. Saying "three of these are from Germany" leaves
# exactly one, and still asks the player to know which.
RELATIONS = {
    "wd:director":  ("directed by {}", "Three of these were directed by {}."),
    "wd:composer":  ("composed by {}", "Three of these were composed by {}."),
    "wd:author":    ("written by {}", "Three of these were written by {}."),
    "wd:continent": ("in {}", "Three of these are in {}."),
    "wd:capital":   ("the capital of {}", "Three of these have {} as their capital."),
    "wd:currency":  ("a place that uses the {}", "Three of these use the {}."),
    "rel:P17":      ("from {}", "Three of these are from {}."),
    "rel:P170":     ("created by {}", "Three of these were created by {}."),
    "rel:P175":     ("performed by {}", "Three of these were performed by {}."),
    "rel:P37":      ("a place where {} is official", "Three of these have {} as an official language."),
    "rel:P112":     ("founded by {}", "Three of these were founded by {}."),
    "rel:P61":      ("discovered by {}", "Three of these were discovered by {}."),
}
PER_CATEGORY = 160          # plenty for repeat play without bloating the bundle

# `rel:P17` is Wikidata's "country", which for a PLACE, a team or a company means
# origin, and for an artwork often means where it hangs. "Three of these are from
# France" beside the Mona Lisa is wrong — it is an Italian painting in a French
# museum. Restricted to the categories whose subjects are places, events,
# organizations and teams, where "from" is true.
P17_CATEGORIES = {"geography", "history", "sports", "business"}


def fold(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def reads_off_the_page(subject, value):
    """Does the subject's name already contain the property being tested?

    "Bach: Mass in B minor" beside a composer of Bach is not a question. Same
    rule the Match Up content pass applied, including the adjectival stem so
    "Russia"/"Russian" is caught.
    """
    sw, vw = set(fold(subject).split()), set(fold(value).split())
    if not sw or not vw:
        return False
    if sw & vw:
        return True
    return any(len(a) >= 4 and len(b) >= 4 and (a.startswith(b) or b.startswith(a))
               for a in sw for b in vw)


def build(rows, difficulty):
    """(category, relation) -> value -> [subjects]; then 3-of-a-kind + 1 outsider."""
    groups = collections.defaultdict(lambda: collections.defaultdict(set))
    diff_of, url_of = {}, {}
    for q in rows:
        rel = ":".join(q[0].split(":")[:2])
        if rel not in RELATIONS or not q[7] or not q[2]:
            continue
        if rel == "rel:P17" and q[4] not in P17_CATEGORIES:
            continue
        if not (0 <= q[3] < len(q[2])):
            continue
        value, subject = q[2][q[3]], q[7]
        if not value or reads_off_the_page(subject, value):
            continue
        groups[(q[4], rel)][value].add(subject)
        diff_of[subject] = q[5]
        url_of[subject] = q[8]

    out, per_cat = [], collections.Counter()
    # Recognizable subjects first — the same lesson the Match Up pass learned when
    # ranking by nothing produced "Hoysala Kingdom -> Halebidu".
    def rank(s):
        return (diff_of.get(s, 5), difficulty.get((url_of.get(s) or "").split("/wiki/")[-1], 5))

    for (cat, rel), byval in sorted(groups.items()):
        big = {v: sorted(subs, key=rank) for v, subs in byval.items() if len(subs) >= 3}
        if len(big) < 2:
            continue                     # need at least one other group for an outsider
        for value in sorted(big, key=lambda v: rank(big[v][0])):
            if per_cat[cat] >= PER_CATEGORY:
                break
            trio = big[value][:3]
            # The outsider comes from the SAME category and relation, so the round
            # is a real discrimination rather than "one of these is a different
            # kind of thing entirely".
            others = [(v, s) for v in big if v != value for s in big[v][:2]]
            if not others:
                continue
            others.sort(key=lambda p: rank(p[1]))
            # Rotate through the candidates instead of always taking the most
            # recognizable: that made "Snow White" the answer four rounds running.
            out_value, outsider = others[per_cat[cat] % min(len(others), 12)]
            if outsider in trio or reads_off_the_page(outsider, value):
                continue
            opts = trio + [outsider]
            RNG.shuffle(opts)            # rotate the answer position (rule R8)
            ci = opts.index(outsider)
            prop, stem = RELATIONS[rel]
            # Tense-free on purpose: one template has to serve "directed by",
            # "in Africa" and "where French is official" without reading as
            # machine output ("Sherlock Holmes is created by Arthur Conan Doyle").
            why = (f"{outsider} — {prop.format(out_value)}. "
                   f"The other three — {prop.format(value)}.")
            out.append([
                f"oddrel:{hashlib.sha1(f'{rel}|{cat}|{value}'.encode()).hexdigest()[:14]}",
                f"{stem.format(value)} Which one is not?", opts, ci, cat,
                max(2, min(5, diff_of.get(outsider, 3))), why,
                outsider, url_of.get(outsider, ""),
            ])
            per_cat[cat] += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    rows = json.load(open(ROOT / "assets" / "corpus.json"))["questions"]
    difficulty = json.load(open(ROOT / "assets" / "difficulty.json"))["difficulty"]
    built = build(rows, difficulty)
    print(f"built {len(built)} relation-derived Odd One Out rounds")
    print("by category:", dict(collections.Counter(r[4] for r in built).most_common()))
    for r in built[:5]:
        print(f"   {r[2]} -> {r[2][r[3]]}\n      {r[6][:100]}")
    if not args.apply:
        print("\n(dry run — pass --apply to append)")
        return

    base = json.load(open(ROOT / "assets" / "oddoneout.json"))
    have = {r[0] for r in base["questions"]}
    added = [r for r in built if r[0] not in have]
    all_rows = base["questions"] + added
    body = json.dumps(all_rows, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(all_rows)},"questions":{body}}}'
    for m in MIRRORS:
        p = ROOT / m / "oddoneout.json"
        if p.exists():
            p.write_text(payload)
    print(f"\nappended {len(added)}; oddoneout.json now {len(all_rows)} rows")


if __name__ == "__main__":
    main()
