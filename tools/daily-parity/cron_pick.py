#!/usr/bin/env python3
"""Daily-parity golden — cron side (Decision 037 / Daily Six).

The Daily Six aggregator recomputes the day's six question ids in Python. If that picker
drifts from the JS/Swift/Kotlin one, the published `qids` disagree with what every client
plays. Import the REAL aggregator picker and emit the same "<day> <id1> … <idN>" format as
web_pick.mjs for run.sh to diff.
"""
import json
import sys

sys.path.insert(0, "tools")
from aggregate_dailysix import pick_daily  # the picker the cron actually uses

DAYS = ["2026-07-01", "2026-07-02", "2026-12-31", "2027-02-28"]


def main():
    corpus_path, out_path = sys.argv[1], sys.argv[2]
    with open(corpus_path) as f:
        corpus = json.load(f)
    ids = [q[0] for q in corpus["questions"]]  # compact rows: index 0 = id
    if len(ids) < 100:
        print(f"FAIL: only {len(ids)} ids", file=sys.stderr)
        sys.exit(1)
    with open(out_path, "w") as f:
        for day in DAYS:
            f.write(f"{day} {' '.join(pick_daily(ids, day, 'mixed', 7))}\n")
    print(f"cron: {len(DAYS)} days written")


if __name__ == "__main__":
    main()
