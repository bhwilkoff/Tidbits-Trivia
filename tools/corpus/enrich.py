#!/usr/bin/env python3
"""E1 — additive Wikidata enrichment pass (SOLO-BACKLOG E1; Decision 030-adjacent).

One build-time pass over the corpus's answer entities that, per entity, emits:
  - a Commons image URL (P18)            -> unlocks Picture ID (Q7)
  - numeric facts + units                -> unlocks Closest Call (M5), Ordering
    (population, area, elevation, years,    (Q4), This-or-That bigger/older (Q1)
     atomic number, mass, ...)
  - aliases / also-known-as              -> unlocks Type-the-answer (Q6),
                                            Matching (Q5), better MCQ matching

Output is ADDITIVE: a separate assets/enrich.json keyed by Wikipedia title, so
every client consumes it without a corpus rewrite (shared-data-plane evolution
rule). Existing questions are untouched. Raw API responses are cached so reruns
are instant.

Stdlib only (urllib) — no third-party deps, matching the corpus toolchain.

Usage: python3 enrich.py [--corpus ../../assets/corpus.json] [--out ../../assets/enrich.json]
"""
import argparse, json, os, time, urllib.parse, urllib.request

API = "https://www.wikidata.org/w/api.php"
CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache")
RAW_CACHE = os.path.join(CACHE_DIR, "enrich_raw.json")

# Wikidata numeric properties worth asking "closest to" / "which is bigger".
# label is human-facing; `kind` drives later question phrasing.
NUMERIC_PROPS = {
    "P1082": ("population", "count"),
    "P2046": ("area", "km2"),
    "P2048": ("height", "m"),
    "P2044": ("elevation", "m"),
    "P571":  ("inception", "year"),
    "P569":  ("birth_year", "year"),
    "P570":  ("death_year", "year"),
    "P1086": ("atomic_number", "count"),
    "P2067": ("mass", "kg"),
    "P2386": ("diameter", "m"),
    "P1538": ("households", "count"),
}
IMAGE_PROP = "P18"


def fetch(titles):
    """wbgetentities for up to 50 enwiki titles -> {title: entity}."""
    params = {
        "action": "wbgetentities", "sites": "enwiki",
        "titles": "|".join(titles), "props": "claims|aliases|sitelinks",
        "languages": "en", "format": "json",
    }
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "TidbitsTrivia/1.0 (enrichment)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def commons_url(filename):
    # Special:FilePath redirects to the actual file; width keeps it light.
    return "https://commons.wikimedia.org/wiki/Special:FilePath/" + \
        urllib.parse.quote(filename.replace(" ", "_")) + "?width=800"


def year_from_time(iso):
    # Wikidata time value: "+1879-03-14T00:00:00Z" -> 1879 (sign-aware).
    try:
        s = iso.lstrip("+")
        neg = iso.startswith("-")
        y = int(s.split("-")[0])
        return -y if neg else y
    except Exception:
        return None


def extract(entity):
    out = {"qid": entity.get("id")}
    claims = entity.get("claims", {})

    # Image
    if IMAGE_PROP in claims:
        try:
            fn = claims[IMAGE_PROP][0]["mainsnak"]["datavalue"]["value"]
            out["image"] = commons_url(fn)
        except Exception:
            pass

    # Numerics
    numbers = {}
    for pid, (label, kind) in NUMERIC_PROPS.items():
        claim_list = claims.get(pid)
        if not claim_list:
            continue
        try:
            if kind == "year":
                y = year_from_time(claim_list[0]["mainsnak"]["datavalue"]["value"]["time"])
                if y is not None:
                    numbers[label] = {"value": y, "unit": "year"}
            else:
                # Population (P1082) has many dated claims and Wikidata's first is
                # often a bogus/partial figure (e.g. Canada -> 44) — take the
                # LARGEST valid amount, which is the real magnitude. Other
                # numerics are single-valued, so first == max anyway.
                amounts = []
                for c in claim_list:
                    try:
                        amounts.append(float(c["mainsnak"]["datavalue"]["value"]["amount"].lstrip("+")))
                    except Exception:
                        pass
                if amounts:
                    amt = max(amounts)
                    numbers[label] = {"value": int(amt) if amt.is_integer() else amt, "unit": kind}
        except Exception:
            pass
    if numbers:
        out["numbers"] = numbers

    # Aliases (also-known-as)
    al = entity.get("aliases", {}).get("en", [])
    aliases = [a["value"] for a in al][:8]
    if aliases:
        out["aliases"] = aliases

    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--out", default="../../assets/enrich.json")
    ap.add_argument("--limit", type=int, default=0, help="cap entities (0 = all)")
    args = ap.parse_args()

    corpus = json.load(open(args.corpus))
    qs = corpus["questions"] if isinstance(corpus, dict) else corpus
    titles = []
    seen = set()
    for q in qs:
        url = q[-1] if isinstance(q, list) else q.get("source_url", "")
        if not url or "/wiki/" not in url:
            continue
        t = url.split("/wiki/")[-1]
        if t and t not in seen:
            seen.add(t)
            titles.append(urllib.parse.unquote(t).replace("_", " "))
    if args.limit:
        titles = titles[: args.limit]
    print(f"{len(titles)} distinct answer entities to enrich")

    os.makedirs(CACHE_DIR, exist_ok=True)
    raw = json.load(open(RAW_CACHE)) if os.path.exists(RAW_CACHE) else {}

    pending = [t for t in titles if t not in raw]
    print(f"{len(pending)} uncached; {len(titles) - len(pending)} from cache")
    for i in range(0, len(pending), 50):
        batch = pending[i:i + 50]
        data = None
        for attempt in range(5):
            try:
                data = fetch(batch); break
            except Exception as e:
                wait = 5 * (attempt + 1)
                print(f"  batch {i} failed ({e}); backoff {wait}s")
                time.sleep(wait)
        if data is None:
            print("  giving up this batch; rerun to resume from cache")
            break
        ents = data.get("entities", {})
        # Map returned entities back to the requested title via sitelinks.
        by_title = {}
        for ent in ents.values():
            sl = ent.get("sitelinks", {}).get("enwiki", {})
            if sl.get("title"):
                by_title[sl["title"]] = ent
        for t in batch:
            raw[t] = by_title.get(t)  # None if no enwiki entity (still cache the miss)
        print(f"  enriched {min(i + 50, len(pending))}/{len(pending)}")
        time.sleep(1.0)
        json.dump(raw, open(RAW_CACHE, "w"))

    entities = {}
    img = nums = ali = 0
    for t in titles:
        ent = raw.get(t)
        if not ent:
            continue
        e = extract(ent)
        # Key by the underscored title (how clients hold the source page).
        key = t.replace(" ", "_")
        if "image" in e or "numbers" in e or "aliases" in e:
            entities[key] = e
            img += "image" in e
            nums += "numbers" in e
            ali += "aliases" in e

    import hashlib
    body = json.dumps(entities, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(entities)},"entities":{body}}}'
    with open(args.out, "w") as f:
        f.write(payload)
    print(f"\nwrote {len(entities)} enriched entities (version {version}) to {args.out}")
    print(f"  with image: {img}  with numbers: {nums}  with aliases: {ali}")


if __name__ == "__main__":
    main()
