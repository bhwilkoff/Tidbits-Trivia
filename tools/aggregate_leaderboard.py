#!/usr/bin/env python3
"""Wave E — the $0 aggregate plane (§M).

Read the per-venue/season standings written by devices to RTDB (public read), rank them,
and write static JSON to data/leaderboard/ — served free/cacheable from GitHub Pages. Clients
read this JSON, NOT RTDB, so live reads stay far under the Spark free tier. One cron run per
hour; commits only when the output changes.

Input  (RTDB): standings/{season}/{venue}/{uid} = {name, score, nights, updatedAt}
Output (repo): data/leaderboard/{season}/{venue}.json   -> ranked rows for that venue
               data/leaderboard/{season}/_overall.json   -> cross-venue totals for the season
               data/leaderboard/index.json               -> {season: [venue, ...]}
"""
import json
import os
import urllib.request

RTDB = "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"
OUT = "data/leaderboard"


def fetch_standings():
    with urllib.request.urlopen(f"{RTDB}/standings.json", timeout=30) as r:
        return json.load(r) or {}


def ranked(rows):
    # Highest score first; ties broken by more nights attended, then name for stability.
    return sorted(rows, key=lambda x: (-int(x.get("score", 0)), -int(x.get("nights", 0)), x.get("name", "")))


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"), sort_keys=True)


def main():
    data = fetch_standings()
    index = {}
    for season, venues in data.items():
        if not isinstance(venues, dict):
            continue
        index[season] = sorted(venues.keys())
        overall = {}  # uid -> aggregated across venues this season
        for venue, players in venues.items():
            if not isinstance(players, dict):
                continue
            rows = [{"uid": uid, "name": p.get("name", ""), "score": int(p.get("score", 0)),
                     "nights": int(p.get("nights", 0))} for uid, p in players.items() if isinstance(p, dict)]
            write_json(f"{OUT}/{season}/{venue}.json", ranked(rows))
            for row in rows:
                o = overall.setdefault(row["uid"], {"uid": row["uid"], "name": row["name"], "score": 0, "nights": 0, "venues": 0})
                o["name"] = row["name"] or o["name"]
                o["score"] += row["score"]
                o["nights"] += row["nights"]
                o["venues"] += 1
        write_json(f"{OUT}/{season}/_overall.json", ranked(list(overall.values())))
    write_json(f"{OUT}/index.json", index)
    print(f"Aggregated {len(index)} season(s): {index}")


if __name__ == "__main__":
    main()
