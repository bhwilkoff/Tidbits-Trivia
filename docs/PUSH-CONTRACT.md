# Push notifications — "the appointment" ($0 data contract)

**Status: ANDROID + WEB SENDING ARE LIVE (2026-08-04). iOS is still gated on the
APNs `.p8`, which only Apple's Developer portal can issue.** The cron skips any
leg whose secret is absent, so it sends on two legs today and picks up the third
the moment the APNs secrets exist. The return-trigger every async global mode
depends on (MONETIZATION §4c: "async lives or dies on the return trigger").
Verified $0 on all three platforms from a GitHub Actions cron — **no card, no
always-on server.** The only unavoidable cost is the $99/yr Apple membership
already carried.

Governed by **R-NET-2** (the cron is the league office — it also sends the
reminders). Notifications are **user-value, transactional** ("your Daily is
ready", "you're about to lose your rundle spot"), never marketing — App Store
Guideline 4.5.4 compliant, with an in-app opt-out.

## Three send paths, one cron (not one unified path)

Because the Apple app has **no Firebase SDK** (hand-rolled `FirebaseRTDB` REST
client — CLAUDE.md "Apple frameworks only"), iOS cannot get an FCM token (there
is no REST swap for an APNs→FCM token). So iOS goes **direct to APNs**. The clean
shape is three independent $0 legs from the same cron:

| Platform | Send path | Client gets token via | Cron lib | Cost |
|---|---|---|---|---|
| iOS / iPadOS | **APNs-direct** (HTTP/2 + `.p8` ES256 JWT) | `UNUserNotificationCenter` + `registerForRemoteNotifications` | `aioapns`/`PyAPNs2` | $0 |
| Android | **FCM HTTP v1** | `FirebaseMessaging.getToken()` | `google-auth` + `requests` | $0 |
| Web | **Web Push + VAPID** | `pushManager.subscribe()` + service worker | `pywebpush` | $0 |

FCM is genuinely free to send on Spark (Firebase pricing: "Cloud Messaging:
No-cost", "No payment method needed"), unmetered, no Blaze required — Blaze is
only forced by Cloud Functions, which we don't use. APNs is free within the
Developer Program. Browser push services are free.

## The token registry — owner-only, keyed by auth uid

Push tokens are mildly sensitive (a send-capability handle), so they must **not**
go under the world-readable `players/{key}`. They mirror the `playersPrivate`
precedent — owner-only read/write, keyed by the **auth uid** (a token is
per-device; a device authenticates as a uid):

```
pushTokens/{uid}/{platform} = <token or subscription blob>
  # ios     -> hex APNs device token
  # android -> FCM registration token
  # web     -> JSON of the PushSubscription (endpoint + p256dh + auth)
```

Rule (mirrors `playersPrivate`):
```json
"pushTokens": {
  "$uid": {
    ".read":  "auth != null && auth.uid === $uid",
    ".write": "auth != null && auth.uid === $uid"
  }
}
```

Write-own-only, read-own-only: a client sets only its own token and cannot
enumerate anyone else's. One human with two devices → two uids under their
profile → "notify all my devices" for free. Email→uids (all a person's devices)
resolves server-side via the existing `emailOwners`/`players` linkage if needed.

## The cron reads all tokens as admin

Security rules gate *clients*; the cron reads the private `pushTokens` tree with
**admin credentials that bypass rules** — a Google OAuth token minted from the
**same FCM service account** (scopes `firebase.database` + `firebase.messaging`),
then `GET https://<db>.firebaseio.com/pushTokens.json?access_token=<oauth>`. One
key does double duty (FCM send + RTDB admin read). One extra read per tick, far
under Spark — same as `leaderboard.yml`.

## Owner setup (one-time, all free) — REQUIRED before push works

The send side is written (`tools/send_reminders.py` + `reminders.yml`) but inert
until these are done:

1. **APNs `.p8` Auth Key** — Apple Developer → Keys → new key with APNs enabled.
   Secrets: `APNS_AUTH_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_BUNDLE_ID=com.learningischange.tidbitstrivia`.
2. **iOS Push capability** — enable Push Notifications on the App ID (adds the
   `aps-environment` entitlement). *Do this before adding the entitlement to
   `project.yml`, or the signed cloud build breaks.*
3. **FCM service account** — **DONE 2026-08-04.** Key created with
   `gcloud iam service-accounts keys create` against
   `firebase-adminsdk-fbsvc@tidbits-trivia-f2ddb` and stored as the
   `FCM_SERVICE_ACCOUNT` repo secret. This one key does double duty: FCM send
   **and** the cron's admin read of the private `pushTokens` tree.
4. **VAPID keypair** (web) — **DONE 2026-08-03.** Generated with
   `npx web-push generate-vapid-keys`; the public half is wired into
   `js/push.js` (it is not a secret — it ships to every browser) and
   `VAPID_PRIVATE_KEY` + `VAPID_SUBJECT` are set as repo secrets. The web
   reminder toggle now renders, verified in Chrome.
5. Deploy the `pushTokens` rule (DONE — see below).

## Client behavior (all platforms)

- **Prompt with context, not on cold launch:** request notification permission
  *after* the player finishes a Daily, so the ask has a reason (better grant
  rate + reads better in review).
- On grant, get the token and write `pushTokens/{uid}/{platform}`. Re-upload on
  token rotation and on launch.
- An **in-app toggle** turns reminders off (4.5.4 requirement) — deletes the
  token node.

## What the cron sends

Daily, staggered off the hour (`:47`, off the `:17` leaderboard and `:34`
board crons): "Your Daily is ready" to anyone who hasn't played today. Later
modes add rundle-danger and duel-turn pushes. The cron reads `pushTokens` +
`dailyBoard/{today}` (who's played) and fans out to the three legs.

## Status

- ✅ RTDB `pushTokens` rule deployed + live-verified (owner-only enforced).
- ✅ `tools/send_reminders.py` + `.github/workflows/reminders.yml` written
  (inert until the owner secrets above exist — the workflow no-ops cleanly when
  secrets are absent).
- ✅ iOS token capture (`PushManager` + app-delegate hook + prompt after a Daily)
  — build-verified. **Entitlement is an owner step (§Owner setup 2).**
- ✅ **Android token capture (2026-08-03)** — `notifications/PushTokens` (runtime
  POST_NOTIFICATIONS ask after a Daily, `FirebaseMessaging.getToken()`,
  `pushTokens/{authUid}/android`) + `AppFirebaseMessagingService.onNewToken` for
  rotation + the `firebase-messaging` dependency and manifest service, which had
  been sitting commented out as "goes here when push ships".
- ✅ **Web token capture (2026-08-03)** — `js/push.js` subscribes through the
  existing service worker and stores the whole `PushSubscription` blob (what
  pywebpush wants back); `sw.js` gained `push` + `notificationclick` handlers
  (cache bumped to v57). Inert until the owner pastes the VAPID public key —
  with the placeholder in place the toggle does not render at all, because a
  switch that silently does nothing is worse than no switch.
- ✅ **The in-app opt-out now exists on all three** (it was required by §Client
  behavior and had never been built on ANY platform): iOS Settings →
  Notifications, Android Settings → Notifications, web Records → Settings.
  Turning it off **deletes the token node** — a local flag would leave the cron
  still reminding you — and the launch-time re-upload checks the same flag, or
  the next launch would quietly restore the token the player just deleted.
- Verified: iOS toggle screenshot-verified on the 17 Pro simulator, web toggle
  rendered + `enable()` proven to no-op cleanly with the placeholder key,
  Android compiles clean.
