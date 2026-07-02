# Matchmaking / Online-Play Services for Android + Web — Research (2026-07-02)

> **Status:** RESEARCH — owner asked for "3rd party matching services that we
> could use for Android and the web app, preferably options that are free apis
> or otherwise integrate into our current github stack." Apple online stays on
> GameKit (Decision 039). All facts below verified against official pricing
> pages / docs on **2026-07-02** by three parallel research passes (managed
> BaaS · game-specific services · serverless/GitHub-native angles).
>
> **The filter that kills most options:** the client pair is *plain Kotlin
> Android* + *vanilla-JS browser*. Most game services are Unity-engine-only or
> have no web SDK. Traffic shape is tiny: 2–4 player rooms, one small message
> every few seconds, ~10-minute rooms — our `NightPeer` transport seam needs
> only "an ordered byte/JSON pipe per room + a way to pair strangers."

---

## TL;DR recommendation

1. **Firebase Realtime Database (Spark free tier)** — the recommendation.
   Free forever, no credit card, **hard-stops instead of billing** on overage.
   Official SDKs on exactly our two platforms (Kotlin + no-build-step browser
   JS). **Zero server code**: rooms + a quick-match queue are enforceable with
   Security Rules alone (Cloud Functions are NOT needed and are Blaze-only
   anyway). 100 simultaneous connections ≈ 25 concurrent 4-player rooms —
   plenty for beta and beyond; the paid step is metered, not a cliff. And the
   story writes itself: RTDB is **Google's own designated replacement** for
   the Play Games multiplayer APIs it killed in 2020.
2. **Nostr ephemeral relays** — the zero-account dark horse / fallback. Public
   relays forwarding ephemeral events (kinds 20000–29999, never stored) fit
   our encrypted wire *exactly*: the room code already keys AES-GCM, so
   payloads stay private on public infrastructure; publish to 3–5 relays for
   redundancy (Trystero ships this as its default strategy in production —
   the tolerance proof). Truly free forever, no vendor, no account. Cost:
   Android Nostr libraries are alpha-or-app-extracted; relays owe us nothing.
3. **Ably** (200 conns / 6M msgs/mo, free forever) — best managed quotas +
   presence, but proper auth needs a small token-minting endpoint somewhere,
   which breaks "no server" cleanly. Keep as the managed alternative.

Everything else fell to the filter — details below.

---

## Why the obvious names don't work

| Option | Killer |
|---|---|
| Epic Online Services | Free and generous — but **no web/browser SDK exists** (lobbies/matchmaking/P2P are native-SDK-only). |
| Photon Realtime | Real JS SDK + JoinRandomRoom, but **no Java/Kotlin SDK** (C++ NDK only → JNI tax) and a 20-CCU dev-only free cap. |
| PlayFab | Free tier = **1,000 *lifetime* players**; matchmaking queue is REST-usable but **PlayFab Party has no web SDK** — it matches players who then have no channel to talk on. |
| Colyseus | Web-perfect, but the community Kotlin SDK is dead (0.14 vs server 0.17). |
| Unity Lobby/Relay/Matchmaker | Relay transport is Unity-engine-bound; Lobby REST alone is a directory, not a pipe. |
| Nakama (self-host) | The best *product* (official JS + Java SDKs, built-in 2–4 matchmaker) but needs a ~$5/mo VPS + ops — not free, and more machine than this traffic needs. |
| Hathora | **Shut down May 2026** (acquired; customers migrated to Nitrado). |
| Pusher | Android SDK frozen since 2022; auth endpoint required anyway. |
| PubNub | Fine tech, but free tier caps at **200 monthly active users** — the tightest player ceiling of the group. |
| Supabase | Good quotas (200 conns, 2M msgs/mo) but **free projects pause after 1 week of database inactivity** — fragile for a low-traffic game without a keep-alive cron. |
| Liveblocks / Momento / PartyKit-hosted | No Android client / conflicting enterprise-only pricing signals / legacy after the Cloudflare acquisition. |
| Cloudflare Workers + Durable Objects | Technically the strongest DIY shape on a real free tier — but **ruled out by the owner** (Decision 039); listed for the record only. |

## The GitHub-stack angle, honestly assessed

We investigated using GitHub itself (gists/issues as a state relay, Actions as
infrastructure) since it's the stack we already ship on:

- **Rate-limit math**: authenticated reads with ETag/304s are effectively free
  and CORS works from GitHub Pages — but **content-writes cap at 500/hour**
  (a host writing state every ~3s burns that in ~2.5 games) and raw gist URLs
  cache ~5 minutes on the CDN.
- **The web-auth wall is fatal**: GitHub's OAuth **device flow is CORS-blocked
  in browsers** — a pure GitHub-Pages client cannot complete any GitHub OAuth
  flow without a proxy, and gists require *classic*-PAT scopes fine-grained
  tokens don't cover. "Paste a classic PAT to play trivia" is not shippable UX.
- **TOS**: no clause forbids it and prior art (utterances/giscus) runs unbanned
  for years — but nobody has shipped gist-based realtime multiplayer, and the
  reasons are the three walls above.
- **GitHub Actions** can't be in the game loop (cron ≥5 min + drift; dispatch
  has no latency SLO) — it stays useful only as a stale-room janitor.

**Verdict: fallback-grade cleverness, not the answer.** GitHub stays what it
is for us — hosting, CI, and (later, if wanted) an Actions janitor.

## WebRTC P2P (for the record)

Best latency (the only buzzer-capable option), and Cloudflare's TURN free tier
(1,000 GB/mo) plus Metered/ExpressTURN would cover relaying — but no library
spans native-Kotlin + browser with free signaling (Trystero is web-only with an
unstable wire; PeerJS is semi-dormant, STUN-only), so we would own a signaling
contract + TURN credential minting ourselves. Phone-on-LTE↔LTE needs TURN
(~20%+ of connections). More moving parts than host-paced trivia needs; park it
until a mode genuinely needs sub-second latency.

---

## How the recommendation maps onto what we already built

The `NightPeer`/`NightPeerLink` transport seam (Android `NightTransport.kt`,
Apple `NightLink.swift`) means a new transport never touches game logic. A
**FirebaseRtdbTransport** is:

- **Room = a path** `/rooms/<id>`; frames written as push-keyed children under
  `/rooms/<id>/msgs` (ordered, timestamped); clients listen `childAdded` —
  that's the ordered pipe the seam wants. Web listens with the same SDK.
- **Quick match = a queue node** `/queue/<bucket>` claimed with an RTDB
  transaction (first-writer-wins is exactly a transaction); loser becomes
  joiner, winner becomes the host-paced leader — the same leader model
  GameKit Quick Match uses on Apple (Decision 039's auto-paced LiveNight).
- **Private matches** reuse our 4-letter room-code UX as the room id.
- **Security Rules** gate writes (auth.uid seat claims, room size, rate) with
  Firebase **Anonymous Auth** (free) as the identity — no accounts, no PII.
- Android keeps `encodeDefaults=true` JSON; web the same wire; **Apple stays
  on GameKit** (Decision 039). If cross-store play is ever wanted, Firebase
  has an iOS SDK too — an owner decision for later, not part of this.

Scale honesty: Spark's 100 simultaneous connections ≈ 25 concurrent rooms ≈
hundreds of games/day. Overage = service pauses til next window (no bill). The
metered paid tier starts at pennies if the game ever outgrows that.

**Owner decision points before implementation:** (1) approve Firebase as the
Android/web online vendor (one new free account, no card); (2) confirm
Anonymous Auth (device-scoped, no sign-in) is acceptable for v1 identity;
(3) Nostr fallback — build it only if we want a zero-vendor escape hatch.

## Sources

Compiled from three research passes with all official-source URLs and access
dates embedded; the full per-service detail (limits tables, SDK versions,
pause policies, TOS quotes) is preserved in the session log of 2026-07-02.
Key: firebase.google.com/pricing · /docs/database/usage/limits ·
/docs/functions/get-started (Blaze-only confirmation) · supabase.com/pricing
(1-week pause) · ably.com/pricing · onlineservices.epicgames.com (no web SDK) ·
photonengine.com/sdks (no Kotlin SDK) · developer.microsoft.com/games/products/
playfab/pricing (1,000 lifetime players) · heroiclabs.com/pricing ·
docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api ·
github.com/dmotz/trystero · developers.cloudflare.com/realtime/turn.
