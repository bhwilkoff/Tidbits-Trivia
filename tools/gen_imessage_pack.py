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
import collections
import json
import pathlib
import re
import sqlite3

ROOT = pathlib.Path(__file__).resolve().parent.parent
DB = ROOT / "TidbitsTrivia/Resources/corpus.sqlite"
OUT = ROOT / "TidbitsMessages/Resources/pack.json"


def template(prompt):
    """A prompt's SHAPE, with the specifics removed.

    "Which of these four was born earliest?" and "Who among these was born first?"
    are different strings but the same puzzle, and a round built of five of them is
    one puzzle asked five times.
    """
    t = prompt.strip()

    # Strip the SUBJECT, not just the digits. "In what year was David Luiz born?" and
    # "In what year was Dove Cameron born?" differ only by who is being asked about —
    # normalising digits alone left them as two shapes, and a round drew four of them
    # in a row. Proper-noun runs become X so the question's SHAPE is what remains.
    # The leading word is lowercased first: it is capitalised for being sentence-
    # initial, not for being a name.
    if t and t[0].isupper():
        t = t[0].lower() + t[1:]
    t = re.sub(r"[A-Z][\w.'’-]*(?:\s+(?:[A-Z][\w.'’-]*|of|the|de|van|von|da|di|la|le))*",
               "X", t)
    t = t.lower()
    t = re.sub(r"\d+", "N", t)
    t = re.sub(r"[\"“”'’]", "", t)
    t = re.sub(r"\s+", " ", t)
    # The superlative-ordering family dominates the corpus and wears at least thirty
    # surface phrasings — "oldest", "eldest", "dates back furthest", "started first".
    # Collapse them so they compete as ONE shape rather than thirty. Written as an
    # explicit alternation rather than a bare /first/, which would also swallow
    # legitimately different questions like "who was the first person to orbit Earth?".
    if re.search(r"\b(oldest|eldest|earliest)\b", t) \
       or re.search(r"\b(dates? back|been around|has been going)\b", t) \
       or re.search(r"\bfurthest back\b", t) \
       or re.search(r"\b(born|came|come|started|start|appeared|appear|began|begin|"
                    r"founded|established|released|formed|opened|aired|debuted|"
                    r"came out|come out|launched|published)\s+(first|earliest)\b", t) \
       or re.search(r"\b(longest|furthest)\b.*\b(ago|running|standing)\b", t):
        return "SUPERLATIVE-ORDER"
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-category", type=int, default=400)
    a = ap.parse_args()

    con = sqlite3.connect(DB)
    cats = [r[0] for r in con.execute(
        "SELECT category_id FROM questions GROUP BY category_id ORDER BY COUNT(*) DESC")]

    rows, per_cat = [], {}
    # GLOBAL, not per-category. The same prompt filed under two categories is still
    # the same question, and a round draws across categories.
    seen_prompts = set()
    for cat in cats:
        # Deterministic: ORDER BY id, never RANDOM(). A pack that changes shape on
        # every regeneration makes its golden test meaningless and would silently
        # change which questions a shipped build can ask.
        #
        # difficulty 1-4 only: a 5 is a genuinely hard question, and the first thing
        # a group thread does with a brutal question is stop playing.
        # Read the WHOLE eligible pool, then choose from it. `ORDER BY id LIMIT 400`
        # is not a sample: ids cluster by the generator that produced them, so the
        # first 400 were 58% one puzzle ("which of these is oldest?") against 9.5%
        # in the corpus at large — and two IDENTICAL prompts could land in one
        # five-question round. Still deterministic: ORDER BY id fixes the pool, and
        # the round-robin below is a pure function of it. Never RANDOM().
        q = con.execute(
            """SELECT id, prompt, option0, option1, option2, option3, correct_index,
                      category_id, difficulty, explanation
               FROM questions
               WHERE category_id = ?
                 AND difficulty BETWEEN 1 AND 4
                 AND option0 <> '' AND option1 <> '' AND option2 <> '' AND option3 <> ''
                 AND length(prompt) <= 180
                 AND length(explanation) BETWEEN 1 AND 240
               ORDER BY id""", (cat,))

        # Bucket by shape, then take one from each in turn. Every shape gets equal
        # footing regardless of how many the corpus holds, so a family with 8,000
        # rows contributes the same as one with 12 until the small ones run dry.
        buckets = collections.OrderedDict()
        for r in q:
            if r[1] in seen_prompts:
                continue          # an exact repeat is the same question twice
            seen_prompts.add(r[1])
            buckets.setdefault(template(r[1]), []).append(r)

        got, exhausted = [], False
        while len(got) < a.per_category and not exhausted:
            exhausted = True
            for shape in list(buckets):
                if len(got) >= a.per_category:
                    break
                if buckets[shape]:
                    got.append(buckets[shape].pop(0))
                    exhausted = False

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
