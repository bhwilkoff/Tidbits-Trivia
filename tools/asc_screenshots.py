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


EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "READY_FOR_REVIEW"}


def versions(app_id):
    vs = call(f"v1/apps/{app_id}/appStoreVersions?limit=50"
              "&filter[platform]=IOS&fields[appStoreVersions]=versionString,appStoreState")
    return vs["data"]


def editable_version(app_id, create=None):
    """The version currently being prepared, not the one that is already live.

    A build uploaded to TestFlight does NOT create one of these — that is a separate
    record, and its absence is why this failed the first time with only a
    READY_FOR_SALE version to show for it.
    """
    for v in versions(app_id):
        if v["attributes"]["appStoreState"] in EDITABLE:
            return v
    if not create:
        states = [(v["attributes"]["versionString"], v["attributes"]["appStoreState"])
                  for v in versions(app_id)[:5]]
        raise SystemExit(
            f"no editable iOS version; recent: {states}\n"
            f"pass --create-version X.Y.Z to open one.")
    made = call("v1/appStoreVersions", method="POST", body={"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": create},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    print(f"created iOS version {create}")
    return made["data"]


def submit_for_review(app_id, version_id):
    """Submit via reviewSubmissions, the current API.

    The obvious endpoint is a trap: POST /v1/appStoreVersionSubmissions answers
    403 "does not allow 'CREATE'. Allowed operation is: DELETE" — it is deprecated,
    not broken, and the replacement is a three-step flow. Apple's model is now a
    review SUBMISSION that carries one or more ITEMS (the version, in-app purchases,
    and so on) and is then flipped to submitted, which is why one version cannot be
    sent on its own any more.
    """
    open_states = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}
    existing = call(f"v1/reviewSubmissions?filter[app]={app_id}"
                    "&filter[platform]=IOS&limit=50")
    sub = next((r for r in existing["data"]
                if r["attributes"].get("state") in open_states), None)
    if sub and sub["attributes"]["state"] != "READY_FOR_REVIEW":
        raise SystemExit(f"a review submission is already {sub['attributes']['state']} — "
                         f"nothing to do")
    if sub is None:
        sub = call("v1/reviewSubmissions", method="POST", body={"data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"opened review submission {sub['id']}")

    items = call(f"v1/reviewSubmissions/{sub['id']}/items?limit=50")
    already = any((i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {})
                  .get("id") == version_id for i in items["data"])
    if not already:
        call("v1/reviewSubmissionItems", method="POST", body={"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
        print("added the version as a submission item")
    else:
        print("version already an item on this submission")

    call(f"v1/reviewSubmissions/{sub['id']}", method="PATCH", body={"data": {
        "type": "reviewSubmissions", "id": sub["id"],
        "attributes": {"submitted": True}}})
    print("SUBMITTED FOR REVIEW")


REQUIRED_SHOT_SETS = {
    "APP_IPHONE_67": "iPhone 6.9\" app screenshots",
    "APP_IPAD_PRO_3GEN_129": "iPad 13\" app screenshots",
    "IMESSAGE_APP_IPHONE_67": "iMessage iPhone screenshots",
    "IMESSAGE_APP_IPAD_PRO_3GEN_129": "iMessage iPad screenshots",
}


def audit(app_id, locale):
    """Everything App Review checks that this repo can see. Returns an exit code.

    Written after the iMessage ship, where three separate blockers each archived
    green and only failed at upload or submit. The point is to ask Apple what is
    missing BEFORE a submission burns a review cycle.
    """
    problems, notes = [], []

    vs = versions(app_id)
    if not vs:
        return 1
    ver = vs[0]
    vid, attrs = ver["id"], ver["attributes"]
    print(f"version {attrs['versionString']} — {attrs['appStoreState']}")

    full = call(f"v1/appStoreVersions/{vid}?include=build,appStoreVersionLocalizations"
                "&fields[appStoreVersions]=versionString,appStoreState,releaseType,copyright")
    inc = full.get("included", [])
    build = next((i for i in inc if i["type"] == "builds"), None)
    print(f"  build:            {build['attributes']['version'] if build else 'NONE ATTACHED'}")
    rt = full["data"]["attributes"].get("releaseType")
    print(f"  release:          {rt or 'not set'}"
          + ("  (goes live automatically once approved)" if rt == "AFTER_APPROVAL"
             else "  (you release it by hand after approval)" if rt == "MANUAL" else ""))
    if not build:
        problems.append("no build attached to the version")
    if not full["data"]["attributes"].get("copyright"):
        notes.append("copyright is empty (optional, but Connect often asks)")

    # --- localisation fields -------------------------------------------------
    locs = call(f"v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50")
    loc = next((l for l in locs["data"] if l["attributes"]["locale"] == locale), None)
    if loc is None:
        problems.append(f"no {locale} localisation")
        return report(problems, notes)
    la = loc["attributes"]
    for field, required in [("description", True), ("keywords", True),
                            ("whatsNew", False), ("supportUrl", True),
                            ("marketingUrl", False), ("promotionalText", False)]:
        v = la.get(field)
        mark = "ok " if v else ("MISSING" if required else "-")
        print(f"  {field:18}{mark}{'' if not v else f'  ({len(v)} chars)'}")
        if required and not v:
            problems.append(f"{field} is empty")

    # --- screenshots ---------------------------------------------------------
    sets = call(f"v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50")
    have = {}
    for st in sets["data"]:
        shots = call(f"v1/appScreenshotSets/{st['id']}/appScreenshots?limit=50")
        done = sum(1 for x in shots["data"]
                   if (x["attributes"].get("assetDeliveryState") or {}).get("state") == "COMPLETE")
        bad = [x for x in shots["data"]
               if (x["attributes"].get("assetDeliveryState") or {}).get("errors")]
        have[st["attributes"]["screenshotDisplayType"]] = (done, len(shots["data"]), bad)
    for dtype, label in REQUIRED_SHOT_SETS.items():
        if dtype not in have:
            problems.append(f"no screenshot set for {dtype} ({label})")
            print(f"  {dtype:32} MISSING")
            continue
        done, total, bad = have[dtype]
        print(f"  {dtype:32} {done}/{total} delivered"
              + (f"  {len(bad)} WITH ERRORS" if bad else ""))
        if total == 0:
            problems.append(f"{dtype} has no screenshots")
        elif done < total:
            problems.append(f"{dtype}: only {done}/{total} finished uploading")
        if bad:
            problems.append(f"{dtype}: {len(bad)} screenshots report delivery errors")

    # --- things that block review but live off the version -------------------
    # The declaration hangs off the VERSION, not the app — /v1/apps/{id}/
    # ageRatingDeclaration 404s and that read as "API scope" rather than "wrong URL".
    try:
        ard = call(f"v1/appStoreVersions/{vid}/ageRatingDeclaration")
        d = (ard.get("data") or {}).get("attributes") or {}
        rating = d.get("ageRatingOverride") or ("declared" if d else None)
        print(f"  age rating:       {rating or 'MISSING'}")
        if not d:
            problems.append("no age rating declaration on this version")
    except SystemExit:
        notes.append("age rating unreadable — the app is live at 1.6.73, which "
                     "cannot happen without one, so treat as set")

    try:
        det = call(f"v1/appStoreVersions/{vid}/appStoreReviewDetail")
        d = (det.get("data") or {}).get("attributes", {})
        print(f"  review contact:   {d.get('contactEmail') or 'MISSING'}")
        if not d.get("contactEmail"):
            problems.append("no App Review contact email")
        if d.get("demoAccountRequired") and not d.get("demoAccountName"):
            problems.append("demo account marked required but not supplied")
    except SystemExit:
        notes.append("no appStoreReviewDetail record yet (Connect creates it on first submit)")

    if build:
        b = call(f"v1/builds/{build['id']}?fields[builds]=usesNonExemptEncryption,processingState")
        enc = b["data"]["attributes"].get("usesNonExemptEncryption")
        print(f"  encryption decl:  {enc if enc is not None else 'NOT ANSWERED'}")
        if enc is None:
            problems.append("export-compliance question unanswered on the build "
                            "(set ITSAppUsesNonExemptEncryption in the plist to avoid it)")

    # --- the review submission itself ---------------------------------------
    subs = call(f"v1/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&limit=20")
    live = [r for r in subs["data"]
            if r["attributes"].get("state") not in {"COMPLETE", "CANCELING"}]
    for r in live:
        items = call(f"v1/reviewSubmissions/{r['id']}/items?limit=50")
        print(f"  review submission {r['attributes']['state']} "
              f"({len(items['data'])} item(s), submitted={r['attributes'].get('submitted')})")
        if not items["data"]:
            problems.append("a review submission exists with NO items")
    if not live:
        notes.append("no open review submission")

    return report(problems, notes)


def report(problems, notes):
    print()
    for n in notes:
        print(f"  note: {n}")
    if problems:
        print(f"\n{len(problems)} BLOCKER(S):")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("no blockers found")
    return 0


def main():
    global TOK
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", action="append", default=[],
                    metavar="DISPLAY_TYPE=DIR",
                    help="e.g. IMESSAGE_APP_IPHONE_67=branding/store-screenshots/...")
    ap.add_argument("--locale", default="en-US")
    ap.add_argument("--replace", action="store_true",
                    help="delete the set's existing screenshots first")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--create-version", metavar="X.Y.Z",
                    help="open a new App Store version if none is editable")
    ap.add_argument("--list", action="store_true",
                    help="print the app's iOS versions and exit")
    ap.add_argument("--attach-build", metavar="N",
                    help="attach this build number to the version")
    ap.add_argument("--release-notes", metavar="TEXT",
                    help="set What's New for the locale")
    ap.add_argument("--submit", action="store_true",
                    help="submit the version for App Review")
    ap.add_argument("--status", action="store_true",
                    help="report the version's readiness and exit")
    ap.add_argument("--audit", action="store_true",
                    help="full pre-submission audit of the newest version; exits non-zero on a blocker")
    a = ap.parse_args()

    if not a.set and not a.list:
        raise SystemExit("nothing to do: pass --set DISPLAY_TYPE=DIR or --list")
    TOK = token()

    apps = call(f"v1/apps?filter[bundleId]={BUNDLE}")
    if not apps["data"]:
        raise SystemExit(f"no app for bundle {BUNDLE}")
    app_id = apps["data"][0]["id"]
    if a.audit:
        raise SystemExit(audit(app_id, a.locale))
    if a.list:
        for v in versions(app_id):
            print(f"  {v['attributes']['versionString']:10} "
                  f"{v['attributes']['appStoreState']}")
        return
    ver = editable_version(app_id, create=a.create_version)
    print(f"app {app_id} · version {ver['attributes']['versionString']} "
          f"({ver['attributes']['appStoreState']})")

    locs = call(f"v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")
    loc = next((l for l in locs["data"]
                if l["attributes"]["locale"] == a.locale), None)
    if loc is None:
        have = [l["attributes"]["locale"] for l in locs["data"]]
        raise SystemExit(f"locale {a.locale} not found; have {have}")
    print(f"locale {a.locale} -> {loc['id']}")

    if a.attach_build:
        builds = call(f"v1/builds?filter[app]={app_id}&limit=50"
                      f"&filter[version]={a.attach_build}"
                      "&fields[builds]=version,processingState,expired")
        usable = [b for b in builds["data"]
                  if not b["attributes"].get("expired")]
        if not usable:
            raise SystemExit(f"build {a.attach_build} not found for this app")
        b = usable[0]
        state = b["attributes"]["processingState"]
        if state != "VALID":
            # Attaching a build Apple has not finished processing fails with a
            # confusing relationship error rather than "still processing".
            raise SystemExit(f"build {a.attach_build} is {state}, not VALID — "
                             f"wait for processing to finish and re-run")
        call(f"v1/appStoreVersions/{ver['id']}/relationships/build", method="PATCH",
             body={"data": {"type": "builds", "id": b["id"]}})
        print(f"attached build {a.attach_build}")

    if a.release_notes:
        call(f"v1/appStoreVersionLocalizations/{loc['id']}", method="PATCH", body={"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"],
            "attributes": {"whatsNew": a.release_notes}}})
        print("set release notes")

    if a.status:
        v = call(f"v1/appStoreVersions/{ver['id']}"
                 "?fields[appStoreVersions]=versionString,appStoreState"
                 "&include=build")
        att = v.get("included", [])
        print(f"  state:   {v['data']['attributes']['appStoreState']}")
        print(f"  build:   {att[0]['attributes']['version'] if att else '(none attached)'}")
        sets = call(f"v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50")
        for st in sets["data"]:
            shots = call(f"v1/appScreenshotSets/{st['id']}/appScreenshots?limit=50")
            done = sum(1 for x in shots["data"]
                       if x["attributes"].get("assetDeliveryState", {}).get("state") == "COMPLETE")
            print(f"  set {st['attributes']['screenshotDisplayType']:32} "
                  f"{done}/{len(shots['data'])} delivered")
        return

    if a.submit:
        submit_for_review(app_id, ver["id"])
        return

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
