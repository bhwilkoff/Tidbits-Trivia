#!/usr/bin/env python3
"""Build delight-rewrite in-files for the sequential Sonnet pass (Decision 032).

Selects still-robotic describe/cloze clues ("Who/What is this — …?", "Fill in the
blank: …"), grounds each with its Wikipedia lead from corpus_source.sqlite, and
writes batches of {id, answer, options, summary} to /tmp/delight_new/in_XXX.json,
highest-QRank (most-played subjects) first — best questions where players see them.

Usage: python3 build_delight_batches.py [--batch 60] [--limit 300] [--start 0]
Then an agent rewrites each in-file -> /tmp/delight_new/out_XXX.json, and
apply_delight.py (pointed at that dir) merges leak-guarded.
"""
import argparse, json, os, re, sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CORPUS = os.path.join(ROOT, "assets", "corpus.json")
SRC = os.path.join(HERE, "..", "corpus_source.sqlite")
OUT = "/tmp/delight_new"

WHO = re.compile(r'^(Who|What) is this\s*[—-]')
FIB = re.compile(r'^Fill in the blank')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int, default=60)
    ap.add_argument("--limit", type=int, default=300)
    ap.add_argument("--start", type=int, default=0)
    args = ap.parse_args()

    con = sqlite3.connect(SRC)
    # title -> (lead, description), and title -> qrank for priority
    lead_by_title = {}
    for qid, title, lead, desc in con.execute(
            "SELECT p.qid, p.title, p.lead, p.description FROM prose p"):
        if title and lead:
            lead_by_title[title] = lead
    qrank_by_title = {}
    for title, qrank in con.execute("SELECT title, qrank FROM subject"):
        if title is not None:
            qrank_by_title[title] = qrank or 0

    qs = json.load(open(CORPUS))["questions"]
    cand = []
    for q in qs:
        qid, prompt, options, ci = q[0], q[1], q[2], q[3]
        if qid.startswith("src:describe:") and WHO.search(prompt):
            pass
        elif qid.startswith("src:cloze:") and FIB.search(prompt):
            pass
        else:
            continue
        title = qid.split(":", 2)[2].replace("_", " ")
        lead = lead_by_title.get(title)
        if not lead:
            continue  # no grounding -> can't safely rewrite
        cand.append({
            "id": qid,
            "answer": options[ci],
            "options": options,
            "summary": lead[:900],
            "_qrank": qrank_by_title.get(title, 0),
        })

    cand.sort(key=lambda c: c["_qrank"], reverse=True)
    total = len(cand)
    window = cand[args.start:args.start + args.limit]
    for c in window:
        del c["_qrank"]

    os.makedirs(OUT, exist_ok=True)
    n = 0
    for i in range(0, len(window), args.batch):
        chunk = window[i:i + args.batch]
        idx = args.start // args.batch + n
        path = os.path.join(OUT, f"in_{idx:03d}.json")
        json.dump(chunk, open(path, "w"), ensure_ascii=False)
        n += 1
    print(f"groundable robotic candidates: {total:,}")
    print(f"wrote {n} in-files ({len(window)} items) to {OUT} "
          f"[start={args.start} limit={args.limit} batch={args.batch}]")


if __name__ == "__main__":
    main()
