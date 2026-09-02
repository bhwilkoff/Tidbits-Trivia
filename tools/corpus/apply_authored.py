"""Add hand-authored questions for FAMOUS subjects the corpus does not cover.

The owner wants the corpus back above 100K WHILE weak rows are being culled, so
the growth has to be higher quality than the average row, not filler. These are
written from the `prose` lead of subjects that currently have ZERO questions and
sit at the very top of the fame distribution -- YouTube, Wikipedia, the Titanic,
the periodic table, FC Barcelona -- so every added row is about something a pub
table has actually heard of.

Every batch passes gates before anything is written, because an authored row has
no generator to blame:

  * ANSWER LEAK -- the answer must not appear in its own prompt (word-boundary,
    not substring: an earlier version of this check reported leaks in "humming
    BIRD" and "FRANCISCo").
  * FOUR UNIQUE OPTIONS, and no option repeating another after case/space
    folding.
  * NO DUPLICATE PROMPT already in the corpus, and no id collision.
  * SAME-KIND DISTRACTORS are the author's job, not the gate's, but the gate does
    refuse an option set where only one option is of a different length class
    than the rest by a wide margin -- the "length tell" that makes a question
    guessable without knowing anything.
  * The subject must really have zero coverage, or the batch is padding an
    already-covered subject.

Shuffling is seeded by the question id so a rerun produces the same option order
-- an unseeded shuffle would rewrite the corpus (and its content hash) on every
invocation.
"""
import json
import random
import re
import sys
import unicodedata
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
CATS = {"screen", "geography", "music", "history", "arts", "sports", "science", "business"}


def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_")


def main(paths):
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    prompts = {q[1].strip().lower() for q in qs}
    ids = {q[0] for q in qs}
    covered = {q[7] for q in qs if len(q) > 7 and q[7]}

    added, rejected = [], []
    for p in paths:
        for item in json.loads(Path(p).read_text()):
            subj, prompt = item["subject"], item["prompt"].strip()
            ans, opts = item["answer"], list(item["options"])
            why = item["why"].strip()

            def bad(reason):
                rejected.append((prompt[:60], reason))

            if item["cat"] not in CATS:
                bad(f"bad category {item['cat']}"); continue
            if not 1 <= int(item["diff"]) <= 5:
                bad("bad difficulty"); continue
            if re.search(rf"\b{re.escape(ans)}\b", prompt, re.I):
                bad("answer leaks into the prompt"); continue
            allopts = [ans] + opts
            if len(allopts) != 4:
                bad(f"{len(allopts)} options"); continue
            if len({o.strip().lower() for o in allopts}) != 4:
                bad("duplicate options"); continue
            lens = sorted(len(o) for o in allopts)
            if lens[-1] > lens[-2] * 2 and lens[-1] - lens[-2] > 12:
                bad("length tell: one option far longer than the rest"); continue
            if prompt.lower() in prompts:
                bad("prompt already in the corpus"); continue
            if subj in covered:
                bad(f"subject '{subj}' already has questions"); continue

            n = 1
            while f"src:describe:{slug(subj)}-{n}" in ids:
                n += 1
            qid = f"src:describe:{slug(subj)}-{n}"
            order = list(allopts)
            random.Random(qid).shuffle(order)
            row = [qid, prompt, order, order.index(ans), item["cat"], int(item["diff"]),
                   why, subj, f"https://en.wikipedia.org/wiki/{slug(subj)}", []]
            qs.append(row)
            ids.add(qid)
            prompts.add(prompt.lower())
            added.append(row)

    print(f"added: {len(added)}")
    for r in added:
        print(f"    [{r[4]}/{r[5]}] {r[1][:66]}\n         -> {r[2][r[3]]}   {r[2]}")
    print(f"\nrejected: {len(rejected)}")
    for p, why in rejected:
        print(f"    {why}: {p}")
    if not added:
        return

    doc["questions"] = qs
    doc["count"] = len(qs)
    doc["version"] = md5(json.dumps(
        qs, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} rows   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main(sys.argv[1:] or [str(ROOT / "tools/corpus/authored/batch01.json")])
