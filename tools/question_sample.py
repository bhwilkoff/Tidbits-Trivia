"""Draw a stratified sample of shipped questions for human/model reading.

`tools/corpus/quality_gate.py` already checks CONSTRUCTION — read-off answers,
duplicate options, fame tells, broken shapes — and it runs over the whole corpus.
It cannot check whether a question is TRUE, or whether its clue actually
identifies its answer. That is a semantic judgement, and the only honest way to
make it is to read questions.

So this does not grade anything. It samples so that reading is representative
rather than whatever the first query happened to return: stratified across
category and difficulty, seeded so a finding can be reproduced, and printed with
the answer and explanation attached so a claim can be checked without a second
query.

    python3 tools/question_sample.py --n 60 --seed 7
    python3 tools/question_sample.py --n 40 --category history --json out.json
"""
import argparse
import json
import random
import sqlite3
import sys
from pathlib import Path

DB = "TidbitsTrivia/Resources/corpus.sqlite"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--category")
    ap.add_argument("--db", default=DB)
    ap.add_argument("--json", help="also write the sample here")
    a = ap.parse_args()

    if not Path(a.db).exists():
        sys.exit(f"{a.db} missing")
    c = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)

    where, args = "", []
    if a.category:
        where, args = "where category_id = ?", [a.category]
    strata = c.execute(
        f"select category_id, difficulty, count(*) from questions {where} "
        "group by category_id, difficulty", args).fetchall()
    total = sum(n for _, _, n in strata)
    rng = random.Random(a.seed)

    picked = []
    for cat, diff, n in strata:
        # Proportional, but every stratum that exists gets at least one row —
        # a rare category is exactly where a bad template hides unnoticed.
        take = max(1, round(a.n * n / total))
        rows = c.execute(
            "select id, prompt, option0, option1, option2, option3, correct_index,"
            " category_id, difficulty, explanation, source_title from questions"
            " where category_id = ? and difficulty = ?", (cat, diff)).fetchall()
        picked += rng.sample(rows, min(take, len(rows)))
    rng.shuffle(picked)
    picked = picked[:a.n]

    out = []
    for r in picked:
        (qid, prompt, o0, o1, o2, o3, ci, cat, diff, expl, src) = r
        opts = [o0, o1, o2, o3]
        out.append({"id": qid, "category": cat, "difficulty": diff, "prompt": prompt,
                    "options": opts, "answer": opts[ci] if 0 <= ci < 4 else None,
                    "explanation": expl, "source": src})

    for i, q in enumerate(out, 1):
        print(f"\n[{i:02d}] ({q['category']}/d{q['difficulty']}) {q['id']}")
        print(f"  Q: {q['prompt']}")
        for j, o in enumerate(q["options"]):
            print(f"     {'*' if o == q['answer'] else ' '} {o}")
        if q["explanation"]:
            print(f"  why: {q['explanation'][:190]}")
        if q["source"]:
            print(f"  src: {q['source']}")

    print(f"\n{len(out)} questions, seed={a.seed}, from {total} in scope")
    if a.json:
        Path(a.json).write_text(json.dumps(out, indent=2))
        print(f"json: {a.json}")


if __name__ == "__main__":
    main()
