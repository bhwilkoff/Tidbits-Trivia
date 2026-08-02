"""When the prompt names a nationality, the options must share it.

Rendered a Picture ID round: "Who is this American painter?" over Claude Monet,
Bob Ross, Caravaggio and Raphael. One American among a Frenchman and two
Italians. The clue states the nationality, so the player never needs to know the
painting, the painter, or anything else.

192 questions are free in exactly that way: the prompt names a nationality, the
answer holds it, and EVERY distractor is a different one that the corpus states
plainly.

    This Russian writer...      -> Spurgeon [British], Coward [British], Hubbard [American]
    This Japanese biologist...  -> Newton [British], Kaczynski [American], Hawking [British]
    This Australian writer...   -> Hamilton, Lowell, Fisher [all American]

Two things keep this from crying wolf. English, Scottish, Welsh and British are
one family — nobody eliminates Benedict Arnold from an "English inventor"
question on the grounds that Wikidata calls him British. And a hyphenated origin
in the prompt ("this Italian-American physicist") is two claims at once, so those
are left alone.

Only the FULLY free questions are repaired. Where one distractor differs and
another shares the nationality, the tell does not decide the question, and
rewriting 2,162 further rows to chase it would churn far more than it fixes.

The replacement keeps every constraint the earlier distractor repairs
established — same category, same era, no word shared with the prompt, nothing
already on screen — so the repairs agree rather than take turns undoing each
other.

    python3 tools/corpus/fix_nationality_distractors.py [--apply]

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
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from quality_gate import readable_description, kind_map           # noqa: E402

CORPUS = ROOT / "assets" / "corpus.json"
ENRICH = ROOT / "assets" / "enrich.json"
RNG = random.Random(20260801)

NATIONS = ("American|British|English|French|Italian|German|Spanish|Dutch|Russian|"
           "Japanese|Chinese|Indian|Canadian|Australian|Swedish|Norwegian|Danish|"
           "Polish|Greek|Irish|Scottish|Mexican|Brazilian|Argentine|Austrian|Swiss|"
           "Belgian|Portuguese|Turkish|Korean|Egyptian|Nigerian|Israeli|Iranian|"
           "Hungarian|Czech|Finnish|Romanian|Ukrainian|Welsh|Colombian|Chilean|"
           "Cuban|Peruvian|Vietnamese|Thai|Indonesian|Filipino|Pakistani")
IN_PROMPT = re.compile(r"\bthis\s+(" + NATIONS + r")\b", re.I)
IN_DESC = re.compile(r"^(" + NATIONS + r")\b", re.I)
HYPHENATED = re.compile(r"\bthis\s+\w+-\w+", re.I)
FAMILY = {"english": "british", "scottish": "british", "welsh": "british"}

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for", "de",
        "la", "le", "el", "s", "is", "was", "or"}


def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


def family(n):
    return FAMILY.get(n.lower(), n.lower())


def nationality_map(rows):
    out = {}
    for q in rows:
        d = readable_description(q[6] or "", q[7])
        if not d or d == "PERSON-BY-DATES":
            continue
        m = IN_DESC.match(d)
        if m:
            out.setdefault(q[7], family(m.group(1)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    nat = nationality_map(rows)

    years = {}
    for t, e in json.loads(ENRICH.read_text())["entities"].items():
        b = e.get("numbers", {}).get("birth_year")
        if b and -3500 < int(b["value"]) <= 2025:
            years[t.replace("_", " ")] = int(b["value"])

    # Same KIND as well as same nationality. The first run ignored kind and
    # replaced three people with three Swiss/Russian subjects of whatever type
    # was to hand, which pushed KIND-MISMATCH from 0 to 46. The repairs in this
    # directory have to agree with each other, not take turns.
    kind = kind_map(rows)
    pool = collections.defaultdict(set)
    for q in rows:
        for o in (q[2] or []):
            n, k = nat.get(str(o)), kind.get(str(o))
            if n and k:
                pool[(n, k, q[4])].add(str(o))
                pool[(n, k, "*")].add(str(o))
    pool = {k: sorted(v) for k, v in pool.items()}

    fixed = refused = 0
    examples, refusals = [], []
    # A question this rule can see and cannot repair is still a free question.
    # Raising the budget would hide it, so it is dropped instead — the same call
    # made for the incoherent Odd One Out sets and the unanswerable type-ins.
    drop = set()
    for q in rows:
        opts, ci = q[2], q[3]
        if not opts or len(opts) < 4 or not (0 <= ci < len(opts)):
            continue
        prompt = q[1] or ""
        m = IN_PROMPT.search(prompt)
        if not m or HYPHENATED.search(prompt):
            continue
        want = family(m.group(1))
        if nat.get(str(opts[ci])) != want:
            continue
        others = [(i, str(o)) for i, o in enumerate(opts) if i != ci]
        known = [(i, o) for i, o in others if nat.get(o)]
        if len(known) != len(others) or any(nat[o] == want for _, o in known):
            continue                       # not free: something shares the claim

        banned = {fold(o) for o in opts}
        prompt_words = sig(prompt)
        ya = years.get(str(opts[ci]))
        ka = kind.get(str(opts[ci]))
        if not ka:
            refused += 1
            drop.add(q[0])
            continue
        cands = [n for n in (pool.get((want, ka, q[4])) or pool.get((want, ka, "*")) or [])
                 if fold(n) not in banned and not (sig(n) & prompt_words)
                 and not (ya and years.get(n) and abs(years[n] - ya) > 350)]
        if len(cands) < len(others):
            refused += 1
            drop.add(q[0])
            if len(refusals) < 5:
                refusals.append(f"{q[0]}: too few {want} {q[4]} {ka} options")
            continue

        before = list(opts)
        picks = RNG.sample(cands, len(others))
        # The era rule applies to the SET, not to each swap: one run put a
        # 350-year gap between two replacements that were each within 350 of the
        # answer. Check what the player will actually see.
        span = [years[n] for n in picks + [str(opts[ci])] if n in years]
        if span and max(span) - min(span) > 350:
            refused += 1
            drop.add(q[0])
            continue
        for (slot, _), name in zip(others, picks):
            opts[slot] = name
        fixed += 1
        if len(examples) < 6:
            examples.append((prompt[:52], before, list(opts), want))

    print(f"free-by-nationality questions repaired: {fixed}")
    print(f"refused (left alone rather than half-fixed): {refused}")
    for p, b, n, w in examples:
        print(f"\n   {p}...  [{w}]\n     was: {b}\n     now: {n}")
    for r in refusals:
        print(f"   REFUSED {r}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    keep = [q for q in rows if q[0] not in drop]
    body = json.dumps(keep, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(keep)},"questions":{body}}}')
    print(f"{len(rows)} -> {len(keep)} rows (unrepairable free questions dropped)")
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
