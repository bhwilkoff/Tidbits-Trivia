#!/usr/bin/env python3
"""
Tidbits Trivia — offline corpus generator.

Pulls popular Wikipedia articles per category, runs the SAME two
template shapes the Swift TemplateEngine uses (descriptionOf /
subjectFrom) with the SAME quality gates, and writes a read-only
`corpus.sqlite` that ships in the app bundle.

Stdlib only (urllib) — no third-party deps. Idempotent: rebuilds the DB
from scratch each run.

Usage:
    python3 generate_corpus.py [--out PATH] [--per-category N] [--target N]
"""
import argparse, json, re, sqlite3, sys, time, urllib.parse, urllib.request, random, threading

API = "https://en.wikipedia.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; contact ben@learningischange.com)"

# Global polite rate limiter — Wikipedia 429s aggressive concurrent use.
_MIN_INTERVAL = 0.18
_lock = threading.Lock()
_last = [0.0]

def _throttle():
    with _lock:
        wait = _MIN_INTERVAL - (time.monotonic() - _last[0])
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.monotonic()

# Per-category seed search queries → recognizable, low-vandalism subjects.
CATEGORY_SEEDS = {
    "history":   ["ancient history", "world war", "empire", "revolution", "monarch",
                  "ancient civilization", "historical battle", "explorer", "dynasty", "treaty"],
    "science":   ["physics", "chemistry", "biology", "astronomy", "scientist",
                  "chemical element", "human anatomy", "mathematics", "invention", "species"],
    "geography": ["capital city", "country", "river", "mountain", "ocean",
                  "national park", "volcano", "desert", "island", "world heritage site"],
    "arts":      ["novel", "painting", "author", "poet", "philosophy",
                  "art movement", "sculpture", "playwright", "classic literature", "mythology"],
    "screen":    ["film director", "academy award film", "actor", "television series", "science fiction film",
                  "animated film", "film genre", "movie franchise", "screenwriter", "classic film"],
    "music":     ["composer", "rock band", "musical instrument", "jazz musician", "opera",
                  "music genre", "singer", "symphony", "album", "songwriter"],
    "sports":    ["olympic sport", "footballer", "basketball player", "tennis", "world cup",
                  "athlete", "baseball", "boxing", "cricket", "motorsport"],
}

def get(params, retries=6):
    params = {**params, "format": "json", "maxlag": "5"}
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < retries - 1:
                backoff = min(60, 4 * (2 ** attempt))
                print(f"  … {e.code}, backing off {backoff}s", file=sys.stderr)
                time.sleep(backoff)
                continue
            print(f"  ! HTTP {e.code}", file=sys.stderr)
            return {}
        except Exception as e:
            if attempt == retries - 1:
                print(f"  ! request failed: {e}", file=sys.stderr)
                return {}
            time.sleep(2 * (attempt + 1))
    return {}

def search_titles(query, limit=200):
    titles, offset = [], 0
    while len(titles) < limit:
        data = get({"action": "query", "list": "search", "srsearch": query,
                    "srlimit": min(50, limit - len(titles)), "sroffset": offset,
                    "srnamespace": "0"})
        hits = data.get("query", {}).get("search", [])
        if not hits:
            break
        titles += [h["title"] for h in hits]
        offset += len(hits)
        if "continue" not in data:
            break
    return titles

def fetch_summaries(titles):
    """Batched extract+description+url for up to 50 titles per call."""
    out = {}
    for i in range(0, len(titles), 50):
        batch = titles[i:i+50]
        data = get({"action": "query", "prop": "extracts|description|info",
                    "exintro": "1", "explaintext": "1", "inprop": "url",
                    "redirects": "1", "titles": "|".join(batch)})
        pages = data.get("query", {}).get("pages", {})
        for p in pages.values():
            title = p.get("title")
            if not title:
                continue
            out[title] = {
                "title": title,
                "description": p.get("description"),
                "extract": p.get("extract"),
                "url": p.get("fullurl"),
                "type": p.get("description") or "",
            }
    return out

# ---- Quality gates + templates (mirror of Swift TemplateEngine) ----

def is_usable(s):
    d, e, t = s.get("description"), s.get("extract"), s.get("title", "")
    if not d or not (6 <= len(d) <= 90):
        return False
    if not e or len(e) < 40:
        return False
    lt = t.lower()
    if lt.startswith("list of") or "(disambiguation)" in lt:
        return False
    if "may refer to" in (e or "").lower():
        return False
    return True

def redact(text, title):
    bare = re.sub(r"\s*\([^)]*\)", "", title)
    out = text
    for needle in {title, bare}:
        if needle:
            out = re.sub(re.escape(needle), "—————", out, flags=re.IGNORECASE)
    return out

def display_title(t):
    return re.sub(r"\s*\([^)]*\)", "", t)

def first_sentence(text):
    t = text.strip()
    m = re.search(r"\.\s", t)
    return (t[:m.start()] + ".") if m else t

def cap(c):
    return c[:1].upper() + c[1:] if c else c

def difficulty(s):
    n = len(s.get("extract") or "")
    return 2 if n >= 600 else (3 if n >= 300 else 4)

def pick_distractors(subject, pool, value_fn, exclude, rng, k=3):
    subj_words = set((subject.get("description") or "").lower().split())
    ranked = []
    seen = set()
    cands = []
    for c in pool:
        if c["title"] == subject["title"]:
            continue
        v = (value_fn(c) or "").strip()
        if not v or v.lower() == exclude.lower() or v.lower() in seen:
            continue
        words = set((c.get("description") or "").lower().split())
        overlap = len(subj_words & words)
        cands.append((overlap, v))
    cands.sort(key=lambda x: x[0], reverse=True)
    for _, v in cands:
        if v.lower() in seen:
            continue
        seen.add(v.lower())
        ranked.append(v)
    slice_ = ranked[:8]
    rng.shuffle(slice_)
    return slice_[:k]

def make_question(subject, pool, category, idx, rng, use_desc=None):
    if use_desc is None:
        use_desc = (idx % 2 == 0)
    if use_desc:
        correct = subject.get("description")
        if not correct:
            return None
        ds = pick_distractors(subject, pool, lambda c: c.get("description"), correct, rng)
        if len(ds) != 3:
            return None
        prompt = f"How is {display_title(subject['title'])} best described?"
        options = [cap(correct)] + [cap(d) for d in ds]
        template = "descriptionOf"
        answer = cap(correct)
    else:
        clue = redact(first_sentence(subject.get("extract") or subject.get("description")), subject["title"])
        if len(clue) < 25:
            return None
        ds = pick_distractors(subject, pool, lambda c: c.get("title"), subject["title"], rng)
        if len(ds) != 3:
            return None
        prompt = f"Which subject is this? “{clue}”"
        options = [display_title(subject["title"])] + [display_title(d) for d in ds]
        template = "subjectFrom"
        answer = display_title(subject["title"])

    rng.shuffle(options)
    correct_index = options.index(answer)
    explanation = first_sentence(subject.get("extract") or "") or (subject.get("description") or "")
    qid = f"corpus:{template}:{subject['title']}".replace(" ", "_")
    return (qid, prompt, options[0], options[1], options[2], options[3],
            correct_index, category, difficulty(subject), explanation,
            subject["title"], subject.get("url") or "", template)

def build_category(category, seeds, per_category):
    print(f"[{category}] searching…")
    titles = []
    for q in seeds:
        titles += search_titles(q, limit=max(60, per_category // len(seeds) + 40))
    titles = list(dict.fromkeys(titles))  # dedupe, keep order
    print(f"[{category}] {len(titles)} candidate titles → fetching summaries")
    summaries = fetch_summaries(titles)
    usable = [s for s in summaries.values() if is_usable(s)]
    print(f"[{category}] {len(usable)} usable subjects")
    rng = random.Random(hash(category) & 0xFFFFFFFF)
    rng.shuffle(usable)
    rows, ids = [], set()
    # Emit BOTH template variants per subject (different ids) to roughly
    # double yield toward the 10k target without lowering quality gates.
    for i, subj in enumerate(usable):
        for use_desc in (True, False):
            q = make_question(subj, usable, category, i, rng, use_desc=use_desc)
            if q and q[0] not in ids:
                ids.add(q[0])
                rows.append(q)
    print(f"[{category}] {len(rows)} questions")
    return rows

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="../../TidbitsTrivia/Resources/corpus.sqlite")
    ap.add_argument("--per-category", type=int, default=1600)
    ap.add_argument("--target", type=int, default=10000)
    args = ap.parse_args()

    all_rows = []
    for c, s in CATEGORY_SEEDS.items():
        all_rows += build_category(c, s, args.per_category)

    # De-dup globally by source title to avoid the same subject twice.
    seen_titles, deduped = set(), []
    for r in all_rows:
        key = (r[12], r[10])  # template + source title
        if key in seen_titles:
            continue
        seen_titles.add(key)
        deduped.append(r)

    print(f"TOTAL: {len(deduped)} questions")

    conn = sqlite3.connect(args.out)
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS questions")
    cur.execute("""CREATE TABLE questions(
        id TEXT PRIMARY KEY, prompt TEXT, option0 TEXT, option1 TEXT,
        option2 TEXT, option3 TEXT, correct_index INTEGER, category_id TEXT,
        difficulty INTEGER, explanation TEXT, source_title TEXT,
        source_url TEXT, template_id TEXT)""")
    cur.executemany(
        "INSERT OR IGNORE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", deduped)
    cur.execute("CREATE INDEX idx_category ON questions(category_id)")
    conn.commit()
    n = cur.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    conn.close()
    print(f"Wrote {n} questions to {args.out}")

if __name__ == "__main__":
    main()
