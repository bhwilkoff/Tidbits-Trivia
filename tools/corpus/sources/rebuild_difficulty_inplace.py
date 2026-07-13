#!/usr/bin/env python3
"""Deterministic per-QUESTION difficulty rebuild for assets/corpus.json (index 5).

NOT to be confused with build_difficulty.py, which produces the per-SUBJECT
Ladder tiers in assets/difficulty.json (untouched here). This script rewrites
ONLY index-5 (the integer 1..5 difficulty) inside each corpus.json question,
byte-for-byte preserving every other field, using a composite-hardness formula
from docs/CORPUS-100K-PLAN.md and FIXED-PERCENTILE tier slicing so the output
distribution is exactly ~20/30/30/15/5 regardless of H's shape.

  H = 0.40*(1-fame) + 0.30*fact_obscurity + 0.15*(1-richness)
      + 0.10*(1-answer_recognizability) + category_offset      (clamped [0,1])

Pure Python, no LLM calls. Reads corpus_source.sqlite READ-ONLY (subject+prose).

Usage: python3 rebuild_difficulty_inplace.py
"""
import json, os, re, sqlite3, sys, time
from bisect import bisect_right
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
CORPUS = os.path.join(ROOT, "assets", "corpus.json")

# Target cumulative fractions: 20 / 30 / 30 / 15 / 5  ->  0.20 0.50 0.80 0.95
CUM = [0.20, 0.50, 0.80, 0.95]

CAT_OFFSET = {
    "science": 0.05, "arts": 0.03, "history": 0.0, "geography": 0.0,
    "music": 0.0, "screen": -0.03, "sports": -0.03,
}


def norm(s):
    """underscore/space + case normalized title key."""
    return re.sub(r"\s+", " ", s.replace("_", " ")).strip().lower()


# ---- fact_obscurity classifier (checked HIGH -> MED-HIGH -> MED -> LOW -> default)
_HIGH = re.compile(
    r"approximately how much|how much|\bweigh|\bhow (?:many|tall|long|wide|deep|"
    r"high|far|old|fast|large|heavy)\b|\batomic number\b|\bin (?:metres|meters|"
    r"kilometres|kilometers|km|kg|kilograms|square|feet|foot|miles|tonnes|tons|"
    r"degrees)\b|\belevation\b|\bmass of\b|\barea of\b|\bwhat is the .*(?:in "
    r"metres|in meters|in km|in kg|square)",
    re.I,
)
_MEDHIGH = re.compile(
    r"\b(?:largest|tallest|highest|most populous|longest|biggest|smallest|"
    r"greatest|deepest|widest|heaviest|oldest|richest|most)\b|which came first|"
    r"came first|\bearliest\b|born first|released first|died first|founded first",
    re.I,
)
_MED = re.compile(
    r"\bwho\b|fill in the blank|____|\bcomposed\b|\bcreated\b|\bdirected\b|"
    r"\bwrote\b|\bfounded\b|\bdesigned\b|\bdeveloped\b|\bmanufactured\b|"
    r"\bperformed\b|\bpainted\b|author of|creator of|is described|which .* is "
    r"described",
    re.I,
)
_LOW = re.compile(
    r"in what year|in which year|\bwhat year\b|\bborn\b|\bdied\b|\bfounded\b|"
    r"\breleased\b|\bdiscovered\b|\bestablished\b|in which country|which country|"
    r"which continent|\bcontinent\b|\bnationality\b",
    re.I,
)


def fact_obscurity(prompt):
    if _HIGH.search(prompt):
        return 0.85
    if _MEDHIGH.search(prompt):
        return 0.65
    if _MED.search(prompt):
        return 0.45
    if _LOW.search(prompt):
        return 0.15
    return 0.50


_YEAR = re.compile(r"^\d{4}$")
_SHORTNUM = re.compile(r"^\d{1,3}$")


def read_db():
    uri = f"file:{DB}?mode=ro"
    for attempt in range(2):
        try:
            con = sqlite3.connect(uri, uri=True, timeout=30)
            subj = con.execute(
                "SELECT title, qrank FROM subject WHERE keep=1 AND title IS NOT NULL"
            ).fetchall()
            prose = con.execute(
                "SELECT title FROM prose WHERE title IS NOT NULL"
            ).fetchall()
            con.close()
            return subj, prose
        except sqlite3.OperationalError as e:
            if attempt == 0:
                time.sleep(0.5)
                continue
            raise


def main():
    subj, prose = read_db()

    # fame_percentile: rank of qrank among all keep=1 subjects, 0..1 (1 = most famous)
    ranks = sorted(r[1] for r in subj if r[1] is not None)
    n_subj = len(ranks)
    fame_exact, fame_lower, fame_norm = {}, {}, {}
    high_fame_titles = set()  # top ~40% fame -> recognizable answers
    for title, qr in subj:
        pct = bisect_right(ranks, qr) / n_subj if qr is not None else 0.35
        fame_exact[title] = pct
        fame_lower[title.lower()] = pct
        fame_norm[norm(title)] = pct
        if pct >= 0.60:
            high_fame_titles.add(title)
            high_fame_titles.add(title.lower())
            high_fame_titles.add(norm(title))

    prose_set = set()
    for (title,) in prose:
        prose_set.add(title)
        prose_set.add(title.lower())
        prose_set.add(norm(title))

    def fame_of(src_title):
        if src_title in fame_exact:
            return fame_exact[src_title]
        lo = src_title.lower()
        if lo in fame_lower:
            return fame_lower[lo]
        nm = norm(src_title)
        if nm in fame_norm:
            return fame_norm[nm]
        return 0.35  # median-ish default; never auto-max-hard on a miss

    def in_prose(src_title):
        return (
            src_title in prose_set
            or src_title.lower() in prose_set
            or norm(src_title) in prose_set
        )

    def ans_recognizable(ans):
        a = ans.strip()
        if a in high_fame_titles or a.lower() in high_fame_titles or norm(a) in high_fame_titles:
            return True
        if _YEAR.match(a) or _SHORTNUM.match(a):
            return True
        return False

    data = json.load(open(CORPUS, encoding="utf-8"))
    questions = data["questions"]

    scored = []  # (H, id, index, fame, obsc)
    for i, q in enumerate(questions):
        qid, prompt, opts, correct, cat = q[0], q[1], q[2], q[3], q[4]
        src_title = q[7] if len(q) > 7 and q[7] else ""
        fame = fame_of(src_title)
        obsc = fact_obscurity(prompt)
        richness = 1.0 if in_prose(src_title) else 0.4
        correct_ans = opts[correct] if 0 <= correct < len(opts) else ""
        arec = 1.0 if ans_recognizable(correct_ans) else 0.5
        H = (0.40 * (1 - fame) + 0.30 * obsc + 0.15 * (1 - richness)
             + 0.10 * (1 - arec) + CAT_OFFSET.get(cat, 0.0))
        H = max(0.0, min(1.0, H))
        scored.append((H, qid, i, fame, obsc))

    # FIXED-PERCENTILE tier slicing: stable-sort by (H asc, id) then slice.
    order = sorted(range(len(scored)), key=lambda k: (scored[k][0], scored[k][1]))
    N = len(order)
    cuts = [round(N * c) for c in CUM]  # [c1,c2,c3,c4]

    def tier_for_rank(r):
        if r < cuts[0]:
            return 1
        if r < cuts[1]:
            return 2
        if r < cuts[2]:
            return 3
        if r < cuts[3]:
            return 4
        return 5

    tier_by_index = [0] * N
    for rank_pos, k in enumerate(order):
        idx = scored[k][2]
        tier_by_index[idx] = tier_for_rank(rank_pos)

    # Rewrite index 5 in place, preserve all else.
    for i, q in enumerate(questions):
        q[5] = tier_by_index[i]

    with open(CORPUS, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

    # ---- reporting
    dist = Counter(q[5] for q in questions)
    print(f"\nFINAL overall distribution (N={N}):")
    for d in range(1, 6):
        c = dist[d]
        print(f"  d{d}: {c:6d}  {100*c/N:5.2f}%")

    cat_dist = defaultdict(Counter)
    for q in questions:
        cat_dist[q[4]][q[5]] += 1
    print("\nPer-category distribution (row% across d1..d5):")
    print(f"  {'category':10s} {'n':>7s}  " + "  ".join(f"d{d}" for d in range(1, 6)))
    for cat in sorted(cat_dist):
        cc = cat_dist[cat]
        tot = sum(cc.values())
        pcts = "  ".join(f"{100*cc[d]/tot:4.1f}" for d in range(1, 6))
        print(f"  {cat:10s} {tot:7d}  {pcts}")

    # spot checks: fame/obsc kept in scored keyed by original index
    meta = {scored[k][2]: (scored[k][3], scored[k][4]) for k in range(len(scored))}

    def show(i):
        q = questions[i]
        fame, obsc = meta.get(i, (0, 0))
        ans = q[2][q[3]] if 0 <= q[3] < len(q[2]) else "?"
        p = q[1][:90].replace("\n", " ")
        return f"  [{q[4]}/d{q[5]}] {p} -> {ans} (fame={fame:.2f}, obsc={obsc:.2f})"

    import random
    random.seed(42)
    by_tier = defaultdict(list)
    for i, q in enumerate(questions):
        by_tier[q[5]].append(i)
    print("\n12 spot-check samples:")
    print(" -- 3 from d1 --")
    for i in random.sample(by_tier[1], 3):
        print(show(i))
    print(" -- 3 from d3 --")
    for i in random.sample(by_tier[3], 3):
        print(show(i))
    print(" -- 3 from d5 --")
    for i in random.sample(by_tier[5], 3):
        print(show(i))
    print(" -- 3 random --")
    for i in random.sample(range(len(questions)), 3):
        print(show(i))


if __name__ == "__main__":
    main()
