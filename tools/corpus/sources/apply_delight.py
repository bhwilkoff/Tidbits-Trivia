#!/usr/bin/env python3
"""Apply the LLM delight-rewrites to corpus.json, with safety gates (Decision 032).

Reads /tmp/delight/out_*.json ({id, question}) produced by the delight-rewrite
workflow and replaces each describe row's prompt with its delightful rewrite —
but ONLY if the rewrite passes guards (no answer leak, is a real question, not
SKIP). Rewrites that fail keep the original robotic clue. Then writes corpus.json
(web/Android) + corpus.sqlite (iOS); rerun gen_*.py after.

Usage: python3 apply_delight.py
"""
import glob, json, os, re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CORPUS = os.path.join(ROOT, "assets", "corpus.json")
STOP = {"the", "and", "for", "was", "were", "are", "his", "her", "its", "from", "with",
        "who", "what", "that", "this", "american", "british", "english", "french", "german"}


def answer_words(ans):
    ans = re.sub(r"\s*\([^)]*\)", "", ans)   # drop disambiguator
    return [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z'’]+", ans)
            if len(w) >= 4 and w.lower() not in STOP]


def main():
    files = (glob.glob("/tmp/delight/out_*.json") + glob.glob("/tmp/delight2/out_*.json")
             + glob.glob("/tmp/delight3/out_*.json"))
    rewrites = {}
    for f in files:
        try:
            for r in json.load(open(f)):
                if r.get("id") and r.get("question"):
                    rewrites[r["id"]] = r["question"].strip()
        except Exception as e:
            print("  warn: bad output file", f, e)
    print(f"collected {len(rewrites):,} rewrites from {len(files)} batch files")

    data = json.load(open(CORPUS))
    qs = data["questions"]
    applied = leaked = skipped = bad = 0
    for q in qs:
        if not (q[0].startswith("src:describe") or q[0].startswith("src:cloze")):
            continue
        nw = rewrites.get(q[0])
        if not nw or nw == "SKIP":
            skipped += 1
            continue
        if len(nw) < 25 or "?" not in nw:
            bad += 1
            continue
        answer = q[2][q[3]]
        low = nw.lower()
        if any(re.search(rf"\b{re.escape(w)}\b", low) for w in answer_words(answer)):
            leaked += 1                       # rewrite leaked the answer → keep original
            continue
        q[1] = nw
        applied += 1

    print(f"  applied {applied:,} delightful rewrites")
    print(f"  kept original: {skipped:,} skip/none · {leaked:,} leaked-answer · {bad:,} malformed")

    import hashlib
    body = json.dumps(qs, ensure_ascii=False, separators=(",", ":"))
    ver = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{ver}","count":{len(qs)},"questions":{body}}}'
    for p in (CORPUS, os.path.join(ROOT, "android/app/src/main/assets/corpus.json")):
        open(p, "w").write(payload)
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    import build_corpus
    build_corpus.write_sqlite(qs, build_corpus.IOS_SQLITE)
    print("  wrote corpus.json (web/Android) + corpus.sqlite (iOS) — now rerun gen_*.py")

    print("\n  SAMPLE delightful questions:")
    shown = 0
    for q in qs:
        if (q[0].startswith("src:describe") or q[0].startswith("src:cloze")) and rewrites.get(q[0]) and q[1] == rewrites[q[0]]:
            print(f"    {q[1]}  ->  {q[2][q[3]]}")
            shown += 1
            if shown >= 6:
                break


if __name__ == "__main__":
    main()
