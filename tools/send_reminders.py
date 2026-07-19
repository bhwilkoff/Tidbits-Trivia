#!/usr/bin/env python3
"""The reminders cron — "the appointment" (docs/PUSH-CONTRACT.md).

Reads the owner-only push-token registry + today's Daily board, works out who has a token
but hasn't played today, and sends "Your Daily is ready" via three $0 legs: APNs-direct
(iOS), FCM HTTP v1 (Android), Web Push/VAPID (web). Driven by .github/workflows/reminders.yml.

$0, no always-on server. INERT until the owner adds the secrets (§Owner setup in the
contract) — every leg is skipped cleanly when its secret is absent, so the workflow is
safe to enable before the setup is complete. All send legs import lazily so a missing
library never crashes the run.

Env (all optional; a leg runs only if its inputs are present):
  FCM_SERVICE_ACCOUNT   JSON — RTDB admin read + FCM send
  APNS_AUTH_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID   — iOS
  VAPID_PRIVATE_KEY, VAPID_SUBJECT   — web
"""
import datetime
import json
import os
import sys
import urllib.request

RTDB = "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"
TITLE = "Your Daily is ready"
BODY = "Today's seven are up. Keep your streak — and see where you land against the world."


def today() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%d")


def google_token(sa_json: str, scopes: list[str]) -> str | None:
    """Mint a short-lived OAuth access token from a service-account JSON (headless)."""
    try:
        from google.oauth2 import service_account
        import google.auth.transport.requests
    except ImportError:
        print("google-auth not installed; skipping FCM/RTDB-admin legs")
        return None
    info = json.loads(sa_json)
    creds = service_account.Credentials.from_service_account_info(info, scopes=scopes)
    creds.refresh(google.auth.transport.requests.Request())
    return creds.token


def admin_get(path: str, access_token: str) -> dict:
    url = f"{RTDB}/{path}.json?access_token={access_token}"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r) or {}


def recipients(push_tokens: dict, played: set[str]) -> dict:
    """{uid: {platform: token}} for uids with a token who have NOT played today."""
    out = {}
    for uid, platforms in (push_tokens or {}).items():
        if uid in played or not isinstance(platforms, dict):
            continue
        out[uid] = platforms
    return out


def send_apns(token: str, cfg: dict) -> bool:
    try:
        import jwt  # PyJWT
        import httpx
    except ImportError:
        return False
    now = int(datetime.datetime.now().timestamp())
    auth = jwt.encode({"iss": cfg["team"], "iat": now},
                      cfg["key"], algorithm="ES256", headers={"kid": cfg["kid"]})
    payload = {"aps": {"alert": {"title": TITLE, "body": BODY}, "sound": "default"}}
    headers = {"authorization": f"bearer {auth}", "apns-topic": cfg["bundle"],
               "apns-push-type": "alert", "apns-priority": "10"}
    try:
        with httpx.Client(http2=True) as c:
            resp = c.post(f"https://api.push.apple.com/3/device/{token}",
                          headers=headers, json=payload, timeout=20)
        return resp.status_code == 200
    except Exception as e:
        print(f"  apns error: {e}")
        return False


def send_fcm(token: str, project: str, access_token: str) -> bool:
    body = json.dumps({"message": {"token": token,
                                   "notification": {"title": TITLE, "body": BODY}}}).encode()
    req = urllib.request.Request(
        f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
        data=body, headers={"Authorization": f"Bearer {access_token}",
                            "Content-Type": "application/json"}, method="POST")
    try:
        urllib.request.urlopen(req, timeout=20)
        return True
    except Exception as e:
        print(f"  fcm error: {e}")
        return False


def send_web(sub, vapid_key: str, subject: str) -> bool:
    try:
        from pywebpush import webpush
    except ImportError:
        return False
    try:
        webpush(subscription_info=sub if isinstance(sub, dict) else json.loads(sub),
                data=json.dumps({"title": TITLE, "body": BODY}),
                vapid_private_key=vapid_key, vapid_claims={"sub": subject})
        return True
    except Exception as e:
        print(f"  web error: {e}")
        return False


def main():
    sa = os.environ.get("FCM_SERVICE_ACCOUNT")
    if not sa:
        print("FCM_SERVICE_ACCOUNT not set — push is not configured yet; nothing to do.")
        return
    project = json.loads(sa).get("project_id", "tidbits-trivia-f2ddb")
    token = google_token(sa, ["https://www.googleapis.com/auth/firebase.database",
                              "https://www.googleapis.com/auth/firebase.messaging",
                              "https://www.googleapis.com/auth/userinfo.email"])
    if not token:
        return

    push_tokens = admin_get("pushTokens", token)
    board = admin_get(f"dailyBoard/{today()}", token)
    played = set(board.keys()) if isinstance(board, dict) else set()
    targets = recipients(push_tokens, played)
    print(f"{len(targets)} recipient(s) with a token who haven't played {today()}")

    apns_cfg = None
    if all(os.environ.get(k) for k in ("APNS_AUTH_KEY_P8", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID")):
        apns_cfg = {"key": os.environ["APNS_AUTH_KEY_P8"], "kid": os.environ["APNS_KEY_ID"],
                    "team": os.environ["APNS_TEAM_ID"], "bundle": os.environ["APNS_BUNDLE_ID"]}
    vapid_key = os.environ.get("VAPID_PRIVATE_KEY")
    vapid_sub = os.environ.get("VAPID_SUBJECT", "mailto:ben@learningischange.com")

    sent = {"ios": 0, "android": 0, "web": 0}
    for uid, platforms in targets.items():
        if apns_cfg and "ios" in platforms and send_apns(platforms["ios"], apns_cfg):
            sent["ios"] += 1
        if "android" in platforms and send_fcm(platforms["android"], project, token):
            sent["android"] += 1
        if vapid_key and "web" in platforms and send_web(platforms["web"], vapid_key, vapid_sub):
            sent["web"] += 1
    print(f"sent: {sent}")


if __name__ == "__main__":
    main()
