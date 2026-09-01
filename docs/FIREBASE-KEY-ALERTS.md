# The "Google API Key exposed" alert

GitGuardian flags a Google API key in this repo. **It is a Firebase Web API key, it
is not a secret, and it is supposed to be there.** This note exists so the alert does
not get re-investigated from scratch every time it fires — and so a real one is not
lost in the noise.

Investigated 2026-09-01.

## What the alert is seeing

Two client keys, in seven places, all of which need them:

| Key | Where |
|---|---|
| `AIzaSyCns8…3BGaA` (shared client) | `TidbitsTrivia/Core/Networking/FirebaseRTDB.swift`, `js/firebase-config.js`, `windows/Tidbits.Core/Networking/FirebaseRtdb.cs`, `tools/multiplayer_run.py`, `tools/rtdb_join.py` |
| `AIzaSyAor5…I3vzQ` (Android) | `android/app/google-services.json` (×2) |

Every Firebase client needs its project's API key compiled in. It is an **identifier
for the project**, not a credential: it says *which* Firebase project to talk to, and
grants nothing on its own. Google documents it as safe to include in client code, and
there is no way to ship a Firebase client app without it — extracting it from any
installed app is trivial regardless of what the repo contains.

## What actually protects the data

`database.rules.json`, and the rules are tight:

- **Nothing is world-readable.** Every path requires `auth != null`.
- **A player can only write their own row** — `live/$code/teams/$uid` and
  `answers/$qid/$uid` both require `auth.uid === $uid`.
- **Only the host can mutate a room** — `pub`, `scores` and room deletion all check
  `meta/host === auth.uid`.
- **Profiles are owner-only** — `players/$key` requires the uid to match, or a
  verified-email ownership record.

This is not theoretical. The multiplayer harness in this repo hits it constantly:
every run logs `could not clear roster: HTTP Error 401: Unauthorized`, because an
anonymous client is correctly refused permission to delete another player's row. The
rules are enforced and observably working.

## Was anything new leaked?

No. The pushes on 2026-09-01 touched `data/daily/*.json`, `docs/IMESSAGE-SUBMISSION.md`
and `tools/capture-imessage-screenshots.sh` — none of which contain a key. GitGuardian
rescans the whole repository on each push and re-reports pre-existing matches, so the
alert's "pushed date" is the date of *a* push, not of the key's introduction.

Also checked: no service-account JSON, no PEM private key, nothing under
`~/.config` or `~/keystores` committed. The one `-----BEGIN` match is a regex in
`workers/tidbits-auth/src/admin.js` that *strips* PEM headers while signing a JWT.

## What is still worth doing (owner, Google Cloud Console)

Being non-secret is not the same as being unrestricted. Two things genuinely reduce
risk and neither is done from this repo:

1. **Restrict the API keys.** Console → APIs & Services → Credentials. Restrict the
   web key by HTTP referrer (`tidbitstrivia.com`), the iOS key by bundle id, the
   Android key by package + signing certificate. An unrestricted key can be pointed at
   *other* APIs enabled on the project and burn quota or billing — that is the real
   exposure, and it has nothing to do with the RTDB.
2. **Consider Firebase App Check.** It attests that traffic comes from your genuine
   apps, which closes the "someone extracted the key from the IPA" path that rules
   alone cannot.

## What to do with the alert

Mark it resolved / accepted-risk in GitGuardian rather than leaving it open. An alert
channel that fires on a known-safe, unavoidable value trains everyone to ignore it —
and the next alert might be a real one.

**Rotating these keys would not improve security** and would require shipping a new
build to every platform. It is not the fix.
