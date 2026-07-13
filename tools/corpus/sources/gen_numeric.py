#!/usr/bin/env python3
"""ADDITIVE grounded-MCQ generator, NUMERIC family — "estimate the value" MCQs mined
from the `fact` table's kind='num' Wikidata quantities of corpus_source.sqlite.

No LLM. Every answer is a real Wikidata numeric fact; the three distractors are OTHER
real same-type values of the SAME property (wrong-by-construction, realistic), with a
scaled fallback only when a subject has too few numeric siblings. Every question is
dropped unless it passes the shared quality gates (answer-leak, verbatim, distinct-4,
readable) PLUS the numeric-family gates that make an estimate question fair:

  * PHYSICAL-PLAUSIBILITY BOUNDS per prop  — reject corrupt source values (Wikidata
    stores Windhoek "5,133,000,000 km2", a mountain under "height", the Universe's
    mass, etc.). Copied discipline from gen_facts2.py.
  * TYPE GATE per prop  — population/area/elevation/length only for GEOGRAPHIC places;
    height/weight only for PEOPLE (Q5). A building's "area" or a particle's "mass" is
    a different unit under the same label and must never enter the pool.
  * NUMERIC SEPARATION  — the real value and every distractor must differ by >=20% and
    render to a DIFFERENT displayed number, so there is exactly one defensible answer.

Two source units are silently corrupt and are normalized here, both losslessly and
non-ambiguously:
  * P2048 height is entered in BOTH metres (0.5-2.75) and centimetres (50-272) with no
    unit flag; the two ranges do not overlap, so cm values are divided by 100. Values
    in the 2.75-50 gap or above 272 are corrupt -> dropped.
  * P2043 (length) geography values are the KILOMETRE figure mislabelled 'm' in the
    source (Nile = 6650); treated as km.

FAMILIES (prop -> question)
  P1082 population   "Approximately what is the population of {s}?"   geography
  P2046 area (km2)   "Roughly how large is {s} by area?"             geography
  P2044 elevation    "Approximately what is the elevation of {s}?"   geography
  P2043 length (km)  "Approximately how long is {s}?"                geography, rivers
  P2048 height (m)   "About how tall is {s}?"                        people (Q5)
  P2067 mass (kg)    "Approximately how much does {s} weigh?"        people (Q5)

  P2386 diameter is DELIBERATELY EXCLUDED: only ~115 rows, almost all astronomical, the
  values span ~20 orders of magnitude in one 'm' label with no formattable coherent
  type -> correctness over volume, dropped outright.

OUTPUT  tools/corpus/_numeric_staged.json  ->  {"count": N, "questions": [rows]}
Row shape matches assets/corpus.json exactly:
  [id, prompt, options[4], correctIndex, category, difficulty,
   explanation, sourceTitle, sourceURL]

Does NOT touch assets/corpus.json or any shipped file. Staging only.

Usage:  python3 sources/gen_numeric.py
"""
import hashlib, json, math, os, re, sqlite3, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from build_corpus import leaks as _leaks, url_title as _url_title
except Exception:  # pragma: no cover - defensive
    def _leaks(answer, text):
        t = text.lower()
        for w in re.findall(r"[a-z']{4,}", answer.lower()):
            if w in t:
                return True
        return False
    def _url_title(title):
        return title.replace(" ", "_")

DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "_numeric_staged.json"))

_NONLATIN = re.compile(r"[^\x00-ɏḀ-ỿ‐-‧‰-⁞]")
def readable(s):
    return bool(s) and not _NONLATIN.search(s)

def _h(*parts):
    return int(hashlib.md5("|".join(map(str, parts)).encode()).hexdigest(), 16)

# ----------------------------------------------------------- per-prop config
# prop -> dict(kind, cat/type gate flags, bounds, prompt, dim word for explanation)
# type gate: geo -> category=='geography' ; person -> 'Q5' in p31 ; river adds Q4022.
PROPS = {
    # "factor" caps how far a distractor may sit from the answer (multiplicative). Loose
    # for wide-dynamic-range geography; TIGHT for height/weight so a 1.9 m athlete's
    # distractors stay in a believable adult band instead of reaching a 0.7 m outlier.
    #
    # P1082 POPULATION is DELIBERATELY EXCLUDED. Population is a time-series quantity and
    # the source `fact` table stores a single UNDATED snapshot per subject — frequently a
    # decades-old one (US = 3,929,214 is the 1790 census; France = 1946; India/Pakistan/
    # Iran/Philippines/Argentina off by 70-99%). A spot-check of 30 well-known countries
    # found ~50% catastrophically stale, and there is NO field to distinguish a current
    # value from a stale one. A question whose stated answer is simply WRONG is worse than
    # none, so the whole family is dropped (mirrors gen_facts2 excluding mass-superlatives
    # for a data-integrity reason). Area/elevation/height/length/weight are STATIC facts
    # and are not affected.
    "P2046": dict(kind="area",  gate="geo",   bounds=(0.01, 1.8e7), factor=12.0,
                  prompt="Roughly how large is {s} by area?", dim="area"),
    # elevation floored at 200 m: below that the value is near sea-level noise and a
    # poor estimate question ("elevation of Eindhoven = 17 m"). The floor keeps the
    # meaningful ones — mountains and high-altitude cities (Denver, La Paz, Addis).
    "P2044": dict(kind="elev",  gate="geo",   bounds=(200.0, 9000.0), factor=12.0,
                  prompt="Approximately what is the elevation of {s}?", dim="elevation"),
    "P2043": dict(kind="len",   gate="river", bounds=(1.0, 7500.0), factor=12.0,
                  prompt="Approximately how long is {s}?", dim="length"),
    # height floored at 1.4 m: below that a "notable person" value is almost always a
    # child, a dwarfism edge case, or corruption (Travis Kelce stored 0.58 m — he is
    # 1.96 m), and a tight factor around a corrupt-tiny answer yields an all-sub-1 m
    # option set that both ships a wrong answer and looks broken. Adult-height floor
    # keeps the real questions and their distractors believable.
    "P2048": dict(kind="height", gate="person", bounds=(1.4, 2.75), factor=12.0,
                  prompt="About how tall is {s}?", dim="height"),
    "P2067": dict(kind="mass",  gate="person", bounds=(35.0, 650.0), factor=2.6,
                  prompt="Approximately how much does {s} weigh?", dim="weight"),
}

# Buildings / monuments / museums are frequently tagged category='geography' but their
# "area" is a floor area in m2 mislabelled km2 (One World Trade Center "325,279 km2",
# Buddhas of Bamiyan "105 km2"). Drop any geography subject that IS one of these built
# structures. Deliberately EXCLUDES the ambiguous "landmark"/"tourist attraction" tags,
# which real cities (Volgograd) also carry.
STRUCT_P31 = {
    "Q41176",   # building
    "Q811979",  # architectural structure
    "Q11303",   # skyscraper
    "Q1021645", # office building
    "Q33506",   # museum
    "Q207694",  # art museum
    "Q16560",   # palace
    "Q23413",   # castle
    "Q751876",  # château
    "Q12518",   # tower
    "Q2977",    # cathedral
    "Q16970",   # church building
    "Q32815",   # mosque
    "Q44613",   # monastery
    "Q839954",  # archaeological site
    "Q4989906", # monument
    "Q838948",  # work of art
    "Q5191724", # (Leaning Tower of Pisa type)
    "Q328468",  # (concentration camp memorial)
    "Q1497375", # (heritage site type)
    "Q120560",  # minor basilica
}

def normalize(prop, raw):
    """Return the value in the family's canonical unit, or None to DROP.
    Applies the two documented unit-corruption fixes before bounds are checked."""
    if raw is None:
        return None
    v = float(raw)
    if prop == "P2048":
        # Height is entered in THREE units with no flag; the bands do not overlap, so
        # each maps unambiguously to metres. (The adult-height quality floor lives in
        # bounds, applied after this.)  metres 0.5-2.75 | inches 55-90 (Reagan=71in=1.80m,
        # Elizabeth II=64in=1.63m) | centimetres 140-272 (Yao Ming=229cm=2.29m).
        if 0.5 <= v <= 2.75:
            return v
        if 55.0 <= v <= 90.0:
            return v * 0.0254                 # inches -> metres
        if 140.0 <= v <= 272.0:
            return v / 100.0                  # centimetres -> metres
        return None                           # gaps / >272 == corrupt or wrong unit
    return v                                  # P2043 geography value already = km

# ---------------------------------------------------------------- formatting
def _sig(v, n=2):
    if v == 0:
        return 0.0
    d = n - 1 - int(math.floor(math.log10(abs(v))))
    return round(v, d)

def scale_for(kind, values):
    """Choose ONE display scale from the whole option set so formatting can never be a
    tell (all four share the representation). Keyed on the MINIMUM so a word scale is
    used only when EVERY option renders naturally in it (no "0.012 million")."""
    m = min(abs(x) for x in values)
    if kind == "count":
        return "B" if m >= 1e9 else ("M" if m >= 1e6 else "")
    if kind == "area":
        return "M" if m >= 1e6 else ""
    return ""

def fmt(kind, v, scale):
    if kind == "count":
        if scale == "B": return f"{_sig(v/1e9):g} billion"
        if scale == "M": return f"{_sig(v/1e6):g} million"
        return f"{int(round(v)):,}"
    if kind == "area":
        if scale == "M": return f"{_sig(v/1e6):g} million km²"
        if abs(v) < 10:  return f"{_sig(v):g} km²"
        return f"{int(round(v)):,} km²"
    if kind == "height":
        return f"{v:.2f} m"
    if kind == "elev":
        return f"{int(round(v)):,} m"
    if kind == "mass":
        return f"{int(round(v)):,} kg"
    if kind == "len":
        return f"{int(round(v)):,} km"
    return f"{v:g}"

def fmt_solo(kind, v):
    """Free-standing value for the explanation line (its own scale)."""
    return fmt(kind, v, scale_for(kind, [v]))

def disp_num(kind, v, scale):
    """The numeric value the formatted string actually shows (post-rounding), so the
    >=20% answer gate can be re-checked on what the PLAYER SEES, not just the raw fact."""
    if kind == "count":
        if scale == "B": return _sig(v / 1e9) * 1e9
        if scale == "M": return _sig(v / 1e6) * 1e6
        return float(round(v))
    if kind == "area":
        if scale == "M": return _sig(v / 1e6) * 1e6
        if abs(v) < 10:  return _sig(v)
        return float(round(v))
    if kind == "height":
        return round(v, 2)
    return float(round(v))              # elev / mass / len

# Answer<->distractor gap is the STRICT correctness gate: >=20% guarantees exactly one
# defensible answer. Distractor<->distractor need only be far enough not to look like
# duplicate options (>=8%); forcing 20% BETWEEN distractors too would push a bounded
# range like human height (0.5-2.75 m) to spit out an absurd 0.7 m "height" for a 1.9 m
# athlete just to satisfy mutual spacing.
SEP_ANS = 0.20
SEP_MUT = 0.08
def separated(a, b, thr):
    """>=thr apart in magnitude (works for negatives via max-magnitude gap)."""
    return abs(a - b) >= thr * max(1e-9, abs(a), abs(b))


def main():
    con = sqlite3.connect(DB)

    subj, p31_of = {}, {}
    for qid, title, cat, qr, p31 in con.execute(
            "SELECT qid, title, category, qrank, p31 FROM subject WHERE keep=1"):
        p31_of[qid] = set((p31 or "").split(",")) - {""}
        if cat is not None:
            subj[qid] = (title, cat, qr)

    ranks = sorted((v[2] for v in subj.values()), reverse=True)
    n = len(ranks)
    thresh = [ranks[min(n - 1, n * k // 5)] for k in range(1, 5)]
    def difficulty(qr):
        for i, t in enumerate(thresh):
            if qr >= t:
                return i + 1
        return 5
    def nudge(d, delta):
        return max(1, min(5, d + delta))

    def gate_ok(prop, qid, cat):
        g = PROPS[prop]["gate"]
        types = p31_of.get(qid, ())
        if g in ("geo", "river"):
            if cat != "geography" or (types & STRUCT_P31):   # no built structures
                return False
            return g == "geo" or "Q4022" in types            # river needs Q4022
        if g == "person":
            return "Q5" in types
        return False

    # members[prop] = list of (qid, normValue, category, p31set), in-bounds + type-gated.
    members = {}
    for prop in PROPS:
        lo, hi = PROPS[prop]["bounds"]
        rows = con.execute(
            "SELECT qid, value FROM fact WHERE prop=? AND kind='num' AND value IS NOT NULL",
            (prop,)).fetchall()
        lst = []
        for qid, raw in rows:
            if qid not in subj:
                continue
            cat = subj[qid][1]
            if not gate_ok(prop, qid, cat):
                continue
            v = normalize(prop, raw)
            if v is None or not (lo <= v <= hi):
                continue
            lst.append((qid, v, cat, p31_of.get(qid, set())))
        members[prop] = lst

    out = []
    perprop = {p: 0 for p in PROPS}

    def pick_distractors(prop, ans_qid, ans_val, cat, p31, seed):
        """3 distractor VALUES, each >=20% from the answer AND from each other.
        Priority: same-category+shared-p31 siblings -> same-category siblings ->
        scaled (x3, x0.3, x10, x0.1, x0.5) fallbacks. Returns [] if <3 achievable."""
        kind = PROPS[prop]["kind"]
        lo, hi = PROPS[prop]["bounds"]
        # keep distractors within the prop's factor of the answer: a far outlier (Nile
        # as a distractor for a creek, a 0.7 m "height") is a trivially eliminable
        # giveaway AND drags the set into an ugly cross-scale render. Positive domains.
        FACTOR = PROPS[prop]["factor"]
        flo = ans_val / FACTOR if ans_val > 0 else None
        fhi = ans_val * FACTOR if ans_val > 0 else None

        def usable(vals, chosen):
            if flo is not None and not (flo <= vals <= fhi):
                return False
            if not separated(vals, ans_val, SEP_ANS):     # strict answer gate
                return False
            for c in chosen:
                if not separated(vals, c, SEP_MUT):        # light anti-duplicate gate
                    return False
            return True

        chosen = []
        shared = [m for m in members[prop]
                  if m[0] != ans_qid and m[2] == cat and (m[3] & p31)]
        samecat = [m for m in members[prop]
                   if m[0] != ans_qid and m[2] == cat and not (m[3] & p31)]
        # nearest-magnitude-first: distractors that hug the >=20% boundary are the most
        # competitive AND avoid absurd far outliers (a 0.72 m "height" for a 1.85 m
        # athlete). Deterministic md5 tie-break for equal ratios.
        def prox(m):
            r = max(m[1] / ans_val, ans_val / m[1]) if m[1] > 0 else 1e9
            return (r, hashlib.md5((seed + m[0]).encode()).hexdigest())
        for pool in (sorted(shared, key=prox), sorted(samecat, key=prox)):
            for m in pool:
                if len(chosen) >= 3:
                    break
                if usable(m[1], chosen):
                    chosen.append(m[1])
            if len(chosen) >= 3:
                break
        if len(chosen) < 3:                       # scaled fallback, closest-first
            # every factor clears the >=20% answer gate (<=0.80 or >=1.25); the per-prop
            # factor bound in usable() then clips the ones that are too far.
            for f in (0.75, 1.35, 0.65, 1.6, 0.55, 1.9, 0.45, 2.3, 0.33, 3.0):
                if len(chosen) >= 3:
                    break
                cand = ans_val * f
                if not (lo <= cand <= hi):
                    continue
                if usable(cand, chosen):
                    chosen.append(cand)
        return chosen[:3] if len(chosen) >= 3 else []

    def finalize(rid, prompt, ans_disp, distract_disp, cat, diff, expl, src_title):
        if not prompt or not ans_disp or not readable(ans_disp):
            return False
        if _leaks(ans_disp, prompt) or ans_disp.strip().lower() in prompt.lower():
            return False
        opts = []
        for d in distract_disp:
            if d and d != ans_disp and d not in opts and readable(d) and not _leaks(d, prompt):
                opts.append(d)
            if len(opts) == 3:
                break
        if len(opts) < 3:
            return False
        ci = _h(rid) % 4
        options = opts[:3] + [ans_disp]
        options[3], options[ci] = options[ci], options[3]
        if len(set(options)) != 4 or options[ci] != ans_disp:
            return False
        out.append([rid, prompt, options, ci, cat, diff, expl, src_title,
                    f"https://en.wikipedia.org/wiki/{_url_title(src_title)}"])
        return True

    for prop, cfg in PROPS.items():
        kind = cfg["kind"]
        for qid, val, cat, p31 in members[prop]:
            title, _, qr = subj[qid]
            rid = f"num:{prop}:{qid}"
            dvals = pick_distractors(prop, qid, val, cat, p31, rid)
            if not dvals:
                continue
            setvals = [val] + dvals
            scale = scale_for(kind, setvals)
            ans_disp = fmt(kind, val, scale)
            distract_disp = [fmt(kind, d, scale) for d in dvals]
            # display-distinct gate (rounding must not collapse two options)
            if len({ans_disp, *distract_disp}) != 4:
                continue
            # re-assert the strict 20% answer gate on the DISPLAYED numbers: 2-sig-fig
            # rounding can pull a borderline pair (raw 20.1%) down to a visible ~19%.
            da = disp_num(kind, val, scale)
            if any(not separated(da, disp_num(kind, d, scale), SEP_ANS) for d in dvals):
                continue
            prompt = cfg["prompt"].format(s=title)
            expl = f"The {cfg['dim']} of {title} is about {fmt_solo(kind, val)}."
            if finalize(rid, prompt, ans_disp, distract_disp, cat,
                        nudge(difficulty(qr), +1), expl, title):
                perprop[prop] += 1

    con.close()

    # dedup by id (defensive; ids are already unique per qid)
    seen, deduped = set(), []
    for r in out:
        if r[0] in seen:
            continue
        seen.add(r[0]); deduped.append(r)
    out = deduped

    payload = {"count": len(out), "questions": out}
    with open(OUT, "w") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    # ---- report ----
    print(f"wrote {OUT}")
    print(f"  total generated: {len(out):,}")
    print("  per prop:")
    names = {"P2046": "area", "P2044": "elevation",
             "P2043": "length", "P2048": "height", "P2067": "weight"}
    for p in PROPS:
        print(f"    {p} {names[p]:11s} {perprop[p]:>6,}   (in-bounds pool: {len(members[p]):,})")
    catc = {}
    for r in out:
        catc[r[4]] = catc.get(r[4], 0) + 1
    print("  category distribution:")
    for c, n in sorted(catc.items(), key=lambda x: -x[1]):
        print(f"    {c:12s} {n:>6,}")

    import random
    rng = random.Random(42)
    sample = rng.sample(out, min(20, len(out)))
    print("\n  --- random sample of 20 ---")
    for r in sample:
        rid, prompt, options, ci, cat, diff, expl, st, su = r
        print(f"\n  [{cat}] {prompt}")
        for i, o in enumerate(options):
            print(f"     {'*' if i == ci else ' '} {o}")
    return out


if __name__ == "__main__":
    main()
