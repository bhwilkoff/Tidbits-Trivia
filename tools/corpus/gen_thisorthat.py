#!/usr/bin/env python3
"""This-or-That (Q1) question set — built from E1 numeric enrichment.

Pairs two same-category entities that both carry a comparable number and asks a
binary "which …?" — rendered as a 2-option MCQ (reuses the existing answer
surface; no new input UI). Two shapes:
  - "Which came first?"  (birth_year | inception)   -> earlier wins
  - "Which is bigger?"   (population | area)          -> larger wins
Gated so the comparison is fair and unambiguous: same category, both values
present, and a meaningful margin (years ≥ 8 apart; sizes ≥ 1.4× apart). Capped
per (category, shape) so one fact-type can't dominate.

Output: assets/thisorthat.json (+ iOS Resources + Android assets copies), same
compact column order as corpus.json. No image column.

Usage: python3 gen_thisorthat.py
"""
import argparse, hashlib, json, os, re, urllib.parse

YEAR_MARGIN = 8
SIZE_RATIO = 1.4
PER_BUCKET = 70


def display_name(title):
    s = urllib.parse.unquote(title).replace("_", " ")
    s = re.sub(r"\s*\([^)]*\)", "", s)   # drop "(disambiguation)"
    s = s.split(",")[0]                   # drop ", Greece"
    return s.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--enrich", default="../../assets/enrich.json")
    ap.add_argument("--out", default="../../assets/thisorthat.json")
    args = ap.parse_args()

    corpus = json.load(open(args.corpus))
    qs = corpus["questions"] if isinstance(corpus, dict) else corpus
    enrich = json.load(open(args.enrich))["entities"]

    # title -> category (from the corpus question that produced it) + url
    cat_of, url_of = {}, {}
    for q in qs:
        if "/wiki/" not in q[8]:
            continue
        t = q[8].split("/wiki/")[-1]
        cat_of.setdefault(t, q[4])
        url_of.setdefault(t, q[8])

    # Collect (title, name, category, value) per comparable metric.
    def gather(metric):
        rows = []
        for t, ent in enrich.items():
            n = ent.get("numbers", {}).get(metric)
            if not n or t not in cat_of:
                continue
            rows.append((t, display_name(t), cat_of[t], n["value"]))
        return rows

    out, seen_pairs = [], set()

    def emit_pairs(rows, shape, margin_ok, prompt, fmt_expl, year=False):
        by_cat = {}
        for r in rows:
            by_cat.setdefault(r[2], []).append(r)
        for cat, items in by_cat.items():
            items = sorted(items, key=lambda r: r[3])
            made = 0
            # walk adjacent-ish pairs so the margin is satisfiable but not absurd
            for i in range(len(items)):
                for j in range(i + 1, min(i + 5, len(items))):
                    a, b = items[i], items[j]
                    if a[1] == b[1] or not margin_ok(a[3], b[3]):
                        continue
                    key = tuple(sorted((a[0], b[0]))) + (shape,)
                    if key in seen_pairs:
                        continue
                    seen_pairs.add(key)
                    # a has the smaller value (sorted asc). correct option index
                    # is whichever the prompt asks for.
                    opts = [a[1], b[1]]
                    correct = 0 if shape in ("first", "smaller") else 1
                    out.append([
                        f"tot:{shape}:{a[0]}|{b[0]}", prompt, opts, correct,
                        cat, 2, fmt_expl(a, b), a[1] + " / " + b[1], url_of.get(a[0], ""),
                    ])
                    made += 1
                    if made >= PER_BUCKET:
                        break
                if made >= PER_BUCKET:
                    break

    # Which came first (earlier year = smaller value = index 0)
    def yr(v):
        return f"{abs(int(v))} {'BC' if v < 0 else 'AD'}" if v < 0 else str(int(v))
    emit_pairs(gather("birth_year"), "first",
               lambda x, y: abs(x - y) >= YEAR_MARGIN,
               "Which came first?",
               lambda a, b: f"{a[1]} ({yr(a[3])}) came before {b[1]} ({yr(b[3])}).")
    emit_pairs(gather("inception"), "first",
               lambda x, y: abs(x - y) >= YEAR_MARGIN,
               "Which came first?",
               lambda a, b: f"{a[1]} ({yr(a[3])}) came before {b[1]} ({yr(b[3])}).")

    # Size comparisons (population P1082 / area P2046) are deferred: population's
    # first-claim is unreliable (Canada -> 44) and the corpus's area-bearing
    # entities are mostly sub-km² islands that round to "0 km²". Revisit once
    # enrich.py picks the best numeric claim. Chronology ("which came first") is
    # verified clean, so This-or-That ships as a chronology mode for now.

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "thisorthat.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "thisorthat.json")
    for path in (args.out, res_copy, and_copy):
        with open(path, "w") as f:
            f.write(payload)
    print(f"wrote {len(out)} this-or-that questions (version {version})")
    for q in out[:6]:
        print(" ", q[1], "->", q[2], "ans:", q[2][q[3]])


if __name__ == "__main__":
    main()
