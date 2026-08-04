#!/usr/bin/env python3
"""Publish the Daily's seven questions as static JSON, so the web stops downloading
the whole corpus to work out which seven they are.

The Daily's pick ranks EVERY id (Decision 037/050), so a shard would compute a
different seven than iPhone, Android, Windows and the cron — which is why the web
alone still called `loadFull()` and paid **13 MB gzipped** to answer seven
questions. The cron already knows the answer; it just never published it.

Output: `data/daily/{day}.json` = the seven FULL rows, ~6 KB. Not just the ids:
resolving ids would need either the full corpus again or an id→shard index, and
the rows themselves are smaller than the index would be.

**A three-day window, not one file.** The cron runs in UTC and `dayKey()` on a
client is the LOCAL date, so at any instant players are legitimately asking for
yesterday, today or tomorrow. Publishing one file would 404 for everyone west of
UTC for part of every day, and a 404 falls back to the 13 MB path — correct, but
it would silently undo the whole point.

The client treats this as a CACHE, never as an authority: a miss, a malformed
file or a corpus-version mismatch falls back to computing the seven locally. That
is what keeps the published set from becoming a second source of truth — the
five-engine daily golden still governs.

Usage:
    python3 tools/publish_daily.py [--corpus assets/corpus.json] [--days 3]
    python3 tools/publish_daily.py --check      # verify, write nothing
"""
import argparse
import datetime
import json
import os
import pathlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aggregate_dailyboard import pick_daily_balanced  # the SAME picker the board uses

OUT = pathlib.Path("data/daily")
DAILY_COUNT = 7


def load_corpus(path):
    with open(path) as f:
        d = json.load(f)
    rows = d["questions"] if isinstance(d, dict) else d
    version = d.get("version", "") if isinstance(d, dict) else ""
    return rows, version


def seven_for(rows, day):
    ids = [r[0] for r in rows]
    cats = [r[4] for r in rows]
    qids = pick_daily_balanced(ids, cats, day, "mixed", DAILY_COUNT)
    by_id = {r[0]: r for r in rows}
    return [by_id[i] for i in qids]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="assets/corpus.json")
    ap.add_argument("--days", type=int, default=3,
                    help="window size centred on today (default 3 = yesterday/today/tomorrow)")
    ap.add_argument("--check", action="store_true", help="compute + report, write nothing")
    args = ap.parse_args()

    rows, version = load_corpus(args.corpus)
    today = datetime.date.today()
    span = range(-(args.days // 2), args.days // 2 + 1)
    days = [(today + datetime.timedelta(days=n)).isoformat() for n in span]

    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    for day in days:
        qs = seven_for(rows, day)
        payload = {"day": day, "v": version, "count": len(qs), "questions": qs}
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        print(f"  {day}: {len(qs)} questions, {len(body.encode()):,} bytes"
              f"  [{', '.join(q[4] for q in qs)}]")
        if args.check:
            continue
        (OUT / f"{day}.json").write_text(body)
        written.append(day)

    if args.check:
        return

    # Keep the directory from growing without bound: only the published window plus a
    # few days of history are useful, and an archive replay recomputes anyway.
    keep = set(days) | {(today - datetime.timedelta(days=n)).isoformat() for n in range(1, 5)}
    for f in OUT.glob("*.json"):
        if f.stem != "index" and f.stem not in keep:
            f.unlink()

    index = {"latest": today.isoformat(), "v": version,
             "days": sorted(p.stem for p in OUT.glob("*.json") if p.stem != "index")}
    (OUT / "index.json").write_text(json.dumps(index, separators=(",", ":")))
    print(f"published {len(written)} day(s) → {OUT}/  (corpus v{version})")


if __name__ == "__main__":
    main()
