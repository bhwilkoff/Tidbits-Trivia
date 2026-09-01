"""Fix the reveal unit on the surviving length superlatives (F-011 tail).

The F-011 prune left only geography members in sup:P2043 — whose source
values are the KILOMETRE figure mislabelled 'm' (the exact mislabel
gen_numeric documents). The comparisons are now correct but every reveal
still reads "Malaita has the greatest length of the four (160 m)" where it
means 160 km. gen_facts2 now formats new rows with km; this repairs the
shipped ones.

    python3 tools/corpus/fix_sup_length_units.py [--apply]

Then run tools/corpus/resync_corpus.sh and bump sw.js CACHE.
"""
import argparse
import hashlib
import json
import pathlib
import re
import sys


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    fixed = 0
    examples = []
    for q in rows:
        if not q[0].startswith("sup:P2043:"):
            continue
        new = re.sub(r"\(([\d.,]+) m\)\.$", r"(\1 km).", q[6] or "")
        if new and new != q[6]:
            if len(examples) < 3:
                examples.append((q[6], new))
            q[6] = new
            fixed += 1

    print(f"length-superlative reveals corrected to km: {fixed}")
    for b, n in examples:
        print(f"\n   was: {b}\n   now: {n}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then resync + CACHE bump)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{corpus_version(body)}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
