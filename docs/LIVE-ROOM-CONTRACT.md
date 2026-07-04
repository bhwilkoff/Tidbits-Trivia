# Tidbits Live / Trivia Night — cross-platform room contract (Firebase RTDB)

The one backend that powers BOTH products (Decision 044): a **Mac-hosted Tidbits
Live** event (the marquee) AND a casual **Trivia Night** hosted from **any**
platform — iOS / iPadOS / tvOS / Android / **web**. Players on all six surfaces
join the same `live/{code}` room. One backend all reach: **Firebase RTDB** (project
`tidbits-trivia-f2ddb`, the same non-secret config as `js/firebase-config.js`).
GameKit is Apple-only and mDNS/TCP can't reach a browser, so RTDB is the only
common denominator.

**Hosts** (own `meta`/`pub`/`scores`): Trivia Night — `LiveHostNet`+`LiveNightHost`
(Apple), `FirebaseNet` host methods+`NightHostScreen` (Android), `js/firebase.js`
host methods+`openNightHost` (web). Tidbits Live — `MacLiveHostNet` (macOS only).

Swift source of truth: `TidbitsTrivia/Core/Networking/LiveRoom.swift` +
`FirebaseRTDB.swift`. Web mirror: `js/live.js`. Android mirror: `FirebaseNet.live*`.
**Additive-only** — never repurpose a key.

**Join surfaces (all built 2026-07-03):**
- **web** — `js/live.js`, route `#/live/CODE`.
- **iOS/iPadOS + tvOS** — the shared Core `LivePlayerClient` (@MainActor @Observable
  on the `FirebaseRTDB` REST client) behind `LiveJoinView` (iOS) / `TVLivePlayerView`
  (tvOS).
- **Android** — `FirebaseNet.live*` (real Firebase SDK) behind `LiveRoomScreen`.
- **Unified "Join a game"** (iOS/tvOS/Android): one code box probes `live/{code}/meta`
  (`FirebaseRTDB.exists` / `FirebaseNet.probeLive`); a hit opens the Live player, a
  miss falls back to the LAN Trivia Night. Web is Live-only (no mDNS in a browser).

## Tree — `live/{code}`

`{code}` is a 4-char room code (alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`,
no confusable chars) shown on the big screen for players to enter.

| Path | Writer | Shape |
|---|---|---|
| `meta` | host | `{ host: uid, createdAt: ms, name, venue, state: "lobby"\|"live"\|"ended" }` |
| `pub` | host | the live question state players render (see below) |
| `scores/{uid}` | host | integer — a team's running score (host owns scoring) |
| `teams/{uid}` | that player | `{ name, joinedAt: ms }` |
| `answers/{qid}/{uid}` | that player | `{ choice?: Int, text?: String, ts: ms }` |

### `pub` (host-published, players stream it)
```json
{
  "round": 1, "roundTitle": "History",
  "qid": "r0q3", "qNum": 3, "qTotal": 5,
  "phase": "question",            // intro | question | reveal | ended
  "prompt": "…", "options": ["A","B","C","D"], "format": "classic",
  "answerIndex": 2                // ONLY present in phase "reveal"
}
```
`qid = "r{roundIndex}q{questionIndex}"` is stable across reveal/advance so answers
key cleanly. `answerIndex` is withheld until reveal so a joined phone can't peek.

## Security rules (`database.rules.json` → `live`)

- **Host owns** `meta` / `pub` / `scores` — write gated on `meta/host === auth.uid`.
  First `meta` write (room creation) is allowed because `!data.exists()`.
- **Players own** their `teams/{uid}` and `answers/{qid}/{uid}` — write gated on
  `auth.uid === $uid`.
- **Room teardown**: a `live/{code}` root write matches only the host deleting the
  whole subtree (`!newData.exists()`).
- Everything requires anonymous auth (`auth != null`); no accounts, no PII.

> **Deploy step (owner):** these rules ship in `database.rules.json` but must be
> pushed to the project — `firebase deploy --only database` (or paste in the
> console). Until deployed, `live/*` writes are denied by default. The existing
> `rooms/*` Quick Match rules are unchanged.

## Verification

`FirebaseRTDB` was proven end-to-end against the **live** project (swiftc
self-test): anon auth → put → get → patch → roster read → SSE stream → delete all
pass. The full multi-device Live flow (Mac host + phone/web join) needs the rules
deployed + real devices — see the device checklist in the join-surfaces work.
