#!/usr/bin/env python3
"""One table for a day of Apple TV runs: every scenario dir under build/qa/,
its verdict, its failed assertions, and its evidence path — the campaign's
at-a-glance state without opening N report.json files.

Usage:
  python3 tools/atv_report.py                 # today
  python3 tools/atv_report.py 2026-08-24
  python3 tools/atv_report.py --md            # markdown (paste into the playbook)
"""
import json, sys, time
from pathlib import Path

day = next((a for a in sys.argv[1:] if not a.startswith("-")), time.strftime("%F"))
md = "--md" in sys.argv
root = Path(f"build/qa/atv-{day}")
if not root.exists():
    sys.exit(f"no runs under {root}")

rows = []
for d in sorted(root.iterdir()):
    if not d.is_dir():
        continue
    rep = d / "report.json"
    shots = len(list(d.glob("shot-*.png")))
    if not rep.exists():
        rows.append((d.name, "⚠ interrupted", f"{shots} frames, no report"))
        continue
    r = json.loads(rep.read_text())
    if "error" in r:   # a crash-proof report from a runner failure
        rows.append((d.name, "⚠ runner error", r["error"][:60]))
        continue
    if "assertions" not in r:
        # A depth-audit report ({"checked": N, "fails": [...]}) shares the dir.
        fl = r.get("fails", [])
        rows.append((d.name, "✅" if not fl else f"❌ {len(fl)} fails",
                     f"audit, {r.get('checked','?')} checked"))
        continue
    fails = [k for k, v in r["assertions"].items() if not v["pass"]]
    rows.append((d.name, "✅" if not fails else "❌ " + ",".join(fails),
                 f"{shots} frames"))

ok = sum(1 for _, v, _ in rows if v == "✅")
if md:
    print(f"| run | verdict | notes |\n|---|---|---|")
    for n, v, note in rows:
        print(f"| `{n}` | {v} | {note} |")
else:
    w = max(len(n) for n, _, _ in rows)
    for n, v, note in rows:
        print(f"{n:<{w}}  {v:<28} {note}")
print(f"\n{ok}/{len(rows)} runs green — {root}")
