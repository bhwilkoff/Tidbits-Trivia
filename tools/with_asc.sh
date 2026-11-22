#!/bin/bash
# Run a command with the App Store Connect API key from the login Keychain, never from a file left on disk.
# The Key ID and Issuer ID are exported, and the .p8 is written to a private temporary directory (ASC_KEY_PATH)
# that is removed when the command ends.
#   tools/with_asc.sh tools/submit-appstore.sh ...
#   tools/with_asc.sh python3 tools/asc_certs.py ...
# This app's own items win (account tidbits, one base64 token each, optional).
# Without them the ONE shared Apple-team key is used: account
# `archivewatch`, services `archivewatch:ASC_KEY_P8`, `archivewatch:ASC_KEY_ID`, `archivewatch:ASC_ISSUER_ID`
# (a chunk count, then base64 pieces at `archivewatch:<NAME>.0 ...`; written by Archive Watch's secrets.sh).
# In CI the three values are already in the environment from GitHub Actions secrets, and nothing is read here.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: tools/with_asc.sh COMMAND [ARGS...]" >&2; exit 2; }
if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || { [ -z "${ASC_KEY_PATH:-}" ] && [ ! -f "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" ]; }; then
  OWN=tidbits
  SHARED=archivewatch
  item() { security find-generic-password -a "$1" -s "$2" -w 2>/dev/null; }
  shared() { local n i out=""; n="$(item "$SHARED" "$SHARED:$1")" || return 1; [[ "$n" =~ ^[0-9]+$ ]] || return 1
             for ((i = 0; i < n; i++)); do out+="$(item "$SHARED" "$SHARED:$1.$i")" || return 1; done; printf '%s' "$out"; }
  # base64 of the value: ASC_KEY_P8 is stored as the base64 of the .p8, the ids as plain text in the app's own items
  b64_of() {
    local v
    if v="$(item "$OWN" "$OWN:$1")" && [ -n "$v" ]; then
      if [ "$1" = ASC_KEY_P8 ]; then printf '%s' "$v"; else printf '%s' "$v" | base64 | tr -d '\n'; fi
    else
      shared "$1"
    fi
  }
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT
  chmod 700 "$dir"
  export ASC_KEY_ID="$(b64_of ASC_KEY_ID | base64 -d)" ASC_ISSUER_ID="$(b64_of ASC_ISSUER_ID | base64 -d)"
  [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ] || { echo "with_asc.sh: no ASC key in the Keychain (Archive Watch's shared items, or tidbits:ASC_* items)" >&2; exit 1; }
  b64_of ASC_KEY_P8 | base64 -d > "$dir/AuthKey_$ASC_KEY_ID.p8"
  [ -s "$dir/AuthKey_$ASC_KEY_ID.p8" ] || { echo "with_asc.sh: the ASC .p8 is not in the Keychain" >&2; exit 1; }
  chmod 600 "$dir/AuthKey_$ASC_KEY_ID.p8"
  export ASC_KEY_PATH="$dir/AuthKey_$ASC_KEY_ID.p8"
  "$@"
else
  exec "$@"
fi
