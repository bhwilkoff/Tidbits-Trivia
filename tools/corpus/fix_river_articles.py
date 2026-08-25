"""Put the "the" back into "Approximately how long is Nile?" (F-007).

fix_missing_article.py is deliberately conservative: it only articles titles
whose HEAD NOUN takes "the" in every ordinary use (…River, …Sea, …Mountains),
because a bare-name rule would produce "the Sudan". But the num:P2043 family is
different — its generator gate already proved every subject is a river (Q4022),
and bare river names DO take the article: the Nile, the Danube, the Po. The
type knowledge makes the aggressive rule safe exactly where the general script
cannot be.

Patches prompt AND explanation of every num:P2043: row whose subject is not
already preceded by "the". gen_numeric.py now renders new rows correctly; this
repairs the shipped ones.

    python3 tools/corpus/fix_river_articles.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"


def article(text, subj):
    if re.search(r"\bthe\s+" + re.escape(subj) + r"\b", text, re.I):
        return text
    return re.sub(r"\b(is|of)\s+" + re.escape(subj) + r"\b",
                  lambda m: f"{m.group(1)} the {subj}", text, count=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    fixed = 0
    examples = []
    for q in rows:
        if not q[0].startswith("num:P2043:"):
            continue
        subj = q[7] or ""
        if not subj or subj.lower().startswith("the "):
            continue
        new_prompt = article(q[1] or "", subj)
        new_expl = article(q[6] or "", subj)
        if new_prompt == q[1] and new_expl == q[6]:
            continue
        if len(examples) < 8:
            examples.append((q[1][:66], new_prompt[:70]))
        q[1], q[6] = new_prompt, new_expl
        fixed += 1

    print(f"river prompts given their definite article: {fixed}")
    for b, n in examples:
        print(f"\n   was: {b}\n   now: {n}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
