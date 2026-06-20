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

GROUP = 4
MIN_GAP = 6          # adjacent years in a group must differ by >= this
PER_CATEGORY = 60


def display_name(title):
    s = urllib.parse.unquote(title).replace("_", " ")
    s = re.sub(r"\s*\([^)]*\)", "", s)
    return s.split(",")[0].strip()


def yr(v):
    return f"{abs(int(v))} BC" if v < 0 else str(int(v))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--enrich", default="../../assets/enrich.json")
    ap.add_argument("--out", default="../../assets/order.json")
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

    # Per category, collect (name, year, title); prefer birth_year then inception.
    by_cat = {}
    for t, ent in enrich.items():
        if t not in cat_of:
            continue
        nums = ent.get("numbers", {})
        n = nums.get("birth_year") or nums.get("inception")
        if not n:
            continue
        name = display_name(t)
        if len(name) < 3 or name.replace(".", "").isdigit():
            continue
        by_cat.setdefault(cat_of[t], []).append((name, int(n["value"]), t))

    out = []
    for cat, items in by_cat.items():
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
                f"order:{cat}:{start}:{grp[0][2]}", "Put these in order — earliest first.",
                names, years, cat, expl, names[0], url_of.get(grp[0][2], ""),
            ])
            made += 1
            if made >= PER_CATEGORY:
                break

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "order.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "order.json")
    for path in (args.out, res_copy, and_copy):
        with open(path, "w") as f:
            f.write(payload)
    print(f"wrote {len(out)} ordering questions (version {version})")
    for q in out[:4]:
        print("  ", q[4], "|", q[5])


if __name__ == "__main__":
    main()
