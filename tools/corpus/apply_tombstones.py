"""Drop the `corpus` tombstones from assets/corpus.json.

The shape generators (`gen_match.py`, `gen_order.py`, …) consume their own
tombstone bucket through `genguard.merge`. The `corpus` bucket has no such
consumer — it records rows removed straight out of `assets/corpus.json`, and
until now that removal was done by hand, which is why writing a tombstone and
shipping the row were two separate acts that could silently drift apart.

This makes it one act, and idempotent: run it after any audit that writes
`corpus` tombstones, then run `tools/corpus/resync_corpus.sh` to push the
result into every platform mirror.

    python3 tools/corpus/apply_tombstones.py            # report
    python3 tools/corpus/apply_tombstones.py --write    # rewrite corpus.json
"""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS_JSON = ROOT / "assets/corpus.json"
TOMBSTONES = ROOT / "tools/corpus/tombstones.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    tomb = json.loads(TOMBSTONES.read_text()).get("corpus", {})
    data = json.loads(CORPUS_JSON.read_text())
    rows = data["questions"]
    # A question is a positional array; id is field 0.
    keep = [q for q in rows if q[0] not in tomb]
    dropped = [q for q in rows if q[0] in tomb]

    print(f"corpus.json rows:        {len(rows):,}")
    print(f"corpus tombstones:       {len(tomb):,}")
    print(f"rows to drop (present):  {len(dropped):,}")
    print(f"rows after:              {len(keep):,}")
    if dropped:
        reasons = Counter(tomb[q[0]].split(":")[0] for q in dropped)
        for why, n in reasons.most_common():
            print(f"    {n:>5,}  {why}")

    if a.write and dropped:
        # Byte-identical to export_json.py, INCLUDING the content-hash version:
        # the web client busts its IndexedDB cache on that string, so writing new
        # questions under the old version leaves every returning player on the
        # corpus we just removed rows from.
        body = json.dumps(keep, ensure_ascii=False, separators=(",", ":"))
        version = hashlib.md5(body.encode()).hexdigest()[:12]
        CORPUS_JSON.write_text(
            f'{{"version":"{version}","count":{len(keep)},"questions":{body}}}')
        print(f"\nwrote {CORPUS_JSON.relative_to(ROOT)} (version {version})")
        print("now run: tools/corpus/resync_corpus.sh")
    elif a.write:
        print("\nnothing to drop — corpus.json already matches the tombstones.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
