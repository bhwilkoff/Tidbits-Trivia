"""Fetch business subjects from Wikidata, because the pipeline has none left.

Decision 050 measured "Mixed Bag" as 29.8% Film & TV against 2.5% business, and
preferred growing the thin categories over changing the draw. Half of that turned
out to be impossible: the Stage C source holds 1,207 unused SCIENCE subjects and
ZERO unused business ones. Business cannot be grown from what was already
fetched, so this fetches more.

Four question shapes, each chosen because the fact is single-valued and
structurally checkable — the same property that made the original wd:* questions
safe:

    founder      Who founded Patagonia?
    inception    In what year was Patagonia founded?      (kept SPARSE — see below)
    country      In which country is Patagonia based?
    industry     What industry is Patagonia in?

The inception shape is capped hard. Bare date questions were 22.9% of the corpus
and 41% of rounds carried three or more of them before prune_date_padding.py cut
18,004 of them; re-importing thousands here would undo that in the name of
fixing a different problem.

Distractors are drawn from the SAME shape's value pool (companies for a company
answer, people for a founder answer, countries for a country answer), which is
what keeps KIND-MISMATCH and NATIONALITY-FREE quiet by construction rather than
by repair.

    python3 tools/corpus/fetch_business.py --fetch     # live WDQS, ~20s between queries
    python3 tools/corpus/fetch_business.py --apply     # emit rows into assets/corpus.json

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import hashlib
import json
import pathlib
import random
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import wikidata as wd                                             # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
CACHE = pathlib.Path(__file__).resolve().parent / "cache" / "business.json"
RNG = random.Random(20260802)

# Sitelink floor: a company nobody has written about in 40 languages is not a
# company a player has heard of, and an unrecognisable subject is what made the
# pruned date questions worthless.
SITELINKS = 40
MAX_INCEPTION_ROWS = 400


QUERY = """SELECT ?item ?itemLabel ?founderLabel ?inception ?countryLabel
                  ?industryLabel ?desc ?sl WHERE {
  ?item wdt:P31/wdt:P279* wd:Q4830453 .
  ?item wikibase:sitelinks ?sl . FILTER(?sl >= %d)
  OPTIONAL { ?item wdt:P112 ?founder . }
  OPTIONAL { ?item wdt:P571 ?inception . }
  OPTIONAL { ?item wdt:P17  ?country . }
  OPTIONAL { ?item wdt:P452 ?industry . }
  OPTIONAL { ?item schema:description ?desc . FILTER(LANG(?desc) = "en") }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} LIMIT 3000"""


def fetch(live):
    if CACHE.exists():
        print(f"[business] cache hit: {CACHE}")
        return json.loads(CACHE.read_text())
    if not live:
        print("[business] no cache and --fetch not given; nothing to do")
        return []
    print(f"[business] querying WDQS for companies with >= {SITELINKS} sitelinks…")
    rows = wd.sparql(QUERY % SITELINKS)
    out = []
    for r in rows:
        out.append({
            "name": wd.clean(wd.val(r, "itemLabel")),
            "founder": wd.clean(wd.val(r, "founderLabel")),
            "inception": wd.year_of(wd.val(r, "inception")),
            "country": wd.clean(wd.val(r, "countryLabel")),
            "industry": wd.clean(wd.val(r, "industryLabel")),
            "desc": wd.clean(wd.val(r, "desc")),
            "sitelinks": int(wd.val(r, "sl") or 0),
        })
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(out, ensure_ascii=False))
    print(f"[business] {len(out)} rows cached")
    return out


# A subject whose NAME needs a definite article ("the National Football League",
# "the European Central Bank") is dropped rather than guessed at. Every template
# here puts the name after a preposition — "In which country is X based?" — so a
# missing article is audible, and the rules that would catch it (MISSING-ARTICLE)
# key on suffixes these names do not have. Guessing the article wrong is how
# "the Sudan" and "the Death Valley" nearly shipped; 28 subjects is a cheap loss.
NEEDS_ARTICLE = re.compile(
    r"^(World|United|European|International|National|Royal|Federal|Global)\b"
    r"|\b(League|Association|Organization|Organisation|Commission|Council|Fund|"
    r"Authority|Agency|Union|Alliance|Federation|Consortium)$")

# Not a business, whatever Wikidata's subclass graph says. The description is the
# tell: an agency of the UN is not a company, and filing it under BUSINESS is the
# same defect as Netflix under music.
NOT_A_BUSINESS = re.compile(
    r"\b(United Nations|intergovernmental|specialized agency|"
    r"international organization|international financial institution|"
    r"agency of the|non-governmental)\b", re.I)


def merge(rows):
    """One record per company; Wikidata returns a row per value combination."""
    by = {}
    for r in rows:
        n = r["name"]
        if not n or (n.startswith("Q") and n[1:].isdigit()):
            continue
        if NEEDS_ARTICLE.search(n) or NOT_A_BUSINESS.search(r["desc"] or ""):
            continue
        cur = by.setdefault(n, {"name": n, "founders": set(), "countries": set(),
                                "industries": set(), "inception": None,
                                "desc": r["desc"], "sitelinks": r["sitelinks"]})
        for key, field in (("founder", "founders"), ("country", "countries"),
                           ("industry", "industries")):
            if r[key]:
                cur[field].add(r[key])
        if r["inception"]:
            cur["inception"] = r["inception"]
    return by


def stem(shape, name, i):
    """Several true phrasings per shape, picked by hash — PROMPT-REPETITION caps
    any single prompt at 1% of the corpus, and one stem over thousands of rows
    would breach it on its own."""
    banks = {
        "founder": [f"Who founded {name}?", f"Which person founded {name}?",
                    f"{name} was founded by whom?", f"Who started {name}?"],
        "country": [f"In which country is {name} based?",
                    f"{name} is headquartered in which country?",
                    f"Which country is {name} based in?"],
        "industry": [f"What industry is {name} in?",
                     f"{name} operates in which industry?",
                     f"Which industry does {name} belong to?"],
        "inception": [f"In what year was {name} founded?",
                      f"{name} was founded in which year?"],
    }
    b = banks[shape]
    return b[int(hashlib.sha1(f"{shape}:{name}:{i}".encode()).hexdigest()[:8], 16) % len(b)]


def build(by):
    """Emit corpus rows. Distractors come from the same shape's value pool."""
    pools = collections.defaultdict(collections.Counter)
    for c in by.values():
        for f in c["founders"]:
            pools["founder"][f] += 1
        for x in c["countries"]:
            pools["country"][x] += 1
        for x in c["industries"]:
            pools["industry"][x] += 1
    pool = {k: [n for n, _ in v.most_common()] for k, v in pools.items()}

    rows, inception_used = [], 0
    for name, c in sorted(by.items(), key=lambda kv: -kv[1]["sitelinks"]):
        desc = c["desc"] or "Company."
        reveal = f"{name}: {desc[0].upper() + desc[1:] if desc else 'Company.'}"
        if not reveal.rstrip().endswith((".", "!", "?")):
            reveal += "."

        for shape, values in (("founder", c["founders"]),
                              ("country", c["countries"]),
                              ("industry", c["industries"])):
            if len(values) != 1:
                continue                    # multi-valued is not single-answer
            answer = next(iter(values))
            # "Which country is Air France based in?" answers France; "Who
            # started Robert Bosch?" answers Robert Bosch. When the company name
            # carries the answer the question is free, and ANSWER-IN-PROMPT
            # caught 57 of them the moment they were applied.
            # Split on hyphens too: "Agence France-Presse" carries "France".
            name_words = {w.lower().strip(".,")
                          for w in re.split(r"[\s\-–—/]+", name)}
            if any(len(w) > 3 and w.lower() in name_words
                   for w in re.split(r"[\s\-–—/]+", answer)):
                continue
            others = [x for x in pool[shape] if x != answer]
            if len(others) < 3:
                continue
            picks = RNG.sample(others[:400], 3)
            opts = picks + [answer]
            RNG.shuffle(opts)
            qid = f"biz:{shape}:" + hashlib.sha1(name.encode()).hexdigest()[:12]
            rows.append([qid, stem(shape, name, 0), opts, opts.index(answer),
                         "business", 2, reveal, name, ""])

        if c["inception"] and inception_used < MAX_INCEPTION_ROWS:
            y = int(c["inception"])
            if 1600 < y <= 2025:
                cand = sorted({y + d for d in (-31, -17, -8, 6, 13, 24) if 1600 < y + d <= 2025})
                if len(cand) >= 3:
                    picks = [str(x) for x in RNG.sample(cand, 3)]
                    opts = picks + [str(y)]
                    RNG.shuffle(opts)
                    qid = "biz:inception:" + hashlib.sha1(name.encode()).hexdigest()[:12]
                    rows.append([qid, stem("inception", name, 0), opts,
                                 opts.index(str(y)), "business", 2, reveal, name, ""])
                    inception_used += 1
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    raw = fetch(a.fetch)
    if not raw:
        return 1
    by = merge(raw)
    rows = build(by)
    kinds = collections.Counter(r[0].split(":")[1] for r in rows)
    print(f"companies: {len(by):,}   questions built: {len(rows):,}   {dict(kinds)}")
    for r in rows[:6]:
        print(f"\n   {r[1]}\n     options: {r[2]}  answer: {r[2][r[3]]}\n     reveal:  {r[6][:82]}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    data = json.loads(CORPUS.read_text())
    have = {q[0] for q in data["questions"]}
    fresh = [r for r in rows if r[0] not in have]
    width = max(len(q) for q in data["questions"])
    fresh = [r + [""] * (width - len(r)) for r in fresh]
    out = data["questions"] + fresh
    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(
        f'{{"version":"{data["version"]}","count":{len(out)},"questions":{body}}}')
    print(f"\nadded {len(fresh):,} rows; corpus {len(data['questions']):,} -> {len(out):,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
