#!/usr/bin/env python3
"""Give Business the shape rounds it has never had — additively.

Business is the only category with ZERO rows in the bundled shape sources, which
is why picking Business with Picture ID, Which First?, In Order, Name It, Match
Up, Odd One Out or Name as Many hands the player a round with no business
questions in it. Measured over 1,260 assembled rounds, every one of those
combinations came back 0% on-category.

This APPENDS rather than regenerating, and that is the whole design. Running
`gen_picture.py` / `gen_thisorthat.py` / `gen_typeanswer.py` today would drop
457 / 301 / 886 shipped rows apiece — rows that exist nowhere but the generated
artifact (see tools/corpus/authored/README.md). Appending sidesteps that
entirely: existing ids are never touched, and re-runs are idempotent by id.

Covers the three shapes derivable from data the corpus already has:

    picture.json     from subjects with a Commons image   (76 available)
    thisorthat.json  from inception years                 (74)
    order.json       from inception years                 (74)

Match Up, Odd One Out, Name as Many and Name It stay authored work. The first
three need a relation or a grouping the corpus does not carry for companies.
Name It was built and then dropped: it needs a prompt that identifies exactly ONE
company, and the bare descriptions do not — generating from them produced
"American multinational technology company — name it." three times over for three
different answers, and "United States — name it." seven times, because those rows
hold a relation answer in the explanation field rather than a description.

    python3 tools/corpus/gen_business_shapes.py [--apply]
"""
import argparse
import hashlib
import json
import pathlib
import random
import re
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIRRORS = ("assets", "TidbitsTrivia/Resources", "android/app/src/main/assets")
# Deterministic: the same corpus must produce the same rows on every run, or the
# three tracked copies drift apart and every platform ships a different quiz.
RNG = random.Random(20260801)


def is_description(d):
    """Is this a type description, or a relation answer that landed in the field?

    Rows whose explanation is "Visa Inc.: United States" carry the answer to some
    other question, not a description of the subject. Seven business subjects
    produced the prompt "United States — name it." that way. A description has
    lowercase type words in it; a proper noun does not.
    """
    if not d or len(d) < 13:
        return False
    words = [w for w in re.findall(r"[A-Za-z'&-]+", d) if len(w) > 1]
    if len(words) < 2:
        return False
    return not all(w[0].isupper() or w.lower() in {"the", "of", "and"} for w in words)


def name_of(title):
    s = urllib.parse.unquote(title).replace("_", " ")
    return re.sub(r"\s*\([^)]*\)", "", s).strip()


def load():
    qs = json.load(open(ROOT / "assets" / "corpus.json"))["questions"]
    enrich = json.load(open(ROOT / "assets" / "enrich.json"))["entities"]
    subs = {}
    for q in qs:
        if q[4] != "business" or "/wiki/" not in (q[8] or ""):
            continue
        t = q[8].split("/wiki/")[-1]
        subs.setdefault(t, {"url": q[8], "desc": "", "diff": q[5]})
        expl = q[6] or ""
        if ":" in expl and "→" not in expl and not subs[t]["desc"]:
            d = expl.split(":", 1)[1].strip()
            if is_description(d):
                subs[t]["desc"] = d
    return subs, enrich


def write(rel, new_rows):
    """Append rows to a shape file across all three tracked copies, by id."""
    base = json.load(open(ROOT / "assets" / rel))
    have = {r[0] for r in base["questions"]}
    added = [r for r in new_rows if r[0] not in have]
    rows = base["questions"] + added
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(rows)},"questions":{body}}}'
    for m in MIRRORS:
        p = ROOT / m / rel
        if p.exists():
            p.write_text(payload)
    return len(added), len(rows)


def build(subs, enrich):
    out = {"picture.json": [], "thisorthat.json": [], "order.json": []}

    imaged = sorted(t for t in subs if enrich.get(t, {}).get("image"))
    dated = sorted((t, int(enrich[t]["numbers"]["inception"]["value"])) for t in subs
                   if enrich.get(t, {}).get("numbers", {}).get("inception"))

    # --- Picture ID: name the company from its image. Distractors are other
    #     business subjects, so a wrong answer is never a different KIND of thing
    #     (the giveaway the play sweep found on Zlatan Ibrahimovic).
    pool = [name_of(t) for t in imaged]
    for t in imaged:
        me = name_of(t)
        others = [n for n in pool if n != me]
        if len(others) < 3:
            continue
        opts = RNG.sample(others, 3) + [me]
        RNG.shuffle(opts)
        d = subs[t]["desc"] or "company"
        out["picture.json"].append([
            f"bizpic:{t}", f"Which company is this?", opts, opts.index(me),
            "business", subs[t]["diff"], f"{me}: {d}", me, subs[t]["url"],
            enrich[t]["image"],
        ])

    # --- Which First? / In Order, from founding years.
    for i in range(0, len(dated) - 1, 2):
        (ta, ya), (tb, yb) = dated[i], dated[i + 1]
        if ya == yb:
            continue
        a, b = name_of(ta), name_of(tb)
        first = 0 if ya < yb else 1
        # The reveal has to state the claim: "3M (1902) and AMD (1969)." names two
        # years and no answer, which is exactly no help to the player who missed it.
        early, late = ((a, ya), (b, yb)) if first == 0 else ((b, yb), (a, ya))
        out["thisorthat.json"].append([
            f"biztot:{ta}|{tb}", "Which company was founded first?", [a, b], first,
            "business", 2,
            f"{early[0]} ({early[1]}) was founded before {late[0]} ({late[1]}).",
            f"{a} / {b}", subs[ta]["url"],
        ])
    quads = [dated[i:i + 4] for i in range(0, len(dated) - 3, 4)]
    for qi, quad in enumerate(quads):
        if len({y for _, y in quad}) < 4:
            continue
        quad = sorted(quad, key=lambda p: p[1])
        names = [name_of(t) for t, _ in quad]
        years = [y for _, y in quad]
        out["order.json"].append([
            f"bizorder:{qi}:{quad[0][0]}", "Put these in order — earliest first.",
            names, years, "business",
            " → ".join(f"{n} ({y})" for n, y in zip(names, years)),
            names[0], subs[quad[0][0]]["url"],
        ])

    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    subs, enrich = load()
    built = build(subs, enrich)
    for rel, rows in built.items():
        print(f"{rel:18} +{len(rows)} business rows")
        for r in rows[:2]:
            print(f"      {str(r[1])[:82]}")
    if not args.apply:
        print("\n(dry run — pass --apply to append)")
        return
    print()
    for rel, rows in built.items():
        added, total = write(rel, rows)
        print(f"{rel:18} appended {added}, now {total} rows")


if __name__ == "__main__":
    main()
