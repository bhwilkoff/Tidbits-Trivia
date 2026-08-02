"""Prove the three things a generator re-run must never do.

`genguard.merge` is the only thing standing between `python3 gen_typeanswer.py`
and 12,856 reverted rows. A test that mocked the artifact would prove nothing
about the real ones, so each case here runs against a COPY of a shipped artifact
with a real generator's output.

    python3 tools/corpus/test_genguard.py
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import genguard                                                    # noqa: E402

SHAPES = ["oddoneout", "picture", "thisorthat", "typeanswer",
          "closest", "order", "match"]


def rows(p):
    d = json.loads(pathlib.Path(p).read_text())
    return d["questions"] if isinstance(d, dict) else d


def run(shape, out, *extra):
    r = subprocess.run([sys.executable, f"gen_{shape}.py", "--out", str(out), *extra],
                       cwd=HERE, capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"gen_{shape}.py failed:\n{r.stdout}\n{r.stderr}")
    return r.stdout


def main():
    tomb = json.load(open(HERE / "tombstones.json"))
    fails = []
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        for shape in SHAPES:
            live = ROOT / "assets" / f"{shape}.json"
            work = td / f"{shape}.json"
            shutil.copy(live, work)
            shipped = {r[0]: r for r in rows(live)}

            run(shape, work)
            got = {r[0]: r for r in rows(work)}

            lost = [i for i in shipped if i not in got]
            reverted = [i for i in shipped if i in got and shipped[i] != got[i]]
            revived = [i for i in tomb.get(shape, {}) if i in got]
            added = len(got) - len(shipped)

            for label, bad in (("deleted", lost), ("reverted", reverted),
                               ("revived a tombstoned row", revived)):
                if bad:
                    fails.append(f"{shape}: {label} {len(bad):,} (e.g. {bad[0]})")
            print(f"  {shape:<12} kept {len(shipped):,}  added {added:,}  "
                  f"lost {len(lost)}  reverted {len(reverted)}  revived {len(revived)}")

            # --regenerate must be the ONLY way the generator's text wins, and it
            # must still not delete or resurrect anything.
            shutil.copy(live, work)
            run(shape, work, "--regenerate")
            got2 = {r[0]: r for r in rows(work)}
            if [i for i in shipped if i not in got2]:
                fails.append(f"{shape}: --regenerate deleted shipped rows")
            if [i for i in tomb.get(shape, {}) if i in got2]:
                fails.append(f"{shape}: --regenerate revived a tombstoned row")

    if fails:
        print("\nFAIL")
        for f in fails:
            print("   ", f)
        return 1
    print("\na re-run of every generator is additive: nothing deleted, "
          "nothing reverted, nothing resurrected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
