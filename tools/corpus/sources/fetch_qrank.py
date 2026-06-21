#!/usr/bin/env python3
"""Qrank — cross-project Wikidata entity popularity (Decision 032, selection layer).

Downloads qrank.csv.gz (CC0, ~104 MB, QID,QRank) once into the build cache and
exposes load_qrank() -> {qid: rank}. Qrank aggregates trailing-12-month pageviews
across ALL Wikimedia projects per QID, so it captures global worth-knowing-ness a
single-language pageview count misses.

Source: https://qrank.toolforge.org/download/qrank.csv.gz  (CC0-1.0)
"""
import csv, gzip, io, os, urllib.request

URL = "https://qrank.toolforge.org/download/qrank.csv.gz"
UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
CACHE = os.path.join(os.path.dirname(__file__), "..", "cache", "qrank.csv.gz")


def ensure(refresh=False):
    path = os.path.abspath(CACHE)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and not refresh:
        return path
    print(f"[qrank] downloading {URL} …")
    req = urllib.request.Request(URL, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
        total = 0
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
            total += len(chunk)
    print(f"[qrank] cached {total/1e6:.1f} MB -> {path}")
    return path


def load_qrank(refresh=False):
    """Return {qid: rank_int}. Streams the gzip; ~27M rows, a few hundred MB RAM."""
    path = ensure(refresh)
    out = {}
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        rd = csv.reader(fh, delimiter="\t") if _is_tsv(path) else csv.reader(fh)
        header = next(rd, None)
        # Qrank ships as CSV "Entity,QRank"; tolerate either delimiter.
        for row in rd:
            if len(row) < 2:
                continue
            qid, rank = row[0].strip(), row[1].strip()
            if qid.startswith("Q") and rank.isdigit():
                out[qid] = int(rank)
    print(f"[qrank] loaded {len(out):,} ranked entities")
    return out


def _is_tsv(path):
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        first = fh.readline()
    return "\t" in first and "," not in first.split("\t")[0]


if __name__ == "__main__":
    q = load_qrank()
    # sanity: a few famous QIDs
    for name, qid in [("Harry Potter", "Q8337"), ("Napoleon", "Q517"), ("Monet", "Q296")]:
        print(f"  {name} ({qid}): {q.get(qid)}")
