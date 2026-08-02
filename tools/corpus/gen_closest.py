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
import sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
import genguard

PER_BUCKET = 160  # cap per (category, metric) so one fact type can't dominate


def display_name(title):
    s = urllib.parse.unquote(title).replace("_", " ")
    s = re.sub(r"\s*\([^)]*\)", "", s)
    return s.split(",")[0].strip()


# Wikidata's `inception` covers companies, bands, TV series, poems, territories
# and concentration camps alike, and one verb cannot carry all of them. The old
# stem asked "In what year was X founded or created?" of every one — which reads
# as machine output at best ("Sir Gawain and the Green Knight founded or
# created?"), and at worst puts a brochure verb on Auschwitz. The category is the
# only type signal these rows have, so it picks the verb.
_INCEPTION_VERB = {
    "business":  "founded",
    "sports":    "founded",     # clubs and leagues
    "music":     "formed",      # bands
    "screen":    "first released",
    "arts":      "created",
    "history":   "established",
    "geography": "established",
    "science":   "established",
}

# The category alone is not enough, because some of them are simply wrong:
# Netflix and Manchester United are both filed under `music` in the corpus, so a
# category-only rule produced "In what year was Netflix formed?". The one-line
# description in the corpus explanation ("American video streaming service",
# "Association football club in England", "Australian rock band") is a far better
# type signal, so it decides first and the category is the fallback.
_DESC_VERB = [
    ("formed",         ("band", "duo", "trio", "quartet", "musical group", "girl group", "boy band")),
    ("founded",        ("company", "corporation", "service", "manufacturer", "retailer", "airline",
                        "bank", "brand", "business", "firm", "startup", "club", "team", "publisher",
                        "studio", "network", "chain", "conglomerate", "automaker", "brewery")),
    ("first released", ("film", "movie", "video game", "album", "single", "song", "series",
                        "sitcom", "television", "tv ")),
    ("written",        ("novel", "poem", "romance", "play", "book", "epic", "essay", "manuscript")),
    ("established",    ("territory", "region", "state", "province", "city", "camp", "university",
                        "college", "museum", "organisation", "organization", "agency", "institute")),
]


def inception_verb(desc, cat):
    d = (desc or "").lower()
    for verb, keys in _DESC_VERB:
        if any(k in d for k in keys):
            return verb
    return _INCEPTION_VERB.get(cat, "established")


def inception_stem(name, cat, desc=""):
    return f"In what year was {name} {inception_verb(desc, cat)}?"


# metric -> (prompt builder(name, cat), domain min, max, step, tolerance, unit, value filter)
METRICS = {
    "birth_year":  (lambda n, c, d: f"In what year was {n} born?",         1000, 2025, 1, 40, "", lambda v: 1000 <= v <= 2025),
    "death_year":  (lambda n, c, d: f"In what year did {n} die?",          1000, 2025, 1, 40, "", lambda v: 1000 <= v <= 2025),
    "inception":   (inception_stem,                                     1000, 2025, 1, 40, "", lambda v: 1000 <= v <= 2025),
    "atomic_number": (lambda n, c, d: f"What is the atomic number of {n}?", 1, 118, 1, 6, "", lambda v: 1 <= v <= 118),
    "elevation":   (lambda n, c, d: f"How high is {n} above sea level?",   0, 9000, 10, 700, "m", lambda v: 0 < v <= 9000),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--enrich", default="../../assets/enrich.json")
    ap.add_argument("--out", default="../../assets/closest.json")
    genguard.add_args(ap)
    args = ap.parse_args()

    corpus = json.load(open(args.corpus))
    qs = corpus["questions"] if isinstance(corpus, dict) else corpus
    enrich = json.load(open(args.enrich))["entities"]

    cat_of, url_of, desc_of = {}, {}, {}
    for q in qs:
        if "/wiki/" not in q[8]:
            continue
        t = q[8].split("/wiki/")[-1]
        cat_of.setdefault(t, q[4]); url_of.setdefault(t, q[8])
        # "Netflix: American video streaming service" -> the part after the colon
        # is a one-line type description, which is what picks the inception verb.
        if q[6] and ":" in q[6]:
            desc_of.setdefault(t, q[6].split(":", 1)[1].strip())

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
                f"closest:{metric}:{t}", prompt_fn(name, cat, desc_of.get(t, '')), v, lo, hi, step, tol, unit,
                cat, f"{name}: {disp}.", name, url_of.get(t, ""),
            ])

    out = genguard.merge('closest', out, args.out,

                         regenerate=args.regenerate, prune=args.prune)

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "closest.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "closest.json")
    # `--out /tmp/x.json` reads as "write somewhere harmless so I can look",
    # and it did not: these tracked copies were written regardless, so a safety
    # check that generated to a temp file silently replaced the iOS and Android
    # copies. Only the default --out touches the mirrors now.
    _mirrors = [res_copy, and_copy] if args.out == ap.get_default('out') else []
    for path in [args.out] + _mirrors:
        with open(path, "w") as f:
            f.write(payload)
    from collections import Counter
    print(f"wrote {len(out)} closest-call questions (version {version})")
    print("by metric:", dict(Counter(q[0].split(':')[1] for q in out)))
    for q in out[:5]:
        print("  ", q[1], "-> answer", q[2], q[7], "| domain", q[3], q[4])


if __name__ == "__main__":
    main()
