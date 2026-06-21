#!/usr/bin/env python3
"""Question-quality SCORING SYSTEM (Decision 032) — rate every question 0–100 on
three dimensions and cut the ones a robot clearly wrote / no human would enjoy.

  RECOG   — is the subject recognizable / worth knowing? (Qrank percentile)
  INTEREST— does it have a hook, or is it a mundane taxonomic/administrative fact
            no one would care to know? (description analysis)
  FIT     — does the question suit its type, and are the answer + options clean?

composite = 0.30·RECOG + 0.38·INTEREST + 0.32·FIT  (0–100).

Run to see the distribution + the worst examples. With --apply it rewrites the
sets keeping only composite ≥ --min (default 45), propagating through the corpus
(the bundled generators mine the kept corpus rows).

Usage: python3 score_questions.py [--min 45] [--apply]
"""
import argparse, json, os, re, sqlite3
from bisect import bisect_left

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))

# --- mundane (robot-wrote-it) vs hooky (a human would pick it) -------------
DRY = re.compile(r"""\b(
    species|genus|subspecies|taxon|moth|butterfly|beetle|weevil|fly|wasp|midge|
    snail|mollusc|barnacle|lichen|fungus|alga|sedge|grass|shrub|
    census-designated|civil\ parish|unincorporated\ community|
    commune\ in|municipality\ (of|in)|village\ in|hamlet|locality|townland|
    railway\ station|metro\ station|tram\ stop|
    is\ an?\ (village|commune|town|suburb|neighbou?rhood|ward|borough|settlement)
)\b""", re.I | re.X)
HOOK = re.compile(r"""\b(
    first|largest|biggest|tallest|highest|deepest|longest|oldest|smallest|only|
    most|best[-\ ]known|famous|famed|iconic|legendary|renowned|celebrated|notorious|
    pioneer|invented|founded|discovered|landmark|masterpiece|classic|revolutionary|
    record|award|Nobel|Oscar|Academy\ Award|Grammy|Pulitzer|Olympic|champion|
    best[-\ ]selling|hit|acclaimed|influential|controversial)\b""", re.I | re.X)
# identifying role/kind words that make a describe clue answerable
ROLE = re.compile(r"""\b(actor|actress|singer|musician|composer|band|rapper|director|
    filmmaker|writer|author|novelist|poet|playwright|painter|artist|sculptor|architect|
    philosopher|scientist|physicist|chemist|biologist|mathematician|inventor|economist|
    politician|president|prime\ minister|king|queen|emperor|monarch|general|leader|
    activist|explorer|athlete|footballer|player|boxer|driver|
    film|movie|series|show|album|song|novel|book|play|painting|game|
    country|city|capital|river|mountain|lake|island|empire|war|battle|dynasty|
    element|planet|species|disease|invention|company|team)\b""", re.I | re.X)


def clue_of(p):
    m = re.search(r"[“\"](.+?)[”\"]", p)
    return m.group(1) if m else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min", type=float, default=45)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    subj = {}
    for t, qr, cat, person, g in con.execute(
            "SELECT title, qrank, category, (p31 LIKE '%Q5%' OR gender IS NOT NULL), gender FROM subject WHERE keep=1"):
        subj[t.replace(" ", "_")] = (qr or 0, cat, bool(person))
    ranks = sorted(v[0] for v in subj.values())
    def pct(qr):
        return 100 * bisect_left(ranks, qr) // max(1, len(ranks))

    corpus_path = os.path.join(ROOT, "assets", "corpus.json")
    qs = json.load(open(corpus_path))["questions"]

    scored = []
    for q in qs:
        tmpl = q[0].split(":")[1] if ":" in q[0] else ""
        title_key = (q[8].split("/wiki/")[-1] if "/wiki/" in (q[8] or "") else q[7].replace(" ", "_"))
        s = subj.get(title_key) or subj.get(q[7].replace(" ", "_"))
        recog = pct(s[0]) if s else 35
        clue = clue_of(q[1])

        # INTEREST
        interest = 62
        cl = clue.lower()
        if DRY.search(cl):
            interest -= 48
        if HOOK.search(cl):
            interest += 22
        if tmpl in ("describe", "cloze") and len(clue) < 16:
            interest -= 18

        # FIT
        opts = q[2] or []
        distinct = len(set(opts)) == len(opts) and len(opts) == 4
        fit = 70 if distinct else 30
        if tmpl in ("describe", "cloze"):
            if ROLE.search(cl):
                fit += 15            # the clue actually identifies a kind of thing
            else:
                fit -= 20
            if re.fullmatch(r"\(?\b\d{3,4}\b[-–]?\d{0,4}\)?", clue.strip()):
                fit -= 40            # date-only
            fit = min(fit, 100)
        elif tmpl == "continent":
            fit = 78                 # clean structured question
        elif tmpl in ("capital", "currency", "author", "composer", "director", "elemSymbol"):
            fit = 82

        recog = max(0, min(100, recog))
        interest = max(0, min(100, interest))
        fit = max(0, min(100, fit))
        composite = round(0.30 * recog + 0.38 * interest + 0.32 * fit, 1)
        scored.append((composite, recog, interest, fit, tmpl, q))

    scored.sort(key=lambda x: x[0])
    keep = [x for x in scored if x[0] >= args.min]
    cut = [x for x in scored if x[0] < args.min]

    import statistics
    comps = [x[0] for x in scored]
    print(f"=== SCORED {len(scored):,} corpus questions ===")
    print(f"  composite: min {min(comps)} / median {statistics.median(comps):.0f} / mean {statistics.mean(comps):.0f} / max {max(comps)}")
    buckets = {b: 0 for b in (0, 30, 40, 45, 50, 60, 70, 80, 90)}
    for c in comps:
        for b in sorted(buckets, reverse=True):
            if c >= b:
                buckets[b] += 1; break
    print(f"  by band: {buckets}")
    print(f"  cut at <{args.min}: {len(cut):,}  ({100*len(cut)//len(scored)}%)")
    print("\n  WORST 12 (these read like a robot wrote them):")
    for comp, r, i, f, tmpl, q in scored[:12]:
        print(f"    [{comp:>4} r{r} i{i} f{f}] {q[1][:74]} -> {q[2][q[3]]}")
    print("\n  BEST 6:")
    for comp, r, i, f, tmpl, q in scored[-6:]:
        print(f"    [{comp:>4}] {q[1][:74]} -> {q[2][q[3]]}")

    if args.apply:
        kept_rows = [x[5] for x in keep]
        body = json.dumps(kept_rows, ensure_ascii=False, separators=(",", ":"))
        import hashlib
        ver = hashlib.md5(body.encode()).hexdigest()[:12]
        payload = f'{{"version":"{ver}","count":{len(kept_rows)},"questions":{body}}}'
        for p in (corpus_path, os.path.join(ROOT, "android/app/src/main/assets/corpus.json")):
            open(p, "w").write(payload)
        import build_corpus   # reuse the iOS sqlite writer so all platforms match
        build_corpus.write_sqlite(kept_rows, build_corpus.IOS_SQLITE)
        print(f"\n  APPLIED: kept {len(kept_rows):,} corpus rows → corpus.json (web/Android) + corpus.sqlite (iOS)."
              f"\n  Now rerun the gen_*.py so the bundled sets mine the filtered corpus.")
    con.close()


if __name__ == "__main__":
    main()
