#!/usr/bin/env python3
"""Make every option the same KIND of thing as the answer.

Found by rendering the highest layout-risk question and looking at it. The clue
described "a shrub of the dogbane family"; the options were Myrtle, Nerium, Date
palm — and European hornet. An insect among three plants.

Across the corpus, 966 questions offer a distractor of a different kind
entirely: a giraffe among plants for "the last survivor of an order that first
appeared over 290 million years ago", a soursop among decapod crustaceans. The
player does not need the fact; they need to notice one of these is an animal.

The repair keeps the answer where it is and redraws the offending distractors
from subjects of the SAME kind, using the corpus's own one-line descriptions
(plant / animal / person / place / work / org / event / chemical / disease). It
refuses rather than half-fixing: a question with too few same-kind neighbours is
left alone and reported, because a wrong distractor is worse than a mismatched
one.

    python3 tools/corpus/fix_kind_distractors.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import json
import pathlib
import random
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
RNG = random.Random(20260801)      # deterministic; three mirrors must agree

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for", "de",
        "la", "le", "el", "s", "is", "was", "or"}

KINDS = [
    ("plant",    r"\b(plant|shrub|tree|flower|grass|fern|moss|herb|vine|"
                 r"flowering plant|conifer|palm|cactus)\b"),
    ("animal",   r"\b(insect|bird|mammal|fish|reptile|amphibian|spider|beetle|wasp|"
                 r"hornet|moth|butterfly|dinosaur|crustacean|mollusc|primate)\b"),
    ("person",   r"\b(born \d{4}|politician|footballer|actor|actress|singer|writer|"
                 r"player|physicist|philosopher|emperor|monarch|composer|director)\b"),
    ("place",    r"\b(country|city|town|village|island|river|mountain|region|province|"
                 r"capital|lake|desert|county|municipality)\b"),
    ("work",     r"\b(film|movie|song|album|novel|book|poem|series|sitcom|anime|"
                 r"video game|painting|opera|symphony|manga|sculpture)\b"),
    ("org",      r"\b(company|corporation|club|team|university|bank|airline|band|"
                 r"agency|organisation|organization|brand)\b"),
    ("event",    r"\b(battle|war\b|siege|revolution|treaty|massacre|disaster|"
                 r"earthquake|eruption|pandemic|election)\b"),
    ("chemical", r"\b(chemical element|compound|molecule|protein|enzyme|mineral|isotope)\b"),
    ("disease",  r"\b(disease|disorder|syndrome|infection|cancer|virus|bacterium)\b"),
]
KINDS = [(n, re.compile(p, re.I)) for n, p in KINDS]


def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


def descriptions(rows):
    out = {}
    for q in rows:
        e = q[6] or ""
        if ":" in e and "→" not in e:
            _, d = e.split(":", 1)
            d = d.strip()
            if d and len(d) > 8 and not d[0].isdigit():
                out.setdefault(q[7], d)
    return out


def kind_map(rows):
    """name -> kind, but ONLY where the name means one thing.

    The kind is looked up by option TEXT, and a title is not a unique key: the
    film Insomnia was typed as a disease because the word is also a subject in
    its own right. A misread ANSWER kind is the dangerous case — it would
    replace three perfectly good distractors with wrong-kind ones — so any name
    that two different subjects describe differently is dropped rather than
    guessed at.
    """
    seen = collections.defaultdict(set)
    for q in rows:
        e = q[6] or ""
        if ":" not in e or "→" in e:
            continue
        _, d = e.split(":", 1)
        d = d.strip()
        # ONLY the first sentence. The explanation field does double duty — the
        # player-facing reveal and the machine-readable subject description — and
        # fix_hollow_reveals.py appends a Wikipedia sentence to it.
        d = re.split(r"(?<=[.!?])\s", d, maxsplit=1)[0].strip()
        if not d or len(d) <= 8 or d[0].isdigit():
            continue
        for n, rx in KINDS:
            if rx.search(d):
                seen[q[7]].add(n)
                break
    return {name: next(iter(ks)) for name, ks in seen.items() if len(ks) == 1}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    kind = kind_map(rows)
    # Birth years, so a kind repair cannot undo the era repair. The first run of
    # this script paired Ramon Llull with someone 620 years away and the quality
    # gate failed the build — which is what the gate is for, but the two repairs
    # have to agree rather than take turns.
    years = {}
    ents = json.loads((ROOT / "assets" / "enrich.json").read_text())["entities"]
    for t, e in ents.items():
        b = e.get("numbers", {}).get("birth_year")
        if b and -3500 < int(b["value"]) <= 2025:
            years[t.replace("_", " ")] = int(b["value"])

    # Candidate options per (kind, category) — a plant distractor for a science
    # question should still be a science plant.
    pool = collections.defaultdict(set)
    for q in rows:
        for o in (q[2] or []):
            k = kind.get(str(o))
            if k:
                pool[(k, q[4])].add(str(o))
        for o in (q[2] or []):
            k = kind.get(str(o))
            if k:
                pool[(k, "*")].add(str(o))
    pool = {k: sorted(v) for k, v in pool.items()}

    fixed = refused = 0
    examples, refusals = [], []
    by_reason = collections.Counter()
    for q in rows:
        opts, ci = q[2], q[3]
        if not opts or len(opts) < 4 or not (0 <= ci < len(opts)):
            continue
        answer = str(opts[ci])
        want = kind.get(answer)
        if not want:
            continue
        wrong = [i for i, o in enumerate(opts)
                 if i != ci and kind.get(str(o)) and kind.get(str(o)) != want]
        if not wrong:
            continue

        banned = {fold(o) for o in opts}
        prompt_words = sig(q[1])
        ya = years.get(answer)
        cands = [n for n in (pool.get((want, q[4])) or pool.get((want, "*")) or [])
                 if fold(n) not in banned and not (sig(n) & prompt_words)
                 and not (ya and years.get(n) and abs(years[n] - ya) > 350)]
        if len(cands) < len(wrong):
            refused += 1
            by_reason[want] += 1
            if len(refusals) < 6:
                refusals.append(f"{q[0]}: {answer} ({want}) — too few same-kind {q[4]} options")
            continue

        before = list(opts)
        picks = RNG.sample(cands, len(wrong))
        for slot, name in zip(wrong, picks):
            opts[slot] = name
        fixed += 1
        if len(examples) < 5:
            examples.append((q[1][:56], before, list(opts), answer))

    print(f"questions with a wrong-kind distractor repaired: {fixed}")
    print(f"refused (left alone rather than half-fixed): {refused}")
    if by_reason:
        print("   refusals by the answer's kind:", dict(by_reason.most_common(6)))
    for p, b, n, ans in examples:
        print(f"\n   {p}...\n     was: {b}\n     now: {n}   (answer {ans})")
    for r in refusals:
        print(f"   REFUSED {r}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
