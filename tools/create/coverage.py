"""Measure whether the corpus can actually serve a GREAT quiz for each common topic.

Mirrors the shipped Create relevance rule (Round 8 / QA-SWEEP-LOG Q26-Q28):
tokenize, OR-match, drop answer-giveaways + trivial difficulty, then keep only
the rows matching the MOST typed words. Reports what a player would really get.

    python3 tools/create/coverage.py [--limit 8] [--csv out.csv]

Run this BEFORE promising "every created quiz is full of incredible questions" —
it is the difference between a claim and a measurement.
"""
import sqlite3, sys, csv, collections, unicodedata

def fold(s):
    """Lowercase + strip diacritics — mirrors the shipped `fold` on all four stacks."""
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c)).lower()

DB = "TidbitsTrivia/Resources/corpus.sqlite"
TARGET = 8

STOPWORDS = {"the","and","for","with","from","that","this","his","her","its",
             "was","were","are","who","what","which","how","why","all","any"}

def tokens(topic):
    t = "".join(c if (c.isalnum()) else " " for c in fold(topic)).split()
    raw = [x for x in t if len(x) >= 3]
    kept = [x for x in raw if x not in STOPWORDS]
    return kept or raw

def coverage(cur, topic, target=TARGET):
    toks = tokens(topic)
    if not toks:
        return None
    clause = " OR ".join(
        "(lower(prompt) LIKE ? OR lower(source_title) LIKE ? OR lower(explanation) LIKE ? OR lower(tags) LIKE ? OR search_text LIKE ?)"
        for _ in toks)
    args = []
    for t in toks:
        args += [f"%{t}%"] * 5
    cur.execute(
        f"SELECT id,prompt,option0,option1,option2,option3,correct_index,category_id,difficulty,"
        f"explanation,source_title,tags FROM questions WHERE {clause} LIMIT 4000", args)
    rows, reserve = [], []
    for r in cur.fetchall():
        (qid, prompt, o0, o1, o2, o3, ci, cat, diff, expl, title, tags) = r
        if qid.startswith("src:continent:") or (diff or 2) <= 1:
            continue                      # repetitive template / trivially easy
        hay = fold(" ".join(x or "" for x in (prompt, title, expl, tags)))
        m = sum(1 for t in toks if t in hay)
        if not m:
            continue
        answer = [o0, o1, o2, o3][ci or 0]
        # An answer that IS the topic is held in reserve, not dropped: for a person
        # most good questions answer with their name, so a hard drop starved the
        # pool. Reserve fills only the tail when the clean pool is short.
        if answer and any(t in fold(answer) for t in toks):
            reserve.append((m, cat, diff))
        else:
            rows.append((m, cat, diff))

    def top_tier(rs):
        if not rs:
            return []
        b = max(x[0] for x in rs)
        return [x for x in rs if x[0] == b]

    rows = top_tier(rows)
    if len(rows) < target:
        rows = rows + top_tier(reserve)[: target - len(rows)]
    best = max((x[0] for x in rows), default=0)
    cats = collections.Counter(c for _, c, _ in rows)
    return {
        "topic": topic, "pool": len(rows), "tokens": len(toks), "matched": best,
        "categories": len(cats), "top_category": (cats.most_common(1)[0][0] if cats else ""),
        "enough": len(rows) >= target,
    }

def main():
    target = TARGET
    if "--limit" in sys.argv:
        target = int(sys.argv[sys.argv.index("--limit") + 1])
    con = sqlite3.connect(DB); cur = con.cursor()
    results, by_domain = [], collections.defaultdict(list)
    for line in open("tools/create/topics.txt"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        domain, topic = line.split("\t", 1)
        r = coverage(cur, topic, target)
        if r:
            r["domain"] = domain
            results.append(r); by_domain[domain].append(r)

    thin = [r for r in results if not r["enough"]]
    print(f"topics: {len(results)}   can fill {target}: {len(results)-len(thin)}   THIN: {len(thin)}")
    print(f"median pool: {sorted(r['pool'] for r in results)[len(results)//2]}")
    print("\nby domain (thin / total):")
    for d, rs in sorted(by_domain.items()):
        t = sum(1 for r in rs if not r["enough"])
        print(f"  {d:<10} {t}/{len(rs)}")
    if thin:
        print(f"\nTHIN TOPICS (pool < {target}) — these are the ones that cannot yet")
        print("deliver a great quiz and must drive corpus work or live generation:")
        for r in sorted(thin, key=lambda r: r["pool"]):
            print(f"  {r['pool']:>4}  {r['domain']:<10} {r['topic']}")
    if "--csv" in sys.argv:
        path = sys.argv[sys.argv.index("--csv") + 1]
        with open(path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["domain","topic","pool","tokens","matched","categories","top_category","enough"])
            w.writeheader(); w.writerows(results)
        print(f"\nwrote {path}")

if __name__ == "__main__":
    main()
