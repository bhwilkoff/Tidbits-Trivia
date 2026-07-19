#!/usr/bin/env python3
"""Daily Six — the $0 global daily competition aggregator (docs/DAILY-SIX-CONTRACT.md).

Read the per-day player results written to RTDB (public read), and for each recent day
publish a ranked board + a score histogram (for local percentile) + per-question global
accuracy as static JSON to data/dailysix/ — served free/cacheable from GitHub Pages.
Clients read this JSON, NOT RTDB, so live reads stay far under the Spark free tier
(R-NET-1). One RTDB read + at most one commit per hour (R-NET-2).

Input  (RTDB): dailySix/{day}/{uid} = {name, avatarSeed, score, correct, marks, ms, at}
Output (repo): data/dailysix/{day}.json  -> {day, qids, n, hist, perQ, top}
               data/dailysix/index.json  -> {latest, days:[...]}

Offline verification (no RTDB): --input <file.json> reads an RTDB-shaped dump instead.
The day's six question ids are recomputed with the SAME pickDaily as every client, so
qids in the output are authoritative (--corpus points at the id list; optional).
"""
import argparse
import json
import os
import urllib.request

RTDB = "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"
OUT = "data/dailysix"
TOP_CAP = 100          # visible leaderboard size; everyone else uses the histogram
KEEP_DAYS = 5          # only recent days are republished; older days are frozen


def fetch_dailysix(input_file):
    if input_file:
        with open(input_file) as f:
            return json.load(f) or {}
    with urllib.request.urlopen(f"{RTDB}/dailySix.json", timeout=30) as r:
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


def summarize_day(players, qids):
    """players: {uid: {name, avatarSeed, score, correct, marks, ...}} -> the published shape."""
    rows, hist, per_q_hits = [], {}, [0] * 6
    for uid, p in players.items():
        if not isinstance(p, dict):
            continue
        score = int(p.get("score", 0))
        correct = int(p.get("correct", 0))
        rows.append({
            "name": p.get("name", ""),
            "avatarSeed": p.get("avatarSeed", ""),
            "score": score,
            "correct": correct,
        })
        hist[str(score)] = hist.get(str(score), 0) + 1
        marks = str(p.get("marks", ""))
        for i in range(min(6, len(marks))):
            if marks[i] == "1":
                per_q_hits[i] += 1

    n = len(rows)
    top = sorted(rows, key=lambda r: (-r["score"], -r["correct"], r["name"]))[:TOP_CAP]
    per_q = [round(per_q_hits[i] / n, 4) if n else 0.0 for i in range(6)]
    return {"qids": qids, "n": n, "hist": hist, "perQ": per_q, "top": top}


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"), sort_keys=True)


def load_ids(corpus_file):
    if not corpus_file:
        return None
    with open(corpus_file) as f:
        data = json.load(f)
    # Accept either a bare list of ids or a list of {id: ...} objects.
    if data and isinstance(data[0], dict):
        return [str(q["id"]) for q in data]
    return [str(x) for x in data]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", help="RTDB-shaped JSON dump (offline test) instead of a live read")
    ap.add_argument("--corpus", help="corpus id list, to recompute the authoritative qids")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    data = fetch_dailysix(args.input)
    all_ids = load_ids(args.corpus)

    days = sorted(k for k in data.keys() if isinstance(data.get(k), dict))
    recent = days[-KEEP_DAYS:]
    for day in recent:
        qids = pick_daily(all_ids, day, "mixed", 6) if all_ids else []
        summary = summarize_day(data[day], qids)
        summary["day"] = day
        write_json(f"{args.out}/{day}.json", summary)

    index = {"latest": days[-1] if days else None, "days": days[-30:]}
    write_json(f"{args.out}/index.json", index)
    print(f"Aggregated {len(recent)} recent day(s) of {len(days)} total: {recent}")


if __name__ == "__main__":
    main()
