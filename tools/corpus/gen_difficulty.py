#!/usr/bin/env python3
"""F3 — derived difficulty from Wikipedia pageviews (popularity ≈ easiness).

The corpus's built-in difficulty is nearly flat (82% are "3"). This derives a
real 1–5 rating per answer subject from recent pageviews (Action API
`prop=pageviews`, batched 50 titles/request): the most-viewed subjects are the
best-known (difficulty 1), the least-viewed are obscure (difficulty 5). Emitted
as an ADDITIVE overlay (assets/difficulty.json: title → 1..5) — the corpus is
untouched; the Ladder mode (and future 50:50/adaptive) read the overlay.

Output: assets/difficulty.json (+ iOS Resources + Android assets copies).

Usage: python3 gen_difficulty.py
"""
import argparse, hashlib, json, os, time, urllib.parse, urllib.request

ACTION = "https://en.wikipedia.org/w/api.php"
CACHE = os.path.join(os.path.dirname(__file__), "cache", "pageviews_raw.json")


def _get(params):
    url = ACTION + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "TidbitsTrivia/1.0 (difficulty)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def fetch(titles):
    """Sum pageviews per title, FOLLOWING the continuation the pageviews prop
    paginates with (a 50-title batch returns only ~9 titles' views per page)."""
    base = {"action": "query", "prop": "pageviews", "titles": "|".join(titles),
            "format": "json", "formatversion": "2", "pvipdays": "60"}
    totals, norm = {}, {}
    cont = {}
    for _ in range(40):  # safety cap on continuation rounds
        data = _get({**base, **cont})
        for n in data.get("query", {}).get("normalized", []):
            norm[n["from"]] = n["to"]
        for p in data.get("query", {}).get("pages", []):
            pv = p.get("pageviews") or {}
            s = sum(v for v in pv.values() if isinstance(v, int))
            if s:
                totals[p["title"]] = totals.get(p["title"], 0) + s
        if "continue" in data:
            cont = data["continue"]
            time.sleep(0.3)
        else:
            break
    return totals, norm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--out", default="../../assets/difficulty.json")
    args = ap.parse_args()

    qs = json.load(open(args.corpus))["questions"]
    titles, seen = [], set()
    for q in qs:
        if "/wiki/" not in q[8]:
            continue
        t = urllib.parse.unquote(q[8].split("/wiki/")[-1]).replace("_", " ")
        if t not in seen:
            seen.add(t); titles.append(t)
    print(f"{len(titles)} distinct subjects")

    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    raw = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    pending = [t for t in titles if t not in raw]
    print(f"{len(pending)} uncached")
    for i in range(0, len(pending), 30):
        batch = pending[i:i + 30]
        result = None
        for attempt in range(6):
            try:
                result = fetch(batch); break
            except Exception as e:
                print(f"  batch {i} failed ({e}); backoff"); time.sleep(8 * (attempt + 1))
        if result is None:
            print("  giving up; rerun to resume"); break
        by_title, norm = result
        for t in batch:
            actual = norm.get(t, t)
            raw[t] = by_title.get(actual, by_title.get(t, 0))
        print(f"  {min(i + 30, len(pending))}/{len(pending)}")
        time.sleep(1.0)
        json.dump(raw, open(CACHE, "w"))

    # Rank by views; quintiles -> difficulty 1 (most viewed) .. 5 (least).
    scored = [(t, raw.get(t, 0)) for t in titles]
    scored.sort(key=lambda x: x[1], reverse=True)
    n = len(scored)
    difficulty = {}
    for rank, (t, views) in enumerate(scored):
        if views <= 0:
            difficulty[t.replace(" ", "_")] = 5
        else:
            difficulty[t.replace(" ", "_")] = min(5, 1 + rank * 5 // max(1, n))

    body = json.dumps(difficulty, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(difficulty)},"difficulty":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "difficulty.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "difficulty.json")
    for path in (args.out, res_copy, and_copy):
        with open(path, "w") as f:
            f.write(payload)
    from collections import Counter
    print(f"wrote {len(difficulty)} difficulty ratings (version {version})")
    print("distribution:", dict(sorted(Counter(difficulty.values()).items())))
    # spot-check
    for t in ["United_States", "Canada", "Albert_Einstein", "Chola_dynasty", "Bardsey_Island"]:
        if t in difficulty:
            print(f"  {t}: diff {difficulty[t]} ({raw.get(t.replace('_',' '),0)} views)")


if __name__ == "__main__":
    main()
