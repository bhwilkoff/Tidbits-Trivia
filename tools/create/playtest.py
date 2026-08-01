"""Play-test the Create feature over a large topic list and flag TOPIC DRIFT.

`coverage.py` answers "can the corpus fill a quiz for this topic?" (a count).
This answers the harder question the owner actually asked: **are the questions
about the thing the player typed?** Type "Denver" and a quiz about John Denver's
discography is a full quiz and a complete failure.

It mirrors the shipped Swift `CorpusDatabase.search` exactly (same tokens, same
OR pre-filter, same score, same top-tier + diversify), then labels every selected
question with a drift class:

  substr  the typed word appears only INSIDE a longer word ("art" in "Mozart")
  entity  the corpus has rows titled exactly the topic, but this row is a
          DIFFERENT named entity that merely contains the word ("John Denver")
  offtext neither the title nor the prompt contains any typed word — the row
          was matched through explanation/tags noise alone

    python3 tools/create/playtest.py                 # top1000.txt, summary
    python3 tools/create/playtest.py --topic Denver  # one topic, full detail
    python3 tools/create/playtest.py --worst 40      # the 40 driftiest topics
"""
import sqlite3, sys, re, math, collections, unicodedata, pathlib

DB = "TidbitsTrivia/Resources/corpus.sqlite"
TARGET = 8
STOPWORDS = {"the", "and", "for", "with", "from", "that", "this", "his", "her", "its",
             "was", "were", "are", "who", "what", "which", "how", "why", "all", "any"}


def fold(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s or "") if not unicodedata.combining(c)).lower()


def strip_parens(s):
    out, depth = "", 0
    for c in s or "":
        if c in "([":
            depth += 1
        elif c in ")]":
            depth = max(0, depth - 1)
        elif depth == 0:
            out += c
    return out.strip()


def tokens(topic):
    # Mirrors the shipped `topicTokens`: a Wikipedia disambiguator is not part of
    # what the player means, so it must not count as a topic word here either —
    # otherwise "Toy Story (franchise)" reports every Toy Story film as drift.
    t = "".join(c if c.isalnum() else " " for c in fold(strip_parens(topic))).split()
    raw = [x for x in t if len(x) >= 3]
    kept = [x for x in raw if x not in STOPWORDS]
    return kept or raw


def word_in(token, text):
    return re.search(r"(?<![a-z0-9])" + re.escape(token) + r"(?![a-z0-9])", text) is not None


COLS = ("id,prompt,option0,option1,option2,option3,correct_index,category_id,difficulty,"
        "explanation,source_title,tags")


CAP = 4000


def candidates(cur, toks, cap=None):
    clause = " OR ".join(
        "(lower(prompt) LIKE ? OR lower(source_title) LIKE ? OR lower(explanation) LIKE ? "
        "OR lower(tags) LIKE ? OR search_text LIKE ?)" for _ in toks)
    args = []
    for t in toks:
        args += [f"%{t}%"] * 5
    lim = f" LIMIT {cap}" if cap else ""
    cur.execute(f"SELECT {COLS} FROM questions WHERE {clause}{lim}", args)
    return cur.fetchall()


# ---------------------------------------------------------------- v2 selection

def phrase_of(topic):
    return " ".join(tokens(topic))


def admitting_tags(tags, phrase):
    """Tags are Wikipedia CATEGORIES, and only some of them mean "about".

    "Albums produced by Michael Jackson" makes a Thriller question a Michael
    Jackson question. "Actresses from Denver" does NOT make a Kristin Cavallari
    birth-year question a Denver question — it is where she happens to be from,
    and the question the player reads never mentions Denver at all.

    The preposition is the whole signal: `by`/`of` are agentive or possessive
    ("Songs written by", "Mayors of"), `from`/`in`/`at` are incidental. A tag
    that LEADS with the topic ("Michael Jackson songs") is agentive too.
    """
    out = []
    for t in tags:
        # Deliberately NOT "the tag starts with the topic": that admitted
        # "Abraham Lincoln High School (Brooklyn) alumni" (so a Lincoln quiz asked
        # Neil Sedaka's birth year) and "Artificial intelligence companies" (so an
        # AI quiz asked when Salesforce was founded). A leading topic is usually a
        # DIFFERENT entity that merely begins with the same words.
        if re.search(r"\b(by|of)\s+(?:the\s+)?" + re.escape(phrase) + r"(?![a-z0-9])", t):
            out.append(t)
    return out


PERSONISH = re.compile(r"^[a-z]+ [a-z]+$")


def tier_of(row, toks, phrase, single_guard):
    """Relevance TIER, or None to reject outright.

    3 the row's subject IS the topic (title or a tag equals it)
    2 the whole typed phrase appears, word-bounded, in the title or tags
    1 every typed word appears, word-bounded, in the title or tags
    0 every typed word appears, word-bounded, across title/tags/prompt

    Explanation text never buys acceptance — it is where the "Madeleine Albright
    was in Denver once" class of false hit comes from — though it still scores.
    """
    f_title = fold(row["title"])
    subject = " ".join(tokens(row["title"]))
    admit_tags = " ".join(admitting_tags(row["tags"], phrase))
    if subject == phrase:
        return 3
    if word_in(phrase, f_title):
        # When the typed word is ITSELF a subject in this corpus, a bare two-word
        # title that merely contains it is a different named thing — "Bob Denver",
        # "Denver Pyle", "Samuel Adams". The player typed the place, not the person.
        if single_guard and PERSONISH.match(subject):
            return None
        return 2
    need = len(toks) if len(toks) <= 2 else len(toks) - 1
    if sum(1 for t in toks if word_in(t, f_title)) >= need:
        return 1
    # The player must be able to SEE what they typed: admission comes from the
    # title or the prompt/options they read — never from the explanation alone,
    # which is where the "she once taught in Denver" class of false hit lives.
    # NOT the options: on the simulator that made the topic match as a DISTRACTOR
    # ("Zlatan Ibrahimović" returned a picture of Neymar), and the giveaway rule
    # had already removed every row where the topic was the correct answer.
    read = f_title + " " + fold(row["prompt"])
    if sum(1 for t in toks if word_in(t, read)) >= need:
        return 0
    # An agentive tag ("Albums produced by Michael Jackson") is a real connection
    # but an INVISIBLE one — the question never says so. Last resort only.
    if admit_tags:
        return -1
    return None


def select_v2(cur, topic, limit=TARGET):
    toks = tokens(topic)
    if not toks:
        return [], toks
    phrase = " ".join(toks)
    rows = candidates(cur, toks, cap=None)
    # Does the typed thing exist as its own subject? That is what licenses the
    # surname guard: "Denver" is a place in this corpus, so "Bob Denver" is a
    # different entity. "Potter" is not a subject, so "Harry Potter" is the
    # best reading of it.
    single_guard = False
    if len(toks) == 1:
        for r in rows:
            if " ".join(tokens(r[10])) == phrase:
                single_guard = True
                break
    clean, reserve = [], []
    for r in rows:
        (qid, prompt, o0, o1, o2, o3, ci, cat, diff, expl, title, tags) = r
        if qid.startswith("src:continent:") or (diff or 2) <= 1:
            continue
        row = dict(id=qid, prompt=prompt, title=title, cat=cat, diff=diff,
                   answer=[o0, o1, o2, o3][ci or 0], expl=expl, options=[o0, o1, o2, o3],
                   tags=[fold(x) for x in (tags or "").split("|") if x])
        tier = tier_of(row, toks, phrase, single_guard)
        if tier is None:
            continue
        f_title, f_prompt, f_expl = fold(title), fold(prompt), fold(expl)
        row["tier"] = tier
        row["matched"] = tier
        row["score"] = sum(
            (3 if any(word_in(t, x) for x in row["tags"]) else 0)
            + (2 if word_in(t, f_title) else 0)
            + (1 if word_in(t, f_prompt) else 0)
            + (1 if word_in(t, f_expl) else 0) for t in toks)
        (reserve if any(word_in(t, fold(row["answer"])) for t in toks) else clean).append(row)

    def take(pool):
        out = []
        for tier in (3, 2, 1, 0, -1):
            if len(out) >= limit:
                break
            lane = sorted([x for x in pool if x["tier"] == tier], key=lambda x: -x["score"])
            out += diversify(lane, limit - len(out))
        return out[:limit]

    out = take(clean)
    if len(out) < limit:
        taken = {x["id"] for x in out}
        out += [x for x in take(reserve) if x["id"] not in taken][: limit - len(out)]
    return out, toks


def select(cur, topic, limit=TARGET):
    """The shipped selection, returning the rows a player would actually see."""
    toks = tokens(topic)
    if not toks:
        return [], toks
    clean, reserve = [], []
    for r in candidates(cur, toks):
        (qid, prompt, o0, o1, o2, o3, ci, cat, diff, expl, title, tags) = r
        if qid.startswith("src:continent:") or (diff or 2) <= 1:
            continue
        f_title, f_prompt, f_expl = fold(title), fold(prompt), fold(expl)
        f_tags = [fold(x) for x in (tags or "").split("|") if x]
        score = 0
        matched = 0
        for t in toks:
            hit = False
            if any(t in x for x in f_tags):
                score += 3; hit = True
            if t in f_title:
                score += 2; hit = True
            if t in f_prompt:
                score += 1; hit = True
            if t in f_expl:
                score += 1; hit = True
            matched += 1 if hit else 0
        if matched == 0:
            continue
        answer = [o0, o1, o2, o3][ci or 0]
        row = dict(id=qid, prompt=prompt, title=title, cat=cat, diff=diff, options=[o0, o1, o2, o3],
                   answer=answer, expl=expl, tags=f_tags, score=score, matched=matched)
        (reserve if any(t in fold(answer) for t in toks) else clean).append(row)

    def top_tier(rs):
        if not rs:
            return []
        b = max(x["matched"] for x in rs)
        return sorted([x for x in rs if x["matched"] == b], key=lambda x: -x["score"])

    ranked = top_tier(clean)
    out = diversify(ranked, limit)
    if len(out) < limit:
        taken = {x["id"] for x in out}
        out += [x for x in top_tier(reserve) if x["id"] not in taken][: limit - len(out)]
    return out, toks


def diversify(ranked, limit):
    per_cat = max(2, math.ceil(limit / 3))
    lanes, order = {}, []
    for q in ranked:
        c = q["cat"]
        if c not in lanes:
            lanes[c] = []; order.append(c)
        if len(lanes[c]) < per_cat:
            lanes[c].append(q)
    out, progressed = [], True
    while len(out) < limit and progressed:
        progressed = False
        for c in order:
            if lanes.get(c):
                out.append(lanes[c].pop(0)); progressed = True
                if len(out) >= limit:
                    break
    if len(out) < limit:
        taken = {x["id"] for x in out}
        out += [x for x in ranked if x["id"] not in taken][: limit - len(out)]
    return out


def exact_title_exists(cur, topic):
    cur.execute("SELECT 1 FROM questions WHERE lower(source_title) = ? LIMIT 1", (fold(topic),))
    return cur.fetchone() is not None


def drift(row, toks, topic, has_exact):
    """Label a selected row against what the PLAYER can see. Empty = on-topic.

    invisible  the typed words never appear in the title, prompt or options —
               whatever the retrieval thought, the player reads a question with
               no visible connection to what they asked for
    substr     the words appear only inside longer words ("art" in "Mozart")
    entity     the typed thing is its own subject here, and this row is a
               different named subject that merely contains the word
    """
    f_title, f_prompt = fold(row["title"]), fold(row["prompt"])
    hay = f_title + " " + f_prompt + " " + fold(" ".join(row.get("options", [])))
    if not any(t in hay for t in toks):
        return "invisible"
    if not any(word_in(t, hay) for t in toks):
        return "substr"
    # A ROW title keeps its disambiguator — that is what the shipped rule does,
    # because the parenthetical carries meaning there ("Dangerous (Michael Jackson
    # album)"). Stripping it here reported "Estado Novo (Portugal)" as a two-word
    # personal name and flagged every Toy Story film as drift on the franchise.
    subject = " ".join(x for x in re.split(r"[^a-z0-9]+", f_title) if x)
    # Compare against the whole typed phrase, not the significant tokens: "He-Man"
    # reduces to the token "man", and comparing to that called the He-Man rows
    # themselves drift.
    topic_flat = " ".join(x for x in re.split(r"[^a-z0-9]+", fold(strip_parens(topic))) if x)
    if has_exact and subject not in (topic_flat, " ".join(toks)):
        if PERSONISH.match(subject) and any(word_in(t, f_title) for t in toks):
            return "entity"
    return ""


def run(topics, limit=TARGET, v2=False):
    con = sqlite3.connect(DB)
    cur = con.cursor()
    picker = select_v2 if v2 else select
    rows = []
    for topic in topics:
        sel, toks = picker(cur, topic, limit)
        has_exact = exact_title_exists(cur, topic)
        flags = [drift(r, toks, topic, has_exact) for r in sel]
        rows.append(dict(topic=topic, n=len(sel), sel=sel, flags=flags,
                         bad=sum(1 for f in flags if f),
                         classes=collections.Counter(f for f in flags if f)))
    return rows


def read_sweep(path):
    """Score a SWEEP-Q log emitted by the app itself (TIDBITS_CREATE_SWEEP).

    This is the measurement that counts: the lines came out of the shipped Swift
    running against the bundled corpus on a simulator, not out of a Python
    re-implementation that could agree with itself while the app disagrees.
    """
    con = sqlite3.connect(DB)
    cur = con.cursor()
    by_topic = collections.OrderedDict()
    for line in pathlib.Path(path).read_text(errors="replace").splitlines():
        if line.startswith("SWEEP-TOPIC\t"):
            _, topic, n = line.split("\t")[:3]
            by_topic.setdefault(topic, [])
        elif line.startswith("SWEEP-Q\t"):
            p = line.split("\t")
            if len(p) < 7:
                continue
            by_topic.setdefault(p[1], []).append(
                dict(id=p[2], title=p[3], cat=p[4], prompt=p[5], answer=p[6], options=[p[6]]))
    out = []
    for topic, qs in by_topic.items():
        toks = tokens(topic)
        has_exact = exact_title_exists(cur, topic)
        flags = [drift(q, toks, topic, has_exact) for q in qs]
        out.append(dict(topic=topic, n=len(qs), sel=qs, flags=flags,
                        bad=sum(1 for f in flags if f),
                        classes=collections.Counter(f for f in flags if f)))
    return out


def main():
    args = sys.argv[1:]
    if "--sweep" in args:
        rows = read_sweep(args[args.index("--sweep") + 1])
        tot = sum(r["n"] for r in rows)
        bad = sum(r["bad"] for r in rows)
        classes = collections.Counter()
        for r in rows:
            classes.update(r["classes"])
        empty = [r for r in rows if r["n"] == 0]
        print(f"topics={len(rows)}  questions={tot}  drifting={bad} "
              f"({bad/max(1,tot):.1%})  {dict(classes)}  empty={len(empty)}")
        for r in sorted(rows, key=lambda r: -r["bad"])[:20]:
            if not r["bad"]:
                break
            print(f"  {r['bad']}/{r['n']}  {r['topic']}   {dict(r['classes'])}")
            for q, f in zip(r["sel"], r["flags"]):
                if f:
                    print(f"      [{f}] {q['title']!r} :: {q['prompt'][:90]}")
        return
    limit = TARGET
    v2 = "--v2" in args
    if "--topic" in args:
        topic = args[args.index("--topic") + 1]
        r = run([topic], limit, v2)[0]
        print(f"TOPIC: {topic}   {r['n']} questions, {r['bad']} drifting {dict(r['classes'])}")
        for q, f in zip(r["sel"], r["flags"]):
            print(f"  [{f or 'ok':7}] ({q['cat']}/{q['diff']} s={q['score']}) {q['title']!r}")
            print(f"            {q['prompt']}")
            print(f"            -> {q['answer']}")
        return
    path = pathlib.Path("tools/create/top1000.txt")
    topics = [l.strip() for l in path.read_text().splitlines() if l.strip()]
    rows = run(topics, limit, v2)
    tot = sum(r["n"] for r in rows)
    bad = sum(r["bad"] for r in rows)
    classes = collections.Counter()
    for r in rows:
        classes.update(r["classes"])
    empty = [r for r in rows if r["n"] == 0]
    thin = [r for r in rows if 0 < r["n"] < limit]
    print(f"topics={len(rows)}  questions={tot}  drifting={bad} ({bad/max(1,tot):.1%})  {dict(classes)}")
    print(f"empty={len(empty)}  thin={len(thin)}  full={len(rows)-len(empty)-len(thin)}")
    if "--worst" in args:
        n = int(args[args.index("--worst") + 1])
        for r in sorted(rows, key=lambda r: -r["bad"])[:n]:
            print(f"  {r['bad']}/{r['n']}  {r['topic']}   {dict(r['classes'])}")
    if "--empty" in args:
        for r in empty:
            print("  EMPTY:", r["topic"])


if __name__ == "__main__":
    main()
