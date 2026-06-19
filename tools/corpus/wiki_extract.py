#!/usr/bin/env python3
"""
Tidbits — Wikipedia article fact extractor (stdlib-only).

Turns a Wikipedia article into verifiable fact tuples we can quiz on. The
design is PRECISION-FIRST: every stage has a drop-exit, and a fact must
survive all of them. A wrong fact in a trivia app is far worse than a missed
one. See .claude/skills/wikipedia-fact-extraction for the method + sources.

Pipeline: fetch → infobox (oracle) → clean → segment → define (lead) →
coref → relate → score+gate → emit.

Stdlib only (urllib, re, html, unicodedata). Caches each article to
cache/articles/ so re-runs never re-hit the rate-limited API.

Usage (verification demo):
    python3 wiki_extract.py "Marie Curie" "Mount Everest" "The Godfather"
"""
import html, json, os, re, sys, time, threading, urllib.parse, urllib.request

API = "https://en.wikipedia.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; contact ben@learningischange.com)"
CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache", "articles")

# Polite serial rate limiter (Wikimedia enforces REST limits as of 2026).
_MIN_INTERVAL = 0.2
_lock = threading.Lock()
_last = [0.0]

def _throttle():
    with _lock:
        wait = _MIN_INTERVAL - (time.monotonic() - _last[0])
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.monotonic()

def _get(params, retries=5):
    params = {**params, "format": "json", "formatversion": "2", "maxlag": "5"}
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < retries - 1:
                back = int(e.headers.get("Retry-After") or 0) or min(60, 4 * (2 ** attempt))
                print(f"  … {e.code}, backing off {back}s", file=sys.stderr)
                time.sleep(back); continue
            print(f"  ! HTTP {e.code}", file=sys.stderr); return {}
        except Exception as e:
            if attempt == retries - 1:
                print(f"  ! request failed: {e}", file=sys.stderr); return {}
            time.sleep(2 * (attempt + 1))
    return {}

# ---------------------------------------------------------------------------
# Stage 0 — Fetch (wikitext for the infobox; plaintext extract for the prose)
# ---------------------------------------------------------------------------

def fetch_article(title):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", title)[:120]
    path = os.path.join(CACHE_DIR, safe + ".json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    parse = _get({"action": "parse", "page": title, "prop": "wikitext", "redirects": "1"})
    wikitext = (parse.get("parse") or {}).get("wikitext") or ""
    q = _get({"action": "query", "prop": "extracts|info|pageprops", "explaintext": "1",
              "exsectionformat": "wiki", "inprop": "url", "redirects": "1", "titles": title})
    pages = (q.get("query") or {}).get("pages") or []
    page = pages[0] if pages else {}
    art = {
        "title": page.get("title") or title,
        "extract": page.get("extract") or "",
        "wikitext": wikitext,
        "url": page.get("fullurl") or "",
        "pageprops": page.get("pageprops") or {},
    }
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(path, "w") as f:
        json.dump(art, f)
    return art

# ---------------------------------------------------------------------------
# Stage 1 — Infobox parse (depth-counting scanner — regex cannot match nesting)
# ---------------------------------------------------------------------------

def find_template(wikitext, name="Infobox"):
    m = re.search(r"\{\{\s*" + name, wikitext, re.I)
    if not m:
        return None
    i, depth, j, n = m.start(), 0, m.start(), len(wikitext)
    while j < n - 1:
        two = wikitext[j:j+2]
        if two == "{{":
            depth += 1; j += 2; continue
        if two == "}}":
            depth -= 1; j += 2
            if depth == 0:
                return wikitext[i:j]
            continue
        j += 1
    return None

def split_top_level(body, sep="|"):
    """Split on `sep` only at template-depth-0 AND link-depth-0."""
    parts, buf, dt, dl, k = [], [], 0, 0, 0
    while k < len(body):
        two = body[k:k+2]
        if two == "{{": dt += 1; buf.append(two); k += 2; continue
        if two == "}}": dt -= 1; buf.append(two); k += 2; continue
        if two == "[[": dl += 1; buf.append(two); k += 2; continue
        if two == "]]": dl -= 1; buf.append(two); k += 2; continue
        c = body[k]
        if c == sep and dt == 0 and dl == 0:
            parts.append("".join(buf)); buf = []
        else:
            buf.append(c)
        k += 1
    parts.append("".join(buf))
    return parts

def _clean_value(v):
    v = re.sub(r"\{\{\s*(?:convert|cvt)\s*\|\s*([\d,.]+)\s*\|\s*([^|}]+).*?\}\}", r"\1 \2", v, flags=re.I)
    v = re.sub(r"\{\{\s*(?:nowrap|nobold|noitalic)\s*\|\s*([^}]*)\}\}", r"\1", v, flags=re.I)
    v = re.sub(r"\{\{\s*(?:start date|birth date|death date)(?:\s+and\s+age)?\s*\|\s*([\d|]+).*?\}\}",
               lambda m: m.group(1).split("|")[0], v, flags=re.I)
    for _ in range(3):
        v, n = re.subn(r"\{\{[^{}]*\}\}", "", v)
        if not n: break
    v = strip_wiki(v)
    items = [x.strip(" *#") for x in re.split(r"\n[*#]+|<br\s*/?>", v) if x.strip(" *#")]
    if len(items) > 1:
        return items
    return items[0] if items else ""

def parse_infobox(wikitext):
    tpl = find_template(wikitext, "Infobox")
    if not tpl:
        return {}
    fields = split_top_level(tpl[2:-2], "|")[1:]   # [0] is "Infobox <type>"
    out = {}
    for f in fields:
        if "=" not in f:
            continue
        key, val = f.split("=", 1)
        key = key.strip().lower()
        cleaned = _clean_value(val.strip())
        if key and cleaned:
            out[key] = cleaned
    return out

# ---------------------------------------------------------------------------
# Stage 2 — Clean wiki/HTML artifacts (order is load-bearing)
# ---------------------------------------------------------------------------

_PRONUNCIATION = re.compile(
    r"\(\s*(?:/[^)]*?/|listen|pronounced[^)]*|(?:[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?):\s*[^)]*)\)")

def strip_wiki(t):
    t = re.sub(r"<!--.*?-->", "", t, flags=re.S)              # comments
    t = re.sub(r"<ref[^>]*?/>", "", t, flags=re.I)            # self-closing refs
    t = re.sub(r"<ref[^>]*?>.*?</ref>", "", t, flags=re.I | re.S)
    for _ in range(3):                                         # simple templates
        t, n = re.subn(r"\{\{[^{}]*\}\}", "", t)
        if not n: break
    t = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]|]+)\]\]", r"\1", t)  # [[a|b]] -> b
    t = re.sub(r"\[https?://\S+\s+([^\]]+)\]", r"\1", t)      # [url text] -> text
    t = re.sub(r"\[https?://\S+\]", "", t)
    t = re.sub(r"'{2,5}", "", t)                              # bold/italic
    t = re.sub(r"<[^>]+>", "", t)                             # html tags
    t = html.unescape(t)                                      # entities (after tags)
    t = _PRONUNCIATION.sub("", t)                             # IPA / Lang: parens (DROP)
    t = re.sub(r"\[\d+\]|\[citation needed\]", "", t, flags=re.I)
    t = re.sub(r"[ \t]+", " ", t).replace(" ,", ",").replace(" .", ".").strip()
    return t

# ---------------------------------------------------------------------------
# Stage 3 — Sentence segmentation (protect-then-split)
# ---------------------------------------------------------------------------

_DOT = "·DOT·"
_ABBREV = set("""mr mrs ms dr prof st sr jr rev fr gen sen gov rep col capt lt sgt
pres supt hon etc vs viz al cf ca approx est lit fl ib ibid op no vol pp ed trans
orig mt ft co corp inc ltd dept jan feb mar apr jun jul aug sep sept oct nov dec
e.g i.e u.s u.k u.n""".split())

def _protect(text):
    text = re.sub(r"\b([A-Za-z](?:\.[A-Za-z])+)\.",
                  lambda m: m.group(1).replace(".", _DOT) + _DOT, text)   # U.S. e.g.
    def _abbr(m):
        w = m.group(1)
        return w + _DOT if w.lower().strip(".") in _ABBREV else m.group(0)
    text = re.sub(r"\b([A-Za-z]{1,6})\.", _abbr, text)
    text = re.sub(r"\b([A-Z])\.(\s+[A-Z])", r"\1" + _DOT + r"\2", text)   # middle initial
    text = re.sub(r"(\d)\.(\d)", r"\1" + _DOT + r"\2", text)              # decimals
    return text

def segment(text):
    text = _protect(text)
    raw = re.split(r'(?<=[.!?])["\')\]]?\s+(?=[A-Z"“(\[])', text)
    return [s.replace(_DOT, ".").strip() for s in raw if s.replace(_DOT, ".").strip()]

# ---------------------------------------------------------------------------
# Stage 4 — Definitional / appositive extraction (lead sentence only)
# ---------------------------------------------------------------------------

NATIONALITIES = set("""polish french american british english german italian russian
japanese chinese spanish dutch canadian australian indian brazilian mexican swedish
norwegian danish finnish greek roman egyptian persian turkish irish scottish welsh
austrian swiss belgian portuguese hungarian czech romanian korean vietnamese thai
argentine chilean colombian peruvian israeli iranian iraqi syrian lebanese moroccan
nigerian kenyan ethiopian ukrainian serbian croatian bulgarian icelandic""".split())

DEF_COPULA = re.compile(
    r"^(?P<subject>.+?)\s*(?:\((?P<paren>[^)]*)\))?\s+"
    r"(?P<copula>is|was|are|were)\s+(?:an|a|the)?\s*"
    r"(?P<type>[A-Za-z][\w\s\-'’]*?)"
    r"(?:\s+(?P<rest>(?:who|that|which|known|best|widely|also|famously|primarily|"
    r"chiefly|mainly|located|based|situated|by|in|from|with|for|directed|produced|"
    r"written|composed|painted|designed|released|published|created|made)\b.*)|[.,].*|$)")

def _normalize(s):
    s = re.sub(r"\([^)]*\)", "", s)
    s = re.sub(r"[^\w\s]", "", s, flags=re.U).lower().strip()
    return s

def subject_is_title(subject, title):
    ns, nt = _normalize(subject), _normalize(title)
    if not ns or not nt:
        return False
    if ns == nt or ns in nt or nt in ns:
        return True
    return ns.split()[-1] == nt.split()[-1]

def split_type(type_phrase):
    type_phrase = re.sub(r"^(?:a|an|the)\s+", "", type_phrase.strip(), flags=re.I)
    type_phrase = re.sub(r"^\d{3,4}\s+", "", type_phrase)   # leading year (films)
    toks, nats = type_phrase.split(), []
    # Consume the run of leading nationality adjectives + connectors
    # ("Polish and naturalised-French …"), collecting each nationality.
    while toks:
        head = toks[0].lower().strip("-")
        parts = head.split("-")
        nat_part = head if head in NATIONALITIES else next(
            (p for p in parts if p in NATIONALITIES), None)
        if nat_part:
            nats.append(nat_part.capitalize())
            toks = toks[1:]
        elif head in ("and", "naturalised", "naturalized", "born"):
            toks = toks[1:]
        else:
            break
    occ = " ".join(toks).strip()
    occ = re.sub(r"\s+(?:directed|produced|written|composed|painted|designed|"
                 r"released|published|created|made|founded|and)$", "", occ, flags=re.I)
    facts = []
    # Emit nationality ONLY when there is exactly one — a dual nationality
    # ("American-British") is ambiguous (the other reads as a valid answer too).
    if len(nats) == 1:
        facts.append(("nationality", nats[0]))
    # Reject non-noun "types" from copula false-matches ("is connected to" →
    # "connected"; "was the reason" → "reason"). A single participle/adjective or
    # an abstract filler word is not a thing you can be "best known as".
    low = occ.lower()
    bad = low in _NON_TYPE or (len(occ.split()) == 1 and re.search(r"(ed|ing)$", low))
    if occ and not bad and 2 <= len(occ) <= 45:
        facts.append(("type", occ))
    return facts

_NON_TYPE = {"connected", "reason", "result", "part", "member", "one", "group",
             "name", "term", "example", "kind", "number", "series", "set", "point",
             "place", "thing", "form", "way", "case", "type", "matter", "subject",
             "area", "aspect", "process", "state", "period", "event", "term", "home"}

# ---------------------------------------------------------------------------
# Stage 3b — Date / number normalization
# ---------------------------------------------------------------------------

MONTHS = {m: i for i, m in enumerate(
    ["january", "february", "march", "april", "may", "june", "july", "august",
     "september", "october", "november", "december"], 1)}

LIFE_RANGE = re.compile(
    r"(?P<born>\b\d{1,2}\s+[A-Z][a-z]+\s+\d{3,4}|\b[A-Z][a-z]+\s+\d{1,2},?\s+\d{3,4}|\b\d{3,4})"
    r"\s*[-–—]\s*"
    r"(?P<died>\b\d{1,2}\s+[A-Z][a-z]+\s+\d{3,4}|\b[A-Z][a-z]+\s+\d{1,2},?\s+\d{3,4}|\b\d{3,4})")
BORN_LABELED = re.compile(r"\bborn\b[^,;)]*?\b(\d{3,4})\b", re.I)
YEAR_IN_TEXT = re.compile(r"\bin\s+(1\d{3}|20\d{2})\b")

def _year(s):
    m = re.search(r"\b(\d{3,4})\b", s or "")
    return int(m.group(1)) if m else None

# ---------------------------------------------------------------------------
# Stage 5 — Coreference-safe stem construction
# ---------------------------------------------------------------------------

_PRONOUN_SUBJ = re.compile(r"^(He|She|It|They|His|Her|Its|Their)\b")
_DEFINITE_SUBJ = re.compile(
    r"^The\s+(city|town|company|band|film|movie|book|novel|team|league|album|song|"
    r"organization|species|river|mountain|island|country|state|empire|battle|war)\b", re.I)
# Residual deixis AFTER resolution → drop (refers to a non-title entity).
_DROP_DEIXIS = re.compile(
    r"\b(it|its|they|them|their|he|she|his|her|this|that|these|those|such|"
    r"the former|the latter)\b", re.I)

def selfcontain(sentence, title):
    if _PRONOUN_SUBJ.match(sentence):
        return _PRONOUN_SUBJ.sub(title, sentence, count=1)
    if _DEFINITE_SUBJ.match(sentence):
        return _DEFINITE_SUBJ.sub(title, sentence, count=1)
    return sentence

def is_quizzable_stem(sentence):
    return not _DROP_DEIXIS.search(sentence)

# ---------------------------------------------------------------------------
# Stage 6 — Relation / triple extraction (subject bound to the title)
# ---------------------------------------------------------------------------

# Note: 'and' is deliberately NOT a connector — it joins SEPARATE entities, so a
# coordinated "X and Y" must read as two objects (then get dropped as ambiguous),
# never one tangled object. Name particles (de/da/van/von…) stay.
_OBJ = (r"(?P<obj>(?:[\"“][^\"”]+[\"”])|"
        r"(?:[A-Z][\w.'’\-]*(?:\s+(?:of|the|de|da|van|von|del|della|di|du|le|la|in)?\s*[A-Z][\w.'’\-]*)*))")
# "by [the] [Nationality] [role-noun] NAME" — skip the descriptive prefix and
# bind the actual person. The prefix is optional, so "by Jane Austen" still works.
_BY_AGENT = (r"(?:(?:the\s+)?(?:[A-Za-z][a-zé\-]+\s+){0,3}(?:author|writer|novelist|poet|"
             r"playwright|composer|artist|painter|director|sculptor|architect|"
             r"filmmaker|musician|singer|inventor|scientist|engineer|group|band|"
             r"duo|trio|quartet|ensemble|orchestra)\s+)?" + _OBJ)
VERB_PATTERNS = [
    ("won",        re.compile(r"\bwon\s+(?:the\s+)?" + _OBJ + r"(?:\s+in\s+(?P<year>\d{4}))?")),
    ("founded",    re.compile(r"\bfounded\s+(?:the\s+)?" + _OBJ + r"(?:\s+in\s+(?P<year>\d{4}))?")),
    ("wrote",      re.compile(r"\bwrote\s+(?:the\s+)?" + _OBJ + r"(?:\s+in\s+(?P<year>\d{4}))?")),
    ("composed",   re.compile(r"\bcomposed\s+(?:the\s+)?" + _OBJ + r"(?:\s+in\s+(?P<year>\d{4}))?")),
    ("directed",   re.compile(r"\bdirected\s+(?:the\s+)?" + _OBJ + r"(?:\s+in\s+(?P<year>\d{4}))?")),
    ("discovered", re.compile(r"\bdiscovered\s+" + _OBJ + r"(?:\s+in\s+(?P<year>\d{4}))?")),
    ("invented",   re.compile(r"\binvented\s+(?:the\s+)?" + _OBJ + r"(?:\s+in\s+(?P<year>\d{4}))?")),
    ("located_in", re.compile(r"\blocated\s+in\s+" + _OBJ)),
    ("capital_of", re.compile(r"\b(?:is|was)\s+the\s+capital\s+(?:city\s+)?of\s+" + _OBJ)),
    # Passive creator attributions, role-specific (single-valued → unambiguous).
    # 'produced by' is deliberately omitted — producers are many per work.
    ("directed_by", re.compile(r"\bdirected\s+by\s+" + _BY_AGENT)),
    ("written_by",  re.compile(r"\bwritten\s+by\s+" + _BY_AGENT)),
    ("composed_by", re.compile(r"\bcomposed\s+by\s+" + _BY_AGENT)),
    ("painted_by",  re.compile(r"\bpainted\s+by\s+" + _BY_AGENT)),
    ("painted_by",  re.compile(r"\b(?:painting|portrait|sculpture|statue|fresco|mural)\s+by\s+" + _BY_AGENT)),
    ("written_by",  re.compile(r"\b(?:novel|poem|play|book|short story)\s+by\s+" + _BY_AGENT)),
    ("directed_by", re.compile(r"\bfilm\s+by\s+" + _BY_AGENT)),
    ("composed_by", re.compile(r"\b(?:opera|symphony|concerto|song|album)\s+by\s+" + _BY_AGENT)),
]
_VERB_STOP = re.compile(r"\b(and|but|who|which|that|where|while|after|before|when|"
                        r"because|although|though|until|since)\b", re.I)

def _clean_obj(obj):
    obj = obj.strip(" .,;:'\"“”")
    obj = _VERB_STOP.split(obj)[0].strip(" .,;:'\"“”")
    return obj

def extract_relations(clause, title):
    out = []
    for rel, pat in VERB_PATTERNS:
        for m in pat.finditer(clause):
            obj = _clean_obj(m.group("obj"))
            if not (3 <= len(obj) <= 60) or not obj[0:1].isupper():
                continue
            if subject_is_title(obj, title):   # "X is the capital of X" garbage
                continue
            # A bare nationality adjective ("Japanese") is never a creator name.
            if rel.endswith("_by") and obj.lower() in NATIONALITIES:
                continue
            # Coordinated creators ("written by X and Y", "X, Y and Z") are
            # ambiguous → drop. A trailing ", who …" relative clause is NOT
            # coordination and must survive.
            if rel.endswith("_by") and re.match(
                    r"\s*(?:(?:,\s*)?(?:&|and\b)\s+[A-Z]|,\s+[A-Z][a-z])",
                    clause[m.end("obj"):m.end("obj") + 14]):
                continue
            yr = m.groupdict().get("year")
            out.append({"relation": rel, "object": obj, "year": int(yr) if yr else None})
    return out

# ---------------------------------------------------------------------------
# Stage 1b — Infobox-direct facts (the structured oracle, highest precision)
# ---------------------------------------------------------------------------
# Curated key → relation map. Only SINGLE-VALUED keys: a value that cleaned to a
# list (multiple directors/authors) is dropped as ambiguous (gate 6). The
# infobox is ground truth, so these score higher than prose; when prose ALSO
# found the fact they dedup to one high-confidence fact.
# NB: 'artist' is deliberately absent — it means painter on an artwork infobox
# but recording-artist on an album infobox. Prose ("painting by X") handles
# paintings reliably; this avoids cross-type misattribution.
_INFOBOX_PERSON = {
    "director": "directed_by", "author": "written_by",
    "composer": "composed_by", "writer": "written_by", "novelist": "written_by",
}
_INFOBOX_YEAR = {"birth_date": "birth_year", "born": "birth_year",
                 "death_date": "death_year", "died": "death_year"}
# Keys that mark a person infobox (broader than just dates — Einstein's infobox
# has birth_place/death_place but no birth_date).
_PERSON_INFOBOX_KEYS = {
    "birth_date", "birth_year", "born", "death_date", "died", "birth_place",
    "death_place", "occupation", "nationality", "citizenship", "alma_mater",
    "spouse", "children", "known_for", "education", "parents", "relatives", "party",
}
# A clean person name: capitalized words + particles, nothing else (no digits,
# no parentheticals, no lowercase role words leaking in).
_PERSON_RE = re.compile(r"^[A-Z][\w.'’\-]*(?:\s+(?:de|da|van|von|del|della|di|du|le|la|the)?\s*[A-Z][\w.'’\-]*)*$")

def _infobox_value(infobox, key):
    """Return a single scalar value, or None if absent / multi-valued (list)."""
    v = infobox.get(key)
    if isinstance(v, list):
        return None   # multiple values → ambiguous forward question
    return v

def infobox_facts(infobox, title):
    out = []
    for key, rel in _INFOBOX_PERSON.items():
        v = _infobox_value(infobox, key)
        if not v:
            continue
        name = strip_wiki(str(v)).strip().strip(".,;")
        # Reject coordination, merged-name artifacts ("KrentzErik" from a
        # stripped <br> separator), and non-name junk; require a clean name.
        if re.search(r"\b(?:and|&|,|featuring|with)\b", name) or re.search(r"[a-z][A-Z]", name):
            continue
        if not _PERSON_RE.match(name):
            continue
        if not (3 <= len(name) <= 60) or subject_is_title(name, title):
            continue
        out.append({"relation": rel, "object": name, "year": None, "conf": 0.85})
    for key, rel in _INFOBOX_YEAR.items():
        v = _infobox_value(infobox, key)
        if not v:
            continue
        yr = _year(strip_wiki(str(v)))
        if yr and 0 < yr < 2026:
            out.append({"relation": rel, "object": str(yr), "year": yr, "conf": 0.92})
    return out

# ---------------------------------------------------------------------------
# Stage 1–8 — Orchestration
# ---------------------------------------------------------------------------

_META_TITLE = re.compile(r"^(lists?|index|outline|timeline|glossary|comparison)\s+of\b", re.I)

def extract_facts(article, max_body_sentences=12):
    """Return a list of scored, gated fact dicts for one article."""
    title = article["title"]
    if _META_TITLE.search(title) or "(disambiguation)" in title.lower():
        return []
    if "disambiguation" in (article.get("pageprops") or {}):
        return []

    infobox = parse_infobox(article.get("wikitext") or "")
    extract = article.get("extract") or ""
    # Body = text before the first "== Section ==" header is the lead.
    lead = re.split(r"\n==", extract, 1)[0]
    facts = []

    def add(relation, obj, value_type, precision, conf, year=None):
        facts.append({
            "subject": title, "relation": relation, "object": obj,
            "value_type": value_type, "precision": precision,
            "confidence": round(conf, 2), "year": year, "source_url": article.get("url", ""),
        })

    lead_sentences = segment(strip_wiki(lead))
    if not lead_sentences:
        return []

    # Stage 4 — definitional facts from the FIRST sentence only.
    s0 = lead_sentences[0]
    m = DEF_COPULA.match(s0)
    nationality_candidate = None
    # Person signal gates born/died/nationality so an empire's (800–887) is not
    # quizzed as a lifespan and a film is not given a "nationality". Bios use a
    # person infobox; some put dates only in the lead paren (so birth_place /
    # occupation etc. count too, not just birth_date).
    person_signal = any(k in infobox for k in _PERSON_INFOBOX_KEYS)
    if m and subject_is_title(m.group("subject"), title):
        for rel, val in split_type((m.group("type") or "").strip()):
            if rel == "nationality":
                nationality_candidate = val
            else:
                add(rel, val, "string", "exact", 0.85)
        paren = m.group("paren") or ""
        born_explicit = BORN_LABELED.search(paren) or BORN_LABELED.search(s0)
        lr = LIFE_RANGE.search(paren)
        if lr and (person_signal or born_explicit):
            by, dy = _year(lr.group("born")), _year(lr.group("died"))
            if by and 0 < by < 2026:
                add("birth_year", str(by), "year", "year",
                    0.9 + (0.05 if _born_matches(infobox, by) else 0), year=by)
            if dy and by and dy > by:
                add("death_year", str(dy), "year", "year", 0.88, year=dy)
        elif born_explicit:
            by = int(born_explicit.group(1))
            if 0 < by < 2026:
                add("birth_year", str(by), "year", "year", 0.85, year=by)
    if nationality_candidate and person_signal:
        add("nationality", nationality_candidate, "string", "exact", 0.85)

    # Stages 5–6 — relations from lead + early body, coref-resolved + gated.
    for idx, raw in enumerate(lead_sentences[:max_body_sentences]):
        sent = selfcontain(raw, title)
        # Split only on ';' — keep "X and Y" intact so coordinated creators are
        # detected and dropped (ambiguous), not silently reduced to one name.
        for clause in re.split(r";", sent):
            if not is_quizzable_stem_relaxed(clause, title):
                continue
            for tr in extract_relations(clause, title):
                # Creator attributions (_by) are trusted ONLY from the
                # definitional first sentence — a body "the cover was painted
                # by Y" misattributes to the title via coreference.
                if tr["relation"].endswith("_by") and idx != 0:
                    continue
                conf = 0.6 + (0.1 if idx == 0 else 0)
                add(tr["relation"], tr["object"], "string", "exact", conf, year=tr.get("year"))

    # Stage 1b — infobox-direct facts (structured ground truth). The infobox
    # WINS: drop prose facts for any relation the infobox covers, so a partial
    # prose name ("Coppola") never collides with the full infobox name
    # ("Francis Ford Coppola") and trips the multi-value gate.
    ib = infobox_facts(infobox, title)
    ib_rels = {f["relation"] for f in ib}
    facts[:] = [f for f in facts if f["relation"] not in ib_rels]
    for f in ib:
        add(f["relation"], f["object"], "string", "exact", f["conf"], year=f.get("year"))

    return _dedup_score_gate(facts, infobox)

def is_quizzable_stem_relaxed(clause, title):
    """A clause is usable if, after the title-subject is understood, no OTHER
    pronoun governs it. We allow the clause if it contains a known verb pattern
    target and isn't dominated by deixis pointing elsewhere."""
    # Reject hedge / NPOV / relative-time outright.
    if re.search(r"\b(alleged|so-called|reportedly|arguably|supposedly|"
                 r"currently|nowadays|recently|as of)\b", clause, re.I):
        return False
    return True

def _born_matches(infobox, year):
    for k in ("birth_date", "born", "birth_year"):
        v = infobox.get(k)
        if isinstance(v, list): v = " ".join(v)
        if v and str(year) in str(v):
            return True
    return False

def _dedup_score_gate(facts, infobox, threshold=0.55):
    seen, out = {}, []
    for f in facts:
        if f["confidence"] < threshold:
            continue
        key = (f["relation"], _normalize(str(f["object"])))
        if key in seen:
            seen[key]["confidence"] = max(seen[key]["confidence"], f["confidence"])
            continue
        seen[key] = f
        out.append(f)
    return out

# ---------------------------------------------------------------------------
# Question construction (fact → MCQ) with correct-by-construction distractors.
# ---------------------------------------------------------------------------

import random as _random

def _redact_subject(text, subject):
    """Blank the subject (and its bare form) from a displayed clue so the
    answer never leaks (QUESTION-QUALITY rule 6 / reject-funnel gate 2)."""
    bare = re.sub(r"\s*\([^)]*\)", "", subject).strip()
    out = text
    for needle in {subject, bare}:
        if needle:
            out = re.sub(re.escape(needle), "—", out, flags=re.I)
    return re.sub(r"\s{2,}", " ", out).strip()

def _type_bucket(facts):
    """Coarse type head-noun for a fact set (films vs novels vs people) so a
    'created_by' distractor never mixes a director with an author."""
    for f in facts:
        if f["relation"] == "type":
            head = re.findall(r"[a-z]+", str(f["object"]).lower())
            return head[-1] if head else None
    return None

def _year_distractors(year, rng, k=3):
    span = 4 if year >= 1900 else (15 if year >= 1700 else 80)
    pool = [year + d for d in range(-span, span + 1) if d != 0 and 0 < year + d <= 2026]
    rng.shuffle(pool)
    return [str(y) for y in pool[:k]]

# Each entry: (relation, stem_with_{subject}, value_type). The subject is shown
# (these aren't "name the subject" — they quiz a fact ABOUT a known subject).
# Only single-valued relations become forward MCQs (gate 6: unambiguous answer).
# 'won'/'founded'/active person→work relations are extracted but not quizzed
# forward here — they're multi-valued and would admit several correct answers.
_FACT_STEMS = {
    "birth_year":  ("In what year was {subject} born?", "year"),
    "death_year":  ("In what year did {subject} die?", "year"),
    "directed_by": ("Who directed {subject}?", "entity"),
    "written_by":  ("Who wrote {subject}?", "entity"),
    "composed_by": ("Who composed {subject}?", "entity"),
    "painted_by":  ("Who painted {subject}?", "entity"),
    "nationality": ("What was {subject}'s nationality?", "entity"),
}
# nationality draws from a global pool (any nationality is a fair distractor);
# creator relations bucket by work-type so a director never distracts a painter.
_GLOBAL_POOL_RELATIONS = {"nationality"}

def build_mcqs(pool, rng=None, category="general"):
    """pool: list of (title, facts) across many articles in one domain.
    Returns MCQ rows ready for corpus.sqlite. Distractors are drawn from
    SIBLING facts of the same relation + same type bucket, so every distractor
    is definitionally wrong for this subject (gate 2 holds by construction)."""
    rng = rng or _random.Random(0)

    def bucket_key(relation, bucket):
        return (relation, None if relation in _GLOBAL_POOL_RELATIONS else bucket)

    # Index sibling values per (relation, type-bucket) for entity distractors.
    by_rel = {}
    for title, facts in pool:
        bucket = _type_bucket(facts)
        for f in facts:
            if _FACT_STEMS.get(f["relation"], (None, None))[1] == "entity":
                by_rel.setdefault(bucket_key(f["relation"], bucket), set()).add(str(f["object"]))
    rows = []
    for title, facts in pool:
        bucket = _type_bucket(facts)
        # Multi-value gate: if a subject has >1 distinct value for a relation,
        # the forward question is ambiguous (two correct answers) — drop it.
        rel_values = {}
        for f in facts:
            if f["relation"] in _FACT_STEMS:
                rel_values.setdefault(f["relation"], set()).add(str(f["object"]).lower())
        for f in facts:
            spec = _FACT_STEMS.get(f["relation"])
            if not spec:
                continue
            if len(rel_values.get(f["relation"], ())) > 1:
                continue
            stem_t, kind = spec
            ans = str(f["object"])
            if kind == "year":
                ds = _year_distractors(int(f["year"]), rng)
            else:
                sibs = [v for v in by_rel.get(bucket_key(f["relation"], bucket), ()) if v.lower() != ans.lower()]
                if len(sibs) < 3:
                    continue
                ds = rng.sample(sibs, 3)
            stem = stem_t.format(subject=re.sub(r"\s*\([^)]*\)", "", title))
            opts = [ans] + ds
            rng.shuffle(opts)
            rows.append({
                "subject": title, "relation": f["relation"], "prompt": stem,
                "options": opts, "answer": ans, "correct_index": opts.index(ans),
                "confidence": f["confidence"], "source_url": f.get("source_url", ""),
            })
    return rows

# ---------------------------------------------------------------------------
# Verification demo — observe the extraction before trusting it.
# ---------------------------------------------------------------------------

def _demo(titles):
    for t in titles:
        print(f"\n{'='*70}\n{t}\n{'='*70}")
        art = fetch_article(t)
        if not art.get("extract"):
            print("  (no extract — fetch failed or missing article)"); continue
        ib = parse_infobox(art.get("wikitext") or "")
        print(f"  infobox keys: {sorted(ib)[:18]}")
        facts = extract_facts(art)
        if not facts:
            print("  (no facts survived the gates)"); continue
        for f in facts:
            yr = f" [{f['year']}]" if f["year"] else ""
            print(f"  • {f['relation']:14s} = {str(f['object'])[:55]:57s} "
                  f"conf={f['confidence']}{yr}")

def _demo_mcq(titles):
    pool = []
    for t in titles:
        art = fetch_article(t)
        if art.get("extract"):
            pool.append((art["title"], extract_facts(art)))
    rng = _random.Random(42)
    rows = build_mcqs(pool, rng)
    print(f"\n{len(rows)} MCQs built from {len(pool)} articles:\n")
    for r in rows:
        print(f"  Q: {r['prompt']}")
        for i, o in enumerate(r["options"]):
            mark = " ✓" if i == r["correct_index"] else "  "
            print(f"      {mark} {o}")
        print()

if __name__ == "__main__":
    args = sys.argv[1:]
    mcq = "--mcq" in args
    titles = [a for a in args if a != "--mcq"] or \
        ["Marie Curie", "Mount Everest", "The Godfather", "Tokyo", "Albert Einstein", "Mona Lisa"]
    (_demo_mcq if mcq else _demo)(titles)
