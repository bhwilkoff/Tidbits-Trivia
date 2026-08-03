#!/usr/bin/env python3
"""Ordering (Q4) — "put these in order, earliest first" from E1 years.

Groups four same-category entities with well-separated years (birth_year or
inception) into a chronology-ordering question. The client shows them shuffled;
the player reorders; scoring is partial by inversion count. Each group uses
distinct entities (no reuse) and a minimum adjacent-year gap so the order is
decidable.

Output: assets/order.json (+ iOS Resources + Android assets copies).
Row shape: [id, prompt, names_in_correct_order, years, category, explanation,
            source_title, source_url]

Usage: python3 gen_order.py
"""
import argparse, hashlib, json, os, re, urllib.parse
import sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
import genguard

GROUP = 4
MIN_GAP = 6          # adjacent years in a group must differ by >= this
PER_CATEGORY = 60


def display_name(title):
    """The name a card shows.

    Keeps a NON-NUMERIC parenthetical. Wikipedia only adds one when the bare title is
    genuinely ambiguous, and stripping it produced "Bill O'Reilly" in a birth-order round
    of baseball figures — the cricketer born 1905, not the broadcaster born 1949, so
    knowing more made you likelier to get it wrong. A parenthetical with a DIGIT is still
    stripped: "Pinocchio (1940 film)" in a "which came first?" pair hands over the answer.
    See tools/corpus/fix_display_disambiguators.py.
    """
    s = urllib.parse.unquote(title).replace("_", " ")
    m = re.search(r"\(([^)]*)\)", s)
    qual = m.group(1).strip() if m else ""
    s = re.sub(r"\s*\([^)]*\)", "", s)
    s = s.split(",")[0].strip()
    return f"{s} ({qual})" if qual and not re.search(r"\d", qual) else s


def yr(v):
    return f"{abs(int(v))} BC" if v < 0 else str(int(v))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--enrich", default="../../assets/enrich.json")
    ap.add_argument("--out", default="../../assets/order.json")
    genguard.add_args(ap)
    args = ap.parse_args()

    corpus = json.load(open(args.corpus))
    qs = corpus["questions"] if isinstance(corpus, dict) else corpus
    enrich = json.load(open(args.enrich))["entities"]

    cat_of, url_of = {}, {}
    for q in qs:
        if "/wiki/" not in q[8]:
            continue
        t = q[8].split("/wiki/")[-1]
        cat_of.setdefault(t, q[4]); url_of.setdefault(t, q[8])

    # Per (category, DATE KIND). Mixing birth_year with inception is what made
    # "earliest" mean two different things inside one round:
    #
    #     Jean-Philippe Rameau · Jean-Baptiste Lully · Johann Pachelbel · L'Orfeo
    #
    # Three composers ordered by BIRTH and an opera ordered by its PREMIERE, under
    # a prompt that never says which. 247 of 737 rounds mixed a person with a
    # non-person that way. Each round now uses one date kind, and the prompt says
    # so, because the mode has exactly one prompt for all 853 rounds and it was
    # carrying no information at all.
    DATE_PROMPT = {
        "birth_year": "Put these people in order of birth — earliest first.",
        "inception": "Put these in order of when they began — earliest first.",
    }
    by_cat = {}
    for t, ent in enrich.items():
        if t not in cat_of:
            continue
        nums = ent.get("numbers", {})
        for field in ("birth_year", "inception"):
            n = nums.get(field)
            if n:
                break
        else:
            continue
        name = display_name(t)
        if len(name) < 3 or name.replace(".", "").isdigit():
            continue
        by_cat.setdefault((cat_of[t], field), []).append((name, int(n["value"]), t))

    out = []
    for (cat, field), items in sorted(by_cat.items()):
        # Unique by name, sorted by year.
        seen, uniq = set(), []
        for it in sorted(items, key=lambda x: x[1]):
            if it[0] in seen:
                continue
            seen.add(it[0]); uniq.append(it)
        # From each start index, greedily pick the next entity that's >= MIN_GAP
        # later, until 4 are gathered. Overlapping groups, deduped by name set.
        made, used = 0, set()
        for start in range(len(uniq)):
            grp = [uniq[start]]
            last = uniq[start][1]
            k = start + 1
            while k < len(uniq) and len(grp) < GROUP:
                if uniq[k][1] - last >= MIN_GAP:
                    grp.append(uniq[k]); last = uniq[k][1]
                k += 1
            if len(grp) < GROUP:
                continue
            key = frozenset(g[0] for g in grp)
            if key in used:
                continue
            used.add(key)
            names = [g[0] for g in grp]
            years = [g[1] for g in grp]
            expl = " → ".join(f"{g[0]} ({yr(g[1])})" for g in grp)
            out.append([
                f"order:{cat}:{field}:{start}:{grp[0][2]}", DATE_PROMPT[field],
                names, years, cat, expl, names[0], url_of.get(grp[0][2], ""),
            ])
            made += 1
            if made >= PER_CATEGORY:
                break

    out = genguard.merge('order', out, args.out,

                         regenerate=args.regenerate, prune=args.prune)

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "order.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "order.json")
    # `--out /tmp/x.json` reads as "write somewhere harmless so I can look",
    # and it did not: these tracked copies were written regardless, so a safety
    # check that generated to a temp file silently replaced the iOS and Android
    # copies. Only the default --out touches the mirrors now.
    _mirrors = [res_copy, and_copy] if args.out == ap.get_default('out') else []
    for path in [args.out] + _mirrors:
        with open(path, "w") as f:
            f.write(payload)
    print(f"wrote {len(out)} ordering questions (version {version})")
    for q in out[:4]:
        print("  ", q[4], "|", q[5])


if __name__ == "__main__":
    main()
