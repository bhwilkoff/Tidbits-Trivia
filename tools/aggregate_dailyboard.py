#!/usr/bin/env python3
"""The Daily's global board — the $0 aggregator (docs/DAILY-BOARD-CONTRACT.md).

The Daily is one shared set everyone plays; this layer ranks the field. Read the per-day
player results written to RTDB (public read), and for each recent day publish a ranked
board + a score histogram (for local percentile) + per-question global accuracy as static
JSON to data/dailyboard/ — served free/cacheable from GitHub Pages. Clients read this JSON,
NOT RTDB, so live reads stay far under the Spark free tier (R-NET-1). One RTDB read + at
most one commit per hour (R-NET-2).

Input  (RTDB): dailyBoard/{day}/{uid} = {name, avatarSeed, score, correct, marks, ms, at}
Output (repo): data/dailyboard/{day}.json  -> {day, qids, n, hist, perQ, top}
               data/dailyboard/index.json  -> {latest, days:[...]}

Offline verification (no RTDB): --input <file.json> reads an RTDB-shaped dump instead.
The day's question ids are recomputed with the SAME pickDaily as every client, so qids in
the output are authoritative (--corpus points at the id list; optional).
"""
import argparse
import json
import os
import urllib.request

RTDB = "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"
OUT = "data/dailyboard"
DAILY_COUNT = 7        # the Daily's set size (Corpus.daily(day, 7)) — matches every client
TOP_CAP = 100          # visible leaderboard size; everyone else uses the histogram
KEEP_DAYS = 5          # only recent days are republished; older days are frozen


def fetch_board(input_file):
    if input_file:
        with open(input_file) as f:
            return json.load(f) or {}
    with urllib.request.urlopen(f"{RTDB}/dailyBoard.json", timeout=30) as r:
        return json.load(r) or {}


def fnv1a64(s):
    """Byte-identical to js/engine.js fnv1a64 / DailyPick.swift — the canonical Daily hash."""
    h = 0xCBF29CE484222325
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def pick_daily(ids, day, category_id, count):
    """Byte-identical to pickDaily (Decision 037): the `count` smallest FNV-1a-64 ranks."""
    ranked_ids = sorted(ids, key=lambda i: (fnv1a64(f"daily:{day}:{category_id}:{i}"), i))
    return ranked_ids[:count]


# The Daily set VERSION. Two players on different versions answer DIFFERENT
# questions, so ranking them together is meaningless and their marks strings —
# which are aligned to the pick order — index different questions. The version is
# therefore on the wire, and boards are published per version.
DAILY_SET_V1 = 1
DAILY_SET_V2 = 2
DAILY_V2_FROM = "2026-09-01"


def daily_set_version(day):
    return DAILY_SET_V2 if day >= DAILY_V2_FROM else DAILY_SET_V1


def pick_daily_balanced(ids, cats, day, category_id, count):
    """Byte-identical to pickDailyBalanced in js/engine.js.

    Same FNV ranking, then the best unused id from each category in turn, so the
    seven questions span seven categories instead of following the corpus's own
    29%-Film-&-TV shape (Decision 050).
    """
    ranked = sorted(zip(ids, cats),
                    key=lambda p: (fnv1a64(f"daily:{day}:{category_id}:{p[0]}"), p[0]))
    by_cat = {}
    for i, c in ranked:
        by_cat.setdefault(c, []).append(i)
    order = sorted(by_cat, key=lambda c: (fnv1a64(f"dailycat:{day}:{c}"), c))

    out = []
    rnd = 0
    while len(out) < count:
        progressed = False
        for c in order:
            bucket = by_cat[c]
            if rnd < len(bucket):
                out.append(bucket[rnd])
                progressed = True
                if len(out) == count:
                    break
        if not progressed:
            break
        rnd += 1
    return out


def summarize_day(players, qids, want_qv=DAILY_SET_V1):
    """players: {uid: {name, avatarSeed, score, correct, marks, ...}} -> the published shape.

    Per-question accuracy tracks each question's seen/hit counts, so it generalizes if the
    Daily's set size ever changes.
    """
    rows, hist = [], {}
    q_hits, q_seen = [0] * DAILY_COUNT, [0] * DAILY_COUNT
    for uid, p in players.items():
        if not isinstance(p, dict):
            continue
        # A row with no `qv` predates the field and is therefore v1 — which is
        # what every already-shipped client writes. Rows from a DIFFERENT version
        # answered different questions, so they belong on a different board:
        # mixing them would rank players on unequal sets and index one client's
        # marks against another's question list.
        if int(p.get("qv", DAILY_SET_V1)) != want_qv:
            continue
        score = int(p.get("score", 0))
        rows.append({
            "name": p.get("name", ""),
            "avatarSeed": p.get("avatarSeed", ""),
            "score": score,
            "correct": int(p.get("correct", 0)),
        })
        hist[str(score)] = hist.get(str(score), 0) + 1
        marks = str(p.get("marks", ""))
        for i in range(min(DAILY_COUNT, len(marks))):
            q_seen[i] += 1
            if marks[i] == "1":
                q_hits[i] += 1

    n = len(rows)
    top = sorted(rows, key=lambda r: (-r["score"], -r["correct"], r["name"]))[:TOP_CAP]
    per_q = [round(q_hits[i] / q_seen[i], 4) if q_seen[i] else 0.0 for i in range(DAILY_COUNT)]
    return {"qids": qids, "qv": want_qv, "n": n, "hist": hist,
            "perQ": per_q, "top": top}


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"), sort_keys=True)


def load_ids(corpus_file):
    if not corpus_file:
        return None
    with open(corpus_file) as f:
        data = json.load(f)
    # Accept a wrapped corpus ({questions:[[id,...],...]}), a list of {id:...}, or bare ids.
    if isinstance(data, dict) and "questions" in data:
        return [str(q[0]) for q in data["questions"]]
    if data and isinstance(data[0], dict):
        return [str(q["id"]) for q in data]
    return [str(x) for x in data]


def load_cats(corpus_file):
    """Categories parallel to load_ids, for the v2 balanced pick."""
    if not corpus_file:
        return None
    with open(corpus_file) as f:
        data = json.load(f)
    if isinstance(data, dict) and "questions" in data:
        return [str(q[4]) for q in data["questions"]]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", help="RTDB-shaped JSON dump (offline test) instead of a live read")
    ap.add_argument("--corpus", help="corpus id list, to recompute the authoritative qids")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    data = fetch_board(args.input)
    all_ids = load_ids(args.corpus)

    cats = load_cats(args.corpus)

    days = sorted(k for k in data.keys() if isinstance(data.get(k), dict))
    recent = days[-KEEP_DAYS:]
    for day in recent:
        # v1 stays at {day}.json — the path every shipped client already reads.
        # v2, when it exists, is published BESIDE it so a client can fetch the
        # board matching its own qv. Publishing one merged board would rank
        # players who answered different questions against each other.
        v1_qids = pick_daily(all_ids, day, "mixed", DAILY_COUNT) if all_ids else []
        summary = summarize_day(data[day], v1_qids, want_qv=DAILY_SET_V1)
        summary["day"] = day
        write_json(f"{args.out}/{day}.json", summary)

        if daily_set_version(day) == DAILY_SET_V2 and all_ids and cats:
            v2_qids = pick_daily_balanced(all_ids, cats, day, "mixed", DAILY_COUNT)
            v2 = summarize_day(data[day], v2_qids, want_qv=DAILY_SET_V2)
            v2["day"] = day
            write_json(f"{args.out}/{day}-v2.json", v2)

    index = {"latest": days[-1] if days else None, "days": days[-30:]}
    write_json(f"{args.out}/index.json", index)
    print(f"Aggregated {len(recent)} recent day(s) of {len(days)} total: {recent}")


if __name__ == "__main__":
    main()
