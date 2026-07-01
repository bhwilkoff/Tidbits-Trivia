# Online Multiplayer Playbook — Real-Time Online + CPU/Bot Fallback

> **Status:** RESEARCH / PLAYBOOK for a future session. Nothing here is built yet.
> This document is the design brief a future implementation session reads first.
>
> **Scope:** REAL-TIME ONLINE play — strangers and friends competing across the
> world, cross-platform (iOS/iPadOS + tvOS + Android + web), PLUS a believable
> CPU/bot opponent when no human wants to play.
>
> **What already exists (do not re-derive):** SERVERLESS *local* networked
> multiplayer — "Trivia Night" — mDNS + TCP + AES-GCM, host-paced, cross-platform
> Apple↔Android, verified on hardware. It uses a canonical `WireQuestion` payload
> and a host-authoritative round model. This playbook REUSES that game model and
> that payload; the only new thing is the *transport* (a neutral cloud relay) and
> the *matchmaking* layer on top.
>
> **OWNER CONSTRAINT (2026-07-01): online play need NOT be cross-platform.** Only
> *local* multiplayer must stay cross-platform (it already is). This materially
> widens the options: online can be **per-ecosystem** — GameKit `GKMatch`/automatch
> for Apple↔Apple, the Android equivalent (or the shared cloud relay below) for
> Android, each with the **universal offline bot** as the always-available fallback.
> That means v0 (bot) + an Apple-native GameKit path can ship with **zero backend**;
> the neutral Cloudflare/Supabase relay in §3 becomes optional — needed only if/when
> we want true cross-platform online or a web/Android online path, not for launch.
> Re-read §1–§2 with this relaxation in mind: GameKit is no longer "useless as the
> transport" — it's the recommended Apple online path.

---

## TL;DR recommendation

- **Cross-platform online requires a neutral backend.** Neither Apple GameKit nor
  Google Play Games can be the cross-platform transport (see §1, §2).
- **Recommended backend: Cloudflare Durable Objects** as the authoritative
  per-match room (one DO instance = one game room, WebSocket fan-out with
  hibernation), fronted by a Cloudflare Worker for matchmaking + auth, with KV
  for the matchmaking queue and D1/KV for lightweight persistence. **Supabase**
  is the recommended alternative / complement for auth, profiles, ranked
  leaderboards, and Presence (see §3).
- **v0 ships with NO backend:** a bot-only "Play vs CPU" mode that runs fully
  offline against the existing local game engine (see §5, §6). This is the quick
  win and it is owner-unblocked.

---

## 1. Apple GameKit online (Apple-only — cannot match an Android player)

GameKit is Apple's first-party multiplayer + Game Center stack. It is **exclusive
to Apple platforms** — a `GKMatch` peer network only contains players signed into
Game Center on Apple devices. It **cannot match, transport to, or even see an
Android or web player.** Therefore GameKit CANNOT be the cross-platform layer.
It *can* power an Apple-only fast path: matchmaking, friends, invites, presence,
and Game Center leaderboards/achievements.

**Real-time:**
- `GKMatch` — "a peer-to-peer network between a group of players that sign into
  Game Center." Data is sent with
  `sendData(toPlayers:withDataMode:completionHandler:)` /
  `sendDataToAllPlayers(withDataMode:...)`, where `GKMatchSendDataMode` is
  `.reliable` (guaranteed, acked — use for question/answer/score state) or
  `.unreliable` (fast, lossy — irrelevant for trivia). Events arrive via
  `GKMatchDelegate`: `match(_:didReceive:fromPlayer:)`,
  `match(_:player:didChange:)` (connection state),
  `match(_:shouldReinvitePlayer:)` (reconnection), `matchDidFailWithError(_:)`.
  Docs: https://developer.apple.com/documentation/gamekit/gkmatch
- `GKMatchmaker` — creates matches with **no UI**; supports **automatch** (fills
  empty slots with strangers matching the `GKMatchRequest` criteria), invites,
  and `startBrowsingForNearbyPlayers`. Docs:
  https://developer.apple.com/documentation/gamekit/gkmatchmaker
- `GKMatchmakerViewController` — Apple's stock UI to invite players to a
  real-time game and **automatch to fill any empty slots**. Docs:
  https://developer.apple.com/documentation/gamekit/gkmatchmakerviewcontroller
- `GKMatchRequest` — encapsulates the parameters (min/max players, player group,
  player attributes) for a real-time OR turn-based match. Docs:
  https://developer.apple.com/documentation/gamekit/gkmatchrequest

**Turn-based (relevant if we go async, see §4):**
- `GKTurnBasedMatch` — "encapsulates the match data for games where players take
  turns." Apple hosts the match state on Game Center servers; players do not need
  to be online simultaneously. Docs:
  https://developer.apple.com/documentation/gamekit/gkturnbasedmatch
- `GKTurnBasedMatchmakerViewController` — stock UI to invite + automatch a
  turn-based match. Docs:
  https://developer.apple.com/documentation/gamekit/gkturnbasedmatchmakerviewcontroller
- GameKit umbrella: https://developer.apple.com/documentation/gamekit

**Verdict:** Use GameKit ONLY for Apple-side value-adds (Game Center identity,
friends, leaderboards, achievements, an Apple-only quick-match fast path). It is
NOT the cross-platform transport. Do not build the core online loop on it, or the
Android/web clients get orphaned.

---

## 2. Android — Play Games Services multiplayer is DEAD (2026 status confirmed)

**There is no native Google replacement for cross-platform real-time trivia.**

- **Real-time and turn-based multiplayer APIs in Play Games Services ended
  support on March 31, 2020.** They "cannot be enabled for new games." Google's
  own recommended replacements are **Firebase Realtime Database** and **Google
  Cloud Open Match** (i.e., "build your own backend"). Official:
  https://support.google.com/googleplay/android-developer/answer/9469745
- **The broader Play Games Services v1 SDK is now deprecated too:** starting
  **May 2026 the deprecated APIs are removed from the SDK**, and **as early as
  July 2028 calls to these APIs will fail even on older SDK versions.** Devs must
  migrate to Play Games Services v2 (`play-services-games-v2`). Official
  deprecation schedule: https://developer.android.com/games/pgs/deprecation ·
  Deprecated list: https://developers.google.com/games/services/cpp/api/deprecated/deprecated
  · Migrate to v2: https://developer.android.com/games/pgs/android/migrate-to-v2

**Verdict:** Android has NO first-party multiplayer transport. This settles the
architecture: **cross-platform online = our own neutral backend.** Play Games
Services v2 is still useful on Android for sign-in, friends, and leaderboards
(the parity twin of Game Center), but never for the match transport.

---

## 3. THE REALITY: a neutral backend is mandatory — architecture

Because Apple and Google each only match within their own ecosystem, a
cross-platform online game MUST route through a neutral server that all four
clients (iOS, tvOS, Android, web) speak to over an open protocol (**WebSocket** —
uniformly available on all four, including Swift `URLSessionWebSocketTask`, OkHttp
/ Ktor WebSockets on Android, and the browser `WebSocket`).

### 3a. Recommended: Cloudflare Durable Objects (authoritative match rooms)

A **Durable Object (DO)** is a single-instance, single-threaded, globally-addressed
stateful actor. **One DO instance = one authoritative game room.** This maps
*exactly* onto our existing host-paced model: the DO plays the role the local
"host" device plays today, but it is neutral and reachable from any platform.

- **WebSocket fan-out with Hibernation:** a DO coordinates many client WebSockets;
  with the **Hibernation API** (`state.acceptWebSocket()`) the DO is evicted from
  memory while idle but clients stay connected, and **you are not billed for idle
  duration** — ideal for trivia, which is bursty (a message every few seconds, not
  60fps). Per-connection state survives hibernation via
  `serializeAttachment()` / `deserializeAttachment()`.
  Docs: https://developers.cloudflare.com/durable-objects/best-practices/websockets/
  · Hibernation example:
  https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/
  · What are DOs: https://developers.cloudflare.com/durable-objects/concepts/what-are-durable-objects/
- **Authoritative timing lives in the DO** — the DO owns the clock. It timestamps
  question-start, closes the answer window server-side, and computes scores. This
  is the anti-cheat spine (§3d): clients never self-report elapsed time.
- **Worker + KV in front:** a plain Worker handles `POST /matchmake` (auth check,
  queue, room assignment) and hands back a room id; **KV** holds the matchmaking
  queue and a room directory. Persistence of finished matches / ranked stats can
  go in **D1** (SQLite) or KV.
- **Why this over Supabase for the match loop:** the DO gives you a *true
  authoritative single-writer per room* with no extra locking, at near-zero idle
  cost. Supabase Broadcast is a *relay* (see below) — great, but the server-side
  authority (timing/scoring) then has to live in an Edge Function or a Postgres
  trigger rather than in the room actor itself.

### 3b. Recommended alternative / complement: Supabase

Supabase Realtime gives three primitives over WebSockets on **channels** (rooms):
- **Broadcast** — low-latency client→server→clients messaging; the natural fit
  for relaying our `WireQuestion` / answer / score frames. Supports `ack: true`
  (server received it) and `self` (echo to sender). Can also be emitted **from
  the database** via `realtime.send()` / `realtime.broadcast_changes()` in a
  trigger. Docs: https://supabase.com/docs/guides/realtime/broadcast
- **Presence** — track/sync who is in the room (online, answering, disconnected)
  — the friends/lobby/"is my opponent still here" layer. Docs:
  https://supabase.com/docs/guides/realtime/presence
- **Postgres Changes** — subscribe to row changes (heavier; Supabase itself
  recommends Broadcast for most cases). Docs:
  https://supabase.com/docs/guides/realtime/postgres-changes
- **Edge Functions** — server-authoritative scoring/validation endpoints. Docs:
  https://supabase.com/docs/guides/functions
- Realtime overview: https://supabase.com/docs/guides/realtime

Supabase's real strength for us is **auth + profiles + ranked leaderboards +
Presence** (it is a full Postgres + Auth product). A clean split is: **Supabase
= identity/persistence/presence; Cloudflare DO = the authoritative live room.**
Either can host the whole thing for v1; the DO is the better *match-loop* engine.

### 3c. Alt: Firebase (Google's own recommendation)

Firebase Realtime Database / Firestore + Cloud Functions can carry the same
pattern (rooms = documents, listeners = sync). It is viable and is literally what
Google points deprecated PGS users toward. We deprioritize it only because it adds
a third vendor/SDK and pulls Apple clients onto Google infrastructure; keep it as
the fallback if Cloudflare+Supabase don't pan out.

### 3d. The authoritative match-room design (reuses our existing model)

Map the EXISTING host-paced local game onto the room actor. The wire frames are
the SAME `WireQuestion` payload the local Trivia Night already sends; we add a
thin envelope for online concerns.

```
Client (any platform)  ──WebSocket──►  Room actor (Durable Object)
                                        owns: authoritative clock, room state,
                                        roster, per-round answer window, scoring
```

Room state machine (server-authoritative):
1. `LOBBY` — players join via room id; roster + ready state broadcast (Presence).
2. `QUESTION_OPEN` — DO broadcasts the next `WireQuestion` + `serverStartMs` +
   `windowMs` (e.g. 15s). DO starts the authoritative timer.
3. `COLLECTING` — clients send `answerSubmit{questionId, choice, clientElapsedMs}`.
   DO records `serverReceivedMs` and **ignores client-claimed elapsed for
   scoring** (client time is display-only). Late answers past the window are
   rejected server-side.
4. `REVEAL` — DO computes correctness + speed-bonus from ITS OWN timestamps,
   broadcasts per-player results + running scores.
5. Loop to 2 until deck exhausted → `FINAL` → write results to persistence.

**Anti-cheat (server-authoritative):**
- Timing is the server's, never the client's — kills "I answered instantly" fraud.
- The correct-answer key is NEVER sent in the `QUESTION_OPEN` frame; the DO holds
  the key and reveals only in step 4. (Our `WireQuestion` must be split into a
  *public* prompt payload and a *private* answer key held server-side.)
- Rate-limit submissions; one answer per player per question (first accepted).
- Optional: server picks the question order/deck so clients can't pre-fetch.

**Reconnection:** room state persists in DO storage (survives hibernation). A
returning client re-opens the WebSocket, sends `resume{roomId, playerId, token}`,
and the DO replays current room state + score. Mirror of GameKit's
`shouldReinvitePlayer` idea, but transport-neutral. A grace timer (e.g. 30s)
holds a seat before substituting a bot (§5) or forfeiting.

---

## 4. Matchmaking design (keep v1 dead simple)

**Trivia does not need 60fps netcode.** The natural model is **near-real-time
rounds: everyone sees the question at the same server timestamp and answers within
N seconds.** This is forgiving of latency (a few hundred ms of jitter is
invisible when the window is 15s), which is exactly why a WebSocket relay + server
clock is enough and no rollback/prediction is needed.

**v1 matchmaking (simple):**
- **Quick Match:** `POST /matchmake {category?, difficulty?}` → Worker pushes the
  player into a KV-backed queue keyed by `{category, difficulty}` bucket. When the
  bucket reaches the target headcount (e.g. 2–4) within a window, the Worker mints
  a room id (a DO) and returns it to all matched players. If the queue times out
  (see §5), substitute bot(s).
- **Skill/category buckets:** start with coarse buckets — category (or "mixed") ×
  difficulty × a 3-tier skill band derived from a stored rating. Do NOT build Elo
  matchmaking in v1; a single hidden rating with 3 bands is plenty.
- **Party/Friends:** a host creates a private room id (shareable via the existing
  deep-link system + web twin URL) and friends join it directly — this is just
  the LOBBY state with automatch disabled. Presence (Supabase) or Game
  Center/PGS friends power the invite UI per-platform.
- **Latency:** pick the DO/region lazily (Cloudflare places the DO near the
  creator); accept cross-region play since the answer window absorbs latency. Show
  a ping indicator, don't hard-gate on it.

Keep it to ONE queue and ONE room type for v1. Ranked ladders, seasons, and real
Elo are v2.

---

## 5. CPU / Bot fallback — a believable trivia opponent

**Mission alignment (learning-orientation):** a bot must make solo play *engaging
and honest*, never deceptive. **Always disclose the opponent is a bot** — label it
in the roster ("Botsworth · CPU"), never present a bot as a human. Deception fails
the learning-mission test; a clearly-labeled AI sparring partner passes it (it
invites participation and practice without pretending to be someone it isn't).

### 5a. When to substitute a bot
- **Solo mode (v0):** user explicitly chooses "Play vs CPU." Pure offline, no
  backend. This is the whole game against 1–3 bots using the existing local
  engine.
- **Online timeout fill:** if Quick Match finds no human within `T` seconds
  (e.g. 12–20s), offer "Play a CPU now?" or auto-fill remaining seats with bots,
  **clearly labeled**. Never silently swap a human for a bot mid-lobby without a
  visible notice.
- **Mid-match dropout:** if a human disconnects past the grace timer, a bot may
  take over the empty seat to keep the round alive — announced in the reveal
  banner ("Alex left — Botsworth is finishing their seat").

### 5b. Concrete bot-behavior spec

A bot is a small parameterized model evaluated **locally** (solo) or **in the
room actor** (online, so it's server-authoritative and can't be inspected).

```
BotProfile {
  name: String                 // e.g. "Botsworth", "Trivia Tina" — always CPU-tagged
  baseSkill: 0.0...1.0          // global correct-rate at "medium" difficulty
  categorySkill: [Category: Double]  // per-category offset, e.g. Sports +0.15, Science -0.10
  speedMean: Double             // mean answer time in seconds
  speedStdDev: Double           // human-like jitter
  clutchness: Double            // small skill delta on final/high-stake questions
}
```

**Per-question resolution (in the answer window `windowMs`):**
1. **Effective correct-rate** `p` for THIS question:
   `p = clamp(baseSkill + categorySkill[q.category] + difficultyAdj(q.difficulty), 0.02, 0.98)`
   where `difficultyAdj` is e.g. `+0.15 easy / 0 medium / −0.20 hard`.
   Never 0 or 1 — even a strong bot misses easy ones occasionally and a weak bot
   sometimes nails a hard one. That fallibility is what reads as human.
2. **Correct?** Bernoulli draw with probability `p`.
3. **Which wrong answer (if incorrect):** don't pick uniformly — bias toward a
   plausible distractor (the trivia corpus can flag a "trap" option), because
   humans miss toward the tempting wrong answer, not a random one.
4. **Answer time:** sample from a right-skewed distribution (e.g. log-normal with
   `speedMean`/`speedStdDev`), then:
   - correct answers are a bit faster than incorrect ones (knowing feels fast),
   - clamp into `[0.8s, windowMs − buffer]`,
   - occasionally (≈5%) let the bot "run out of clock" and answer very late or not
     at all — humans do freeze up. This variance is the believability payload.
5. **Difficulty tiers → presets:** ship 3–4 named bots (Rookie ~0.55 base,
   Regular ~0.70, Ace ~0.85, plus a "house" bot the app tunes to roughly match the
   player's recent accuracy so solo play stays a fair fight — an adaptive
   `baseSkill` that tracks the user's rolling correct-rate).

**Why this is believable:** the twin realism levers are (a) non-extreme,
category-varying correct-rates so the bot has visible strengths/weaknesses, and
(b) a jittered, right-skewed, occasionally-failing timing model instead of a
constant delay. A bot that answers correctly in exactly 3.0s every time is the
tell; humans are noisy.

**Online authority:** when a bot fills an online seat, run its resolution INSIDE
the room actor (DO/Edge Function) using the same server clock, so from every other
client's perspective the bot is indistinguishable at the protocol layer from a
human seat (except for its honest CPU label).

---

## 6. Phased roadmap

### v0 — Bot-only "Play vs CPU" (NO backend, owner-unblocked) ★ quick win
- Reuse the EXISTING local host-paced engine and `WireQuestion` deck; replace the
  networked opponents with 1–3 `BotProfile`s resolved locally (§5b).
- Ships on all four platforms as a fully-offline mode. Add a PARITY.md row.
- Honest labeling: bots are visibly "CPU."
- **Delivers:** single-player-vs-AI competitive trivia everywhere, immediately,
  with zero infra, zero auth, zero owner blockers. Also becomes the fill/dropout
  brain for v1.
- **Learning-orientation gate:** run the `learning-orientation-design`
  four-question test on the bot mode before building (adaptive difficulty =
  "meet the learner where they are"; honest labeling = agency/clarity).

### v1 — Backend real-time rooms + Quick Match  ⚠ owner-blocked (infra + auth)
- Stand up Cloudflare: Worker (`/matchmake`), Durable Object (room actor), KV
  (queue + room directory), D1/KV (results). WebSocket clients on all 4 platforms.
- Implement the room state machine (§3d) with server-authoritative timing/scoring
  and the split public-prompt / private-answer-key `WireQuestion`.
- Quick Match (one queue, category×difficulty bucket), private friend rooms via
  the existing deep-link + web-twin system, bot timeout-fill (§5a).
- Reconnection via `resume`; grace timer → bot substitution.
- **Owner blockers:** create the Cloudflare (and/or Supabase) project(s); decide
  the identity story — anonymous device id for v1 vs. real accounts; provision
  auth. (MCP access to both Cloudflare and Supabase exists in this workspace,
  which de-risks provisioning.)

### v2 — Friends / Presence / Ranked  ⚠ owner-blocked (accounts, moderation)
- Real accounts + profiles (Supabase Auth), cross-platform friends list, Presence
  ("who's online"), invites. Apple-side can layer Game Center friends;
  Android-side PGS v2 friends — as native affordances, NOT as transport.
- Ranked ladder: real rating (Elo/Glicko), seasons, leaderboards (Game Center /
  PGS v2 as native mirrors of a server-authoritative board).
- Anti-abuse: report/mute, rate limits, profanity filtering on display names —
  required before opening stranger play at scale.
- **Owner blockers:** account system + privacy policy updates, moderation policy,
  store review implications of user-generated presence/chat.

---

## Cross-references
- Existing local transport + game model: SCRATCHPAD.md / DECISIONS.md
  (Trivia Night — mDNS+TCP+AES-GCM v2 wire) and the
  `cross-platform-trivia-night` memory.
- Parity: add "Play vs CPU" (v0) and "Online Quick Match" (v1) rows to PARITY.md.
- Skills to invoke when implementing: `learning-orientation-design` (before the
  bot + any online feature), `shared-data-plane-contract` (the backend is a data
  plane the clients consume), `cross-platform-parity-discipline`,
  `feature-shipping-discipline`, and `architectural-decision-log` (log the
  "neutral backend, GameKit/PGS are Apple/Google-only" decision).

## Source index (all official)
- GameKit: https://developer.apple.com/documentation/gamekit
- GKMatch: https://developer.apple.com/documentation/gamekit/gkmatch
- GKMatchmaker: https://developer.apple.com/documentation/gamekit/gkmatchmaker
- GKMatchmakerViewController: https://developer.apple.com/documentation/gamekit/gkmatchmakerviewcontroller
- GKMatchRequest: https://developer.apple.com/documentation/gamekit/gkmatchrequest
- GKTurnBasedMatch: https://developer.apple.com/documentation/gamekit/gkturnbasedmatch
- GKTurnBasedMatchmakerViewController: https://developer.apple.com/documentation/gamekit/gkturnbasedmatchmakerviewcontroller
- Play multiplayer sunset: https://support.google.com/googleplay/android-developer/answer/9469745
- PGS deprecation schedule: https://developer.android.com/games/pgs/deprecation
- PGS deprecated list: https://developers.google.com/games/services/cpp/api/deprecated/deprecated
- PGS migrate to v2: https://developer.android.com/games/pgs/android/migrate-to-v2
- Cloudflare DO — WebSockets: https://developers.cloudflare.com/durable-objects/best-practices/websockets/
- Cloudflare DO — Hibernation example: https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/
- Cloudflare DO — concepts: https://developers.cloudflare.com/durable-objects/concepts/what-are-durable-objects/
- Supabase Realtime: https://supabase.com/docs/guides/realtime
- Supabase Broadcast: https://supabase.com/docs/guides/realtime/broadcast
- Supabase Presence: https://supabase.com/docs/guides/realtime/presence
- Supabase Postgres Changes: https://supabase.com/docs/guides/realtime/postgres-changes
- Supabase Edge Functions: https://supabase.com/docs/guides/functions
