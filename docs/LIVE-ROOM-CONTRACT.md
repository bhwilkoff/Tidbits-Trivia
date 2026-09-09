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
| `answers/{qid}/{uid}` | that player | `{ choice?, text?, number?, order?:[Int], pairs?:[Int], list?:[String], ts }` |
| `control` | any player (the host's phone remote, G6) | `{ id, verb, pin }` — the host READS and decides; never writes `pub` |
| `media/{id}` | host, ONCE per room | `{ kind: "audio"\|"video", mime, bytes, b64 }` — Decision 060; `bytes` ≤ 3,000,000, `b64` ≤ 4,200,000 chars (rules-validated) |

### `pub` (host-published, players stream it) — ALL question types
```json
{
  "round": 1, "roundTitle": "History",
  "qid": "r0q3", "qNum": 3, "qTotal": 5,
  "phase": "question",            // intro | question | reveal | ended
  "prompt": "…", "format": "classic",
  "options": ["A","B","C","D"],   // MCQ / picture / this-or-that / odd-one-out
  "answerIndex": 2,               // ONLY present in phase "reveal" (MCQ)
  "imageURL": "…",                // pictureId
  "numeric": {"min":,"max":,"step":,"unit":""},   // closestCall (NOT the answer)
  "orderItems": ["…"],            // ordering (SHUFFLED; correct order withheld)
  "matchKeys": ["…"], "matchValues": ["…"],       // matching (values SHUFFLED)
  "enumTarget": 8,                // enumerate (how many in the set)
  "media": {                      // Decision 060: the question's clip, OFFERED to every joiner (absent = no clip)
    "kind": "audio",              // "audio" | "video"
    "url": "room:<id>",           // a direct https FILE link, or room:<id> → live/{code}/media/{id}
    "mime": "audio/mp4", "name": "golden-beep", "bytes": 1644,
    "startedAt": 1757000000000    // epoch ms of the host's Play — absent until the host plays
  }
}
```
**`media` (Decision 060).** A joiner that sees `media` shows an offer ("Listen
to the clip" / "Watch the clip", with the name and size). It fetches a `room:`
node ONCE — when the host's `startedAt` appears or the player taps, whichever
first — decodes `b64` into a blob, and plays it in a native `<audio>`/`<video>`
(AVPlayer / Media3). Nothing plays until the player taps; the host's `startedAt`
readies the clip and positions it at the room's offset. The element survives
`pub` re-renders (recreating it restarts the clip). `url` is never `tidbits-media:`.
**Costs, measured 2026-09-09 (Mac host on an office connection; the venue's
Wi-Fi, not Firebase, is the bottleneck in a room):** a 2.87 MB clip is a
3.83 MB node; one client fetched it in 0.47 s; 10 concurrent clients in 0.83 s
wall (median 0.62 s); **40 concurrent clients in 2.53 s wall (median 1.98 s,
p90 2.14 s), 60 MB/s aggregate, 153 MB moved** — the burst the owner asked
about is fine on the server side. A store-only PICTURE is different: it rides
INSIDE `pub` as a data URL (measured 108 KB for a 266 KB photo, downscaled),
and `pub` is re-sent to every streaming phone on every state change — question,
timer, lock, reveal — so one picture question costs each phone ~400 KB and a
13-picture night for 40 phones ~225 MB, and every host click pushes a 4 MB
burst before anyone sees the reveal. Pictures over ~30 KB belong on the same
once-written node (next). Hosts differ in ENCODING only: the Mac re-encodes (AAC `.m4a`, H.264 640x480
`.mp4`) to get under the cap; Windows sends an MP3/M4A/AAC/MP4/M4V as it is and
refuses anything else or over the cap, saying so under the Play button.
`qid = "r{roundIndex}q{questionIndex}"` is stable across reveal/advance so answers
key cleanly. **Every question type is playable** — only the field(s) for the current
`format` are set. **Nothing that could leak the answer is ever published** (correct
order, pairings, accepted text, the enumerate set): the host **auto-scores on reveal
from its own local `Question`** — MCQ/picture exact, numeric proximity, ordering/
matching partial credit, type-answer via alias-match, enumerate by unique set members.
`answerIndex` is withheld until reveal. The per-question ordering/matching shuffle is
fixed once (publish == reveal) so submitted indices stay valid. The scorer is mirrored
in `LiveNightHost.score` (Swift), `liveScore` (Kotlin), `nhScore` (JS). Tidbits Live
(Mac) publishes the same fields but keeps its manual/referee scoring.

## Security rules (`database.rules.json` → `live`)

- **Host owns** `meta` / `pub` / `scores` — write gated on `meta/host === auth.uid`.
  First `meta` write (room creation) is allowed because `!data.exists()`.
- **Players own** their `teams/{uid}` and `answers/{qid}/{uid}` — write gated on
  `auth.uid === $uid`.
- **Host owns `media/{id}`** (same gate as `pub`), and the rules VALIDATE the
  cap — a node over 3 MB raw / 4.2M base64 chars is refused server-side, so a
  host build with a wrong cap cannot push the room over the free tier.
- **Any player may write `control`** (the phone remote requests; the host
  decides by PIN and command id — `LiveRemote.accepted`).
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
