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
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

RTDB = "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"
TITLE = "Your Daily is ready"
BODY = "Today's seven are up. Keep your streak — and see where you land against the world."

# A token that failed waits before it is tried again, longer each time, and then is given
# up on and reported, never retried daily (owner 2026-11-23: "fix the re-scan of the exact
# same failures. We should never build something that does that."). The push service saying
# the token is gone (404/410/400) starts at a week; a 429/5xx/network blip at a day. A new
# token from the device is a new record, so reinstalling opens it again.
DAY = 86400
WAITS = {True: (7, 30), False: (1, 7, 30)}
MAX_TRIES = max(len(w) for w in WAITS.values()) + 1
FAILURES = "pushFailures"


def now_s() -> float:
    return time.time()


def token_key(token) -> str:
    raw = token if isinstance(token, str) else json.dumps(token, sort_keys=True)
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def due(record, token, now) -> bool:
    """Send unless this same token failed and its wait is not over, or it has been given up on."""
    if not isinstance(record, dict) or record.get("token") != token_key(token):
        return True
    waits = WAITS[bool(record.get("permanent"))]
    tries = int(record.get("tries", 0))
    if tries > len(waits):
        return False
    return now - float(record.get("at", 0)) >= waits[tries - 1] * DAY


def failed(record, token, now, reason, permanent) -> dict:
    same = isinstance(record, dict) and record.get("token") == token_key(token)
    return {"token": token_key(token), "tries": (int(record.get("tries", 0)) if same else 0) + 1,
            "at": int(now), "reason": reason[:120], "permanent": bool(permanent)}


def given_up(record) -> bool:
    return isinstance(record, dict) and int(record.get("tries", 0)) > len(WAITS[bool(record.get("permanent"))])


def outcome(code: int | None, label: str):
    """(ok, reason, permanent); reason None means not the token's fault (our key), so nothing is recorded."""
    if code == 200:
        return True, None, False
    if code in (400, 404, 410):
        return False, f"{label} {code}", True
    if code is None or code == 429 or code >= 500:
        return False, f"{label} {code or 'network'}", False
    return False, None, False


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


def admin_patch(path: str, access_token: str, updates: dict) -> None:
    req = urllib.request.Request(f"{RTDB}/{path}.json?access_token={access_token}",
                                 data=json.dumps(updates).encode(), method="PATCH",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()


def recipients(push_tokens: dict, played: set[str]) -> dict:
    """{uid: {platform: token}} for uids with a token who have NOT played today."""
    out = {}
    for uid, platforms in (push_tokens or {}).items():
        if uid in played or not isinstance(platforms, dict):
            continue
        out[uid] = platforms
    return out


def send_apns(token: str, cfg: dict):
    try:
        import jwt  # PyJWT
        import httpx
    except ImportError:
        return False, None, False
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
        if resp.status_code != 200:
            print(f"  apns error: HTTP {resp.status_code}")
        return outcome(resp.status_code, "apns")
    except Exception as e:
        print(f"  apns error: {e}")
        return outcome(None, "apns")


def send_fcm(token: str, project: str, access_token: str):
    body = json.dumps({"message": {"token": token,
                                   "notification": {"title": TITLE, "body": BODY}}}).encode()
    req = urllib.request.Request(
        f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
        data=body, headers={"Authorization": f"Bearer {access_token}",
                            "Content-Type": "application/json"}, method="POST")
    try:
        urllib.request.urlopen(req, timeout=20)
        return outcome(200, "fcm")
    except urllib.error.HTTPError as e:
        print(f"  fcm error: {e}")
        return outcome(e.code, "fcm")
    except Exception as e:
        print(f"  fcm error: {e}")
        return outcome(None, "fcm")


def send_web(sub, vapid_key: str, subject: str):
    try:
        from pywebpush import webpush
    except ImportError:
        return False, None, False
    try:
        webpush(subscription_info=sub if isinstance(sub, dict) else json.loads(sub),
                data=json.dumps({"title": TITLE, "body": BODY}),
                vapid_private_key=vapid_key, vapid_claims={"sub": subject})
        return outcome(200, "web")
    except Exception as e:
        print(f"  web error: {e}")
        resp = getattr(e, "response", None)
        return outcome(getattr(resp, "status_code", None), "web")


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

    legs = {"ios": (lambda t: send_apns(t, apns_cfg)) if apns_cfg else None,
            "android": lambda t: send_fcm(t, project, token),
            "web": (lambda t: send_web(t, vapid_key, vapid_sub)) if vapid_key else None}
    failures = admin_get(FAILURES, token)
    now = now_s()
    sent = {"ios": 0, "android": 0, "web": 0}
    waiting, updates = 0, {}
    for uid, platforms in targets.items():
        mine = failures.get(uid) if isinstance(failures.get(uid), dict) else {}
        for platform, send in legs.items():
            if not send or platform not in platforms:
                continue
            t, record = platforms[platform], mine.get(platform)
            if not due(record, t, now):
                waiting += 1
                continue
            ok, reason, permanent = send(t)
            if ok:
                sent[platform] += 1
                if record is not None:
                    updates[f"{uid}/{platform}"] = None
            elif reason:
                updates[f"{uid}/{platform}"] = failed(record, t, now, reason, permanent)
    if updates:
        try:
            admin_patch(FAILURES, token, updates)
        except Exception as e:
            print(f"could not record failures ({e}); they will be tried again next run")
    merged = {u: dict(v) for u, v in failures.items() if isinstance(v, dict)}
    for k, v in updates.items():
        u, p = k.split("/")
        merged.setdefault(u, {})[p] = v
    gone = sum(1 for v in merged.values() for r in v.values() if given_up(r))
    print(f"sent: {sent}; {waiting} waiting after a failure; "
          f"{gone} given up after {MAX_TRIES} tries or fewer (until the device sends a new token)")


if __name__ == "__main__":
    main()
