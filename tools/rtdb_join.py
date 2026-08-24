#!/usr/bin/env python3
"""Scripted cross-platform player for the shared RTDB live/{code} plane.

Joins a hosted Trivia Night / Tidbits Live room exactly the way the web app
does (anonymous auth + REST), so a TV/Mac host can be proven end-to-end
WITHOUT a second human: the joiner's name appearing on the host's glass is
the evidence that host -> Firebase -> client works across platforms.

Usage:
  python3 tools/rtdb_join.py --code QATV --name HarnessBot            # join, stay 60s
  python3 tools/rtdb_join.py --code QATV --name HarnessBot --stay 120
  python3 tools/rtdb_join.py --code QATV --answer 2                   # answer current q
"""
import argparse, json, sys, time, urllib.request

API_KEY = "AIzaSyCns8iba6zVqkddEUY_gqoc4eVxz-3BGaA"
DB = "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"


def http(method, url, body=None):
    req = urllib.request.Request(url, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or "null")


def anon_auth():
    d = http("POST",
        f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}",
        {"returnSecureToken": True})
    return d["localId"], d["idToken"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--code", required=True)
    ap.add_argument("--name", default="HarnessBot")
    ap.add_argument("--stay", type=float, default=60)
    ap.add_argument("--answer", type=int, default=None,
                    help="submit this choice for the current pub question, then exit")
    args = ap.parse_args()
    code = args.code.upper()

    uid, tok = anon_auth()
    base = f"{DB}/live/{code}"
    q = f"?auth={tok}"

    meta = http("GET", f"{base}/meta.json{q}")
    if not meta:
        sys.exit(f"room {code} does not exist (no meta)")
    print(f"[join] room {code} meta: state={meta.get('state')} name={meta.get('name')!r}")

    http("PUT", f"{base}/teams/{uid}.json{q}",
         {"name": args.name, "joinedAt": int(time.time() * 1000)})
    print(f"[join] joined as {args.name} (uid {uid[:8]}…)")

    if args.answer is not None:
        pub = http("GET", f"{base}/pub.json{q}") or {}
        qid = pub.get("qid") or pub.get("questionId") or "q0"
        http("PUT", f"{base}/answers/{qid}/{uid}.json{q}",
             {"choice": args.answer, "ts": int(time.time() * 1000)})
        print(f"[join] answered choice={args.answer} for {qid}")

    deadline = time.time() + args.stay
    while time.time() < deadline:
        pub = http("GET", f"{base}/pub.json{q}")
        score = http("GET", f"{base}/scores/{uid}.json{q}")
        print(f"[join] pub={json.dumps(pub)[:120]} score={score}")
        time.sleep(8)

    try:
        http("DELETE", f"{base}/teams/{uid}.json{q}")
        print("[join] left the room")
    except Exception:
        pass


if __name__ == "__main__":
    main()
