#!/usr/bin/env python3
"""Matching (Q5) — link each key to its value, from the corpus's 1:1 Wikidata
relations (capital / currency / element symbol / book author).

Groups four (key, value) pairs of the same relation into a matching question.
The client shows the keys in order and the values shuffled; the player links
each; scoring is the count of correct links. Keys are deduped and groups are
non-overlapping per relation.

Output: assets/match.json (+ iOS Resources + Android assets copies).
Row shape: [id, prompt, keys(4), values(4 — parallel/correct), category,
            explanation, "", ""]

Usage: python3 gen_match.py
"""
import argparse, hashlib, json, os

# id-prefix -> (prompt, key-noun, value-noun). key = source title, value = answer.
RELATIONS = {
    "wd:capital:":    ("Match each country to its capital.", "country", "capital"),
    "wd:currency:":   ("Match each country to its currency.", "country", "currency"),
    "wd:elemSymbol:": ("Match each element to its symbol.", "element", "symbol"),
    "wd:author:":     ("Match each book to its author.", "book", "author"),
}
PER_RELATION = 60


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--out", default="../../assets/match.json")
    args = ap.parse_args()

    qs = json.load(open(args.corpus))["questions"]

    out = []
    for prefix, (prompt, _kn, _vn) in RELATIONS.items():
        # Collect deduped (key, value, category) pairs for this relation.
        pairs, seen = [], set()
        for q in qs:
            if not q[0].startswith(prefix):
                continue
            key = q[7]                    # source title (country / element / book)
            val = q[2][q[3]]              # the answer (capital / symbol / author)
            if not key or not val or key in seen or key == val:
                continue
            seen.add(key)
            pairs.append((key, val, q[4]))
        # Non-overlapping groups of 4.
        made = 0
        for i in range(0, len(pairs) - 3, 4):
            grp = pairs[i:i + 4]
            if len({g[1] for g in grp}) < 4:   # values must be distinct to link cleanly
                continue
            keys = [g[0] for g in grp]
            vals = [g[1] for g in grp]
            cat = grp[0][2]
            expl = " · ".join(f"{k} → {v}" for k, v in zip(keys, vals))
            out.append([f"match:{prefix.strip(':').split(':')[-1]}:{i}:{keys[0]}",
                        prompt, keys, vals, cat, expl, "", ""])
            made += 1
            if made >= PER_RELATION:
                break

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "match.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "match.json")
    for path in (args.out, res_copy, and_copy):
        with open(path, "w") as f:
            f.write(payload)
    from collections import Counter
    print(f"wrote {len(out)} matching questions (version {version})")
    print("by relation:", dict(Counter(q[0].split(':')[1] for q in out)))
    for q in out[:4]:
        print("  ", q[1], "|", q[5])


if __name__ == "__main__":
    main()
