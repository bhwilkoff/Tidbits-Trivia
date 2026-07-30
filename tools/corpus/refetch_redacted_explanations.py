#!/usr/bin/env python3
"""Rebuild the explanations that `fix_cloze_explanations.py` could not repair locally.

That script restores `"<answer> — ____<rest>"` by dropping the redundant head. It cannot
touch rows where the cloze ALSO blanked a sub-word of a multi-word answer:

    Fishing cat — ____ (Prionailurus viverrinus) is a medium-sized wild ____ of South Asia.

Which token went ("cat") is not recoverable from the row, and substituting the whole answer
would read "a medium-sized wild Fishing cat". So instead of guessing, this refetches the real
Wikipedia lead sentence for the subject and uses that:

    The fishing cat (Prionailurus viverrinus) is a medium-sized wild cat of South and
    Southeast Asia.

Naming the answer is correct here — the explanation is only ever shown AFTER the reveal.

    python3 tools/corpus/refetch_redacted_explanations.py [--check] [--limit N]

Responses are cached in tools/corpus/cache/redacted_leads.json, so a re-run is offline and
free. `--check` exits non-zero if any repairable row remains.
"""
import json
import pathlib
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from generate_corpus import clean_clue, first_sentence  # noqa: E402  (repo's own helpers)

ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = ROOT / "tools" / "corpus" / "cache" / "redacted_leads.json"
API = "https://en.wikipedia.org/w/api.php"
UA = "TidbitsTrivia/1.0 (corpus explanation repair; contact via repo)"
BATCH = 20
PAUSE = 1.1  # polite; a 0.4s gap earned a wall of HTTP 429s partway through

# (relative path, explanation index, url index). The JSON sets are mirrored per platform.
JSON_SETS = [
    ("picture.json", 6, 8),
    ("typeanswer.json", 5, 7),
    ("corpus.json", 6, 8),
]
MIRROR_DIRS = [
    ROOT / "assets",
    ROOT / "TidbitsTrivia" / "Resources",
    ROOT / "android" / "app" / "src" / "main" / "assets",
    ROOT / "windows" / "Tidbits.HeadlessTests" / "Fixtures",
]
SQLITE = ROOT / "TidbitsTrivia" / "Resources" / "corpus.sqlite"


def title_of(url: str) -> str:
    if not url:
        return ""
    return urllib.parse.unquote(url.rsplit("/", 1)[-1]).replace("_", " ")


def rows_of(data):
    return data["questions"] if isinstance(data, dict) and "questions" in data else data


def collect_titles() -> set[str]:
    """Every Wikipedia subject that still has a redacted explanation, from any source."""
    titles: set[str] = set()
    for name, ei, ui in JSON_SETS:
        for d in MIRROR_DIRS:
            p = d / name
            if not p.exists():
                continue
            for r in rows_of(json.loads(p.read_text())):
                if "____" in (r[ei] or "") and ui < len(r):
                    titles.add(title_of(r[ui]))
    if SQLITE.exists():
        import sqlite3
        con = sqlite3.connect(SQLITE)
        for (url,) in con.execute(
            "SELECT source_url FROM questions WHERE instr(explanation,'____')>0"
        ):
            titles.add(title_of(url))
        con.close()
    titles.discard("")
    return titles


def load_cache() -> dict:
    return json.loads(CACHE.read_text()) if CACHE.exists() else {}


def fetch_leads(titles: list[str], cache: dict, limit: int | None) -> dict:
    """Fill `cache` with title -> lead sentence. Batched, polite, resumable."""
    todo = [t for t in titles if t not in cache]
    if limit:
        todo = todo[:limit]
    print(f"fetching {len(todo)} subjects ({len(titles) - len(todo)} already cached of {len(titles)})")
    for i in range(0, len(todo), BATCH):
        chunk = todo[i:i + BATCH]
        params = urllib.parse.urlencode({
            "action": "query", "format": "json", "prop": "extracts",
            "exintro": 1, "explaintext": 1, "redirects": 1,
            "titles": "|".join(chunk),
        })
        req = urllib.request.Request(f"{API}?{params}", headers={"User-Agent": UA})
        # Wikipedia 429s in bursts, so back off hard rather than dropping the batch — a
        # dropped batch is a permanently unrepaired row.
        data = None
        for attempt, backoff in enumerate((0, 5, 20, 60)):
            if backoff:
                time.sleep(backoff)
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    data = json.load(resp)
                break
            except Exception as e:                              # noqa: BLE001
                if attempt == 3:
                    print(f"  batch {i // BATCH}: giving up ({e})")
        if data is None:
            continue

        # Follow the redirect/normalisation maps so a requested title still gets its lead.
        alias = {}
        for kind in ("normalized", "redirects"):
            for m in data.get("query", {}).get(kind, []) or []:
                alias[m["to"]] = alias.get(m["from"], m["from"])
        for page in data.get("query", {}).get("pages", {}).values():
            lead = clean_clue(first_sentence(page.get("extract") or ""))
            if not lead:
                continue
            resolved = page.get("title", "")
            for key in {resolved, alias.get(resolved, resolved)}:
                if key:
                    cache[key] = lead
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=0, sort_keys=True))
        done = min(i + BATCH, len(todo))
        print(f"  {done}/{len(todo)}", end="\r", flush=True)
        time.sleep(PAUSE)
    print()
    return cache


def usable(lead: str) -> bool:
    return bool(lead) and "____" not in lead and len(lead) >= 30


def apply_json(path: pathlib.Path, ei: int, ui: int, cache: dict, check_only: bool) -> tuple[int, int]:
    if not path.exists():
        return 0, 0
    data = json.loads(path.read_text())
    rows = rows_of(data)
    fixed = missing = 0
    for r in rows:
        if "____" not in (r[ei] or "") or ui >= len(r):
            continue
        lead = cache.get(title_of(r[ui]), "")
        if not usable(lead):
            missing += 1
            continue
        if not check_only:
            r[ei] = lead
        fixed += 1
    if fixed and not check_only:
        path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    return fixed, missing


def apply_sqlite(cache: dict, check_only: bool) -> tuple[int, int]:
    if not SQLITE.exists():
        return 0, 0
    import sqlite3
    con = sqlite3.connect(SQLITE)
    rows = con.execute(
        "SELECT id, source_url FROM questions WHERE instr(explanation,'____')>0"
    ).fetchall()
    updates, missing = [], 0
    for qid, url in rows:
        lead = cache.get(title_of(url), "")
        if not usable(lead):
            missing += 1
            continue
        updates.append((lead, qid))
    if updates and not check_only:
        con.executemany("UPDATE questions SET explanation = ? WHERE id = ?", updates)
        con.commit()
    con.close()
    return len(updates), missing


def main() -> int:
    check_only = "--check" in sys.argv
    limit = None
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])

    titles = sorted(collect_titles())
    if not titles:
        print("OK: no redacted explanations remain")
        return 0

    cache = load_cache()
    if not check_only:
        cache = fetch_leads(titles, cache, limit)

    total_fixed = total_missing = 0
    for name, ei, ui in JSON_SETS:
        for d in MIRROR_DIRS:
            f, m = apply_json(d / name, ei, ui, cache, check_only)
            if f or m:
                print(f"  {d.name}/{name}: {'would fix' if check_only else 'fixed'} {f}, no lead for {m}")
            total_fixed += f
            total_missing += m
    f, m = apply_sqlite(cache, check_only)
    if f or m:
        print(f"  Resources/corpus.sqlite: {'would fix' if check_only else 'fixed'} {f}, no lead for {m}")
    total_fixed += f
    total_missing += m

    print(f"\n{'repairable' if check_only else 'repaired'}: {total_fixed}; still without a usable lead: {total_missing}")
    if check_only and total_fixed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
