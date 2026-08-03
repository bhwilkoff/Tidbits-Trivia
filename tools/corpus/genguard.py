"""Make re-running a shape generator safe.

Every `gen_*.py` used to end the same way: build a list, serialise it, overwrite
`assets/<shape>.json` and both platform mirrors. That is fine the first time and
destructive every time after, because the shipped artifact is NOT the generator's
output any more. Weeks of repair scripts have edited it in place, hand-authored
rounds live only there, and prune commits have deliberately removed rows from it.

Measured against the shipped artifacts on 2026-08-02, re-running the seven
generators would have:

    deleted   2,896 rows the generator no longer produces
    reverted 12,856 rows to their pre-repair text
    revived     864 rows that a prune commit deliberately removed

Concretely, `gen_typeanswer.py` would have put back this reveal —

    shipped   1883 (TV series) - 1883 is an American Western drama miniseries...
    regen     1883 (TV series) is an American Western drama miniseries...

— undoing the fix for the payoff panel that read like it was scraped, and
`gen_closest.py` would have reverted the bounds fix on 2,506 rows.

So the artifact wins, and the generator is additive:

    keep     every shipped row, with its current text          (no revert, no drop)
    add      generated rows whose id is new                     (the point of a re-run)
    suppress generated rows a prune commit removed              (tombstones.json)

`--regenerate` takes the generator's text for rows that exist in both, for when
you have genuinely improved the generator and want its output. `--prune` lets it
drop shipped-only rows AND records them as tombstones, so the removal survives
the next re-run. Both print what they are about to do.

The tombstone file was seeded from git history: for every revision of every shape
artifact, a commit that removed ids while adding none is a deliberate prune (a
commit that does both is ordinary generator drift, and `order:arts:13:Zeno...`
churns its index on every run, so drift must not be mistaken for intent).
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOMBSTONES = pathlib.Path(__file__).resolve().parent / "tombstones.json"


def _rows(path):
    p = pathlib.Path(path)
    if not p.exists():
        return []
    d = json.loads(p.read_text())
    return d["questions"] if isinstance(d, dict) else d


def tombstoned(shape):
    if not TOMBSTONES.exists():
        return {}
    return json.load(open(TOMBSTONES)).get(shape, {})


def add_tombstones(shape, ids, reason):
    data = json.load(open(TOMBSTONES)) if TOMBSTONES.exists() else {}
    data.setdefault(shape, {}).update({i: reason for i in ids})
    TOMBSTONES.write_text(json.dumps(data, indent=1, sort_keys=True,
                                     ensure_ascii=False) + "\n")


def merge(shape, generated, out_path, *, regenerate=False, prune=False):
    """Return the rows to write, and print exactly what the merge protected.

    A `--prune` run writes tombstones ONLY when it is writing the real artifact.
    Redirecting `--out` to a scratch path to see what a prune WOULD do used to
    record 447 tombstones for the live shape anyway — the same trap as the
    generators writing their platform mirrors regardless of `--out`. A flag that
    means "show me" must not mutate shared state.
    """
    shipped = _rows(out_path)
    by_id = {r[0]: r for r in shipped}
    gen_by_id = {r[0]: r for r in generated}
    dead = tombstoned(shape)

    both = set(by_id) & set(gen_by_id)
    differing = [i for i in both if by_id[i] != gen_by_id[i]]
    shipped_only = [i for i in by_id if i not in gen_by_id]
    fresh = [r for r in generated if r[0] not in by_id and r[0] not in dead]
    revived = [i for i in gen_by_id if i not in by_id and i in dead]

    out = []
    for r in shipped:
        if r[0] in shipped_only and prune:
            continue
        out.append(gen_by_id[r[0]] if (regenerate and r[0] in gen_by_id) else r)
    out += fresh

    print(f"  merge[{shape}]  shipped {len(shipped):,} + new {len(fresh):,} "
          f"-> {len(out):,}")
    if differing:
        verb = "REGENERATED" if regenerate else "kept shipped text for"
        print(f"    {verb} {len(differing):,} rows the generator writes differently")
    if shipped_only:
        verb = "PRUNED" if prune else "kept"
        print(f"    {verb} {len(shipped_only):,} rows the generator no longer produces")
    if revived:
        print(f"    suppressed {len(revived):,} rows a prune commit removed "
              f"(e.g. {revived[0]})")

    if prune and shipped_only:
        real = ROOT / "assets" / f"{shape}.json"
        if pathlib.Path(out_path).resolve() == real.resolve():
            add_tombstones(shape, shipped_only, f"pruned by gen_{shape}.py --prune")
        else:
            print(f"    (scratch --out: NOT recording {len(shipped_only):,} tombstones)")
    return out


def add_args(ap):
    ap.add_argument("--regenerate", action="store_true",
                    help="take the generator's text for rows that already exist")
    ap.add_argument("--prune", action="store_true",
                    help="drop (and tombstone) shipped rows the generator no longer makes")
    return ap
