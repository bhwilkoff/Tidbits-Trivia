#!/usr/bin/env python3
"""Normalize + validate a round of delight out-files before apply_delight.py.

Robust to two agent slips seen in the sequential-Sonnet run:
  1. imperative endings ("... name the film.") -> rewritten to "... which film?"
  2. a flipped id type (src:describe:X emitted for an src:cloze:X input, or vice
     versa) -> repaired by matching the title against the round's in-files.

Reports per-batch leak/malformed/skip/repaired counts (leak check mirrors
apply_delight.py's guard). Does NOT mutate the corpus — run apply_delight.py after.

Usage: python3 finalize_delight.py <lo> <hi>   # inclusive batch indices
       python3 finalize_delight.py 180 184
"""
import glob, json, os, re, sys

DIR = "/tmp/delight_new"
STOP = {"the", "and", "for", "was", "were", "are", "his", "her", "its", "from", "with",
        "who", "what", "that", "this", "american", "british", "english", "french", "german"}
GENERIC = frozenset("""
battle war siege revolution league cup world party national international series film movie
show novel song album band group team club order house company corporation university college
school church temple museum park garden river lake sea ocean bay gulf mountain island isle
peninsula desert valley star system code metal rock genre style award prize medal championship
tournament edition festival association organization movement period empire kingdom republic
dynasty union federation county city town province district gas compound acid oxide disease
syndrome disorder virus protein element method model process project mission program agency
department ministry council committee court treaty act convention society institute foundation
network station line route bridge tower building palace castle cathedral railway conflict crisis
theory language people family character actor actress singer player author director god goddess
dog cat breed plant tree flower fish bird animal region area continent capital currency italian
spanish russian chinese japanese korean indian brazilian mexican canadian australian dutch
swedish polish turkish greek egyptian african european asian
""".split())


def answer_words(ans):
    ans = re.sub(r"\s*\([^)]*\)", "", ans)
    return [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z'’]+", ans)
            if len(w) >= 4 and w.lower() not in STOP and w.lower() not in GENERIC]


def normalize(q):
    if "?" in q:
        return q
    m = re.search(r'\s*[—-]?\s*(?:name|identify|give the name of)\s+(the\s+)?'
                  r'([A-Za-z][A-Za-z ]*?)\.?\s*$', q, re.I)
    if not m:
        return q
    noun = (m.group(2) or "").strip().lower()
    stem = q[:m.start()].rstrip().rstrip('.,;—-').rstrip()
    if noun in ("it", "this", "them", ""):
        return stem + " — what is it?"
    return f"{stem} — which {noun}?"


def main():
    lo, hi = int(sys.argv[1]), int(sys.argv[2])
    # index inputs by id AND by bare title (src:TYPE:Title -> Title) for id repair
    by_id, by_title = {}, {}
    for b in range(lo, hi + 1):
        for it in json.load(open(f"{DIR}/in_{b:03d}.json")):
            by_id[it["id"]] = it
            by_title.setdefault(it["id"].split(":", 2)[2], it["id"])

    skip_file = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "delight_skip_ids.txt")
    skip_ids = []
    grand = 0
    for b in range(lo, hi + 1):
        path = f"{DIR}/out_{b:03d}.json"
        out = json.load(open(path))
        leak = mal = skip = miss = repaired = norm = 0
        for r in out:
            # repair a flipped id-type by matching the title
            if r["id"] not in by_id:
                title = r["id"].split(":", 2)[2] if r["id"].count(":") >= 2 else None
                if title and title in by_title:
                    r["id"] = by_title[title]
                    repaired += 1
            it = by_id.get(r["id"])
            if it is None:
                miss += 1
                continue
            q = r["question"]
            if q != "SKIP" and "?" not in q:
                nq = normalize(q)
                if nq != q:
                    r["question"] = q = nq
                    norm += 1
            if q == "SKIP":
                skip += 1
                skip_ids.append(r["id"])   # un-delightable -> exclude next round
                continue
            if len(q) < 25 or "?" not in q:
                mal += 1
                continue
            if any(re.search(rf"\b{re.escape(w)}\b", q.lower())
                   for w in answer_words(it["answer"])):
                leak += 1
        json.dump(out, open(path, "w"), ensure_ascii=False)
        apply = len(out) - leak - mal - skip - miss
        grand += apply
        print(f"batch {b}: n={len(out)} leak={leak} mal={mal} skip={skip} "
              f"miss={miss} repaired={repaired} norm={norm} -> apply {apply}")
    print(f"would-apply this round: {grand}")

    if skip_ids:
        existing = set()
        if os.path.exists(skip_file):
            existing = {l.strip() for l in open(skip_file) if l.strip()}
        merged = sorted(existing | set(skip_ids))
        if len(merged) != len(existing):
            open(skip_file, "w").write("\n".join(merged) + "\n")
            print(f"skip-list: +{len(merged) - len(existing)} un-delightable ids "
                  f"({len(merged)} total)")


if __name__ == "__main__":
    main()
