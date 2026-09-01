#!/usr/bin/env python3
"""Upload store screenshots to App Store Connect.

Built for the iMessage sets, which are the ones with no other route: the app's own
screenshots come out of `tools/capture-screenshots.sh` and get dragged into the
console, but an iMessage app needs its OWN sets and Connect refuses the version
without them ("You must upload an iMessage screenshot").

Runs in CI, not here. The ASC issuer id lives in GitHub secrets and should stay
there — `.github/workflows/imessage-screenshots.yml` passes it in.

    ASC_KEY_ID=... ASC_ISSUER_ID=... python3 tools/asc_screenshots.py \
        --set IMESSAGE_APP_IPHONE_67=branding/store-screenshots/imessage-iphone-6.9 \
        --set IMESSAGE_APP_IPAD_PRO_3GEN_129=branding/store-screenshots/imessage-ipad-13

Add --replace to clear a set first; without it, an existing set is left alone so a
re-run cannot silently duplicate a panel.
"""
import argparse
import hashlib
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com/"
BUNDLE = "com.learningischange.tidbitstrivia"


def token():
    import jwt
    kid = os.environ.get("ASC_KEY_ID") or sys.exit("set ASC_KEY_ID")
    iss = os.environ.get("ASC_ISSUER_ID") or sys.exit("set ASC_ISSUER_ID")
    key = os.environ.get("ASC_KEY_P8")
    if not key:
        path = os.environ.get(
            "ASC_KEY_PATH",
            os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8"))
        key = pathlib.Path(path).read_text()
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 19 * 60,
                       "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


TOK = None


def call(path, method="GET", body=None, raw_ok=False):
    req = urllib.request.Request(
        BASE + path.lstrip("/"), method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {TOK}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        # Print Apple's own message. Guessing at enum values (the display types are
        # not obvious) wastes far more time than reading the rejection.
        raise SystemExit(f"\nASC {method} {path} -> HTTP {e.code}\n{detail}\n")


def upload_bytes(op, data):
    req = urllib.request.Request(op["url"], method=op["method"],
                                 data=data[op["offset"]:op["offset"] + op["length"]])
    for h in op.get("requestHeaders", []):
        req.add_header(h["name"], h["value"])
    with urllib.request.urlopen(req) as r:
        r.read()


def editable_version(app_id):
    """The version currently being prepared, not the one that is already live."""
    vs = call(f"v1/apps/{app_id}/appStoreVersions?limit=50"
              "&filter[platform]=IOS&fields[appStoreVersions]=versionString,appStoreState")
    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW",
                "READY_FOR_REVIEW"}
    for v in vs["data"]:
        if v["attributes"]["appStoreState"] in editable:
            return v
    states = [(v["attributes"]["versionString"], v["attributes"]["appStoreState"])
              for v in vs["data"][:5]]
    raise SystemExit(f"no editable iOS version; recent: {states}")


def main():
    global TOK
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", action="append", required=True,
                    metavar="DISPLAY_TYPE=DIR",
                    help="e.g. IMESSAGE_APP_IPHONE_67=branding/store-screenshots/...")
    ap.add_argument("--locale", default="en-US")
    ap.add_argument("--replace", action="store_true",
                    help="delete the set's existing screenshots first")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    TOK = token()

    apps = call(f"v1/apps?filter[bundleId]={BUNDLE}")
    if not apps["data"]:
        raise SystemExit(f"no app for bundle {BUNDLE}")
    app_id = apps["data"][0]["id"]
    ver = editable_version(app_id)
    print(f"app {app_id} · version {ver['attributes']['versionString']} "
          f"({ver['attributes']['appStoreState']})")

    locs = call(f"v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")
    loc = next((l for l in locs["data"]
                if l["attributes"]["locale"] == a.locale), None)
    if loc is None:
        have = [l["attributes"]["locale"] for l in locs["data"]]
        raise SystemExit(f"locale {a.locale} not found; have {have}")
    print(f"locale {a.locale} -> {loc['id']}")

    sets = call(f"v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50")
    by_type = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in sets["data"]}
    print(f"existing sets: {sorted(by_type) or '(none)'}")

    for spec in a.set:
        dtype, _, dirname = spec.partition("=")
        files = sorted(pathlib.Path(dirname).glob("*.png"))
        if not files:
            raise SystemExit(f"no PNGs in {dirname}")
        print(f"\n== {dtype} <- {dirname} ({len(files)} files)")

        set_id = by_type.get(dtype)
        if set_id and a.replace and not a.dry_run:
            existing = call(f"v1/appScreenshotSets/{set_id}/appScreenshots?limit=50")
            for s in existing["data"]:
                call(f"v1/appScreenshots/{s['id']}", method="DELETE")
            print(f"   cleared {len(existing['data'])} existing")
        elif set_id and not a.replace:
            existing = call(f"v1/appScreenshotSets/{set_id}/appScreenshots?limit=50")
            if existing["data"]:
                print(f"   set already has {len(existing['data'])} — skipping "
                      f"(pass --replace to overwrite)")
                continue

        if a.dry_run:
            for f in files:
                print(f"   would upload {f.name} ({f.stat().st_size} bytes)")
            continue

        if not set_id:
            created = call("v1/appScreenshotSets", method="POST", body={"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": dtype},
                "relationships": {"appStoreVersionLocalization": {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})
            set_id = created["data"]["id"]
            print(f"   created set {set_id}")

        for f in files:
            data = f.read_bytes()
            reserved = call("v1/appScreenshots", method="POST", body={"data": {
                "type": "appScreenshots",
                "attributes": {"fileSize": len(data), "fileName": f.name},
                "relationships": {"appScreenshotSet": {"data": {
                    "type": "appScreenshotSets", "id": set_id}}}}})
            sid = reserved["data"]["id"]
            for op in reserved["data"]["attributes"]["uploadOperations"]:
                upload_bytes(op, data)
            # The checksum is what turns a reserved row into a real screenshot; skip
            # it and the asset sits in the set forever as an empty placeholder.
            call(f"v1/appScreenshots/{sid}", method="PATCH", body={"data": {
                "type": "appScreenshots", "id": sid,
                "attributes": {"uploaded": True,
                               "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            print(f"   ✓ {f.name}")

    print("\ndone")


if __name__ == "__main__":
    main()
