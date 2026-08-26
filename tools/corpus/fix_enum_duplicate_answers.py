"""Remove double-counted accepted answers from enumerate rows (P4 audit).

Four rows accept the same string in TWO answer groups ("let it be",
"english horn", "wall-e", "seat") — one typed answer could match two
groups. The first group keeps the string; later occurrences are dropped
(a group emptied by the drop is removed).

    python3 tools/corpus/fix_enum_duplicate_answers.py [--apply]

Then run tools/corpus/resync_corpus.sh and bump sw.js CACHE.
"""
import argparse, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENUM = ROOT / "assets" / "enumerate.json"


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    data = json.loads(ENUM.read_text())
    rows = data["questions"] if isinstance(data, dict) else data
    fixed = 0
    for r in rows:
        seen = set(); newgroups = []
        changed = False
        for g in r[2]:
            ng = []
            for x in g:
                if x.lower() in seen:
                    changed = True
                    continue
                seen.add(x.lower()); ng.append(x)
            if ng: newgroups.append(ng)
            elif g: changed = True
        if changed:
            print(f"   {r[0]}: {len(r[2])} -> {len(newgroups)} groups")
            r[2] = newgroups; fixed += 1
    print(f"rows repaired: {fixed}")
    if not a.apply:
        print("(dry run — pass --apply)"); return 0
    if isinstance(data, dict):
        body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
        ENUM.write_text(f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    else:
        ENUM.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {ENUM}"); return 0


if __name__ == "__main__":
    sys.exit(main())
