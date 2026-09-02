"""Population and area facts that are physically impossible, and the questions on them.

`sup:*` (9,162 superlatives) passed the ordering check that found 62 wrong
answers in `chron:*`: 8,777 rows checked, 0 wrong, and the check was A/B'd by
deliberately repointing five answers and watching it report exactly 5. But that
green was HOLLOW, and for a reason already written down this session: the check
compared the corpus against the same fact table the questions were generated
from. Two sources sharing an upstream error are ONE source. The corpus is
perfectly consistent with data that is wrong.

Reading the actual numbers is what found it:

    Which of these has the largest population?
      Verona (86,443) / York (181,131) / Amman (500) / Cannes (73,325)  -> York

Amman has about five million people. The question is simply wrong, and no
internal check could ever have said so.

TWO INDEPENDENT DETECTORS, because guessing here would destroy good questions --
City of London (7,375), Valletta (6,444), Nuuk (17,984) and Jericho (20,416) are
all CORRECT small populations sitting in the same range as corrupt values for
Athens (30,969) and Moscow (30,000). There is no numeric line between them.

  1. PHYSICALLY IMPOSSIBLE AREA. A city with an area over 100,000 km2 cannot
     exist -- the largest by area, Chongqing, is about 82,400. Windhoek is
     recorded at 5,133,000,000 km2, roughly ten times the surface of the Earth;
     Miami at 143,148,642. 87 subjects, no judgement required.

  2. THE WIKIPEDIA LEAD DISAGREES. The `prose` table is a genuinely separate
     source from the `fact` table, so it can see what a self-comparison cannot:
     Moscow's lead says "over 13 million residents" against a stored 30,000, and
     Amman's says "five million as of 2024" against 500. Valletta's lead says
     5,157 against a stored 6,444 -- agreement, so Valletta is left alone. A
     mismatch counts only when the STORED value is under 100,000 AND the lead's
     figure is at least 10x larger. Both halves were added after reading the
     first run's hits: a bare 10x ratio flagged Atlanta (stored 447,841, lead
     "6,400,000") and Baltimore (621,210 vs 9,970,000), where the stored CITY
     figure is right and the lead is quoting the METRO area, and it flagged Banja
     Luka on a stray "139" the extractor mistook for a population. Requiring the
     stored value to be small keeps the genuine corruption -- Berlin 1,200,
     Kazan 7,000, Albuquerque 3,785, Athens 30,969 -- and drops all three false
     positives. Valletta (6,444 vs a lead's 5,157), Nuuk (17,984 vs 20,113) and
     City of London are untouched, as they should be.

Questions built on a rejected value are REPAIRED, not culled. In all 450 of them
the corrupt value is a DISTRACTOR and never the answer, so the option is swapped
for a clean subject of the same KIND and comparable FAME whose value is safely
below the marked answer's -- which keeps the answer correct and makes the
comparison honest again.

That distinction matters more than it looks. Leaving the bad option in does not
merely add noise: Amman's stored 500 sat against York's 181,131 in a "largest
population?" question marked York, and Amman really has about five million, so
the row was flatly wrong. Swapping the distractor fixes the row instead of
throwing away 450 otherwise-good questions while the corpus is being grown back
toward 100K.

A row is only culled if no clean replacement exists for it.
"""
import json
import re
import sqlite3
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
LABELS = ROOT / "tools" / "corpus" / "p31_labels.json"

CITY = r"\bcity\b|\btown\b|municipality|human settlement|big city|county seat"
MAX_CITY_AREA = 100_000          # km2; Chongqing, the largest, is ~82,400
MISMATCH = 10                    # the lead must be at least this many times larger
SMALL = 100_000                  # ...and the stored value this small to be absurd

POP_PATTERNS = [
    re.compile(r"population[^.]{0,60}?([\d][\d,\.]*)\s*(million|billion)\b", re.I),
    re.compile(r"population(?:\s+\w+){0,6}?\s+(?:of|was|is|at)\s+([\d][\d,\.]*)\s*(million|billion)?", re.I),
    re.compile(r"([\d][\d,\.]*)\s*(million|billion)?\s+(?:inhabitants|residents)", re.I),
]


def prose_population(lead):
    for rx in POP_PATTERNS:
        m = rx.search(lead or "")
        if not m:
            continue
        raw = m.group(1).replace(",", "").rstrip(".")
        if not raw or not re.fullmatch(r"[\d.]+", raw):
            continue
        try:
            v = float(raw)
        except ValueError:
            continue
        scale = (m.group(2) or "").lower()
        if scale == "million":
            v *= 1e6
        elif scale == "billion":
            v *= 1e9
        if v >= 100:
            return v
    return None



def gate_kind_map(rows):
    """The QUALITY GATE's own notion of kind, not a private one.

    An earlier version of this repair classified subjects with its own regex over
    p31 labels, and the gate then rejected the result: my classifier and its
    classifier disagreed, so a "same-kind" swap produced 'Metamorphoses' among
    what the gate reads as places. Two classifiers is one too many -- ask the
    component that will judge the answer.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "quality_gate", str(Path(__file__).resolve().parent / "quality_gate.py"))
    qg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qg)
    return qg.kind_map(rows)


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    labels = json.loads(LABELS.read_text())
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    p31, q2t = {}, {}
    for q, t, pp in con.execute("select qid, title, p31 from subject"):
        q2t[q] = t
        p31[t] = set(c for c in (pp or "").split(",") if c)
    val = {}
    for qid, prop, v in con.execute("select qid, prop, value from fact where kind='num'"):
        t = q2t.get(qid)
        if t and v is not None:
            val.setdefault((t, prop), float(v))
    lead = {q2t.get(q): l for q, l in con.execute("select qid, lead from prose") if q2t.get(q)}

    def is_city(t):
        return bool(re.search(CITY, " ".join(labels.get(c, c) for c in p31.get(t, set())).lower()))

    corrupt, why = set(), {}
    for (t, prop), v in val.items():
        if prop == "P2046" and is_city(t) and v > MAX_CITY_AREA:
            corrupt.add((t, prop))
            why[(t, prop)] = f"area {v:,.0f} km2 is physically impossible for a city"
        if prop == "P1082" and is_city(t):
            pv = prose_population(lead.get(t))
            # A stored population of 0 (Pompeii, Pripyat) is not a divisor, and
            # for a ruin or an evacuated town it may even be right -- only treat
            # it as corrupt when the lead names real inhabitants.
            if pv and v <= 0:
                corrupt.add((t, prop))
                why[(t, prop)] = (f"stored population {v:,.0f} but the Wikipedia lead "
                                  f"says about {pv:,.0f}")
                continue
            if pv and 0 < v < SMALL and pv / v >= MISMATCH:
                corrupt.add((t, prop))
                why[(t, prop)] = (f"stored population {v:,.0f} but the Wikipedia lead "
                                  f"says about {pv:,.0f}")

    print(f"corrupt (subject, prop) pairs: {len(corrupt)}")
    for k in sorted(corrupt, key=lambda k: k[0])[:22]:
        print(f"    {k[0]:30} {why[k]}")

    fame = {}
    for t, r in con.execute("select title, qrank from subject"):
        try:
            fame[t] = int(r or 0)
        except (TypeError, ValueError):
            fame[t] = 0
    # Clean replacement pool per prop: same kind (city), value present, not corrupt.
    pool = {}
    for (t, prop), v in val.items():
        if prop in ("P1082", "P2046") and is_city(t) and (t, prop) not in corrupt:
            pool.setdefault(prop, []).append((v, t))

    gkind = gate_kind_map(qs)
    repaired, culled = [], []
    keep = []
    for q in qs:
        fam = q[0].split(":")[0]
        prop = q[0].split(":")[1] if ":" in q[0] else ""
        if fam not in ("sup", "num") or not any((o, prop) in corrupt for o in q[2]):
            keep.append(q)
            continue
        ans_v = val.get((q[2][q[3]], prop))
        if ans_v is None:
            culled.append((q, "answer has no value")); continue
        want_min = any(w in q[1].lower() for w in
                       ("smallest", "shortest", "lowest", "least", "fewest", "tiniest"))
        ans_fame = max(fame.get(q[2][q[3]], 0), 1)
        used = set(q[2])
        ok = True
        for i, o in enumerate(q[2]):
            if (o, prop) not in corrupt:
                continue
            cands = [t for v, t in pool.get(prop, [])
                     if t not in used
                     and (v > ans_v if want_min else v < ans_v)
                     and ans_fame / 8 <= max(fame.get(t, 0), 1) <= ans_fame * 8
                     and (gkind.get(t) is None or gkind.get(q[2][q[3]]) is None
                          or gkind.get(t) == gkind.get(q[2][q[3]]))]
            if not cands:
                ok = False
                break
            pick = sorted(cands)[hash(q[0] + o) % len(cands)]
            q[2][i] = pick
            used.add(pick)
        if not ok:
            culled.append((q, "no clean same-fame replacement"))
            continue
        repaired.append(q)
        keep.append(q)

    print(f"\nREPAIRED (corrupt distractor swapped): {len(repaired)}")
    for q in repaired[:8]:
        prop = q[0].split(":")[1]
        print(f"    {q[1][:40]:42} {[(o[:18], f'{val.get((o,prop),0):,.0f}') for o in q[2]]}  -> {q[2][q[3]]}")
    print(f"\nCULLED (no clean replacement): {len(culled)}")
    if not (repaired or culled):
        print("\nnothing to do")
        return

    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for q, reason in culled:
        tomb[q[0]] = f"built on a corrupt place fact and {reason}"
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
