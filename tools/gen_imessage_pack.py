"""Build the compact question pack the iMessage extension ships.

The extension CANNOT carry the real corpus. corpus.sqlite is 50MB and app
extensions run under far tighter memory ceilings than the host app — this codebase
has already taken a Play rejection from a 299MB heap peak and a repeat from eagerly
parsing JSON at boot (see the android-corpus-oom memories). So the extension gets a
small, balanced, MCQ-only pack instead, generated here and committed.

MCQ-only on purpose: the compact Messages drawer is a few hundred points tall.
Ordering, matching, type-answer and enumerate all need real estate and a keyboard,
and picture rounds need a network fetch inside a memory-constrained extension. Those
are follow-ups, not MVP.

Balanced across categories so a thread does not get eight screen-trivia questions in
a row — `screen` alone is 32k of the 110k corpus and would dominate a naive sample.

    python3 tools/gen_imessage_pack.py [--per-category 400]
"""
import argparse
import json
import pathlib
import sqlite3

ROOT = pathlib.Path(__file__).resolve().parent.parent
DB = ROOT / "TidbitsTrivia/Resources/corpus.sqlite"
OUT = ROOT / "TidbitsMessages/Resources/pack.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-category", type=int, default=400)
    a = ap.parse_args()

    con = sqlite3.connect(DB)
    cats = [r[0] for r in con.execute(
        "SELECT category_id FROM questions GROUP BY category_id ORDER BY COUNT(*) DESC")]

    rows, per_cat = [], {}
    for cat in cats:
        # Deterministic: ORDER BY id, never RANDOM(). A pack that changes shape on
        # every regeneration makes its golden test meaningless and would silently
        # change which questions a shipped build can ask.
        #
        # difficulty 1-4 only: a 5 is a genuinely hard question, and the first thing
        # a group thread does with a brutal question is stop playing.
        q = con.execute(
            """SELECT id, prompt, option0, option1, option2, option3, correct_index,
                      category_id, difficulty, explanation
               FROM questions
               WHERE category_id = ?
                 AND difficulty BETWEEN 1 AND 4
                 AND option0 <> '' AND option1 <> '' AND option2 <> '' AND option3 <> ''
                 AND length(prompt) <= 180
                 AND length(explanation) BETWEEN 1 AND 240
               ORDER BY id LIMIT ?""", (cat, a.per_category))
        got = q.fetchall()
        per_cat[cat] = len(got)
        for r in got:
            rows.append({
                "i": r[0], "p": r[1], "o": [r[2], r[3], r[4], r[5]],
                "c": r[6], "g": r[7], "d": r[8], "e": r[9],
            })

    OUT.parent.mkdir(parents=True, exist_ok=True)
    # Compact separators: the pack ships in the extension bundle and every byte is
    # download size for a feature people reach through a keyboard drawer.
    OUT.write_text(json.dumps({"v": 1, "q": rows}, separators=(",", ":"),
                              ensure_ascii=False))
    kb = OUT.stat().st_size / 1024
    print(f"pack: {len(rows)} questions across {len(per_cat)} categories, {kb:.0f} KB")
    for c, n in sorted(per_cat.items(), key=lambda kv: -kv[1]):
        print(f"  {c:12} {n}")


if __name__ == "__main__":
    main()
