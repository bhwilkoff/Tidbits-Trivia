#!/usr/bin/env python3
"""ADDITIVE grounded-MCQ generator — mine the UNUSED `fact` + `relation` tables of
corpus_source.sqlite into thousands of deterministic, correct-by-construction MCQs.

No LLM. Every answer is a Wikidata fact; every question is dropped unless it passes
the same quality gates the live writer (build_corpus.py) uses — answer-leak,
distinct-4-option, real-distractor, foreign-script guards.

FAMILIES
  Forward FACT (answer = the fact value):
    birth_year(P569) death_year(P570) founded_year(P571, orgs/places only)
    released_year(P577) discovered_year(P575) atomic_number(P1086)
  Forward RELATION (answer = the related entity):
    country(P17) official_language(P37) founder(P112) creator(P170)
    discoverer(P61) manufacturer(P176) performer(P175)

OUTPUT  tools/corpus/_facts_staged.json  ->  {"count": N, "questions": [ rows... ]}
Row shape matches assets/corpus.json exactly:
  [id, prompt, options[4], correctIndex, category, difficulty,
   explanation, sourceTitle, sourceURL]

Does NOT touch assets/corpus.json or any shipped file. Staging only.

Usage:  python3 sources/gen_facts.py
"""
import hashlib, json, os, re, sqlite3, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Reuse the live writer's helpers where they exist; fall back to faithful copies.
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
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "_facts_staged.json"))

# --- founded_year (P571) eligibility ----------------------------------------
# "founded/established" is only truthful for ORGANIZATIONS and POLITIES/SETTLEMENTS.
# It is WRONG for buildings, monuments, artworks, genres, software, natural
# features -> those get an explicit skip via an allowlist (prefer dropping).
FOUNDABLE_P31 = {
    # organizations
    "Q4830453",   # business
    "Q891723",    # public company
    "Q6881511",   # enterprise
    "Q783794",    # company
    "Q167037",    # corporation
    "Q155076",    # juridical person
    "Q43229",     # organization
    "Q163740",    # nonprofit organization
    "Q245065",    # intergovernmental organization
    "Q79913",     # non-governmental organization
    "Q215380",    # musical group (band)
    "Q105543609", # musical group
    "Q5741069",   # rock band
    "Q476028",    # association football club
    "Q847017",    # sports club
    "Q786820",    # automobile manufacturer
    "Q46970",     # airline
    "Q7278",      # political party
    "Q33506",     # museum
    "Q3918",      # university
    "Q875538",    # public university
    "Q2385804",   # educational institution
    "Q327333",    # government agency
    "Q1320047",   # book publisher
    "Q18127",     # record label
    # polities / settlements
    "Q6256",      # country
    "Q3624078",   # sovereign state
    "Q3024240",   # historical country
    "Q7270",      # republic
    "Q179164",    # unitary state
    "Q48349",     # empire
    "Q123480",    # landlocked country
    "Q515",       # city
    "Q1549591",   # big city
    "Q1093829",   # city of the United States
    "Q1637706",   # megacity
    "Q174844",    # megacity (alt)
    "Q200250",    # metropolis
    "Q62049",     # county seat
    "Q3957",      # town
    "Q532",       # village
    "Q15284",     # municipality
    "Q7930989",   # city/town
}

# released_year (P577): only families where "released"/"published" is always
# correct. screen/music -> "released"; books -> "published"; video games ->
# "released". Everything else in `arts` (paintings, plays, sculptures, mixed) is
# dropped because the correct verb varies.
BOOK_P31 = {
    "Q571",       # book
    "Q7725634",   # literary work
    "Q47461344",  # written work
    "Q8261",      # novel
    "Q1004",      # comics
    "Q49084",     # short story
    "Q25379",     # play (published text)
    "Q7725310",   # literary series
}
GAME_P31 = {"Q7889", "Q865493", "Q116774927", "Q112144412"}  # video game (series)

# --- helpers ----------------------------------------------------------------
_NONLATIN = re.compile(r"[^\x00-ɏḀ-ỿ‐-‧‰-⁞]")
def readable(s):
    """Reject options carrying non-Latin script (CJK/Cyrillic/Arabic/…) — an
    unreadable option is an odd-one-out giveaway and useless to a US-EN player."""
    return bool(s) and not _NONLATIN.search(s)

def fmt_year(y):
    y = int(round(y))
    return f"{-y} BC" if y < 0 else str(y)

CUR_YEAR = 2026
def year_distractors(year, seed, n=3):
    """3 distinct plausible near-years, spread scaled to the era. Never a future
    year (that would give the answer away for births/foundings/releases)."""
    y = int(round(year))
    if y >= 1980:   spread = 5
    elif y >= 1900: spread = 8
    elif y >= 1700: spread = 15
    elif y >= 1000: spread = 22
    else:           spread = 30
    offsets = [o for o in range(-spread, spread + 1) if o != 0]
    offsets.sort(key=lambda o: hashlib.md5((seed + ":" + str(o)).encode()).hexdigest())
    out, seen = [], {fmt_year(y)}
    for o in offsets:
        cand = y + o
        if cand > CUR_YEAR + 1:      # no implausible future
            continue
        if cand == 0:                # there is no year 0
            continue
        s = fmt_year(cand)
        if s not in seen:
            seen.add(s); out.append(s)
        if len(out) == n:
            break
    return out

def int_distractors(v, seed, n=3, lo=1, hi=126):
    x = int(round(v))
    offsets = [o for o in range(-6, 7) if o != 0]
    offsets.sort(key=lambda o: hashlib.md5((seed + ":" + str(o)).encode()).hexdigest())
    out, seen = [], {x}
    for o in offsets:
        c = x + o
        if lo <= c <= hi and c not in seen:
            seen.add(c); out.append(str(c))
        if len(out) == n:
            break
    return out


def main():
    con = sqlite3.connect(DB)

    # subjects: id -> (title, category, qrank, p31 set, url). category NULL skipped.
    subj, p31_of, title_of = {}, {}, {}
    for qid, title, cat, qr, p31 in con.execute(
            "SELECT qid, title, category, qrank, p31 FROM subject WHERE keep=1"):
        title_of[qid] = title
        p31_of[qid] = set((p31 or "").split(",")) - {""}
        if cat is not None:
            subj[qid] = (title, cat, qr)

    # difficulty = Qrank quintile over kept, categorized subjects (identical to
    # build_corpus.py: 1 = most popular/easiest, 5 = most obscure/hardest).
    ranks = sorted((v[2] for v in subj.values()), reverse=True)
    n = len(ranks)
    thresh = [ranks[min(n - 1, n * k // 5)] for k in range(1, 5)]
    def difficulty(qr):
        for i, t in enumerate(thresh):
            if qr >= t:
                return i + 1
        return 5

    # clickstream neighbours (strong same-type relation distractors)
    related = {}
    for t, nb in con.execute("SELECT title, neighbour FROM related ORDER BY n DESC"):
        related.setdefault(t, []).append(nb)

    out = []
    fam = {}  # family -> count
    def bump(k): fam[k] = fam.get(k, 0) + 1

    def emit(qid, prop, kind, prompt, answer, distractors, cat, qr):
        """Assemble one row after the shared gates. Returns True if emitted."""
        if not prompt or not answer:
            return False
        if not readable(answer):
            return False
        if _leaks(answer, prompt):          # answer must not sit in the prompt
            return False
        # Verbatim guard — catches numeric/year answers baked into the subject's
        # disambiguator, e.g. "Titanic (1997 film)" giving away the release year.
        # (_leaks tokenizes on letters, so it misses pure-digit answers.)
        if str(answer).strip().lower() in prompt.lower():
            return False
        opts = []
        for d in distractors:
            if d and d != answer and d not in opts and readable(d) and not _leaks(d, prompt):
                opts.append(d)
            if len(opts) == 3:
                break
        if len(opts) < 3:                   # need >=3 real distractors
            return False
        title, _, _ = subj[qid]
        h = int(hashlib.md5((qid + prop + kind).encode()).hexdigest(), 16)
        ci = h % 4
        options = opts[:3] + [answer]
        options[3], options[ci] = options[ci], options[3]
        # final integrity: exactly 4 distinct options, valid index
        if len(set(options)) != 4 or options[ci] != answer:
            return False
        rid = f"{kind}:{prop}:{qid}"
        out.append([rid, prompt, options, ci, cat, difficulty(qr),
                    f"{title}: {answer}", title,
                    f"https://en.wikipedia.org/wiki/{_url_title(title)}"])
        return True

    # ================= FORWARD FACT MCQs =================
    facts = con.execute("SELECT qid, prop, value FROM fact").fetchall()
    # index by (qid) which props exist — for cross-checks not currently needed.
    for qid, prop, value in facts:
        if qid not in subj or value is None:
            continue
        title, cat, qr = subj[qid]
        types = p31_of.get(qid, set())
        is_person = "Q5" in types

        if prop == "P569":   # birth_year — persons only
            if not is_person:
                continue
            ans = fmt_year(value)
            ds = year_distractors(value, qid + prop)
            if emit(qid, prop, "fact", f"In what year was {title} born?", ans, ds, cat, qr):
                bump("birth_year")

        elif prop == "P570": # death_year — persons only
            if not is_person:
                continue
            ans = fmt_year(value)
            ds = year_distractors(value, qid + prop)
            if emit(qid, prop, "fact", f"In what year did {title} die?", ans, ds, cat, qr):
                bump("death_year")

        elif prop == "P571": # founded_year — orgs/places only (allowlist)
            if is_person or not (types & FOUNDABLE_P31):
                continue
            ans = fmt_year(value)
            ds = year_distractors(value, qid + prop)
            if emit(qid, prop, "fact", f"In what year was {title} founded?", ans, ds, cat, qr):
                bump("founded_year")

        elif prop == "P577": # released_year — media/books/games only
            if cat in ("screen", "music"):
                verb = "first released"
            elif types & BOOK_P31:
                verb = "first published"
            elif types & GAME_P31:
                verb = "first released"
            else:
                continue
            ans = fmt_year(value)
            ds = year_distractors(value, qid + prop)
            if emit(qid, prop, "fact", f"In what year was {title} {verb}?", ans, ds, cat, qr):
                bump("released_year")

        elif prop == "P575": # discovered_year — natural discoveries (skip sports "inventions")
            if cat == "sports":
                continue
            ans = fmt_year(value)
            ds = year_distractors(value, qid + prop)
            if emit(qid, prop, "fact", f"In what year was {title} discovered?", ans, ds, cat, qr):
                bump("discovered_year")

        elif prop == "P1086": # atomic_number — elements
            an = int(round(value))
            if not (1 <= an <= 126):
                continue
            ds = int_distractors(value, qid + prop)
            if emit(qid, prop, "fact", f"What is the atomic number of {title}?",
                    str(an), ds, cat, qr):
                bump("atomic_number")

    # ================= FORWARD RELATION MCQs =================
    # prop -> (prompt template, label used in DB)
    REL = {
        "P17":  ("In which country is {k}?",             "country"),
        "P37":  ("Which of these is an official language of {k}?", "official_language"),
        "P112": ("Who founded {k}?",                     "founder"),
        "P170": ("Who created {k}?",                     "creator"),
        "P61":  ("Who is credited with discovering {k}?", "discoverer"),
        "P176": ("Which company manufactures {k}?",      "manufacturer"),
        "P175": ("Who is the performer of {k}?",         "performer"),
    }
    # value pools per prop (all target_labels), plus which target_label -> a
    # subject title (so we can pull that entity's clickstream neighbours as
    # type-safe strong distractors), and multiplicity check per (qid,prop).
    rel_rows = con.execute(
        "SELECT qid, prop, target_qid, target_label FROM relation "
        "WHERE prop IN ('P17','P37','P112','P170','P61','P176','P175') "
        "AND target_label IS NOT NULL AND target_label <> ''").fetchall()
    # person-valued relations: a distractor of the wrong KIND (a country listed as
    # a "founder") is an odd-one-out giveaway. Track each value's kind (person vs
    # thing) from the target's own p31, and only offer same-kind distractors.
    PERSON_PROPS = {"P112", "P170", "P61", "P175"}
    tgt_kind = {}                 # (prop, target_label) -> 'person'/'thing'/None
    pool = {}                     # prop -> [target_label,...]
    multi = {}                    # (qid,prop) -> count  (uniqueness gate)
    for qid, prop, tq, tl in rel_rows:
        pool.setdefault(prop, []).append(tl)
        multi[(qid, prop)] = multi.get((qid, prop), 0) + 1
        types = p31_of.get(tq)
        k = "person" if (types and "Q5" in types) else ("thing" if types else None)
        if tgt_kind.get((prop, tl)) is None:   # first definite kind wins
            tgt_kind[(prop, tl)] = k
    pool_set = {p: set(v) for p, v in pool.items()}

    for qid, prop, tq, tl in rel_rows:
        if qid not in subj:
            continue
        if multi[(qid, prop)] != 1:        # only a single clear value
            continue
        if prop == "P61" and subj[qid][1] == "sports":   # "discovered" != invented
            continue
        title, cat, qr = subj[qid]
        prompt = REL[prop][0].format(k=title)
        ps = pool[prop]
        if len(pool_set[prop]) < 4:        # need a real value pool
            continue
        ans_kind = tgt_kind.get((prop, tl))
        def kind_ok(v):
            if prop not in PERSON_PROPS or ans_kind is None:
                return True
            vk = tgt_kind.get((prop, v))
            return vk is None or vk == ans_kind
        # strong distractors: neighbours of the answer entity that are themselves
        # used as a value of THIS same relation (guarantees type compatibility).
        strong = [nb for nb in related.get(tl, [])
                  if nb in pool_set[prop] and nb != tl and kind_ok(nb)]
        # then deterministic walk through the value pool (build_corpus pattern)
        h = int(hashlib.md5((qid + prop).encode()).hexdigest(), 16)
        i, step = h % len(ps), 1 + (h % 7)
        walk, guard = [], 0
        while guard < len(ps) * 2 and len(walk) < 20:
            v = ps[i % len(ps)]; i += step; guard += 1
            if v != tl and v not in walk and kind_ok(v):
                walk.append(v)
        distractors = strong + [w for w in walk if w not in strong]
        if emit(qid, prop, "rel", prompt, tl, distractors, cat, qr):
            bump(REL[prop][1])

    con.close()

    payload = {"count": len(out), "questions": out}
    with open(OUT, "w") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    print(f"wrote {OUT}")
    print(f"  total generated: {len(out):,}")
    print("  per family:")
    for k in ("birth_year", "death_year", "founded_year", "released_year",
              "discovered_year", "atomic_number", "country", "official_language",
              "founder", "creator", "discoverer", "manufacturer", "performer"):
        print(f"    {k:20s} {fam.get(k, 0):>6,}")
    return out


if __name__ == "__main__":
    main()
