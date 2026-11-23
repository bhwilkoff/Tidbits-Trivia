#!/usr/bin/env python3
"""send_reminders.py must not send to the same dead token every day.

Owner 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that." The cron sent to 37 FCM tokens that answered
404 (UNREGISTERED) every day. A fake RTDB and a fake FCM stand in for Google:
nothing here reaches the network.

    python3 tools/test_send_reminders.py
"""
import io
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))
import send_reminders as S

DAY = 86400


class Fake:
    def __init__(self, tokens, dead):
        self.db = {"pushTokens": tokens}
        self.dead = set(dead)
        self.sends = []

    def urlopen(self, req, timeout=None):
        if isinstance(req, str):
            req = urllib.request.Request(req)
        u = urllib.parse.urlparse(req.full_url)
        if u.hostname == "fcm.googleapis.com":
            token = json.loads(req.data)["message"]["token"]
            self.sends.append(token)
            if token in self.dead:
                raise urllib.error.HTTPError(req.full_url, 404, "Not Found", {}, io.BytesIO(
                    b'{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'))
            return io.BytesIO(b"{}")
        path = u.path.removesuffix(".json").strip("/")
        method = req.get_method()
        if method == "PATCH":
            for k, v in json.loads(req.data).items():
                self.put(f"{path}/{k}".strip("/"), v)
            return io.BytesIO(b"{}")
        node = self.db
        for part in [p for p in path.split("/") if p]:
            node = node.get(part) if isinstance(node, dict) else None
        return io.BytesIO(json.dumps(node).encode())

    def put(self, path, value):
        parts = path.split("/")
        node = self.db
        for p in parts[:-1]:
            node = node.setdefault(p, {})
        if value is None:
            node.pop(parts[-1], None)
        else:
            node[parts[-1]] = value


def run(fake, now):
    env = {"FCM_SERVICE_ACCOUNT": json.dumps({"project_id": "p"})}
    fake.sends.clear()
    with mock.patch.dict(os.environ, env, clear=False), \
            mock.patch.object(S, "google_token", lambda *a: "tok"), \
            mock.patch.object(S.urllib.request, "urlopen", fake.urlopen), \
            mock.patch.object(S, "now_s", lambda: now, create=True), \
            mock.patch("sys.stdout", io.StringIO()) as out:
        S.main()
    return list(fake.sends), out.getvalue()


def main():
    t0 = 1_800_000_000
    fake = Fake({"alive": {"android": "good"}, "gone": {"android": "dead"}}, dead={"dead"})

    sends, _ = run(fake, t0)
    assert sorted(sends) == ["dead", "good"], sends

    sends, _ = run(fake, t0 + DAY)
    assert sends == ["good"], f"a token FCM called UNREGISTERED was sent to again the next day: {sends}"

    # Backoff grows and then stops: never more than the cap, however long the cron runs.
    tries = 1
    for day in range(2, 120):
        sends, out = run(fake, t0 + day * DAY)
        tries += sends.count("dead")
    assert tries <= S.MAX_TRIES, f"a dead token was tried {tries} times in 120 days"
    assert "given up" in out, out

    # A new token from the device opens it again.
    fake.db["pushTokens"]["gone"]["android"] = "fresh"
    sends, _ = run(fake, t0 + 121 * DAY)
    assert sorted(sends) == ["fresh", "good"], sends

    # A token that works clears its record.
    assert not (fake.db.get("pushFailures") or {}).get("gone"), fake.db.get("pushFailures")
    print("send_reminders: a failed token waits 1, 7, 30 days, stops at the cap, and a new token reopens it")


if __name__ == "__main__":
    main()
