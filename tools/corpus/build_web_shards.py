"""Stop the web app downloading 111,599 questions to ask ten.

`Corpus.load()` fetches assets/corpus.json — 52 MB, 13 MB gzipped — and turns
every row into an object before the first question is drawn. That is the same
pattern that got the Android build rejected from Play (Decision 049: 299 MB heap
peak, fixed by querying corpus.sqlite instead). The web still does it, and a
player who opens the site for one round pays for the whole corpus.

This writes stratified shards. Each category's rows are dealt round-robin, so
every shard carries the corpus's own category mix and difficulty spread — a
single shard is a representative corpus, not a slice of one:

    64 shards, 1,741 rows each, ~200 KB gzipped
    shard 0: screen 29% · geography 21% · music 12% · history 9% · sports 9%
             · arts 9% · science 7% · business 4%   (the corpus, exactly)

Rows are also LITE: `tags` is dropped (only Create search reads it) and
`sourceURL` is dropped where it is derivable from the subject, which is 80% of
rows. The client rebuilds the URL and lazy-loads tags if search is used.

corpus.json stays canonical and byte-identical across the three platform mirrors.
These are derived artifacts for one consumer, not a schema change.

    python3 tools/corpus/build_web_shards.py [--shards 64]
"""
import argparse
import collections
import json
import pathlib
import shutil
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
OUT = ROOT / "assets" / "web"

WIKI = "https://en.wikipedia.org/wiki/"


def lite_row(r):
    """Drop what the play path never reads. Index 9 (tags) goes entirely; index 8
    (sourceURL) becomes "" when the client can rebuild it from the subject."""
    derived = WIKI + urllib.parse.quote(str(r[7]).replace(" ", "_"))
    return r[:8] + ["" if r[8] == derived else r[8]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shards", type=int, default=64)
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    by_cat = collections.defaultdict(list)
    for r in rows:
        by_cat[r[4]].append(r)

    shards = [[] for _ in range(a.shards)]
    for cat, rs in by_cat.items():
        for i, r in enumerate(sorted(rs, key=lambda x: x[0])):
            shards[i % a.shards].append(lite_row(r))

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    for i, s in enumerate(shards):
        body = json.dumps(s, ensure_ascii=False, separators=(",", ":"))
        (OUT / f"shard-{i:02d}.json").write_text(
            f'{{"version":"{data["version"]}","shard":{i},"count":{len(s)},'
            f'"questions":{body}}}')

    # The UI shows how many questions a category holds; a shard must not make the
    # corpus look 64x smaller than it is, so the real totals ride the manifest.
    totals = {c: len(v) for c, v in sorted(by_cat.items())}
    manifest = {"version": data["version"], "shards": a.shards,
                "total": len(rows), "perCategory": totals,
                "rowsPerShard": len(shards[0])}
    (OUT / "manifest.json").write_text(json.dumps(manifest, separators=(",", ":")))

    size = sum(f.stat().st_size for f in OUT.glob("shard-*.json"))
    print(f"wrote {a.shards} shards to {OUT.relative_to(ROOT)}")
    print(f"  {len(shards[0]):,} rows each, {size/len(shards)/1024:.0f} KB raw per shard")
    print(f"  corpus total {len(rows):,} rows; manifest carries the real per-category counts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
