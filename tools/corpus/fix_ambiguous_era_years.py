"""Year options that mix BC and AD, so a bare number means nothing.

    In what year was Cambridge founded?   ['19', '27', '1', '4 BC']
    In what year did Augustus die?        ['7 BC', '14', '2 BC', '29']

A player reading "19" against "4 BC" cannot tell whether 19 is AD or BC, and the
two readings are 38 years apart. That is ambiguity in the option set itself, not
difficulty -- exactly what the owner asked to be eliminated ("We don't need
ambiguity"). It is also unfair in a way the player can SEE, which is worse: the
question looks broken.

Repaired, not culled. Where any option in the set carries BC, every bare number
in that set is stamped "AD". Nothing else changes -- same answer, same index,
same distractors -- so eight questions about Augustus, Caligula and the founding
of Strasbourg survive with the ambiguity removed.

Scope check before acting: 87 year-rows contain an option under 1000, but only
these 8 MIX eras. In the other 79 every option is the same era, so a bare number
is unambiguous in context and stamping it would be noise. And an earlier version
of this measurement flagged 209 more rows that were not year questions at all --
their "bare number" options were titles: the films 300 and 24, the album 21.
"""
import json
import re
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
BC = re.compile(r"\b(BC|BCE)\b")
BARE = re.compile(r"^\d{1,4}$")


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    changed = []
    for q in qs:
        opts = [o.strip() for o in q[2]]
        if not any(BC.search(o) for o in opts):
            continue
        if not any(BARE.fullmatch(o) for o in opts):
            continue
        before = list(q[2])
        q[2] = [f"{o} AD" if BARE.fullmatch(o) else o for o in opts]
        if q[2] != before:
            changed.append((q[1], before, q[2]))
    print(f"disambiguated: {len(changed)}")
    for p, b, a in changed:
        print(f"    {p[:52]:54} {b}\n    {'':54} -> {a}")
    if not changed:
        print("nothing to do")
        return
    doc["count"] = len(qs)
    doc["version"] = md5(json.dumps(
        qs, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\nversion {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
