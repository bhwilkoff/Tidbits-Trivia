#!/usr/bin/env python3
"""Stage 2 — Wikipedia Clickstream → confusable-distractor graph (Decision 032).

Clickstream is an empirical record of which articles people actually navigate
between, so a target's neighbours are the entities humans genuinely conflate —
the most plausible wrong answers you can get (Monet → Manet / Renoir / Pissarro).

Streams the latest enwiki clickstream (~508 MB gz) and keeps ONLY edges where
BOTH endpoints are in our curated subject set — so every distractor it yields is
itself a valid answer option, and the stored graph is tiny. No 2 GB on disk.

Writes table: related(title, neighbour, n) — neighbour is a confusable subject,
n = monthly navigation count (strength).

Usage: python3 fetch_clickstream.py [--month YYYY-MM] [--min-n N]
"""
import argparse, gzip, os, sqlite3, urllib.request

UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
BASE = "https://dumps.wikimedia.org/other/clickstream"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--month", default="2026-05")
    ap.add_argument("--min-n", type=int, default=10)
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    subjects = {t.replace("_", " ") for (t,) in con.execute("SELECT title FROM subject WHERE keep=1")}
    print(f"{len(subjects):,} subjects; streaming clickstream {args.month} (both endpoints must be subjects)…")

    con.execute("CREATE TABLE IF NOT EXISTS related (title TEXT, neighbour TEXT, n INTEGER)")
    con.execute("DELETE FROM related")
    con.execute("CREATE INDEX IF NOT EXISTS idx_related_title ON related(title)")

    url = f"{BASE}/{args.month}/clickstream-enwiki-{args.month}.tsv.gz"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    kept, scanned, batch = 0, 0, []
    with urllib.request.urlopen(req, timeout=120) as resp:
        with gzip.GzipFile(fileobj=resp) as gz:
            for raw in gz:
                scanned += 1
                try:
                    prev, curr, typ, n = raw.decode("utf-8", "replace").rstrip("\n").split("\t")
                except ValueError:
                    continue
                if typ not in ("link", "other"):
                    continue
                ni = int(n) if n.isdigit() else 0
                if ni < args.min_n:
                    continue
                c = curr.replace("_", " "); p = prev.replace("_", " ")
                if c == p or c not in subjects or p not in subjects:
                    continue
                # store both directions so either article can pull the other as a decoy
                batch.append((c, p, ni)); batch.append((p, c, ni)); kept += 1
                if len(batch) >= 5000:
                    con.executemany("INSERT INTO related VALUES (?,?,?)", batch); con.commit(); batch = []
                if scanned % 2_000_000 == 0:
                    print(f"  …scanned {scanned//1_000_000}M lines, kept {kept:,} subject-subject edges")
    if batch:
        con.executemany("INSERT INTO related VALUES (?,?,?)", batch); con.commit()

    nodes = con.execute("SELECT COUNT(DISTINCT title) FROM related").fetchone()[0]
    print(f"\n=== CLICKSTREAM ===\n  scanned {scanned:,} lines")
    print(f"  kept {kept:,} subject-subject edges over {nodes:,} subjects")
    con.close()


if __name__ == "__main__":
    main()
