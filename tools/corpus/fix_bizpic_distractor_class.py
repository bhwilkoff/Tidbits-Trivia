"""Rebuild mixed-class bizpic distractors from same-class pools (P4 tail).

28 of 76 bizpic picture rows mixed PEOPLE and COMPANIES in one option set
(bizpic:AOL offered Sergey Brin; bizpic:Gatorade offered Zuckerberg AND
Bezos). The answer's class comes from p31 (exact-token Q5 = person); the
three distractors are re-drawn deterministically (md5 of row id) from the
same-class answers of the OTHER bizpic rows.

    python3 tools/corpus/fix_bizpic_distractor_class.py [--apply]

Then run tools/corpus/resync_corpus.sh and bump sw.js CACHE.
"""
import argparse
import hashlib, hashlib, json, pathlib, re, sqlite3, sys


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


ROOT = pathlib.Path(__file__).resolve().parents[2]
PICTURE = ROOT / "assets" / "picture.json"
SOURCE = ROOT / "tools" / "corpus" / "corpus_source.sqlite"


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    con = sqlite3.connect(SOURCE)
    p31 = {t: set(re.findall(r"Q\d+", p or "")) for t, p in
           con.execute("select title, p31 from subject")}

    def cls(title):
        toks = p31.get(title)
        if toks is None: return None
        return "person" if "Q5" in toks else "org"

    data = json.loads(PICTURE.read_text())
    rows = data["questions"] if isinstance(data, dict) else data
    biz = [q for q in rows if isinstance(q, list) and q[0].startswith("bizpic:")]

    answers = {}
    for q in biz:
        ans = q[2][q[3]]
        answers[ans] = cls(ans)
    pool = {"person": sorted(t for t, c in answers.items() if c == "person"),
            "org": sorted(t for t, c in answers.items() if c == "org")}
    print(f"pools: {len(pool['person'])} people, {len(pool['org'])} orgs")

    fixed = 0
    for q in biz:
        ans = q[2][q[3]]
        c = cls(ans)
        if c is None: continue
        if all(cls(o) == c for o in q[2]): continue     # already same-class
        seed = int(hashlib.md5(q[0].encode()).hexdigest(), 16)
        candidates = [t for t in pool[c] if t != ans]
        picks = []
        n = len(candidates)
        stride = (seed // n) % n or 1
        while __import__("math").gcd(stride, n) != 1:
            stride += 1
        i = seed % n
        while len(picks) < 3 and candidates:
            t = candidates[i % n]
            if t not in picks: picks.append(t)
            i += stride
        opts = picks + [ans]
        order = sorted(range(4), key=lambda k: hashlib.md5(f"{q[0]}:{k}".encode()).hexdigest())
        q[2] = [opts[k] for k in order]
        q[3] = q[2].index(ans)
        fixed += 1
        if fixed <= 5:
            print(f"   {q[0]}: {q[2]} ans={q[2][q[3]]}")
    print(f"rows rebuilt: {fixed}")

    if not a.apply:
        print("(dry run — pass --apply)"); return 0
    if isinstance(data, dict):
        body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
        PICTURE.write_text(f'{{"version":"{corpus_version(body)}","count":{len(rows)},"questions":{body}}}')
    else:
        PICTURE.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {PICTURE}"); return 0


if __name__ == "__main__":
    sys.exit(main())
