#!/usr/bin/env python3
"""Corpus id-parity check (docs/NIGHT-WIRE-SCHEMA.md).

The networked night ships question IDS (with full questions as fallback); an
id-based night only renders identically everywhere if every platform's bundled
corpus carries the SAME id set. This asserts:

  1. Apple  TidbitsTrivia/Resources/corpus.sqlite       (id column)
  2. Web    assets/corpus.json                          (questions[].id)
  3. Android android/app/src/main/assets/corpus.json    (questions[].id)

carry identical ids, and that every per-mode JSON (picture/closest/...) is
byte-identical between the Apple Resources copy and the web/Android asset
copies. Exit 0 = parity holds.
"""
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
failures = 0


def fail(msg: str) -> None:
    global failures
    failures += 1
    print(f"FAIL: {msg}")


def ok(msg: str) -> None:
    print(f"  ok: {msg}")


def json_ids(path: Path) -> set[str]:
    # corpus.json rows are compact arrays; index 0 is the id (DATA-CONTRACT.md).
    data = json.loads(path.read_text())
    return {q[0] for q in data["questions"]}


sqlite_ids = {
    row[0]
    for row in sqlite3.connect(ROOT / "TidbitsTrivia/Resources/corpus.sqlite").execute(
        "SELECT id FROM questions"
    )
}
web_ids = json_ids(ROOT / "assets/corpus.json")
android_ids = json_ids(ROOT / "android/app/src/main/assets/corpus.json")

print("== corpus id parity ==")
if sqlite_ids == web_ids == android_ids:
    ok(f"corpus ids identical across sqlite/web/android ({len(sqlite_ids)} ids)")
else:
    for name, ids in (("apple sqlite", sqlite_ids), ("web json", web_ids), ("android json", android_ids)):
        print(f"  {name}: {len(ids)} ids")
    diff = (sqlite_ids ^ web_ids) | (sqlite_ids ^ android_ids)
    fail(f"corpus id sets differ ({len(diff)} ids not everywhere; e.g. {sorted(diff)[:5]})")

print("== per-mode asset parity (byte-identical) ==")
apple_res = ROOT / "TidbitsTrivia/Resources"
for f in sorted(apple_res.glob("*.json")):
    clean = True
    for other in (ROOT / "assets" / f.name, ROOT / "android/app/src/main/assets" / f.name):
        if not other.exists():
            clean = False
            fail(f"{other.relative_to(ROOT)} missing (Apple bundles {f.name})")
        elif other.read_bytes() != f.read_bytes():
            clean = False
            fail(f"{f.name} differs: Resources vs {other.relative_to(ROOT)}")
    if clean:
        ok(f"{f.name} identical in all three bundles")

print("PASS: corpus id parity" if failures == 0 else f"FAIL: {failures} problem(s)")
sys.exit(0 if failures == 0 else 1)
