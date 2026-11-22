"""The App Store Connect API key for local tools: the environment (CI) first, then the login Keychain, never a
file left on disk. No value is printed here.

One Apple-team key serves every app. This app's own items (`tidbits:ASC_KEY_P8`, `:ASC_KEY_ID`,
`:ASC_ISSUER_ID`, one base64 token each, if ever imported) win; when they are
absent the shared items that Archive Watch's tools/secrets.sh keeps are used: account `archivewatch`, services
`archivewatch:ASC_KEY_P8`, `archivewatch:ASC_KEY_ID`, `archivewatch:ASC_ISSUER_ID`, each a chunk count with the
base64 pieces at `archivewatch:<NAME>.0 ... .n-1`. CI never reaches the Keychain: its key arrives as ASC_KEY_P8 or
as the file the workflow writes.
"""
import base64
import os
import subprocess
import sys


OWN = "tidbits"

SHARED_ACCOUNT = "archivewatch"


def _find(account, service):
    try:
        r = subprocess.run(["security", "find-generic-password", "-a", account, "-s", service, "-w"],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def _own(name):
    return _find(OWN, f"{OWN}:{name}")


def _shared(name):
    count = _find(SHARED_ACCOUNT, f"{SHARED_ACCOUNT}:{name}")
    if not count or not count.isdigit():
        return None
    parts = [_find(SHARED_ACCOUNT, f"{SHARED_ACCOUNT}:{name}.{i}") for i in range(int(count))]
    return None if any(p is None for p in parts) else "".join(parts)


def b64_item(name):
    """The base64 text of a Keychain value (ASC_KEY_P8 holds the .p8, the others a plain string), or None."""
    own = _own(name)
    if own:
        return own if name == "ASC_KEY_P8" else base64.b64encode(own.encode()).decode()
    return _shared(name)


def value(name):
    """ASC_KEY_ID or ASC_ISSUER_ID: the environment, then the Keychain."""
    v = os.environ.get(name)
    if v:
        return v
    b = b64_item(name)
    if not b:
        return None
    try:
        return base64.b64decode(b).decode().strip()
    except ValueError:
        return None


def key_pem(kid):
    """The .p8 as text: ASC_KEY_PATH, ASC_KEY_P8 (base64, CI), the Keychain, then the file a CI runner writes."""
    path = os.environ.get("ASC_KEY_PATH")
    if path:
        return open(path).read()
    b = os.environ.get("ASC_KEY_P8") or b64_item("ASC_KEY_P8")
    if b:
        return base64.b64decode(b).decode()
    return open(os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")).read()


def play_json():
    """The Play service-account JSON as text: the file named by PLAY_SERVICE_ACCOUNT_JSON (CI), then the Keychain
    (`tidbits:PLAY_SERVICE_ACCOUNT_JSON`, then the shared chunked `archivewatch:PLAY_SERVICE_ACCOUNT_JSON`, base64
    of the JSON). None when absent."""
    path = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON")
    if path and os.path.isfile(path):
        return open(path).read()
    b = _own("PLAY_SERVICE_ACCOUNT_JSON") or _shared("PLAY_SERVICE_ACCOUNT_JSON")
    if not b:
        return None
    try:
        return base64.b64decode(b).decode()
    except ValueError:
        return None


if __name__ == "__main__" and sys.argv[1:2] == ["write-play"]:
    text = play_json()
    if not text:
        sys.exit("asc_key.py: no Play service account in the Keychain")
    fd = os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
