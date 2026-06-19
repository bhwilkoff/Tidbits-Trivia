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
import wiki_extract   # proprietary article fact extractor (see the skill)

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

# Fame floor: a subject is only fun to quiz if it's recognizable. The length of
# the intro extract is a strong, free notability proxy — famous subjects have
# multi-paragraph intros; obscure stubs ("X is an American actor.") are short.
# This is the single biggest fix for "nobody has heard of this person" questions.
_FAME_MIN_EXTRACT = 600

def is_usable(s):
    d, e, t = s.get("description"), s.get("extract"), s.get("title", "")
    if not d or not (6 <= len(d) <= 90):
        return False
    if not e or len(e) < _FAME_MIN_EXTRACT:
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
    if _GENERIC_DESC.search(d):              # too generic to anchor a fair MCQ
        return False
    if type_key(s) is None:                  # un-typeable → can't guarantee typed distractors
        return False
    return True

_GENERIC_DESC = re.compile(r"^\s*(\w+\s+){0,2}(person|human|man|woman|place|thing|object|"
                           r"name|surname|given name|topics?)\b", re.I)

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

def blank_name(text, title):
    """Blank ONLY occurrences of the subject's name (title + content words) —
    NOT the leading-proper-noun-run heuristic redact() uses. For reframed clues
    that already start 'This {type} …', so we don't blank a legit 'This American'."""
    bare = re.sub(r"\s*\([^)]*\)", "", title).strip()
    out = text
    for needle in dict.fromkeys([title, bare]):
        if needle:
            out = re.sub(re.escape(needle), "—————", out, flags=re.IGNORECASE)
    for w in re.findall(r"[A-Za-z][A-Za-z’'\-]{2,}", bare):
        if w.lower() in _FUNCTION_WORDS:
            continue
        out = re.sub(rf"\b{re.escape(w)}(?:’s|'s|s|es)?\b", "—————", out, flags=re.IGNORECASE)
    out = re.sub(r"—————(?:[\s,’'.\–\-]+(?:of|the|and|de|von|van)?\s*—————)+", "—————", out, flags=re.IGNORECASE)
    return re.sub(r"\s{2,}", " ", out).strip()

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
            k = i + 1                       # skip a RUN of spaces ("Nigeria.  There")
            while k < L and t[k] == " ":
                k += 1
            nxt2 = t[k] if k < L else ""
            if nxt2 == "" or nxt2.isupper() or nxt2 in "“”\"'‘’":
                j = i - 1
                while j >= 0 and (t[j].isalnum() or t[j] in ".'’-"):
                    j -= 1
                tok = t[j + 1:i]
                letters = re.sub(r"[^A-Za-z]", "", tok)
                has_digit = any(ch.isdigit() for ch in tok)
                # A digit-bearing token ("1750s") is NOT an initial/abbreviation —
                # so a decade ending a sentence ("…the 1750s. The style…") splits.
                if not (letters and not has_digit and (len(letters) <= 1 or tok.lower().rstrip(".") in _ABBREV)):
                    return t[:i + 1]
        i += 1
    # Scan found no interior sentence break → the text IS a single sentence;
    # return it whole. (Don't fall back to a naive ". " split — that re-truncates
    # at the very abbreviations the scan correctly skipped, e.g. "Mrs. Doubtfire".
    # A pathological unbalanced-paren extract is caught by the downstream length gate.)
    return t

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
    # Above the fame floor (600), a longer intro = more famous = easier. Rescaled
    # so the easy/medium/hard spread survives the floor instead of collapsing to "easy".
    n = len(s.get("extract") or "")
    return 2 if n >= 2000 else (3 if n >= 1000 else 4)

# --- Distractor pickers (typed siblings; length-normalized for prose) ---

# --- Type-matched distractors -------------------------------------------------
# Distractors MUST be the same TYPE as the answer (genre↔genre, city↔city,
# actor↔actor). The Wikipedia short description encodes the type; we extract a
# coarse "type key" (head noun, synonym-folded) and draw distractors only from
# the subject's own type bucket. If a subject can't be typed or has <3 same-type
# siblings, we DROP the question — a wrong-type distractor (the old
# word-overlap behaviour) is the exact tell we are killing.
_TYPE_LEADING = set("""american english british french german italian spanish russian
chinese japanese korean indian european african asian north south east west northern
southern eastern western central ancient modern medieval former national international
royal imperial classical contemporary professional famous notable major minor large
small great greater lesser old new young senior junior fictional mythological historical
traditional popular official public private federal scottish irish welsh dutch swedish
norwegian danish polish turkish greek roman egyptian persian arab arabic jewish canadian
australian mexican brazilian argentine chilean austrian swiss belgian portuguese finnish
hungarian czech romanian indonesian filipino vietnamese thai largest smallest oldest""".split())
_TYPE_STOP = re.compile(r"\b(in|of|from|for|by|on|at|near|during|between|that|which|who|"
                        r"known|with|to|and|or|located|based|set)\b", re.I)
_TYPE_FOLD = {
    "singer": "musician", "songwriter": "musician", "singer-songwriter": "musician",
    "rapper": "musician", "guitarist": "musician", "pianist": "musician",
    "drummer": "musician", "bassist": "musician", "vocalist": "musician",
    "band": "musician", "duo": "musician", "composer": "musician",
    "actress": "actor", "filmmaker": "director",
    "novelist": "writer", "author": "writer", "poet": "writer",
    "playwright": "writer", "screenwriter": "writer", "essayist": "writer",
    "journalist": "writer",
    "physicist": "scientist", "chemist": "scientist", "biologist": "scientist",
    "mathematician": "scientist", "astronomer": "scientist", "geologist": "scientist",
    "economist": "scientist", "psychologist": "scientist", "inventor": "scientist",
    "footballer": "athlete", "player": "athlete", "cyclist": "athlete",
    "swimmer": "athlete", "boxer": "athlete", "wrestler": "athlete",
    "sprinter": "athlete", "runner": "athlete", "golfer": "athlete",
    "village": "settlement", "town": "settlement", "city": "settlement",
    "municipality": "settlement", "commune": "settlement", "capital": "settlement",
    "mountain": "peak", "volcano": "peak",
}

def type_key(subject):
    """Coarse type bucket from the short description; None if no head noun."""
    d = re.sub(r"\([^)]*\)", "", subject.get("description") or "")
    d = d.split(",")[0].strip().rstrip(".").lower()
    m = _TYPE_STOP.search(d)
    if m:
        d = d[:m.start()]
    toks = re.findall(r"[a-z][a-z\-]+", d)
    while toks and toks[0] in _TYPE_LEADING:
        toks = toks[1:]
    if not toks:
        return None
    return _TYPE_FOLD.get(toks[-1], toks[-1])

_TYPE_IDX_CACHE = {}
def _type_index(pool):
    idx = _TYPE_IDX_CACHE.get(id(pool))
    if idx is None:
        idx = {}
        for s in pool:
            k = type_key(s)
            if k:
                idx.setdefault(k, []).append(s)
        _TYPE_IDX_CACHE[id(pool)] = idx
    return idx

def _typed(subject, pool, rng, value_fn, exclude, length_match=None, k=3):
    kt = type_key(subject)
    if not kt:
        return []
    cands, seen = [], set()
    excl = (exclude or "").lower()
    for c in _type_index(pool).get(kt, []):
        if c["title"] == subject["title"]:
            continue
        v = (value_fn(c) or "").strip()
        if not v or v.lower() == excl or v.lower() in seen:
            continue
        seen.add(v.lower())
        lenpen = -abs(len(v) - length_match) if length_match is not None else 0
        cands.append((lenpen, v))
    if len(cands) < k:
        return []
    cands.sort(key=lambda x: x[0], reverse=True)
    window = cands[:max(k * 3, 8)]
    rng.shuffle(window)
    return [v for _, v in window[:k]]

def title_distractors(subject, pool, rng, k=3):
    return _typed(subject, pool, rng, lambda c: display_title(c["title"]), display_title(subject["title"]), k=k)

def desc_distractors(subject, pool, rng, k=3):
    correct = subject.get("description") or ""
    return _typed(subject, pool, rng, lambda c: c.get("description"), correct, length_match=len(correct), k=k)

# --- "Describe & identify" — the bar-trivia shape ------------------------------
# A good question LEADS WITH the distinguishing facts and asks a natural
# "who/what is this?". The old robotic framings ("Which subject does this
# describe?", "what is it?") and the categorize shape ("What kind of thing is
# X?") are GONE — no human asks those. Two gates make these feel hand-written:
#   (1) fame floor (is_usable) — the subject is recognizable, and
#   (2) richness — the clue carries real distinguishing detail, never the bare
#       "was an American actor".

# Words that DON'T distinguish a subject — so they don't count toward richness.
_TYPE_NOUNS = set("""actor actress singer musician composer songwriter rapper band
writer author poet novelist playwright journalist artist painter sculptor director
filmmaker producer scientist physicist chemist biologist mathematician astronomer
economist politician philosopher activist explorer inventor architect dancer
comedian footballer player athlete cyclist swimmer boxer golfer film movie
television series show novel book album song single painting sculpture poem play
opera symphony team club city town country river mountain lake dynasty empire""".split())
_CLUE_GENERIC = (COMMON_WORDS | set(_TYPE_LEADING) | _TYPE_NOUNS
                 | set(wiki_extract.NATIONALITIES)
                 | set("this the a an was is were are best known famous noted also "
                       "who which that based located near former".split()))

_MONTHS = set("january february march april may june july august september october "
              "november december".split())

def informative_tokens(clue):
    """Count distinguishing facts: proper nouns (works, places) + years. Strips
    parentheticals first — a '(born December 18, 1963)' birth date is NOT a
    quizzable clue (that's just birthday-guessing), and pronunciations/IPA are
    noise. So '_____ (born 1963) is an American actor' scores 0 → dropped, while
    '… known for his role as Tony Soprano in The Sopranos' stays rich."""
    c = re.sub(r"\([^)]*\)", "", clue)
    proper = {w.lower() for w in re.findall(r"\b[A-Z][A-Za-z'’\-]{2,}\b", c)
              if w.lower() not in _CLUE_GENERIC and w.lower() not in _MONTHS}
    years = set(re.findall(r"\b(?:1\d{3}|20\d{2})\b", c))
    return len(proper) + len(years)

# Person types ask "who"; everything else asks "what". Decided by the type
# HEAD-NOUN (type_key), NOT a loose word match — a novel "by American author X"
# must NOT read as a person just because its description mentions "author".
_PERSON_TYPEKEYS = set("""actor actress musician writer scientist athlete director painter
singer composer poet novelist author journalist sculptor architect engineer
politician philosopher economist historian activist explorer inventor dancer
comedian model conductor pianist guitarist rapper businessman entrepreneur
king queen emperor empress monarch president general admiral saint pope sultan
tsar duke earl baron knight prince princess priest bishop rabbi imam nun monk
lawyer diplomat soldier aristocrat theologian""".split())

def is_person(subject):
    k = type_key(subject)
    if k in _PERSON_TYPEKEYS:
        return True
    if k is not None:                 # typed as a non-person thing → not a person
        return False
    # Untyped: fall back to a life-dates / "born" hint in the lead.
    return bool(re.search(r"\(\s*\d{3,4}\s*[–-]|\bborn\b", subject.get("extract") or ""))

def _first_n(text, n):
    out, rest = [], (text or "").strip()
    for _ in range(n):
        if not rest:
            break
        s = first_sentence(rest)
        out.append(s.strip())
        rest = rest[len(s):].lstrip()
    return " ".join(out)

# Anchor on the LEADING proper-noun run, not the article title — Wikipedia opens
# with the full birth name ("Thomas Jeffrey Hanks"), which differs from the title
# ("Tom Hanks"). Group 'name' = that run; 'rest' = everything after "was/is a/an".
_LEAD = re.compile(
    r"^\s*(?P<name>(?:[A-Z][\w’'.\-]*)(?:[ \-]+(?:of|the|and|de|von|van|al|da|di)?\s*[A-Z][\w’'.\-]*)*)"
    r"\s*(?:\([^)]*\))?\s+(?:was|is|were|are)\s+(?:a|an|the)\s+(?P<rest>.+)$")

def reframe(sentence, subject):
    """'NAME (dates) was an American actor known for X' → 'American actor known
    for X' — the bare descriptive phrase (no leading 'This'/blank), residual name
    redacted. The STEM supplies the natural framing ('Name this …', 'Which …?',
    'Who is the …?'). None when the sentence doesn't open by naming someone."""
    m = _LEAD.match(sentence)
    if m:
        return blank_name(m.group("rest").strip(), subject["title"])
    return None

# The clue is a bare descriptive phrase ("American actor best known for …");
# the stem supplies natural framing. No "{clue} — what is it?" — that reads
# strangely for a titled work ("This 2007 novel by Olga Tokarczuk — what is it?").
STEMS = {
    "describe_person": [
        "This {clue} — who is this?",
        "Name this {clue}.",
        "Who is the {clue}?",
        "Which {clue}?",
    ],
    "describe_thing": [
        "Name this {clue}.",
        "Which {clue}?",
        "Name the {clue}.",
    ],
    "cloze": [
        "Fill in the blank: “{clue}”",
        "Complete it: “{clue}”",
        "Which name completes this? “{clue}”",
    ],
}
SHAPE_ROTATION = ["describe", "cloze", "describe", "describe", "cloze"]

def build_describe(subject, pool, stem, rng):
    # FIRST sentence only — a 2-sentence clue reads awkwardly under "Name this …?"
    # / "Which …?" (the question mark dangles after a second sentence). If the
    # lead sentence is too thin, drop (cloze / fact paths may still cover it).
    c = reframe(clean_clue(first_sentence(subject.get("extract") or "")), subject)
    if not c or len(c) < 30 or informative_tokens(c) < 2:
        return None
    clue = c.rstrip(". ").strip()
    ds = title_distractors(subject, pool, rng)
    if len(ds) != 3:
        return None
    ans = display_title(subject["title"])
    return stem.format(clue=clue), [ans] + ds, ans

def build_cloze(subject, pool, stem, rng):
    s = clean_clue(first_sentence(subject.get("extract") or ""))
    bare = display_title(subject["title"])
    clozed = None
    # Prefer blanking the title verbatim ("The 62nd Academy Awards were held…");
    # otherwise blank the leading name run ("Thomas Jeffrey Hanks (born…) is…").
    for needle in (subject["title"], bare):
        if needle and needle.lower() in s.lower():
            clozed = re.sub(re.escape(needle), "_____", s, count=1, flags=re.IGNORECASE)
            break
    if not clozed:
        m = _LEAD.match(s)
        if m:
            clozed = s[:m.start("name")] + "_____" + s[m.end("name"):]
    if not clozed or len(clozed) < 30 or informative_tokens(clozed) < 2:
        return None
    ds = title_distractors(subject, pool, rng)
    if len(ds) != 3:
        return None
    return stem.format(clue=clozed), [bare] + ds, bare

BUILDERS = {"describe": build_describe, "cloze": build_cloze}

def make_question(subject, pool, category, gi, rng):
    """Seeded round-robin over the shapes; fall through if a subject can't fill
    one. 'describe' picks person/thing phrasing, so we never ask 'what is it?'
    of a human or 'who is this?' of a film."""
    person = is_person(subject)
    n = len(SHAPE_ROTATION)
    for off in range(n):
        shape = SHAPE_ROTATION[(gi + off) % n]
        bank = STEMS["describe_person" if person else "describe_thing"] if shape == "describe" else STEMS[shape]
        stem = bank[(gi // n) % len(bank)]
        built = BUILDERS[shape](subject, pool, stem, rng)
        if not built:
            continue
        prompt, options, answer = built
        # Hard gates: never leak the answer, carry foreign script/math, or balloon.
        if leaks(answer, prompt) or _FOREIGN.search(prompt) or len(prompt) > 320:
            continue
        opts = options[:]; rng.shuffle(opts)
        ci = opts.index(answer)
        explanation = clean_clue(first_sentence(subject.get("extract") or "")) or (subject.get("description") or "")
        qid = f"corpus:{shape}:{subject['title']}".replace(" ", "_")
        return (qid, prompt, opts[0], opts[1], opts[2], opts[3],
                ci, category, difficulty(subject), explanation,
                subject["title"], subject.get("url") or "", shape)
    return None

# --- Fact-based questions (the deep-extraction path; see wiki_extract) -------
# Augments each category with VERIFIABLE fact MCQs mined from the full article
# (birth/death year, director/writer/composer/painter, nationality). Distractors
# are category-pooled type-matched siblings, so they're wrong by construction.
# Bounded per category to keep the crawl polite; every article is cached.

_FACT_EXPL = {
    "birth_year": "{s} was born in {a}.", "death_year": "{s} died in {a}.",
    "directed_by": "{s} was directed by {a}.", "written_by": "{s} was written by {a}.",
    "composed_by": "{s} was composed by {a}.", "painted_by": "{s} was painted by {a}.",
    "nationality": "{s} was {a}.",
}

def build_fact_questions(subjects, category, rng, limit):
    pool = []
    for s in subjects[:limit]:
        art = wiki_extract.fetch_article(s["title"])
        if art.get("extract"):
            pool.append((art["title"], wiki_extract.extract_facts(art)))
    rows = []
    for m in wiki_extract.build_mcqs(pool, rng, category):
        opts = m["options"]
        if len(m["prompt"]) > 320 or _FOREIGN.search(m["prompt"]):
            continue
        if any(_FOREIGN.search(o) for o in opts):
            continue
        rel, subj = m["relation"], m["subject"]
        expl = _FACT_EXPL.get(rel, "{s}: {a}.").format(s=display_title(subj), a=m["answer"])
        qid = f"fact:{rel}:{subj}".replace(" ", "_")
        rows.append((qid, m["prompt"], opts[0], opts[1], opts[2], opts[3],
                     m["correct_index"], category, 3, expl,
                     subj, m.get("source_url") or "", f"fact:{rel}"))
    print(f"[{category}] {len(rows)} fact questions")
    return rows

def build_category(category, seeds, per_category, used_titles=None, facts_per_category=0,
                   facts_only=False):
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
    # Skipped in facts-only mode (existing summary rows are preserved as-is).
    if not facts_only:
        gi = 0
        for subj in usable:
            for _ in range(2):
                q = make_question(subj, usable, category, gi, rng)
                gi += 1
                if q and q[0] not in ids:
                    ids.add(q[0])
                    rows.append(q)
        print(f"[{category}] {len(rows)} summary questions")
    if facts_per_category:
        frng = random.Random((hash(category) ^ 0x9E3779B9) & 0xFFFFFFFF)
        rows += build_fact_questions(usable, category, frng, facts_per_category)
    return rows

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="../../TidbitsTrivia/Resources/corpus.sqlite")
    ap.add_argument("--per-category", type=int, default=1600)
    ap.add_argument("--target", type=int, default=10000)
    ap.add_argument("--facts-per-category", type=int, default=0,
                    help="full-article fact MCQs per category (0=off; ~150 is a good start). "
                         "First run crawls full articles (cached); re-runs are instant.")
    ap.add_argument("--facts-only", action="store_true",
                    help="ADD fact questions to the existing corpus without rebuilding "
                         "summary rows or re-hitting WDQS. Purely additive (INSERT OR IGNORE); "
                         "preserves the shipped summary/Wikidata rows. Use to ratchet up facts.")
    args = ap.parse_args()

    all_rows = []
    used_titles = set()   # each subject lands in exactly one category
    for c, s in CATEGORY_SEEDS.items():
        all_rows += build_category(c, s, args.per_category, used_titles,
                                   args.facts_per_category, args.facts_only)

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
    before = cur.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    if args.facts_only:
        # Purely additive: keep all existing rows, INSERT OR IGNORE only the new
        # fact questions (deterministic qids → existing ones are skipped).
        cur.executemany(
            "INSERT OR IGNORE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", deduped)
    else:
        # Replace the summary AND fact rows (both produced by this run); preserve
        # the Wikidata moat rows (template_id 'wd:*') so we don't re-hit WDQS.
        cur.execute("DELETE FROM questions WHERE template_id NOT LIKE 'wd:%'")
        cur.executemany(
            "INSERT OR IGNORE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", deduped)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_category ON questions(category_id)")
    conn.commit()
    n = cur.execute("SELECT COUNT(*) FROM questions").fetchone()[0]
    nwd = cur.execute("SELECT COUNT(*) FROM questions WHERE template_id LIKE 'wd:%'").fetchone()[0]
    nfact = cur.execute("SELECT COUNT(*) FROM questions WHERE template_id LIKE 'fact:%'").fetchone()[0]
    conn.close()
    if args.facts_only:
        print(f"Facts-only: corpus {before} → {n} (+{n - before} added); {nfact} fact, {nwd} Wikidata.")
    else:
        print(f"Wrote {len(deduped)} summary+fact questions; corpus now {n} ({nfact} fact, {nwd} Wikidata).")

if __name__ == "__main__":
    main()
