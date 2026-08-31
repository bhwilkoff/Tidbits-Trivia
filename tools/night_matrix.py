"""Every platform hosts a Trivia Night; every other platform joins it.

One direction proves almost nothing. Tidbits Live and Trivia Night ride the SAME
RTDB room (`live/{code}`), so a joiner cannot tell which product opened it — which
is exactly why "the Mac can host" has never implied "the Pixel can host". The host
half is different code on every platform, and it is the half that has repeatedly
turned out to be unreachable rather than broken.

Resumable on purpose. A full matrix is ~8 runs at ~8 minutes each, longer than any
one sitting or background task survives, so every result is appended to a ledger and
a re-run skips what already passed:

    python3 tools/night_matrix.py                 # continue the matrix
    python3 tools/night_matrix.py --only pixel    # one host
    python3 tools/night_matrix.py --redo          # re-run even the passing hosts

A full matrix is ~8 runs at ~8 minutes. That outlives a single background task, so
drive it one host at a time and let the ledger carry the state between them:

    for h in windows mac atv ipad iphone pixel firetv androidtv; do
        python3 tools/night_matrix.py --only $h --redo
    done
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devlease  # noqa: E402

LEDGER = Path("build/qa/night-matrix.json")

# Every platform that can HOST. The web hosts a night too (js/app.js NH.*), but it
# has no `--host web` path in multiplayer_run yet — recorded here as a known gap
# rather than silently omitted, because an absent row reads as "not applicable".
HOSTS = ["windows", "mac", "atv", "ipad", "iphone", "pixel", "firetv", "androidtv"]
ALL = HOSTS + ["web"]

# 4 alphanumeric chars — rooms are 4, and a longer code is silently unjoinable from
# the web, whose input is correctly capped.
CODES = {"windows": "NW01", "mac": "NM01", "atv": "NA01", "ipad": "NI01",
         "iphone": "NP01", "pixel": "NX01", "firetv": "NF01", "androidtv": "NT01"}


def ledger():
    try:
        return json.loads(LEDGER.read_text())
    except (OSError, ValueError):
        return {}


def save(d):
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    LEDGER.write_text(json.dumps(d, indent=1))


def run_one(host, settle=45):
    """Host a night on `host`; every other platform joins. Returns the result dict."""
    players = [p for p in ALL if p != host]
    code = CODES[host]
    log = Path(f"build/qa/night-{host}.log")
    log.parent.mkdir(parents=True, exist_ok=True)

    cmd = [sys.executable, "-u", "tools/multiplayer_run.py",
           "--host", host, "--game", "night", "--code", code,
           "--players", ",".join(players), "--settle", str(settle)]
    print(f"\n=== {host} hosts a night ({code}) — joiners: {','.join(players)}")
    with open(log, "w") as f:
        r = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=1800)

    text = log.read_text()
    fails = [l.strip() for l in text.splitlines() if "[FAIL]" in l]
    ok = "RESULT: OK" in text
    # A run that never printed a RESULT did not finish — that is not a pass and not a
    # product failure either; it has to be distinguishable from both.
    finished = "RESULT:" in text
    return {"host": host, "code": code, "ok": ok, "finished": finished,
            "fails": fails[:8], "rc": r.returncode, "log": str(log),
            "at": time.strftime("%Y-%m-%d %H:%M")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--settle", type=float, default=45)
    a = ap.parse_args()

    # --redo re-RUNS; it must not discard what other hosts have already proven.
    # `done = {}` did exactly that: `save(done)` writes the whole dict, so
    # `--only windows --redo` would have wiped every other host's result the moment
    # windows finished. A resumable ledger that silently forgets is worse than none.
    done = ledger()
    wanted = a.only.split(",") if a.only else HOSTS
    todo = [h for h in wanted
            if h in HOSTS and (a.redo or not done.get(h, {}).get("ok"))]

    if not todo:
        print("matrix complete — every host already passed:")
    for host in todo:
        # Never start a host we cannot even hold. Better to skip and say so than to
        # spend eight minutes producing a contended result.
        free, holder = devlease.try_lease(host, task=f"night matrix ({host} hosts)")
        if not free:
            print(f"  [skip] {host} — {holder}")
            continue
        devlease.release(host)          # multiplayer_run takes its own leases
        done[host] = run_one(host, a.settle)
        save(done)
        v = done[host]
        print(f"  {host:10} {'OK' if v['ok'] else ('FAIL' if v['finished'] else 'DID NOT FINISH')}")
        for f in v["fails"]:
            print(f"        {f}")

    print("\n--- matrix ---")
    for h in HOSTS:
        v = done.get(h)
        state = "not run" if not v else ("OK" if v["ok"] else
                                        ("FAIL" if v["finished"] else "unfinished"))
        print(f"  {h:10} {state}")
    print("  web        HOST UNTESTED — js/app.js can host a night, "
          "multiplayer_run has no --host web path")
    save(done)
    return 0 if all(done.get(h, {}).get("ok") for h in HOSTS) else 1


if __name__ == "__main__":
    sys.exit(main())
