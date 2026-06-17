#!/usr/bin/env python3
"""Export corpus.sqlite → compact JSON for the web + Android consumers.

Compact array-per-question form to keep the payload small (gzips well on
GitHub Pages, cached in IndexedDB after first load). Column order matches
the DATA-CONTRACT so every reader maps by index.

Usage: python3 export_json.py [--db PATH] [--out PATH]
"""
import argparse, json, sqlite3

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="../../TidbitsTrivia/Resources/corpus.sqlite")
    ap.add_argument("--out", default="../../assets/corpus.json")
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    rows = conn.execute(
        "SELECT id,prompt,option0,option1,option2,option3,correct_index,"
        "category_id,difficulty,explanation,source_title,source_url FROM questions"
    ).fetchall()
    conn.close()

    questions = [
        [r[0], r[1], [r[2], r[3], r[4], r[5]], r[6], r[7], r[8], r[9], r[10], r[11]]
        for r in rows
    ]
    payload = {"version": 1, "count": len(questions), "questions": questions}
    with open(args.out, "w") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {len(questions)} questions to {args.out}")

if __name__ == "__main__":
    main()
