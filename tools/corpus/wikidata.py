#!/usr/bin/env python3
"""
Tidbits — Wikidata SPARQL question generator (the quality moat).

Derives answers STRUCTURALLY from Wikidata so a question is verifiable by
construction (QUESTION-QUALITY gate 1, single-answer) and distractors are
typed siblings drawn from the same query — for functional properties
(capital-of, currency-of, atomic-number-of) a different entity's value is
DEFINITIONALLY wrong, so gate 2 (distractor-correctness) holds by design.
Bounded, recognizable domains satisfy the popularity gate (5) for free.

Appends verified questions into the existing corpus.sqlite (template_id
"wd:*") alongside the summary-based ones. Stdlib only.

Usage: python3 wikidata.py [--db PATH] [--limit N]
"""
import argparse, json, re, sqlite3, sys, time, urllib.parse, urllib.request, random

WDQS = "https://query.wikidata.org/sparql"
UA = "TidbitsTrivia/1.0 (learning trivia app; contact ben@learningischange.com)"
QID_RE = re.compile(r"^Q\d+$")

def sparql(query, retries=6):
    for attempt in range(retries):
        try:
            url = WDQS + "?" + urllib.parse.urlencode({"query": query})
            req = urllib.request.Request(url, headers={
                "User-Agent": UA, "Accept": "application/sparql-results+json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)["results"]["bindings"]
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                wait = int(e.headers.get("Retry-After") or 0) or (15 * (attempt + 1))
                print(f"  … 429, waiting {wait}s", file=sys.stderr)
                time.sleep(wait + 2); continue
            print(f"  ! HTTP {e.code}", file=sys.stderr); return []
        except Exception as e:
            if attempt == retries - 1:
                print(f"  ! {e}", file=sys.stderr); return []
            time.sleep(8)
    return []

def val(row, key):
    return row.get(key, {}).get("value")

# Each template: a bounded SPARQL query + how to phrase the question.
# answer_entity=True → answer is a Wikidata item (use ?answerLabel); else a
# literal (string/number) in ?answer. numeric=True → numeric-band distractors.
TEMPLATES = [
    {
        "key": "capital", "category": "geography", "answer_entity": True,
        "query": """SELECT ?subjectLabel ?answerLabel ?article WHERE {
          ?subject wdt:P31 wd:Q6256; wdt:P36 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 400""",
        "prompt": lambda s: f"What is the capital of {s}?",
        "explain": lambda s, a: f"{a} is the capital of {s}.",
    },
    {
        "key": "currency", "category": "geography", "answer_entity": True,
        "query": """SELECT ?subjectLabel ?answerLabel ?article WHERE {
          ?subject wdt:P31 wd:Q6256; wdt:P38 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 400""",
        "prompt": lambda s: f"What is the official currency of {s}?",
        "explain": lambda s, a: f"{s} uses the {a}.",
    },
    {
        "key": "continent", "category": "geography", "answer_entity": True,
        "query": """SELECT ?subjectLabel ?answerLabel ?article WHERE {
          ?subject wdt:P31 wd:Q6256; wdt:P30 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 400""",
        "prompt": lambda s: f"On which continent is {s}?",
        "explain": lambda s, a: f"{s} is on the continent of {a}.",
    },
    {
        "key": "unescoCountry", "category": "geography", "answer_entity": True,
        "query": """SELECT ?subjectLabel ?answerLabel ?article WHERE {
          ?subject wdt:P31 wd:Q9259; wdt:P17 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 700""",
        "prompt": lambda s: f"In which country is the World Heritage Site {s}?",
        "explain": lambda s, a: f"{s} is a UNESCO World Heritage Site in {a}.",
    },
    {
        "key": "elementSymbol", "category": "science", "answer_entity": False,
        "query": """SELECT ?subjectLabel ?answer ?article WHERE {
          ?subject wdt:P31 wd:Q11344; wdt:P246 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 200""",
        "prompt": lambda s: f"What is the chemical symbol for {s}?",
        "explain": lambda s, a: f"The chemical symbol for {s} is {a}.",
    },
    {
        "key": "elementNumber", "category": "science", "answer_entity": False, "numeric": True,
        "query": """SELECT ?subjectLabel ?answer ?article WHERE {
          ?subject wdt:P31 wd:Q11344; wdt:P1086 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 200""",
        "prompt": lambda s: f"What is the atomic number of {s}?",
        "explain": lambda s, a: f"{s} has atomic number {a}.",
    },
    {
        "key": "bestPicDirector", "category": "screen", "answer_entity": True,
        "query": """SELECT ?subjectLabel ?answerLabel ?article WHERE {
          ?subject wdt:P166 wd:Q102427; wdt:P57 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 300""",
        "prompt": lambda s: f"Who directed the Best Picture winner {s}?",
        "explain": lambda s, a: f"{s} was directed by {a}.",
    },
]

# Award-winning books → author (several prizes, merged).
BOOK_PRIZES = {"Q16876": "Pulitzer Prize for Fiction", "Q160082": "Booker Prize", "Q1093536": "Hugo Award for Best Novel"}

def book_template():
    rows = []
    for qid in BOOK_PRIZES:
        q = f"""SELECT ?subjectLabel ?answerLabel ?article WHERE {{
          ?subject wdt:P166 wd:{qid}; wdt:P50 ?answer.
          ?article schema:about ?subject; schema:isPartOf <https://en.wikipedia.org/>.
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }} LIMIT 200"""
        rows += sparql(q); time.sleep(1)
    return rows

def clean_label(s):
    return s if s and not QID_RE.match(s) else None

def build_template(t):
    print(f"[wd:{t['key']}] querying…")
    rows = book_template() if t["key"] == "bookAuthor" else sparql(t["query"])
    pairs = []
    for r in rows:
        subj = clean_label(val(r, "subjectLabel"))
        ans = val(r, "answerLabel") if t.get("answer_entity") else val(r, "answer")
        if t.get("answer_entity"):
            ans = clean_label(ans)
        art = val(r, "article")
        if subj and ans:
            pairs.append((subj, str(ans), art))
    # Dedupe by subject (one question per subject); keep first.
    seen, uniq = set(), []
    for p in pairs:
        if p[0] in seen: continue
        seen.add(p[0]); uniq.append(p)
    answer_pool = list({p[1] for p in uniq})
    print(f"[wd:{t['key']}] {len(uniq)} subjects, {len(answer_pool)} distinct answers")

    out = []
    for subj, ans, art in uniq:
        rng = random.Random(hash((t["key"], subj)) & 0xFFFFFFFF)
        if t.get("numeric"):
            try: n = int(float(ans))
            except ValueError: continue
            cand = set()
            while len(cand) < 3:
                d = n + rng.choice([-3, -2, -1, 1, 2, 3, 4, -4, 5, -5]) * rng.randint(1, 2)
                if d > 0 and d != n: cand.add(d)
            distract = [str(d) for d in cand]
        else:
            others = [a for a in answer_pool if a.lower() != ans.lower()]
            if len(others) < 3: continue
            distract = rng.sample(others, 3)
        options = [ans] + distract
        rng.shuffle(options)
        ci = options.index(ans)
        out.append((
            f"wd:{t['key']}:{subj}".replace(" ", "_"),
            t["prompt"](subj), options[0], options[1], options[2], options[3],
            ci, t["category"], 3, t["explain"](subj, ans), subj, art or "", f"wd:{t['key']}",
        ))
    print(f"[wd:{t['key']}] {len(out)} questions")
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="../../TidbitsTrivia/Resources/corpus.sqlite")
    ap.add_argument("--only", default="", help="comma-separated template keys to run")
    ap.add_argument("--gap", type=float, default=4.0, help="seconds between templates")
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))

    book_t = {"key": "bookAuthor", "category": "arts", "answer_entity": True,
              "prompt": lambda s: f"Who wrote the award-winning book {s}?",
              "explain": lambda s, a: f"{s} was written by {a}."}
    rows = []
    for t in TEMPLATES + [book_t]:
        if only and t["key"] not in only:
            continue
        rows += build_template(t); time.sleep(args.gap)

    conn = sqlite3.connect(args.db)
    before = conn.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    conn.executemany(
        "INSERT OR IGNORE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
    conn.commit()
    after = conn.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    by = conn.execute("SELECT template_id, COUNT(*) FROM questions WHERE template_id LIKE 'wd:%' GROUP BY template_id").fetchall()
    conn.close()
    print(f"Inserted {after - before} Wikidata questions (corpus now {after}).")
    for tid, n in by: print(f"  {tid}: {n}")

if __name__ == "__main__":
    main()
