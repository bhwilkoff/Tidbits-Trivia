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

# Generic type-nouns and nationality adjectives that commonly appear INSIDE an
# answer title but which a clue may legitimately use as a category word ("...which
# battle?" for "Battle of Kulikovo"). Treating these as leaks falsely rejected
# ~40% of otherwise-good rewrites, so they are excluded from the leak check (they
# never give away the distinctive part of the answer). Mirrors the authoring brief.
GENERIC = frozenset("""
battle war siege revolution league cup world party national international series
film movie show novel song album band group team club order house company
corporation university college school church temple museum park garden river lake
sea ocean bay gulf mountain island isle peninsula desert valley star system code
metal rock genre style award prize medal championship tournament edition festival
association organization movement period empire kingdom republic dynasty union
federation county city town province district gas compound acid oxide disease
syndrome disorder virus protein element method model process project mission
program agency department ministry council committee court treaty act convention
society institute foundation network station line route bridge tower building
palace castle cathedral railway conflict crisis theory language people family
character actor actress singer player author director group god goddess dog cat
breed plant tree flower fish bird animal region area continent capital currency
italian spanish russian chinese japanese korean indian brazilian mexican canadian
australian dutch swedish polish turkish greek egyptian african european asian
""".split())


def answer_words(ans):
    ans = re.sub(r"\s*\([^)]*\)", "", ans)   # drop disambiguator
    return [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z'’]+", ans)
            if len(w) >= 4 and w.lower() not in STOP and w.lower() not in GENERIC]


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
