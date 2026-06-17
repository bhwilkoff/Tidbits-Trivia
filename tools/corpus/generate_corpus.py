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

_META_TITLE = re.compile(r"^(lists?|glossary|index|outline|comparison|timeline|catalogues?|"
                         r"history of|terminology of)\s+of\b|\b(abbreviations|pictograms|terminology)$|"
                         r"^(forms|types|kinds|positions) of\b|^glossary\b", re.I)
_META_DESC = re.compile(r"wikimedia (list|disambiguation)|list article|may refer to|disambiguation|"
                        r"\bglossary\b|topics referred to|index of|set index|lists of", re.I)

def is_usable(s):
    d, e, t = s.get("description"), s.get("extract"), s.get("title", "")
    if not d or not (6 <= len(d) <= 90):
        return False
    if not e or len(e) < 40:
        return False
    lt = t.lower()
    # Reject list / glossary / index / disambiguation "subjects" — they make
    # nonsense quiz items (e.g. "Glossary of terms in the sport of athletics").
    if _META_TITLE.search(t) or "(disambiguation)" in lt:
        return False
    if _META_DESC.search(d) or "may refer to" in (e or "").lower():
        return False
    if "\\displaystyle" in e or "{\\" in e or "\\(" in e:   # math / LaTeX article
        return False
    return True

# Non-Latin scripts + math symbols that make a clue unreadable. Accented Latin
# (é, ñ, ü) is intentionally NOT here — those are fine in names.
_FOREIGN = re.compile(r"[Ͱ-ϿЀ-ӿ԰-׿؀-ۿ"
                      r"぀-ヿ㐀-鿿가-힯∀-⋿⟨-⟯〈〉]")

# Common descriptor words that legitimately appear in both a subject name and
# its clue — NOT a tell on their own. Only NON-common answer words leaking into
# the prompt count as a leak (see `leaks`).
COMMON_WORDS = set("""empire battle war wars kingdom dynasty republic treaty river
    mountain mountains lake island islands city town county state states united nation national
    american english british french german italian spanish russian chinese japanese korean indian
    european african asian north south east west northern southern eastern western great greater new
    saint university college school company group band series film movie novel book award club team
    teams league party system century world people region province district area force army navy air
    language family order house song album season game games sport sports festival prize war republic
    federal royal national international association federation union organization museum park station
    bridge building tower palace castle church cathedral temple championship cup league first second""".split())

_FUNCTION_WORDS = set("the of and a an in on at to for by with from as or de von van al".split())

def _name_tokens(s):
    return {w.lower() for w in re.findall(r"[A-Za-z]{4,}", s)}

def leaks(answer, prompt):
    """True if a DISTINCTIVE answer word survives in the prompt — the
    answer-in-question tell. Substring match catches plurals/variants
    (Chola→Cholas)."""
    p = prompt.lower()
    for tok in _name_tokens(answer) - COMMON_WORDS:
        if tok in p:
            return True
    return False

def redact(text, title):
    bare = re.sub(r"\s*\([^)]*\)", "", title).strip()
    out = text
    # 1. Whole-title phrase(s).
    for needle in {title, bare}:
        if needle:
            out = re.sub(re.escape(needle), "—————", out, flags=re.IGNORECASE)
    # 2. The leading proper-noun run (Wikipedia first sentences name the subject
    #    first) — catches full-name variants like "Curtis Julian Jones".
    #    Require ≥2 capitalized words (a single-word subject is already caught
    #    by the title pass) so we don't blank a leading "In"/"During" on concept
    #    articles ("In mathematics, …").
    out = re.sub(r"^(The |A |An )?((?:[A-Z][\w’'.\-]*)(?:[ \-]+(?:of |the |and |de |von |van |al-)?[A-Z][\w’'.\-]*)+)",
                 lambda m: (m.group(1) or "") + "—————", out)
    # 3. Every CONTENT title word wherever it appears (aliases, plurals, later
    #    mentions). Skip function words so the clue stays grammatical.
    for w in re.findall(r"[A-Za-z][A-Za-z’'\-]{2,}", bare):
        if w.lower() in _FUNCTION_WORDS:
            continue
        out = re.sub(rf"\b{re.escape(w)}(?:’s|'s|s|es)?\b", "—————", out, flags=re.IGNORECASE)
    # 4. Collapse adjacent blanks (with connectors) into a single token.
    out = re.sub(r"—————(?:[\s,’'.\–\-]+(?:of|the|and|de|von|van)?\s*—————)+", "—————", out, flags=re.IGNORECASE)
    out = re.sub(r"\s{2,}", " ", out).strip()
    return out

def display_title(t):
    return re.sub(r"\s*\([^)]*\)", "", t)

_ABBREV = {"lit", "e.g", "i.e", "approx", "no", "vs", "etc", "st", "mt", "mr", "mrs",
           "ms", "dr", "fl", "ca", "jr", "sr", "col", "gen", "gov", "sen", "rep",
           "prof", "rev", "inc", "ltd", "co", "u.s", "u.k"}

def first_sentence(text):
    """First sentence, but NOT splitting inside parentheses/brackets or after a
    known abbreviation/initial — otherwise 'lit.' or '(大日本帝国; lit. …)' or a
    middle initial truncates the clue mid-phrase and leaks/garbles it."""
    t = text.strip()
    depth, i, L = 0, 0, len(t)
    while i < L:
        ch = t[i]
        if ch in "([":
            depth += 1
        elif ch in ")]" and depth > 0:
            depth -= 1
        elif ch == "." and depth == 0 and i + 1 < L and t[i + 1] == " ":
            nxt2 = t[i + 2] if i + 2 < L else ""
            if nxt2 == "" or nxt2.isupper() or nxt2 in "“”\"'‘’":
                j = i - 1
                while j >= 0 and (t[j].isalnum() or t[j] in ".'’-"):
                    j -= 1
                tok = t[j + 1:i]
                letters = re.sub(r"[^A-Za-z]", "", tok)
                if not (letters and (len(letters) <= 1 or tok.lower().rstrip(".") in _ABBREV)):
                    return t[:i + 1]
        i += 1
    # Depth-aware scan found no sentence end — usually an UNBALANCED paren in
    # the source. Fall back to a plain split so we don't return the whole
    # multi-paragraph article.
    m = re.search(r"\.\s", t)
    return (t[:m.start() + 1]) if m else t

_LANG_RE = re.compile(r"\b(romaniz|pronounc|IPA|listen|lit\.|Russian|Greek|Latin|Arabic|"
                      r"Chinese|Japanese|Hebrew|Hindi|Persian|German|French|Spanish|Italian|"
                      r"Korean|Portuguese|Turkish|Polish|Dutch|Sanskrit)\b", re.I)

def clean_clue(text):
    """Strip parenthetical clutter from a displayed clue: foreign scripts,
    pronunciations/romanizations, empty parens, and short ALL-CAPS acronyms
    (which leak the answer, e.g. '(CSTO)'). Keeps ordinary parentheticals."""
    def repl(m):
        inner = m.group(1).strip()
        if not inner:
            return ""
        if re.search(r"[^\x00-\x7F]", inner):       # non-ASCII (foreign script / IPA)
            return ""
        if _LANG_RE.search(inner):                  # translation / pronunciation note
            return ""
        parts = inner.split(";")[0].split()
        tok = re.sub(r"[^A-Za-z]", "", parts[0]) if parts else ""
        if 2 <= len(tok) <= 6 and tok.isupper():
            return ""                                # leading acronym, e.g. (CSTO; ...)
        return m.group(0)
    out, prev = text, None
    while out != prev:                               # fixpoint: strip nested groups inside-out
        prev = out
        out = re.sub(r"\s*\(([^()]*)\)", repl, out)   # ( … )
        out = re.sub(r"\s*\[([^\[\]]*)\]", repl, out)  # [ … ]  (IPA, CJK glosses)
    out = re.sub(r"\s{2,}", " ", out).replace(" ,", ",").replace(" .", ".").strip()
    return out

def cap(c):
    return c[:1].upper() + c[1:] if c else c

def difficulty(s):
    n = len(s.get("extract") or "")
    return 2 if n >= 600 else (3 if n >= 300 else 4)

# --- Distractor pickers (typed siblings; length-normalized for prose) ---

def _ranked_siblings(subject, pool, value_fn, exclude, length_match=None):
    """Siblings ranked by description word-overlap (same-domain → plausible).
    If length_match is set, prefer values of similar length (kills the
    'longest option is the answer' tell)."""
    subj_words = set((subject.get("description") or "").lower().split())
    cands, seen = [], set()
    for c in pool:
        if c["title"] == subject["title"]:
            continue
        v = (value_fn(c) or "").strip()
        if not v or v.lower() == (exclude or "").lower() or v.lower() in seen:
            continue
        seen.add(v.lower())
        words = set((c.get("description") or "").lower().split())
        overlap = len(subj_words & words)
        lenpen = -abs(len(v) - length_match) if length_match is not None else 0
        cands.append((overlap, lenpen, v))
    cands.sort(key=lambda x: (x[0], x[1]), reverse=True)
    return [v for _, _, v in cands]

def title_distractors(subject, pool, rng, k=3):
    ranked = _ranked_siblings(subject, pool, lambda c: display_title(c["title"]), display_title(subject["title"]))
    slice_ = ranked[:8]; rng.shuffle(slice_); return slice_[:k]

def desc_distractors(subject, pool, rng, k=3):
    correct = subject.get("description") or ""
    ranked = _ranked_siblings(subject, pool, lambda c: c.get("description"), correct, length_match=len(correct))
    slice_ = ranked[:8]; rng.shuffle(slice_); return slice_[:k]

# --- Rotating stems (≤~1/N share each; categorize kept a minority) ---

STEMS = {
    "identify": [
        'Which subject does this describe? “{clue}”',
        'Name it — “{clue}”',
        'What is being described here? “{clue}”',
        'Identify the subject: “{clue}”',
        'These clues point to one thing. What is it? “{clue}”',
        'Guess the article: “{clue}”',
    ],
    "jeopardy": [
        '{clue} — what is it?',
        '{clue} Name the subject.',
        '{clue} What are we describing?',
    ],
    "cloze": [
        'Fill in the blank: “{clue}”',
        'Complete the sentence: “{clue}”',
        'Which name completes this? “{clue}”',
    ],
    "categorize": [
        'What kind of thing is {title}?',
        'What is {title} best known as?',
        'In a few words, what is {title}?',
        'Which description fits {title}?',
    ],
    "oneliner": [
        'Which one is “{clue}”?',
        '“{clue}” — which subject is that?',
        'Which subject matches: “{clue}”?',
    ],
}
# categorize (the old "best described") is 1 of 10 slots → ~10% share.
# Spread the shapes so no single "name the subject from a clue" feel dominates.
# identify+jeopardy+oneliner all read as "describe → name it"; cloze + categorize
# feel distinct, so they get more weight here for variety.
SHAPE_ROTATION = ["identify", "cloze", "jeopardy", "categorize", "oneliner",
                  "cloze", "identify", "categorize", "jeopardy", "cloze"]

def build_identify(subject, pool, stem, rng):
    clue = redact(clean_clue(first_sentence(subject.get("extract") or subject.get("description"))), subject["title"])
    if len(clue) < 25:
        return None
    ds = title_distractors(subject, pool, rng)
    if len(ds) != 3:
        return None
    ans = display_title(subject["title"])
    return stem.format(clue=clue), [ans] + ds, ans

def build_jeopardy(subject, pool, stem, rng):
    s = clean_clue(first_sentence(subject.get("extract") or ""))
    if len(s) < 25:
        return None
    bare = display_title(subject["title"])
    if s.lower().startswith(subject["title"].lower()):
        clue = "This" + s[len(subject["title"]):]
    elif s.lower().startswith(bare.lower()):
        clue = "This" + s[len(bare):]
    else:
        clue = redact(s, subject["title"])
    clue = cap(clue.strip())
    ds = title_distractors(subject, pool, rng)
    if len(ds) != 3:
        return None
    ans = bare
    return stem.format(clue=clue), [ans] + ds, ans

def build_cloze(subject, pool, stem, rng):
    s = clean_clue(first_sentence(subject.get("extract") or ""))
    bare = display_title(subject["title"])
    clozed = None
    for needle in (subject["title"], bare):
        if needle and needle.lower() in s.lower():
            clozed = re.sub(re.escape(needle), "_____", s, count=1, flags=re.IGNORECASE)
            break
    if not clozed or len(clozed) < 25:
        return None
    ds = title_distractors(subject, pool, rng)
    if len(ds) != 3:
        return None
    ans = bare
    return stem.format(clue=clozed), [ans] + ds, ans

def build_categorize(subject, pool, stem, rng):
    correct = subject.get("description")
    if not correct:
        return None
    ds = desc_distractors(subject, pool, rng)
    if len(ds) != 3:
        return None
    ans = cap(correct)
    return stem.format(title=display_title(subject["title"])), [ans] + [cap(d) for d in ds], ans

def build_oneliner(subject, pool, stem, rng):
    correct = subject.get("description")
    if not correct:
        return None
    # The description IS the clue here ("Which one is '<desc>'?"), so a generic
    # one ("American writer") is unanswerable AND collides across subjects.
    # Require something specific: 4+ words, or a comma/parenthetical/digit.
    if len(correct.split()) < 4 and not any(c in correct for c in ",(0123456789"):
        return None
    ds = title_distractors(subject, pool, rng)
    if len(ds) != 3:
        return None
    ans = display_title(subject["title"])
    return stem.format(clue=cap(correct)), [ans] + ds, ans

BUILDERS = {"identify": build_identify, "jeopardy": build_jeopardy, "cloze": build_cloze,
            "categorize": build_categorize, "oneliner": build_oneliner}

def make_question(subject, pool, category, gi, rng):
    """Pick a shape by seeded round-robin (even distribution, capped stems);
    fall through to the next shape if this subject can't fill it."""
    n = len(SHAPE_ROTATION)
    for off in range(n):
        shape = SHAPE_ROTATION[(gi + off) % n]
        stems = STEMS[shape]
        stem = stems[(gi // n) % len(stems)]
        built = BUILDERS[shape](subject, pool, stem, rng)
        if not built:
            continue
        prompt, options, answer = built
        # Hard gates: never ship a question that leaks the answer, still carries
        # foreign script / math symbols (unreadable), or ballooned from an
        # unbalanced-paren parse failure. Fall through to the next shape.
        if shape in ("identify", "jeopardy", "cloze") and leaks(answer, prompt):
            continue
        if _FOREIGN.search(prompt) or len(prompt) > 320:
            continue
        opts = options[:]; rng.shuffle(opts)
        ci = opts.index(answer)
        explanation = clean_clue(first_sentence(subject.get("extract") or "")) or (subject.get("description") or "")
        qid = f"corpus:{shape}:{subject['title']}".replace(" ", "_")
        return (qid, prompt, opts[0], opts[1], opts[2], opts[3],
                ci, category, difficulty(subject), explanation,
                subject["title"], subject.get("url") or "", shape)
    return None

def build_category(category, seeds, per_category, used_titles=None):
    used_titles = used_titles if used_titles is not None else set()
    print(f"[{category}] searching…")
    titles = []
    for q in seeds:
        titles += search_titles(q, limit=max(60, per_category // len(seeds) + 40))
    titles = list(dict.fromkeys(titles))  # dedupe, keep order
    print(f"[{category}] {len(titles)} candidate titles → fetching summaries")
    summaries = fetch_summaries(titles)
    # Global subject dedup: a subject belongs to ONE category — otherwise the
    # same person/place shows up under several categories (Austria in both
    # Geography and History).
    usable = [s for s in summaries.values() if is_usable(s) and s["title"] not in used_titles]
    for s in usable:
        used_titles.add(s["title"])
    print(f"[{category}] {len(usable)} usable subjects")
    rng = random.Random(hash(category) & 0xFFFFFFFF)
    rng.shuffle(usable)
    rows, ids = [], set()
    # Two questions per subject, each a DIFFERENT shape via the running
    # rotation counter (gi) — spreads shapes + stems evenly across the corpus.
    gi = 0
    for subj in usable:
        for _ in range(2):
            q = make_question(subj, usable, category, gi, rng)
            gi += 1
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
    used_titles = set()   # each subject lands in exactly one category
    for c, s in CATEGORY_SEEDS.items():
        all_rows += build_category(c, s, args.per_category, used_titles)

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
    cur.execute("""CREATE TABLE IF NOT EXISTS questions(
        id TEXT PRIMARY KEY, prompt TEXT, option0 TEXT, option1 TEXT,
        option2 TEXT, option3 TEXT, correct_index INTEGER, category_id TEXT,
        difficulty INTEGER, explanation TEXT, source_title TEXT,
        source_url TEXT, template_id TEXT)""")
    # Replace ONLY the summary-based questions; preserve the Wikidata moat
    # rows (template_id 'wd:*') so we don't re-hit the rate-limited WDQS.
    cur.execute("DELETE FROM questions WHERE template_id NOT LIKE 'wd:%'")
    cur.executemany(
        "INSERT OR IGNORE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", deduped)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_category ON questions(category_id)")
    conn.commit()
    n = cur.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    nwd = cur.execute("SELECT COUNT(*) FROM questions WHERE template_id LIKE 'wd:%'").fetchone()[0]
    conn.close()
    print(f"Wrote {len(deduped)} summary questions; corpus now {n} ({nwd} Wikidata preserved).")

if __name__ == "__main__":
    main()
