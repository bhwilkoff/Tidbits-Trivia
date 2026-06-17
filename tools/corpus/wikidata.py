#!/usr/bin/env python3
"""
Tidbits — Wikidata SPARQL question generator (the quality moat).

v2: dataset-driven. A few bounded SPARQL queries each pull a rich DATASET
(countries, chemical elements, Best-Picture films, award books, notable
people by occupation). From each dataset we generate MANY question TYPES —
forward & reverse attribute lookup, superlative ("which is largest?"),
chronology ("which came first?"), numeric ("closest to?"), and
classification / odd-one-out. Every question is a 4-option MCQ, so all four
client platforms render them unchanged (they read the shared corpus).

Answers are derived structurally, so the hard quality gates hold by
construction (single-answer + distractor-correctness for functional
properties; popularity via bounded famous domains; NPOV via single-value
gates). Rotating stems keep phrasing varied; distractors are typed siblings.

Appends into corpus.sqlite under template_id 'wd:*'. Stdlib only.
Usage: python3 wikidata.py [--db PATH] [--only key1,key2] [--gap SECONDS]
"""
import argparse, json, os, re, sqlite3, sys, time, urllib.parse, urllib.request, random

CACHE_DIR = "cache"
ALLOW_LIVE = False   # set by --fetch; otherwise un-cached datasets are skipped

def cached(name, fetch_fn):
    """Cache each fetched dataset to disk so we can regenerate questions
    instantly without re-hitting the (heavily rate-limited) WDQS. Without
    --fetch, an un-cached dataset is SKIPPED (returns []) rather than
    hammering WDQS — so we can ship cached types immediately."""
    path = os.path.join(CACHE_DIR, name + ".json")
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
        print(f"[wd] {name}: {len(data)} (cached)")
        return data
    if not ALLOW_LIVE:
        print(f"[wd] {name}: skipped (no cache; rerun with --fetch when WDQS is cool)")
        return []
    data = fetch_fn()
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f)
    return data

WDQS = "https://query.wikidata.org/sparql"
UA = "TidbitsTrivia/1.0 (learning trivia app; contact ben@learningischange.com)"
QID_RE = re.compile(r"^Q\d+$")
RNG = random.Random(20260617)

def sparql(query, retries=6):
    for attempt in range(retries):
        try:
            url = WDQS + "?" + urllib.parse.urlencode({"query": query})
            req = urllib.request.Request(url, headers={
                "User-Agent": UA, "Accept": "application/sparql-results+json"})
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)["results"]["bindings"]
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < retries - 1:
                wait = int(e.headers.get("Retry-After") or 0) or (15 * (attempt + 1))
                print(f"  … {e.code}, waiting {wait}s", file=sys.stderr); time.sleep(wait + 2); continue
            print(f"  ! HTTP {e.code}", file=sys.stderr); return []
        except Exception as e:
            if attempt == retries - 1:
                print(f"  ! {e}", file=sys.stderr); return []
            time.sleep(8)
    return []

def val(row, key):
    return row.get(key, {}).get("value")

def clean(s):
    return s if s and not QID_RE.match(s) else None

def year_of(iso):
    if not iso: return None
    m = re.match(r"(-?\d+)", iso.lstrip("+"))
    return int(m.group(1)) if m else None

# ---- Question assembly helpers ----

def assemble(tid, category, prompt, correct, distractors, explanation, source, url):
    opts = [correct] + list(distractors)
    RNG.shuffle(opts)
    ci = opts.index(correct)
    # qid keyed on the full option SET (not just the prompt) so superlative /
    # chronology / classification questions — which share a fixed stem — don't
    # collide and get deduped away by INSERT OR IGNORE.
    sig = prompt + "||" + "|".join(sorted(opts))
    qid = f"wd:{tid}:{abs(hash(sig)) % (10**14)}"
    return (qid, prompt, opts[0], opts[1], opts[2], opts[3], ci, category, 3,
            explanation, source, url or "", f"wd:{tid}")

def pick_stem(stems, key):
    return stems[abs(hash(key)) % len(stems)]

def fmt_num(n):
    n = float(n)
    if n >= 1e9: return f"{n/1e9:.1f} billion"
    if n >= 1e6: return (f"{n/1e6:.0f} million" if n >= 1e7 else f"{n/1e6:.1f} million")
    if n >= 1e4: return f"{int(round(n, -3)):,}"
    return f"{int(n):,}"

def numeric_distractors(true_v):
    """Three multiplicative-band distractors straddling the true value,
    jittered, distinct after formatting (no median tell, consistent format)."""
    mults = RNG.sample([0.25, 0.4, 0.6, 1.6, 2.5, 4.0], 3)
    # ensure at least one below and one above 1.0
    if all(m > 1 for m in mults): mults[0] = RNG.choice([0.4, 0.6])
    if all(m < 1 for m in mults): mults[0] = RNG.choice([1.6, 2.5])
    out, seen = [], {fmt_num(true_v)}
    for m in mults:
        f = fmt_num(true_v * m * RNG.uniform(0.9, 1.1))
        if f not in seen:
            seen.add(f); out.append(f)
    return out

# ---- Generic generators over a dataset (list of dict rows) ----

def gen_forward(rows, subj, value, category, stems, tid, explain):
    """'What is the {value} of {subject}?' distractors = sibling values."""
    pool = [r for r in rows if r.get(subj) and r.get(value)]
    all_values = list({r[value] for r in pool})
    if len(all_values) < 4: return []
    out = []
    for r in pool:
        ans = r[value]
        others = [v for v in all_values if v.lower() != ans.lower()]
        if len(others) < 3: continue
        ds = RNG.sample(others, 3)
        prompt = pick_stem(stems, r[subj]).format(s=r[subj])
        out.append(assemble(tid, category, prompt, ans, ds, explain(r), r[subj], r.get("article")))
    return out

def gen_reverse(rows, subj, value, category, stems, tid, explain):
    """'Which {subject} has {value}?' — only when value→subject is ~1:1."""
    by_value = {}
    for r in rows:
        if r.get(subj) and r.get(value):
            by_value.setdefault(r[value], set()).add(r[subj])
    pool = [r for r in rows if r.get(subj) and r.get(value) and len(by_value[r[value]]) == 1]
    subjects = list({r[subj] for r in pool})
    if len(subjects) < 4: return []
    out = []
    for r in pool:
        ans = r[subj]
        others = [s for s in subjects if s.lower() != ans.lower()]
        if len(others) < 3: continue
        ds = RNG.sample(others, 3)
        prompt = pick_stem(stems, r[value]).format(v=r[value])
        out.append(assemble(tid, category, prompt, ans, ds, explain(r), ans, r.get("article")))
    return out

def gen_superlative(rows, label, num, category, stems, tid, mode, dim, n_questions):
    """Pick 4 entities with well-separated numeric values; ask which is max/min."""
    pool = [r for r in rows if r.get(label) and r.get(num) is not None]
    if len(pool) < 8: return []
    out, used = [], set()
    for _ in range(n_questions * 3):
        if len(out) >= n_questions: break
        group = RNG.sample(pool, 4)
        vals = sorted(group, key=lambda r: r[num], reverse=(mode == "max"))
        # require clear separation: extreme differs from runner-up by ≥20%
        a, b = vals[0][num], vals[1][num]
        if b == 0 or abs(a - b) / max(abs(a), 1) < 0.2: continue
        winner = vals[0]
        key = winner[label] + "|" + ",".join(sorted(r[label] for r in group))
        if key in used: continue
        used.add(key)
        prompt = pick_stem(stems, key).format(dim=dim)
        ds = [r[label] for r in group if r[label] != winner[label]]
        out.append(assemble(tid, category, prompt, winner[label], ds,
                            f"{winner[label]} has the {mode}imum {dim} of the four.", winner[label], winner.get("article")))
    return out

def gen_chronology(rows, label, year, category, stems, tid, verb, n_questions):
    """Pick 4 dated entities; ask which came first (earliest year)."""
    pool = [r for r in rows if r.get(label) and r.get(year) is not None]
    if len(pool) < 8: return []
    out, used = [], set()
    for _ in range(n_questions * 3):
        if len(out) >= n_questions: break
        group = RNG.sample(pool, 4)
        years = sorted(group, key=lambda r: r[year])
        if years[1][year] - years[0][year] < 3: continue   # clear earliest
        if len({r[year] for r in group}) < 4: continue       # distinct years
        first = years[0]
        key = first[label] + "|" + ",".join(sorted(r[label] for r in group))
        if key in used: continue
        used.add(key)
        prompt = pick_stem(stems, key).format(verb=verb)
        ds = [r[label] for r in group if r[label] != first[label]]
        out.append(assemble(tid, category, prompt, first[label], ds,
                            f"{first[label]} ({verb} {first[year]}) came first.", first[label], first.get("article")))
    return out

def gen_numeric(rows, label, num, category, stems, tid, unit, explain):
    pool = [r for r in rows if r.get(label) and r.get(num)]
    out = []
    for r in pool:
        ds = numeric_distractors(r[num])
        if len(ds) != 3: continue
        prompt = pick_stem(stems, r[label]).format(s=r[label], unit=unit)
        out.append(assemble(tid, category, prompt, fmt_num(r[num]), ds, explain(r), r[label], r.get("article")))
    return out

def gen_classification(rows, label, klass_key, klass_value, category, stems, tid, other_rows):
    """'Which of these is a {klass}?' correct ∈ class, distractors ∉ class."""
    in_class = [r for r in rows if r.get(label) and r.get(klass_key) == klass_value]
    out_class = [r for r in other_rows if r.get(label) and r.get(klass_key) != klass_value]
    if len(in_class) < 1 or len(out_class) < 3: return []
    out = []
    for r in in_class:
        ds = [x[label] for x in RNG.sample(out_class, 3)]
        prompt = pick_stem(stems, r[label]).format(k=klass_value)
        out.append(assemble(tid, category, prompt, r[label], ds,
                            f"{r[label]} is a {klass_value}.", r[label], r.get("article")))
    return out

# ---- Datasets (one bounded query each) ----

def dataset_countries():
    print("[wd] countries dataset…")
    q = """SELECT ?item ?itemLabel ?capitalLabel ?continentLabel ?currencyLabel ?pop ?area ?inception ?article WHERE {
      ?item wdt:P31 wd:Q6256 .
      OPTIONAL { ?item wdt:P36 ?capital. }
      OPTIONAL { ?item wdt:P30 ?continent. }
      OPTIONAL { ?item wdt:P38 ?currency. }
      OPTIONAL { ?item wdt:P1082 ?pop. }
      OPTIONAL { ?item wdt:P2046 ?area. }
      OPTIONAL { ?item wdt:P571 ?inception. }
      OPTIONAL { ?article schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>. }
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }"""
    agg = {}
    for r in sparql(q):
        qid = val(r, "item"); name = clean(val(r, "itemLabel"))
        if not qid or not name: continue
        d = agg.setdefault(qid, {"country": name, "article": val(r, "article"), "continents": set()})
        if not d.get("capital"): d["capital"] = clean(val(r, "capitalLabel"))
        if not d.get("currency"): d["currency"] = clean(val(r, "currencyLabel"))
        cont = clean(val(r, "continentLabel"))
        if cont: d["continents"].add(cont)
        for k, src in (("pop", "pop"), ("area", "area")):
            v = val(r, src)
            if v:
                try: d[k] = max(d.get(k, 0), float(v))
                except ValueError: pass
        iv = year_of(val(r, "inception"))
        if iv and (d.get("inception") is None or iv < d["inception"]): d["inception"] = iv
    rows = []
    for d in agg.values():
        d["continent"] = next(iter(d["continents"])) if len(d["continents"]) == 1 else None  # NPOV: single-continent only
        d.pop("continents", None)   # drop set → JSON-serializable for caching
        rows.append(d)
    print(f"[wd] {len(rows)} countries")
    return rows

def dataset_elements():
    print("[wd] elements dataset…")
    q = """SELECT ?item ?itemLabel ?symbol ?number ?discovery ?article WHERE {
      ?item wdt:P31 wd:Q11344; wdt:P1086 ?number .
      OPTIONAL { ?item wdt:P246 ?symbol. }
      OPTIONAL { ?item wdt:P575 ?discovery. }
      OPTIONAL { ?article schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>. }
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }"""
    agg = {}
    for r in sparql(q):
        qid = val(r, "item"); name = clean(val(r, "itemLabel"))
        if not qid or not name: continue
        try: num = int(float(val(r, "number")))
        except (TypeError, ValueError): continue
        if num > 118 or name.lower().startswith("un"): continue   # real, named elements only
        d = agg.setdefault(qid, {"element": name, "number": num, "article": val(r, "article")})
        if not d.get("symbol"): d["symbol"] = val(r, "symbol")
        dy = year_of(val(r, "discovery"))
        if dy and (d.get("discovery") is None): d["discovery"] = dy
    rows = list(agg.values())
    print(f"[wd] {len(rows)} elements")
    return rows

def dataset_bestpic():
    print("[wd] best-picture dataset…")
    q = """SELECT ?item ?itemLabel ?directorLabel ?pubdate ?article WHERE {
      ?item wdt:P166 wd:Q102427; wdt:P57 ?director .
      OPTIONAL { ?item wdt:P577 ?pubdate. }
      OPTIONAL { ?article schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>. }
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }"""
    agg = {}
    for r in sparql(q):
        qid = val(r, "item"); name = clean(val(r, "itemLabel"))
        if not qid or not name: continue
        d = agg.setdefault(qid, {"film": name, "article": val(r, "article")})
        if not d.get("director"): d["director"] = clean(val(r, "directorLabel"))
        y = year_of(val(r, "pubdate"))
        if y and d.get("year") is None: d["year"] = y
    rows = list(agg.values())
    print(f"[wd] {len(rows)} best-picture films")
    return rows

BOOK_PRIZES = {"Q16876": "Pulitzer Prize for Fiction", "Q160082": "Booker Prize", "Q1093536": "Hugo Award for Best Novel"}

def dataset_books():
    print("[wd] award-books dataset…")
    rows, agg = [], {}
    for qid_prize in BOOK_PRIZES:
        q = f"""SELECT ?item ?itemLabel ?authorLabel ?pubdate ?article WHERE {{
          ?item wdt:P166 wd:{qid_prize}; wdt:P50 ?author .
          OPTIONAL {{ ?item wdt:P577 ?pubdate. }}
          OPTIONAL {{ ?article schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>. }}
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }} LIMIT 200"""
        for r in sparql(q):
            qid = val(r, "item"); name = clean(val(r, "itemLabel"))
            if not qid or not name: continue
            d = agg.setdefault(qid, {"book": name, "article": val(r, "article")})
            if not d.get("author"): d["author"] = clean(val(r, "authorLabel"))
            y = year_of(val(r, "pubdate"))
            if y and d.get("year") is None: d["year"] = y
        time.sleep(20)
    print(f"[wd] {len(agg)} award books")
    return list(agg.values())

OCCUPATIONS = {"Q169470": "physicist", "Q36834": "composer", "Q1028181": "painter"}

def dataset_people():
    print("[wd] notable-people dataset…")
    rows = []
    for occ_qid, occ_name in OCCUPATIONS.items():
        q = f"""SELECT ?item ?itemLabel ?dob ?article WHERE {{
          ?item wdt:P106 wd:{occ_qid}; wdt:P31 wd:Q5; wdt:P569 ?dob; wikibase:sitelinks ?sl .
          FILTER(?sl >= 50)
          OPTIONAL {{ ?article schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>. }}
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }} LIMIT 250"""
        seen = set()
        for r in sparql(q):
            name = clean(val(r, "itemLabel"))
            y = year_of(val(r, "dob"))
            if not name or name in seen: continue
            seen.add(name)
            rows.append({"person": name, "occupation": occ_name, "born": y, "article": val(r, "article")})
        time.sleep(20)
    print(f"[wd] {len(rows)} notable people")
    return rows

# ---- Stem banks ----

S = {
    "capital": ["What is the capital of {s}?", "{s}'s capital city is…?", "Name the capital of {s}.", "Which city is the capital of {s}?"],
    "capitalRev": ["Of which country is {v} the capital?", "{v} is the capital of which country?", "Which country has {v} as its capital?"],
    "currency": ["What is the official currency of {s}?", "Which currency does {s} use?", "{s}'s money is the…?"],
    "continent": ["On which continent is {s}?", "{s} lies on which continent?", "Which continent is {s} part of?"],
    "supPop": ["Which of these countries is the most populous?", "Which country has the largest population?", "Which of these has the most people?"],
    "supArea": ["Which of these countries is the largest by area?", "Which country covers the most land?", "Which of these is biggest by area?"],
    "numPop": ["About how many people live in {s}?", "{s}'s population is closest to…?", "Roughly how populous is {s}?"],
    "chronCountry": ["Which of these countries came into existence first?", "Which of these is the oldest as a state?", "Which was established earliest?"],
    "elemSymbol": ["What is the chemical symbol for {s}?", "Which symbol represents {s}?", "{s} is denoted by which symbol?"],
    "elemNumber": ["What is the atomic number of {s}?", "{s} sits at which atomic number?", "Which atomic number belongs to {s}?"],
    "elemChron": ["Which of these elements was discovered first?", "Which element has been known longest?", "Which was isolated earliest?"],
    "director": ["Who directed the Best Picture winner {s}?", "Which director made {s}?", "{s} was directed by whom?"],
    "filmChron": ["Which of these Best Picture winners was released first?", "Which of these films is the oldest?", "Which came out earliest?"],
    "author": ["Who wrote the award-winning book {s}?", "Which author wrote {s}?", "{s} was written by whom?"],
    "bookChron": ["Which of these award-winning books was published first?", "Which of these books is the oldest?", "Which was published earliest?"],
    "occChron": ["Which of these people was born first?", "Which of these was born earliest?", "Who is the oldest of these?"],
    "occClass": ["Which of these is a {k}?", "Which of these people was a {k}?", "Which one is a {k}?"],
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="../../TidbitsTrivia/Resources/corpus.sqlite")
    ap.add_argument("--only", default="")
    ap.add_argument("--fetch", action="store_true", help="allow live WDQS fetch for un-cached datasets")
    args = ap.parse_args()
    global ALLOW_LIVE
    ALLOW_LIVE = args.fetch
    only = set(filter(None, args.only.split(",")))
    rows = []

    def fetch(name, fn):
        before = os.path.exists(os.path.join(CACHE_DIR, name + ".json"))
        data = cached(name, fn)
        if not before:
            time.sleep(20)   # only pace between LIVE fetches, not cache reads
        return data
    countries = fetch("countries", dataset_countries)
    elements = fetch("elements", dataset_elements)
    films = fetch("bestpic", dataset_bestpic)
    books = fetch("books", dataset_books)
    people = fetch("people", dataset_people)

    GEN = {
        "capital": lambda: gen_forward(countries, "country", "capital", "geography", S["capital"], "capital", lambda r: f"{r['capital']} is the capital of {r['country']}."),
        "capitalRev": lambda: gen_reverse(countries, "country", "capital", "geography", S["capitalRev"], "capitalRev", lambda r: f"{r['capital']} is the capital of {r['country']}."),
        "currency": lambda: gen_forward(countries, "country", "currency", "geography", S["currency"], "currency", lambda r: f"{r['country']} uses the {r['currency']}."),
        "continent": lambda: gen_forward(countries, "country", "continent", "geography", S["continent"], "continent", lambda r: f"{r['country']} is on {r['continent']}."),
        "supPop": lambda: gen_superlative(countries, "country", "pop", "geography", S["supPop"], "supPop", "max", "population", 120),
        "supArea": lambda: gen_superlative(countries, "country", "area", "geography", S["supArea"], "supArea", "max", "area", 120),
        "numPop": lambda: gen_numeric(countries, "country", "pop", "geography", S["numPop"], "numPop", "people", lambda r: f"{r['country']} has about {fmt_num(r['pop'])} people."),
        "chronCountry": lambda: gen_chronology(countries, "country", "inception", "geography", S["chronCountry"], "chronCountry", "established", 100),
        "elemSymbol": lambda: gen_forward(elements, "element", "symbol", "science", S["elemSymbol"], "elemSymbol", lambda r: f"The symbol for {r['element']} is {r['symbol']}."),
        "elemNumber": lambda: gen_forward([dict(r, numberStr=str(r["number"])) for r in elements], "element", "numberStr", "science", S["elemNumber"], "elemNumber", lambda r: f"{r['element']} has atomic number {r['number']}."),
        "elemChron": lambda: gen_chronology(elements, "element", "discovery", "science", S["elemChron"], "elemChron", "discovered", 80),
        "director": lambda: gen_forward(films, "film", "director", "screen", S["director"], "director", lambda r: f"{r['film']} was directed by {r['director']}."),
        "filmChron": lambda: gen_chronology(films, "film", "year", "screen", S["filmChron"], "filmChron", "released", 80),
        "author": lambda: gen_forward(books, "book", "author", "arts", S["author"], "author", lambda r: f"{r['book']} was written by {r['author']}."),
        "bookChron": lambda: gen_chronology(books, "book", "year", "arts", S["bookChron"], "bookChron", "published", 60),
        "occChron": lambda: gen_chronology(people, "person", "born", "history", S["occChron"], "occChron", "born", 120),
        "occClass": lambda: sum((gen_classification(people, "person", "occupation", occ, "history" if occ in ("physicist","astronomer") else "arts", S["occClass"], "occClass", people) for occ in set(OCCUPATIONS.values())), []),
    }

    for key, fn in GEN.items():
        if only and key not in only: continue
        qs = fn()
        print(f"  wd:{key}: {len(qs)}")
        rows += qs

    # de-dup by qid
    seen, deduped = set(), []
    for r in rows:
        if r[0] in seen: continue
        seen.add(r[0]); deduped.append(r)

    conn = sqlite3.connect(args.db)
    conn.execute("""CREATE TABLE IF NOT EXISTS questions(
        id TEXT PRIMARY KEY, prompt TEXT, option0 TEXT, option1 TEXT, option2 TEXT, option3 TEXT,
        correct_index INTEGER, category_id TEXT, difficulty INTEGER, explanation TEXT,
        source_title TEXT, source_url TEXT, template_id TEXT)""")
    # Replace ONLY the wd:* types this run actually produced — so types from
    # un-cached/skipped datasets (e.g. director/author from an earlier run)
    # are preserved rather than wiped.
    produced = {r[12] for r in deduped}
    for tid in produced:
        conn.execute("DELETE FROM questions WHERE template_id = ?", (tid,))
    conn.executemany("INSERT OR IGNORE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", deduped)
    conn.commit()
    n = conn.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    by = conn.execute("SELECT template_id, COUNT(*) FROM questions WHERE template_id LIKE 'wd:%' GROUP BY template_id ORDER BY 2 DESC").fetchall()
    conn.close()
    print(f"Inserted {len(deduped)} Wikidata questions ({len(by)} types). Corpus now {n}.")
    for tid, c in by: print(f"  {tid}: {c}")

if __name__ == "__main__":
    main()
