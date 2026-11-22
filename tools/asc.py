#!/usr/bin/env python3
"""Tiny App Store Connect API client — authoritative state, not screen-scraping.

The launch checklist kept going stale because it was written from memory and from
the console UI. This asks the API instead, so "is the IAP submitted" has an answer
with a timestamp on it.

Auth uses the same ES256 key the cloud build already uses
(the login Keychain, tools/asc_key.py).

    python3 tools/asc.py apps
    python3 tools/asc.py get 'v1/apps/<id>/inAppPurchasesV2?limit=200'
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com/"


def token():
    try:
        import jwt
    except ImportError:
        sys.exit("pip install pyjwt cryptography (or use tools/.play-venv)")
    import asc_key
    kid = asc_key.value("ASC_KEY_ID") or sys.exit("no ASC_KEY_ID (environment or Keychain)")
    iss = asc_key.value("ASC_ISSUER_ID") or sys.exit("no ASC_ISSUER_ID (environment or Keychain)")
    key = asc_key.key_pem(kid)
    now = int(time.time())
    return jwt.encode(
        {"iss": iss, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def call(path, method="GET", body=None, tok=None):
    tok = tok or token()
    url = path if path.startswith("http") else BASE + path.lstrip("/")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            detail = json.dumps(json.loads(detail), indent=2)
        except Exception:
            pass
        return {"_error": e.code, "_detail": detail}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "apps":
        d = call("v1/apps?limit=200")
        for a in d.get("data", []):
            at = a["attributes"]
            print(f'{a["id"]}  {at.get("bundleId"):<45} {at.get("name")}')
        if "_error" in d:
            print(d["_detail"])
    elif cmd == "get":
        print(json.dumps(call(sys.argv[2]), indent=2)[:20000])
    elif cmd == "post":
        print(json.dumps(call(sys.argv[2], "POST", json.loads(sys.argv[3])), indent=2)[:8000])
    elif cmd == "patch":
        print(json.dumps(call(sys.argv[2], "PATCH", json.loads(sys.argv[3])), indent=2)[:8000])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
