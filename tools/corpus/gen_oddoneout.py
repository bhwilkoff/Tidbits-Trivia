#!/usr/bin/env python3
"""Odd-one-out (Q3) — "which doesn't belong?" as a plain 4-option MCQ.

Built from the corpus's existing country→continent data (wd:continent questions),
so it needs no new enrichment. Each question is three countries from one
continent + one from another (the outlier = the answer); the explanation cites
the continents. Standard MCQ row shape, so every client renders it on the
existing answer surface with zero new UI.

Output: assets/oddoneout.json (+ iOS Resources + Android assets copies).
Row shape: [id, prompt, options(4), correctIndex, category, difficulty,
            explanation, source_title, source_url]

Usage: python3 gen_oddoneout.py
"""
import argparse, hashlib, json, os, sqlite3
import sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
import genguard

PER_MAJORITY = 40   # questions per majority continent
MERGE = {"Insular Oceania": "Oceania"}
MIN_PER_CONT = 6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--out", default="../../assets/oddoneout.json")
    genguard.add_args(ap)
    args = ap.parse_args()

    qs = json.load(open(args.corpus))["questions"]

    # The pool is built from wd:continent rows, and the SUBJECT of one of those is
    # not always a country — "On which continent is Amsterdam?" puts a city in it.
    # The mode's whole premise is that the outlier can only be found by knowing the
    # fact, so an option of a different KIND hands it over:
    #
    #     Botswana · Burkina Faso · AMSTERDAM · Burundi
    #     Djibouti · Egypt · THURSTON ISLAND · Equatorial Guinea
    #     Connecticut · Costa Rica · MAUNA KEA · Cuba
    #
    # 97 shipped rounds were free that way. Keep only subjects Wikidata types as a
    # country; when the type is unknown the subject is kept, since the historical
    # states this corpus is full of are legitimate options.
    _here = os.path.dirname(__file__)
    _src, _labs = os.path.join(_here, "corpus_source.sqlite"), os.path.join(_here, "p31_labels.json")
    is_country = None
    if os.path.exists(_src) and os.path.exists(_labs):
        import sys as _sys
        _sys.path.insert(0, _here)
        from quality_gate import type_family
        _db = sqlite3.connect("file:%s?mode=ro" % _src, uri=True)
        _p31 = {t: (v or "").split(",")[0] for t, v in _db.execute("select title, p31 from subject")}
        _db.close()
        _lab = json.load(open(_labs))
        def is_country(title):
            t = _p31.get(title)
            if not t:
                return True                    # unknown type: keep
            return type_family(_lab.get(t, t)) == "country"

    # country -> continent (deduped), and continent -> [countries]
    cont_of, by_cont, url_of = {}, {}, {}
    for q in qs:
        if not q[0].startswith("wd:continent:"):
            continue
        country, cont = q[7], q[2][q[3]]
        cont = MERGE.get(cont, cont)
        if country in cont_of:
            continue
        if is_country and not is_country(country):
            continue
        cont_of[country] = cont
        by_cont.setdefault(cont, []).append(country)
        url_of[country] = q[8]

    conts = sorted(c for c, v in by_cont.items() if len(v) >= MIN_PER_CONT)
    for c in conts:
        by_cont[c] = sorted(set(by_cont[c]))

    out, seen = [], set()
    for ci, major in enumerate(conts):
        pool = by_cont[major]
        others = [c for c in conts if c != major]
        made = 0
        # Stride through the majority pool in non-overlapping triples; pair each
        # with a rotating outlier continent's rotating country.
        for i in range(0, len(pool) - 2, 3):
            trio = pool[i:i + 3]
            outc = others[(i // 3 + ci) % len(others)]
            opool = by_cont[outc]
            outlier = opool[(i // 3 + ci) % len(opool)]
            key = tuple(sorted(trio + [outlier]))
            if key in seen:
                continue
            seen.add(key)
            # Place the outlier deterministically (rotate position) and shuffle-free.
            opts = trio[:]
            pos = (i // 3) % 4
            opts.insert(pos, outlier)
            opts = opts[:4]
            correct = opts.index(outlier)
            expl = f"{outlier} is in {outc} — the other three are all in {major}."
            out.append([
                f"odd:{major}:{i}:{outlier}", "Which of these is the odd one out?",
                opts, correct, "geography", 3, expl, outlier, url_of.get(outlier, ""),
            ])
            made += 1
            if made >= PER_MAJORITY:
                break

    out = genguard.merge('oddoneout', out, args.out,

                         regenerate=args.regenerate, prune=args.prune)

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "oddoneout.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "oddoneout.json")
    # `--out /tmp/x.json` reads as "write somewhere harmless so I can look",
    # and it did not: these tracked copies were written regardless, so a safety
    # check that generated to a temp file silently replaced the iOS and Android
    # copies. Only the default --out touches the mirrors now.
    _mirrors = [res_copy, and_copy] if args.out == ap.get_default('out') else []
    for path in [args.out] + _mirrors:
        with open(path, "w") as f:
            f.write(payload)
    print(f"wrote {len(out)} odd-one-out questions (version {version})")
    for q in out[:5]:
        print("  ", q[2], "-> odd:", q[2][q[3]], "|", q[6])


if __name__ == "__main__":
    main()
