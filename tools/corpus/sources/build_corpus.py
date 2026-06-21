#!/usr/bin/env python3
"""Stage D.2 — export corpus_source.sqlite -> assets/corpus.json (Decision 032).

Produces the main MCQ corpus the app ships AND the structured rows the bundled-set
generators mine — all in the existing corpus.json row shape, so the whole
downstream pipeline (gen_*.py) runs on it unchanged:

  row = [id, prompt, options[4], correctIndex, category, difficulty,
         explanation, sourceTitle(URL-title), sourceURL]

Rows emitted:
  - descriptionOf MCQ per subject with a clean Wikidata short-description or lead
    sentence (answer = subject; 3 distractors = same-category, nearest-Qrank →
    same kind, same fame = genuinely plausible). Difficulty = Qrank quintile.
  - wd:continent:* rows from the P30 relation (Odd-one-out Q3 + Enumerate Q8).

Deferred to the next pass (need relation-target label resolution): wd:capital /
wd:currency / wd:elemSymbol / wd:author rows for Matching (Q5).

Run AFTER enrich_subjects.py + fetch_prose.py. Usage: python3 build_corpus.py
"""
import hashlib, json, os, re, sqlite3

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
OUT = os.path.join(ROOT, "assets", "corpus.json")
ANDROID_JSON = os.path.join(ROOT, "android", "app", "src", "main", "assets", "corpus.json")
IOS_SQLITE = os.path.join(ROOT, "TidbitsTrivia", "Resources", "corpus.sqlite")


def write_sqlite(rows, path):
    """iOS reads corpus.sqlite (12-col questions table — see DATA-CONTRACT)."""
    import sqlite3 as s3
    if os.path.exists(path):
        os.remove(path)
    c = s3.connect(path)
    c.execute("""CREATE TABLE questions (id TEXT PRIMARY KEY, prompt TEXT,
        option0 TEXT, option1 TEXT, option2 TEXT, option3 TEXT, correct_index INTEGER,
        category_id TEXT, difficulty INTEGER, explanation TEXT, source_title TEXT, source_url TEXT)""")
    c.executemany("INSERT OR REPLACE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                  [(r[0], r[1], r[2][0], r[2][1], r[2][2], r[2][3], r[3], r[4], r[5], r[6], r[7], r[8])
                   for r in rows])
    c.commit(); c.close()

CONTINENT = {  # P30 target QID -> display name
    "Q15": "Africa", "Q46": "Europe", "Q48": "Asia", "Q49": "North America",
    "Q18": "South America", "Q538": "Oceania", "Q55643": "Oceania", "Q51": "Antarctica",
}
CAT_NOUN = {"history": "figure or event", "science": "subject", "geography": "place",
            "arts": "work or artist", "screen": "film, show, or star", "music": "musician or work",
            "sports": "sports figure", "mixed": "subject"}


def url_title(title):
    return title.replace(" ", "_")

def leaks(answer, text):
    """True if the description gives the answer away (a title word appears in it)."""
    t = text.lower()
    for w in re.findall(r"[a-z']{4,}", answer.lower()):
        if w in t:
            return True
    return False

def first_sentence(lead):
    m = re.split(r"(?<=[.!?])\s", lead.strip())
    return m[0] if m else lead

def make_cloze(title, lead):
    """Mask the subject in its own lead sentence → a fill-the-blank MCQ stem.
    Returns the masked sentence, or None if it can't be masked cleanly."""
    s = first_sentence(lead or "").strip()
    if not (25 <= len(s) <= 240):
        return None
    words = [w for w in re.findall(r"[A-Za-z']+", title) if len(w) > 3]
    if not words:
        return None
    masked, hit = s, False
    for w in words:
        new = re.sub(rf"\b{re.escape(w)}\b", "____", masked, flags=re.IGNORECASE)
        if new != masked:
            masked, hit = new, True
    if not hit or leaks(title, masked.replace("____", " ")):
        return None
    return masked


def main():
    con = sqlite3.connect(DB)
    subs = con.execute("""SELECT qid, title, category, qrank FROM subject
                          WHERE keep=1 AND category IS NOT NULL ORDER BY qrank DESC""").fetchall()
    prose = {q: (lead, desc) for q, t, lead, desc in
             con.execute("SELECT qid, title, lead, description FROM prose").fetchall()}
    continents = {}
    for qid, prop, label, tq in con.execute("SELECT qid, prop, label, target_qid FROM relation WHERE label='continent'"):
        if tq in CONTINENT:
            continents[qid] = CONTINENT[tq]

    # difficulty = Qrank quintile over kept subjects (1 = most popular/easiest)
    ranks = sorted((s[3] for s in subs), reverse=True)
    n = len(ranks)
    thresh = [ranks[min(n - 1, n * k // 5)] for k in range(1, 5)]  # 4 cut points
    def difficulty(qr):
        for i, t in enumerate(thresh):
            if qr >= t:
                return i + 1
        return 5

    # group by category (sorted by qrank) for nearest-fame distractors
    by_cat = {}
    for qid, title, cat, qr in subs:
        by_cat.setdefault(cat, []).append((qid, title, qr))
    title_of = {s[0]: s[1] for s in subs}
    qr_of = {s[0]: s[3] for s in subs}

    # clickstream confusables (Stage 2): title -> [neighbour subjects], strongest first.
    # Empirically-confused subjects make the most plausible distractors. Absent
    # until fetch_clickstream.py has run — fall back to nearest-Qrank then.
    confus = {}
    try:
        for t, nb in con.execute("SELECT title, neighbour FROM related ORDER BY n DESC"):
            confus.setdefault(t, []).append(nb)
    except sqlite3.OperationalError:
        pass

    out = []
    made_desc = made_cloze = 0
    for cat, members in by_cat.items():
        titles = [m[1] for m in members]               # already qrank-desc
        cat_set = set(titles)
        for idx, (qid, title, qr) in enumerate(members):
            lead, desc = prose.get(qid, ("", ""))
            # Distractors: prefer clickstream-confusable subjects OF THE SAME
            # category (same type + genuinely confused), then fill with
            # nearest-Qrank (same fame). Shared by both question shapes.
            distractors = []
            for nb in confus.get(title, []):
                if nb != title and nb in cat_set and nb not in distractors:
                    distractors.append(nb)
                if len(distractors) == 3:
                    break
            if len(distractors) < 3:
                near = [titles[j] for j in range(max(0, idx - 4), min(len(titles), idx + 5))
                        if titles[j] != title and titles[j] not in distractors]
                near += [t for t in titles if t != title and t not in distractors and t not in near]
                distractors += near[:3 - len(distractors)]
            if len(distractors) < 3:
                continue
            distractors = distractors[:3]

            def emit(template, prompt, expl, salt):
                options = distractors + [title]
                h = int(hashlib.md5((qid + template + salt).encode()).hexdigest(), 16)
                ci = h % 4
                options[3], options[ci] = options[ci], options[3]
                out.append([f"src:{template}:{url_title(title)}", prompt, options, ci, cat,
                            difficulty(qr), expl, title,   # q[7] = spaced display title
                            f"https://en.wikipedia.org/wiki/{url_title(title)}"])

            # describe — from the Wikidata short description (fall back to lead sentence)
            clue = (desc or "").strip()
            if not (clue and len(clue) >= 8 and not leaks(title, clue)):
                fs = first_sentence(lead) if lead else ""
                clue = fs if (fs and len(fs) > 25 and not leaks(title, fs)) else ""
            if clue:
                emit("describe", f"Which {CAT_NOUN.get(cat, 'subject')} is this: “{clue}”?",
                     f"{title}: {clue}", "d")
                made_desc += 1
            # cloze — mask the subject in its own lead sentence (variety + type-answer source)
            cz = make_cloze(title, lead) if lead else None
            if cz:
                emit("cloze", f"Fill in the blank: “{cz}”", f"{title} — {cz}", "c")
                made_cloze += 1

    # Relation MCQs — regenerated from the resolved 1:1 relations (Matching source
    # for gen_match + bonus Classic variety). Each is a real MCQ (correct value +
    # 3 distractor values drawn from the same relation's value pool).
    REL_PROMPT = {"capital": ("What is the capital of {k}?", "geography"),
                  "currency": ("What currency is used in {k}?", "geography"),
                  "author": ("Who wrote {k}?", "arts"),
                  "composer": ("Who composed {k}?", "music"),
                  "director": ("Who directed {k}?", "screen")}
    rel_rows = con.execute("""SELECT qid, label, target_label FROM relation
        WHERE target_label IS NOT NULL AND label IN ('capital','currency','author','composer','director')""").fetchall()
    pools = {}
    for qid, lbl, tl in rel_rows:
        pools.setdefault(lbl, []).append(tl)
    median_qr = sorted(qr_of.values())[len(qr_of) // 2] if qr_of else 0
    made_rel = 0
    seen_rel = set()
    for qid, lbl, tl in rel_rows:
        key = title_of.get(qid)
        if not key or not tl or (qid, lbl) in seen_rel:
            continue
        seen_rel.add((qid, lbl))
        pool = pools[lbl]
        if len(set(pool)) < 4:
            continue
        h = int(hashlib.md5((qid + lbl).encode()).hexdigest(), 16)
        ds, i, step = [], h % len(pool), 1 + (h % 7)
        guard = 0
        while len(ds) < 3 and guard < len(pool) * 2:
            v = pool[i % len(pool)]; i += step; guard += 1
            if v != tl and v not in ds:
                ds.append(v)
        if len(ds) < 3:
            continue
        prompt_t, rcat = REL_PROMPT[lbl]
        opts = ds + [tl]
        ci = h % 4
        opts[3], opts[ci] = opts[ci], opts[3]
        out.append([f"wd:{lbl}:{qid}", prompt_t.format(k=key), opts, ci, rcat,
                    difficulty(qr_of.get(qid, median_qr)), f"{key} → {tl}", key,
                    f"https://en.wikipedia.org/wiki/{url_title(key)}"])
        made_rel += 1

    # wd:continent rows (Odd-one-out + Enumerate source)
    all_conts = ["Africa", "Europe", "Asia", "North America", "South America", "Oceania"]
    made_cont = 0
    for qid, cont in continents.items():
        title = title_of.get(qid)
        if not title:
            continue
        others = [c for c in all_conts if c != cont]
        h = int(hashlib.md5(qid.encode()).hexdigest(), 16)
        opts = others[:3] + [cont]
        ci = h % 4
        opts[3], opts[ci] = opts[ci], opts[3]
        out.append([f"wd:continent:{qid}", f"On which continent is {title}?", opts, ci,
                    "geography", 2, f"{title} is in {cont}.", title,   # q[7] = spaced display title
                    f"https://en.wikipedia.org/wiki/{url_title(title)}"])
        made_cont += 1

    # Carry forward wd:elemSymbol (element → symbol; P246 is a string we don't
    # fetch yet) AND union the old wd:continent rows with the new ones (the old
    # corpus covered more countries; gen_oddoneout/enumerate dedupe by country).
    # Everything else structured (capital/currency/author/composer/director) is now
    # regenerated above from the resolved relations.
    carried = 0
    seen_cont = {r[7] for r in out if r[0].startswith("wd:continent:")}
    if os.path.exists(OUT):
        try:
            old = json.load(open(OUT)).get("questions", [])
            for r in old:
                rid = r[0] if r else ""
                if not isinstance(rid, str):
                    continue
                if rid.startswith("wd:elemSymbol:"):
                    out.append(r); carried += 1
                elif rid.startswith("wd:continent:") and r[7] not in seen_cont:
                    out.append(r); carried += 1
        except Exception:
            pass

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    for p in (OUT, ANDROID_JSON):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(payload)
    write_sqlite(out, IOS_SQLITE)   # iOS reads the SQLite mirror

    by_cat_n = {}
    for r in out:
        if r[0].startswith("src:describe:"):
            by_cat_n[r[4]] = by_cat_n.get(r[4], 0) + 1
    print(f"wrote {OUT}")
    print(f"  total rows: {len(out):,}  (describe {made_desc:,} / cloze {made_cloze:,} / relation-MCQ {made_rel:,} / continent {made_cont:,} / elemSymbol-carried {carried:,})")
    print(f"  clickstream confusables loaded for {len(confus):,} subjects")
    print(f"  descriptionOf by category: {dict(sorted(by_cat_n.items(), key=lambda x:-x[1]))}")
    con.close()


if __name__ == "__main__":
    main()
