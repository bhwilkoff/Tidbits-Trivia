#!/usr/bin/env python3
"""Stage D.3 — difficulty.json from Qrank quintiles (Decision 032).

Replaces gen_difficulty.py's pageviews-API crawl: Qrank is already a cross-project
popularity score per subject, so difficulty = Qrank quintile (1 = most popular /
easiest … 5 = most obscure / hardest). Offline, deterministic, no rate limit.

Output schema matches the existing difficulty.json the Ladder mode consumes:
  { version, count, difficulty: { Title_With_Underscores: 1..5 } }
+ copies to iOS Resources and Android assets.

Usage: python3 build_difficulty.py
"""
import hashlib, json, os, shutil, sqlite3

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
OUT = os.path.join(ROOT, "assets", "difficulty.json")
COPIES = [os.path.join(ROOT, "TidbitsTrivia", "Resources", "difficulty.json"),
          os.path.join(ROOT, "android", "app", "src", "main", "assets", "difficulty.json")]


def main():
    con = sqlite3.connect(DB)
    rows = con.execute("SELECT title, qrank FROM subject WHERE keep=1").fetchall()
    ranks = sorted((r[1] for r in rows), reverse=True)
    n = len(ranks)
    cuts = [ranks[min(n - 1, n * k // 5)] for k in range(1, 5)]   # 4 quintile cut points

    def diff(qr):
        for i, c in enumerate(cuts):
            if qr >= c:
                return i + 1
        return 5

    difficulty = {t.replace(" ", "_"): diff(qr) for t, qr in rows}
    body = json.dumps(difficulty, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(difficulty)},"difficulty":{body}}}'
    open(OUT, "w").write(payload)
    for dst in COPIES:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(OUT, dst)

    from collections import Counter
    dist = Counter(difficulty.values())
    print(f"wrote {len(difficulty):,} difficulty ratings → {OUT}")
    print(f"  distribution (1=easy..5=hard): {dict(sorted(dist.items()))}")
    con.close()


if __name__ == "__main__":
    main()
