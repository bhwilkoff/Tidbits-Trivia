#!/usr/bin/env python3
"""Closest Call (M5) — numeric estimation questions from E1 numbers.

Each question carries its OWN linear domain [min,max], step, tolerance, unit and
the true answer — so one linear slider on the client handles every metric. The
domain is a fixed band per metric (NOT centered on the answer, which would give
it away). Scored by proximity on the client (adds-only). Three clean linear
metrics for v1: year (inception/birth/death), atomic number, elevation. Population
/ area (which need a log slider) are deferred.

Output: assets/closest.json (+ iOS Resources + Android assets copies).
Row shape: [id, prompt, answer, min, max, step, tolerance, unit, category,
            explanation, source_title, source_url]

Usage: python3 gen_closest.py
"""
import argparse, hashlib, json, os, re, urllib.parse

PER_BUCKET = 160  # cap per (category, metric) so one fact type can't dominate


def display_name(title):
    s = urllib.parse.unquote(title).replace("_", " ")
    s = re.sub(r"\s*\([^)]*\)", "", s)
    return s.split(",")[0].strip()


# metric -> (prompt builder, domain min, max, step, tolerance, unit, value filter)
METRICS = {
    "birth_year":  (lambda n: f"In what year was {n} born?",            1000, 2025, 1, 40, "", lambda v: 1000 <= v <= 2025),
    "death_year":  (lambda n: f"In what year did {n} die?",             1000, 2025, 1, 40, "", lambda v: 1000 <= v <= 2025),
    "inception":   (lambda n: f"In what year was {n} founded or created?", 1000, 2025, 1, 40, "", lambda v: 1000 <= v <= 2025),
    "atomic_number": (lambda n: f"What is the atomic number of {n}?",   1, 118, 1, 6, "", lambda v: 1 <= v <= 118),
    "elevation":   (lambda n: f"How high is {n} above sea level?",      0, 9000, 10, 700, "m", lambda v: 0 < v <= 9000),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--enrich", default="../../assets/enrich.json")
    ap.add_argument("--out", default="../../assets/closest.json")
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

    out, counts = [], {}
    for t, ent in enrich.items():
        if t not in cat_of:
            continue
        nums = ent.get("numbers", {})
        cat = cat_of[t]
        name = display_name(t)
        # Skip names that read as numbers/codes (e.g. band "311") — they'd be
        # confusing in a "what year/number is X?" stem.
        if len(name) < 3 or name.replace(".", "").isdigit():
            continue
        for metric, (prompt_fn, lo, hi, step, tol, unit, ok) in METRICS.items():
            n = nums.get(metric)
            if not n:
                continue
            v = n["value"]
            if not ok(v):
                continue
            bucket = (cat, metric)
            if counts.get(bucket, 0) >= PER_BUCKET:
                continue
            counts[bucket] = counts.get(bucket, 0) + 1
            # Years read without a thousands separator (1822, not 1,822).
            is_year = metric.endswith("year") or metric == "inception"
            disp = (str(int(v)) if is_year else f"{int(v):,}") + ((" " + unit) if unit else "")
            out.append([
                f"closest:{metric}:{t}", prompt_fn(name), v, lo, hi, step, tol, unit,
                cat, f"{name}: {disp}.", name, url_of.get(t, ""),
            ])

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "closest.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "closest.json")
    for path in (args.out, res_copy, and_copy):
        with open(path, "w") as f:
            f.write(payload)
    from collections import Counter
    print(f"wrote {len(out)} closest-call questions (version {version})")
    print("by metric:", dict(Counter(q[0].split(':')[1] for q in out)))
    for q in out[:5]:
        print("  ", q[1], "-> answer", q[2], q[7], "| domain", q[3], q[4])


if __name__ == "__main__":
    main()
