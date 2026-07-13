#!/usr/bin/env python3
"""ADDITIVE grounded-MCQ generator, WAVE 2 — four GROUP families that compare or
flip Wikidata facts across four same-type peers, mined from the same local
corpus_source.sqlite as gen_facts.py.

No LLM. Every answer is derived structurally from a Wikidata fact/relation and
every question is dropped unless it passes the shared quality gates (answer-leak,
verbatim guard, distinct-4-option, real-distractor, foreign-script) PLUS a
per-family correctness gate. Follows gen_facts.py's emit-gate pattern, its
difficulty(qr) quintile logic, and its positional output row schema.

FAMILIES (each groups 4 SAME-TYPE, SAME-CATEGORY subjects)
  SUPERLATIVE (numeric fact): which is most populous / largest / tallest /
    highest / longest / heaviest? Winner must beat runner-up by >=15%.
  CHRONOLOGY (date fact): which was founded / published / born earliest?
    Distinct years, >=2yr gap between earliest and runner-up.
  CLASSIFICATION (occupation): which of these is a {physicist/composer/...}?
    The 3 distractors provably do NOT hold the target occupation.
  REVERSE RELATION (flip a 1:1 relation): of which country is {city} the
    capital? Value must map to exactly ONE subject in the pool.

OUTPUT  tools/corpus/_facts2_staged.json  ->  {"count": N, "questions": [rows]}
Row shape matches assets/corpus.json exactly:
  [id, prompt, options[4], correctIndex, category, difficulty,
   explanation, sourceTitle, sourceURL]

Does NOT touch assets/corpus.json or any shipped file. Staging only.

Usage:  python3 sources/gen_facts2.py
"""
import hashlib, json, os, re, sqlite3, sys

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
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "_facts2_staged.json"))

_NONLATIN = re.compile(r"[^\x00-ɏḀ-ỿ‐-‧‰-⁞]")
def readable(s):
    return bool(s) and not _NONLATIN.search(s)

def _h(*parts):
    return int(hashlib.md5("|".join(map(str, parts)).encode()).hexdigest(), 16)

def fmt_val(v, unit):
    """Human-readable value for an explanation line."""
    v = float(v)
    if unit == "":  # population / count
        if v >= 1e9: return f"{v/1e9:.1f} billion"
        if v >= 1e6: return f"{v/1e6:.1f} million"
        return f"{int(round(v)):,}"
    if unit == "km2":
        return f"{int(round(v)):,} km2"
    if unit == "m":
        if v >= 1000: return f"{v/1000:.1f} km"
        return f"{v:g} m"
    if unit == "kg":
        return f"{v:g} kg"
    return f"{v:g} {unit}".strip()

def fmt_year(y):
    y = int(round(y))
    return f"{-y} BC" if y < 0 else str(y)

# ---------------------------------------------------------------- SUPERLATIVE
# prop -> (dimension word for the explanation, stem bank). "most/least" is baked
# into the stems. All four peers share an exact p31 + category so a neutral
# "which of these ..." stem is unambiguous.
SUP = {
    "P1082": ("population", [
        "Which of these is the most populous?",
        "Which of these has the largest population?",
        "Which of these four has the most people?",
        "Which one below has the biggest population?",
        "Most people of the four — which one?"]),
    "P2046": ("area", [
        "Which of these is the largest by area?",
        "Which of these covers the most land?",
        "Which of these four is biggest by area?",
        "Which one below has the greatest area?",
        "Largest of the four by area — which one?"]),
    "P2048": ("height", [
        "Which of these is the tallest?",
        "Which of these four is the tallest?",
        "Which one below is the tallest?",
        "Tallest of the four — which one?"]),
    "P2044": ("elevation", [
        "Which of these sits at the highest elevation?",
        "Which of these four is highest above sea level?",
        "Which one below has the greatest elevation?",
        "Highest of the four by elevation — which one?"]),
    "P2043": ("length", [
        "Which of these is the longest?",
        "Which of these four is the longest?",
        "Which one below is the longest?",
        "Longest of the four — which one?"]),
    # P2067 (mass) is deliberately EXCLUDED: the fact conflates body weight,
    # molecular mass (g/mol), and astronomical mass (10^53 kg for "Universe")
    # under one "kg" label, so "most massive" is meaningless / wrong. Dropped
    # outright — correctness over volume.
}
# Physical-plausibility bounds per prop. Wikidata routinely stores area/height
# in the wrong unit (m2 as km2, feet as m), producing impossible outliers that
# win the superlative spuriously (Dundee "67,339,690 km2", Petronas "1483 m").
# A single place cannot exceed these; out-of-range members are dropped BEFORE
# grouping so a corrupt value can never become the answer.
SUP_BOUNDS = {
    "P1082": (1, 1.6e9),        # population (India ~1.4e9)
    "P2046": (0.01, 1.8e7),     # area km2 (Russia ~1.71e7)
    "P2048": (0.5, 2.75),       # height m — PEOPLE only (tallest human ~2.72m)
    "P2044": (-450.0, 9000.0),  # elevation m (Everest 8849)
    "P2043": (0.1, 1.2e7),      # length m (Nile ~6.7e6)
}
# Extra type gate per prop (see SUP_KEEP built inside main()): population/area/
# elevation are only meaningful for GEOGRAPHIC places (a building's "area"/"height"
# is a footprint/pinnacle stored in inconsistent units — Petronas "395,000 km2",
# "1483 m"). Height is restricted to people so every value is a metric body height.

# ---------------------------------------------------------------- CHRONOLOGY
# prop -> (verb for stem/explanation, stem bank)
CHRON = {
    "P571": ("founded", [
        "Which of these was founded earliest?",
        "Which of these four came first?",
        "Which one below was established earliest?",
        "Earliest-founded of the four — which one?"]),
    "P577": ("published", [
        "Which of these came out first?",
        "Which of these four appeared earliest?",
        "Which one below is the oldest?",
        "Earliest of the four — which one?"]),
    "P569": ("born", [
        "Which of these people was born first?",
        "Which of these four was born earliest?",
        "Who among these was born first?",
        "Earliest-born of the four — which one?"]),
}

# ---------------------------------------------------------------- CLASSIFICATION
# curated occupation QID -> (singular label, "a"/"an") for distinctive targets
# with clean, non-overlapping meanings and a healthy in-class population.
OCC = {
    "Q169470":  ("physicist", "a"),
    "Q36834":   ("composer", "a"),
    "Q1028181": ("painter", "a"),
    "Q49757":   ("poet", "a"),
    "Q4964182": ("philosopher", "a"),
    "Q6625963": ("novelist", "a"),
    "Q245068":  ("comedian", "a"),
    "Q937857":  ("professional footballer", "a"),
    "Q116":     ("monarch", "a"),
    "Q214917":  ("playwright", "a"),
    "Q170790":  ("mathematician", "a"),
    "Q593644":  ("chemist", "a"),
    "Q11063":   ("astronomer", "an"),
    "Q42973":   ("architect", "an"),
    "Q1281618": ("sculptor", "a"),
    "Q193391":  ("diplomat", "a"),
    "Q1930187": ("journalist", "a"),
}
CLASS_STEMS = [
    "Which of these is {a} {k}?",
    "Which of these four is {a} {k}?",
    "Which one below is best known as {a} {k}?",
    "Pick the {k} from these four.",
    "Who among these is {a} {k}?",
]

# ---------------------------------------------------------------- REVERSE
# prop -> (stem template using {v}, explanation template using {v}/{s})
REV = {
    "P36": ("Of which country is {v} the capital?",
            "{v} is the capital of {s}."),
    "P38": ("Which country uses the {v} as its official currency?",
            "The {v} is the official currency of {s}."),
    "P37": ("Of which country is {v} an official language?",
            "{v} is an official language of {s}."),
}
# widely-shared values whose reverse is ambiguous in reality even if the local
# pool happens to be unique — dropped outright.
REV_SHARED = {
    "P38": {"euro", "united states dollar", "us dollar", "cfa franc",
            "west african cfa franc", "central african cfa franc",
            "east caribbean dollar", "swiss franc", "australian dollar",
            "pound sterling", "danish krone", "indian rupee", "russian ruble"},
    "P37": {"english", "spanish", "french", "arabic", "portuguese", "german",
            "russian", "dutch", "italian", "swahili", "chinese", "mandarin",
            "standard chinese", "malay", "persian", "quechua", "aymara",
            "romanian", "catalan", "greek", "turkish", "tamil"},
}


def main():
    con = sqlite3.connect(DB)

    unit_of = dict(con.execute("SELECT prop, unit FROM fact GROUP BY prop"))

    subj, p31_of, p106_of, p106_first = {}, {}, {}, {}
    for qid, title, cat, qr, p31, p106 in con.execute(
            "SELECT qid, title, category, qrank, p31, p106 FROM subject WHERE keep=1"):
        p31_of[qid] = set((p31 or "").split(",")) - {""}
        toks = [t for t in (p106 or "").split(",") if t]
        p106_of[qid] = set(toks)
        p106_first[qid] = toks[0] if toks else None   # Wikidata lists the primary
                                                       # occupation first
        if cat is not None:
            subj[qid] = (title, cat, qr)

    # difficulty = Qrank quintile (identical to gen_facts.py / build_corpus.py).
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

    out = []
    fam = {}
    def bump(k): fam[k] = fam.get(k, 0) + 1

    def finalize(rid, prompt, answer, distractors, cat, diff, explanation, src_title):
        """Shared gates + row assembly (mirrors gen_facts.emit, decoupled from a
        single subject). Returns True if a valid row was appended."""
        if not prompt or not answer or not readable(answer):
            return False
        if _leaks(answer, prompt):
            return False
        if str(answer).strip().lower() in prompt.lower():
            return False
        opts = []
        for d in distractors:
            if d and d != answer and d not in opts and readable(d) and not _leaks(d, prompt):
                opts.append(d)
            if len(opts) == 3:
                break
        if len(opts) < 3:
            return False
        ci = _h(rid) % 4
        options = opts[:3] + [answer]
        options[3], options[ci] = options[ci], options[3]
        if len(set(options)) != 4 or options[ci] != answer:
            return False
        out.append([rid, prompt, options, ci, cat, diff, explanation, src_title,
                    f"https://en.wikipedia.org/wiki/{_url_title(src_title)}"])
        return True

    # =================================================================
    # GROUP-BUILDER used by SUPERLATIVE and CHRONOLOGY. Buckets subjects by
    # (exact p31, category) so all four peers are genuinely the same type, then
    # deterministically forms non-duplicate groups of 4 with capped subject reuse.
    # =================================================================
    def buckets_for(prop, bounds=None, keep_fn=None):
        lo, hi = bounds if bounds else (None, None)
        b = {}
        for qid, value in con.execute(
                "SELECT qid, value FROM fact WHERE prop=? AND value IS NOT NULL", (prop,)):
            if qid not in subj or value is None:
                continue
            if bounds and not (lo <= value <= hi):   # drop impossible/mis-united
                continue
            cat = subj[qid][1]
            if keep_fn and not keep_fn(qid, cat):     # per-prop type gate
                continue
            for p in p31_of.get(qid, ()):
                b.setdefault((p, cat), []).append((qid, value))
        return b

    def groups(members, seed, cap, reuse, reuse_cap):
        """Yield up to `cap` groups of 4 distinct qids from `members`, honoring a
        per-qid reuse budget. Deterministic order via md5(seed)."""
        ordered = sorted(members, key=lambda m: hashlib.md5((seed + m[0]).encode()).hexdigest())
        made, seen_sig, i = 0, set(), 0
        # sliding window of 4 with step 1 across the shuffled list gives varied,
        # overlapping-but-distinct groups; reuse_cap keeps any subject from
        # dominating.
        while i + 4 <= len(ordered) and made < cap:
            grp = ordered[i:i + 4]
            i += 1
            qids = [g[0] for g in grp]
            if any(reuse.get(q, 0) >= reuse_cap for q in qids):
                continue
            sig = tuple(sorted(qids))
            if sig in seen_sig:
                continue
            seen_sig.add(sig)
            for q in qids:
                reuse[q] = reuse.get(q, 0) + 1
            yield grp
            made += 1

    # ----------------------------------------------------------- SUPERLATIVE
    SUP_KEEP = {
        "P1082": lambda q, c: c == "geography",
        "P2046": lambda q, c: c == "geography",
        "P2044": lambda q, c: c == "geography",
        "P2048": lambda q, c: "Q5" in p31_of.get(q, ()),
    }
    for prop, (dim, stems) in SUP.items():
        reuse = {}
        for (p31, cat), members in buckets_for(
                prop, SUP_BOUNDS.get(prop), SUP_KEEP.get(prop)).items():
            if len(members) < 4:
                continue
            for grp in groups(members, f"sup:{prop}:{p31}:{cat}", cap=25,
                              reuse=reuse, reuse_cap=5):
                ranked = sorted(grp, key=lambda m: m[1], reverse=True)
                vals = [m[1] for m in ranked]
                if len(set(vals)) != 4:            # distinct values
                    continue
                a, b = vals[0], vals[1]
                if a <= 0 or (a - b) / a < 0.15:   # winner beats runner-up by >=15%
                    continue
                wq = ranked[0][0]
                wt, wcat, wqr = subj[wq]
                distract = [subj[m[0]][0] for m in ranked[1:]]
                rid = f"sup:{prop}:{_h(prop, *sorted(m[0] for m in grp)) % (10**12)}"
                stem = stems[_h(rid) % len(stems)]
                expl = f"{wt} has the greatest {dim} of the four ({fmt_val(a, unit_of.get(prop) or '')})."
                if finalize(rid, stem, wt, distract, wcat,
                            nudge(difficulty(wqr), +1), expl, wt):
                    bump("superlative")

    # ----------------------------------------------------------- CHRONOLOGY
    for prop, (verb, stems) in CHRON.items():
        reuse = {}
        for (p31, cat), members in buckets_for(prop).items():
            if len(members) < 4:
                continue
            for grp in groups(members, f"chron:{prop}:{p31}:{cat}", cap=25,
                              reuse=reuse, reuse_cap=5):
                ranked = sorted(grp, key=lambda m: m[1])   # earliest first
                yrs = [int(round(m[1])) for m in ranked]
                if len(set(yrs)) != 4:                     # distinct years
                    continue
                if yrs[1] - yrs[0] < 2:                    # clear earliest
                    continue
                eq = ranked[0][0]
                et, ecat, eqr = subj[eq]
                distract = [subj[m[0]][0] for m in ranked[1:]]
                rid = f"chron:{prop}:{_h(prop, *sorted(m[0] for m in grp)) % (10**12)}"
                stem = stems[_h(rid) % len(stems)]
                # P577 covers both films/music ("released") and books ("published");
                # pick the truthful verb from the earliest subject's category.
                vb = ("released" if ecat in ("screen", "music") else "published") \
                    if prop == "P577" else verb
                expl = f"{et} ({vb} {fmt_year(yrs[0])}) is the earliest of the four."
                if finalize(rid, stem, et, distract, ecat,
                            nudge(difficulty(eqr), +1), expl, et):
                    bump("chronology")

    # ----------------------------------------------------------- CLASSIFICATION
    # in-class = subjects holding the target occupation; distractors = subjects
    # that provably do NOT hold it (checked against their full p106 set),
    # preferring the same category so category alone can't crack the question.
    people = [(qid, subj[qid][0], subj[qid][1], subj[qid][2])
              for qid in subj if p106_of.get(qid)]
    by_cat = {}
    for qid, title, cat, qr in people:
        by_cat.setdefault(cat, []).append(qid)
    for occ_q, (label, art) in OCC.items():
        # PRIMARY-occupation gate: the target must be the person's first-listed
        # occupation, so "which is a physicist?" answers a person genuinely known
        # as one — not someone Wikidata also tags an architect (Arnold Palmer) or
        # journalist (David Letterman) as a secondary role.
        in_class = [(qid, t, c, qr) for (qid, t, c, qr) in people if p106_first[qid] == occ_q]
        in_class.sort(key=lambda r: hashlib.md5((occ_q + r[0]).encode()).hexdigest())
        made = 0
        for qid, title, cat, qr in in_class:
            if made >= 25:
                break
            # candidate distractors: same category, provably NOT this occupation.
            cands = [q for q in by_cat.get(cat, [])
                     if occ_q not in p106_of[q] and q != qid]
            cands.sort(key=lambda q: hashlib.md5((qid + q).encode()).hexdigest())
            if len(cands) < 3:                       # fall back to any category
                extra = [q for q in subj
                         if p106_of.get(q) and occ_q not in p106_of[q] and q != qid]
                extra.sort(key=lambda q: hashlib.md5((qid + "x" + q).encode()).hexdigest())
                cands = cands + [q for q in extra if q not in cands]
            distract = [subj[q][0] for q in cands[:8]]
            rid = f"class:{occ_q}:{_h(occ_q, qid) % (10**12)}"
            stem = CLASS_STEMS[_h(rid) % len(CLASS_STEMS)].format(a=art, k=label)
            expl = f"{title} is {art} {label}."
            if finalize(rid, stem, title, distract, cat,
                        nudge(difficulty(qr), -1), expl, title):
                bump("classification")
                made += 1

    # ----------------------------------------------------------- REVERSE
    # The stems assert "of which COUNTRY", so restrict both the answer subject
    # and the distractor pool to sovereign countries — otherwise a US state
    # capital (Little Rock -> Arkansas) or a defunct empire leaks in as an
    # answer/odd-one-out and the framing is simply wrong.
    COUNTRY_P31 = {"Q6256", "Q3624078"}
    def is_country(qid):
        return bool(p31_of.get(qid, ()) & COUNTRY_P31)
    for prop, (stem_t, expl_t) in REV.items():
        rows = con.execute(
            "SELECT qid, target_label FROM relation WHERE prop=? "
            "AND target_label IS NOT NULL AND target_label <> ''", (prop,)).fetchall()
        by_value, subj_pool = {}, set()
        for qid, tl in rows:
            if qid not in subj or not is_country(qid):
                continue
            by_value.setdefault(tl.strip(), set()).add(qid)
            subj_pool.add(qid)
        shared = REV_SHARED.get(prop, set())
        pool_titles = sorted({subj[q][0] for q in subj_pool})
        for qid, tl in rows:
            if qid not in subj or not is_country(qid):
                continue
            v = tl.strip()
            if len(by_value.get(v, ())) != 1:            # reverse-unique in pool
                continue
            if v.lower() in shared:                      # ambiguous in reality
                continue
            title, cat, qr = subj[qid]
            prompt = stem_t.format(v=v)
            # distractors: other subjects of this relation (same type = countries)
            distract = [t for t in sorted(
                pool_titles, key=lambda t: hashlib.md5((qid + t).encode()).hexdigest())
                if t != title]
            rid = f"rev:{prop}:{qid}"
            expl = expl_t.format(v=v, s=title)
            if finalize(rid, prompt, title, distract, cat,
                        difficulty(qr), expl, title):
                bump(f"reverse_{prop}")

    con.close()

    # Dedup by id: the same 4-subject group can form under two shared p31 types
    # (e.g. Swiss cities are both Q515 and Q1093829), yielding an identical
    # deterministic id. Keep first occurrence.
    seen_id, deduped = set(), []
    for r in out:
        if r[0] in seen_id:
            continue
        seen_id.add(r[0])
        deduped.append(r)
    out = deduped

    payload = {"count": len(out), "questions": out}
    with open(OUT, "w") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    print(f"wrote {OUT}")
    print(f"  total generated: {len(out):,}")
    print("  per family:")
    for k in ("superlative", "chronology", "classification",
              "reverse_P36", "reverse_P38", "reverse_P37"):
        print(f"    {k:18s} {fam.get(k, 0):>6,}")
    return out


if __name__ == "__main__":
    main()
