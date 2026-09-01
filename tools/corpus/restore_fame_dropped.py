"""Bring back the rounds FAME-TELL dropped, with distractors that are peers.

`fix_fame_tell.py` repaired 971 rounds by drawing same-OCCUPATION peers and
deleted 581 it could not, because occupation (`p106`) only exists for people.
Everything that is not a person went in the bin — including four good Volcanoes
questions, which took a suggested topic below the six it needs to be offered:

    This volcanic range in the central Sahara, mostly in northern Chad...
        Tibesti Mountains  vs  Himalayas / Andes / Alps
    This North Atlantic collection of four volcanic archipelagos...
        Macaronesia  vs  Israel / Palestine / Gaza Strip

Both deserved to go as written. Neither deserved to be deleted: the SUBJECT is
good and only the distractors were broken.

The signal for non-people is `p31`, which was rejected for the occupation pass and
was right to be — `p31` for any person is "human", 23,487 subjects, so it paired a
British sports journalist with two male stage actors. But for a PLACE it is exact:
Tibesti Mountains is Q46831, "mountain range", all of 40 subjects.

So the rule is the same rule as the occupation pass, stated properly: draw from the
RAREST type the answer belongs to, and refuse when even that type is too big to
make a plausible peer. A 500-member ceiling separates "mountain range" (40) from
"human" (23,487). Same fame band, same era band, same nationality guard.

    python3 tools/corpus/restore_fame_dropped.py [--apply] [--rev 09553e1~1]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
import json
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fix_fame_tell as fft                                        # noqa: E402
import quality_gate as qg                                          # noqa: E402


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

# A type this large is a category, not a resemblance: "human" holds 23,487
# subjects and says nothing about whether two of them belong in the same round.
MAX_TYPE = 500


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--rev", default="09553e1~1",
                    help="revision holding the rows before the drop")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    have = {r[0] for r in rows}

    raw = subprocess.run(["git", "show", f"{a.rev}:assets/corpus.json"],
                         capture_output=True, cwd=ROOT)
    dropped = [r for r in json.loads(raw.stdout)["questions"] if r[0] not in have]

    sub = fft.load_pool()                       # title -> (qrank, p106, gender)
    import sqlite3
    db = sqlite3.connect(f"file:{fft.SOURCE_DB}?mode=ro", uri=True)
    p31 = {t: (p or "") for t, p in db.execute("select title, p31 from subject")}
    db.close()

    by_type = collections.defaultdict(list)
    for t, p in p31.items():
        if t not in sub:
            continue
        for q in p.split(","):
            if q:
                by_type[q].append((sub[t][0], t))

    # The gate's OWN kind map. A p31 class can still be too loose: Q55983715
    # holds the tarantula hawk AND the ibex, and restoring on p31 alone put
    # 'Coca' and 'Grass' (plants) into a round of animals, which KIND-MISMATCH
    # then rejected. Matching kind is what makes a same-type peer a peer.
    kinds = qg.kind_map(rows)
    raw_expl = {}
    for r in rows:
        if r[7] and r[6]:
            raw_expl.setdefault(r[7], r[6])

    years = qg.birth_years()
    nationality = {}
    for r in rows:
        d = qg.readable_description(r[6] or "", r[7])
        if d and d != "PERSON-BY-DATES":
            m = qg.NAT_IN_DESC.match(d)
            if m:
                nationality.setdefault(r[7], qg._nat_family(m.group(1)))

    restored, examples = [], []
    for r in dropped:
        opts = r[2]
        if not isinstance(opts, list) or len(opts) != 4:
            continue
        ans = str(opts[r[3]])
        rec = sub.get(ans)
        if not rec or not rec[0]:
            continue
        ideal = rec[0]
        text = f"{r[1]}\n{r[6] or ''}"
        anchor = years.get(ans)
        want_nat = nationality.get(ans)
        want_kind = qg.option_kind(ans, kinds, raw_expl)

        # These rows were dropped for the fame tell; restoring one must not
        # reintroduce a DIFFERENT defect. "In which country is Belgian
        # Revolution?" is a present-tense template on a historical subject and
        # belongs in neither corpus.
        if any(str(r[1] or "").startswith(t) for t in qg.PRESENT_TEMPLATES):
            continue

        got = {}
        for ty in p31.get(ans, "").split(","):
            if not ty:
                continue
            pool = by_type.get(ty, ())
            if len(pool) > MAX_TYPE:
                continue
            for q, t in pool:
                if t == ans or not (ideal / 5 <= q <= ideal * 5) or t in text:
                    continue
                if want_nat and nationality.get(t) and nationality[t] != want_nat:
                    continue
                if want_kind and qg.option_kind(t, kinds, raw_expl) != want_kind:
                    continue
                if anchor is not None:
                    y = years.get(t)
                    if y is None or abs(y - anchor) > 200:
                        continue
                if t not in got or len(pool) < got[t][1]:
                    got[t] = (q, len(pool))
        if len(got) < 3:
            continue

        new = fft.pick([(q, t, rare) for t, (q, rare) in got.items()], 3, ideal)
        before = list(opts)
        it = iter(new)
        r[2] = [opts[i] if i == r[3] else next(it) for i in range(4)]
        restored.append(r)
        if len(examples) < 8:
            examples.append((r[1][:70], ans, before, r[2]))

    print(f"rounds FAME-TELL deleted: {len(dropped):,}")
    print(f"  restorable with same-type peers (type under {MAX_TYPE}): {len(restored):,}")
    for prompt, ans, before, after in examples:
        print(f"\n   {prompt}...\n     answer  {ans}"
              f"\n     was     {[o for o in before if o != ans]}"
              f"\n     now     {[o for o in after if o != ans]}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0

    def write(rs):
        body = json.dumps(rs, ensure_ascii=False, separators=(",", ":"))
        CORPUS.write_text(
            f'{{"version":"{corpus_version(body)}","count":{len(rs)},"questions":{body}}}')

    # Re-check against the REAL gate rather than a second copy of its rules, and
    # drop any restored row it objects to. Hand-mirroring KIND-MISMATCH here left
    # four rows that put 'Coca' and 'Grass' in a round of animals: the gate reads
    # `kinds` directly where this script was reading `option_kind`, and a rule
    # re-implemented is a rule that drifts. Asking the gate cannot drift.
    ids = {r[0] for r in restored}
    for attempt in range(4):
        write(rows + restored)
        out = subprocess.run([sys.executable, "tools/corpus/quality_gate.py", "--report"],
                             capture_output=True, text=True, cwd=ROOT).stdout
        flagged = {tok.rstrip(":") for line in out.splitlines()
                   for tok in [line.strip().split(" ", 1)[0]]
                   if tok.rstrip(":") in ids}
        if not flagged:
            break
        print(f"  gate rejected {len(flagged)} restored row(s) — dropping them")
        restored = [r for r in restored if r[0] not in flagged]
        ids = {r[0] for r in restored}

    write(rows + restored)
    print(f"\nwrote {CORPUS} — {len(rows) + len(restored):,} rows "
          f"({len(restored):,} restored)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
