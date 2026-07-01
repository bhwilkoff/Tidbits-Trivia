# Cross-platform Trivia Night — serverless, native-only

How Apple and Android devices can play a networked **Trivia Night** together with
**no dedicated server** — only native platform APIs (and, for the internet case,
GitHub). Investigation + the chosen design. Companion to the Apple implementation
in `TidbitsTrivia/Core/Networking/` (Decision 033) and `PARITY.md` §3b.

## The model (unchanged from Apple / Decision 033)

Host-paced, everyone-plays. The host builds the night once and ships the whole
question list to every device. Each device runs its **own** `GameEngine`/`GameState`
over the identical list and **scores itself locally** (host trusts self-reports —
friendly living-room game, no anti-cheat). Everyone answers on their own screen;
the host taps **Reveal → Next** to pace it. Rejoin-by-device-id resumes a seat.

This model is transport-agnostic — the same `NightMessage` state machine runs over
a LAN socket **or** a GitHub-backed channel. That's what makes both regimes below
share one core.

---

## Two regimes

| Regime | When | Discovery | Transport | Server? |
|---|---|---|---|---|
| **Local** (recommended, ship first) | Everyone in the room, same Wi-Fi | mDNS / DNS-SD | plain TCP + app-layer crypto | none |
| **Remote** (optional, Phase 2) | Players on different networks | room code → GitHub Gist | GitHub REST (polling) | none (GitHub) |

The living-room Trivia Night use case is **local** — that's the 90% case and needs
no GitHub at all. Remote is a nice-to-have with real caveats (below).

---

## The universal-connectivity question: which transports are TRULY cross-platform?

The app-layer (`NightMessage` state machine, room-code crypto, host/client, the
ID-based night below) is **transport-agnostic** — it's written once and each
transport is a thin adapter. So the real question is which link-layers let an iPhone
and an Android phone talk **natively, no server**. Survey:

| Transport | iOS native? | Android native? | Cross-platform? | Needs router? | Bandwidth | Verdict |
|---|---|---|---|---|---|---|
| **Wi-Fi Aware** (`WiFiAware` / `WifiAwareManager`) | ✅ **iOS 26+** | ✅ Android 8+ | ✅ open standard, Apple built it for iPhone↔Android | ❌ device-to-device | High | **Best fit** (we're iOS-26 baseline) — but brand-new, verify interop on HW |
| **BLE GATT / L2CAP** (Core Bluetooth ↔ Android BLE) | ✅ | ✅ | ✅ standard GATT | ❌ none — works anywhere | Low (chunked) | **Universal fallback** — great once payload is tiny (see IDs) |
| **Shared Wi-Fi + mDNS + TCP** | ✅ | ✅ | ✅ | ✅ same router | High | **Baseline, ship first** — works on every iOS/Android version today |
| Bluetooth Classic / SPP / RFCOMM | ❌ apps can't (MFi only) | ✅ | ❌ | — | — | iOS blocks it for app data |
| Multipeer Connectivity | ✅ | ❌ | ❌ | — | — | Apple-only |
| Wi-Fi Direct (P2P) | ❌ | ✅ | ❌ | — | — | Android-only |
| AWDL (`includePeerToPeer`) | ✅ | ❌ | ❌ | — | — | Apple-only (why cross-platform mDNS needs a real router) |
| Google Nearby Connections | ✅ SDK | ✅ SDK | ✅ | ❌ | High | Easy — but a **Google/Play-Services third-party** dep (fails "native only") |
| NFC | ✅ | ✅ | ~ | — | Tiny | Only for the *join handoff* (tap-to-join code), not the channel |

**Takeaways:**
1. **Wi-Fi Aware is the headline.** iOS 26 (this project's floor) added the `WiFiAware`
   framework; Android has had `WifiAwareManager` since 8.0; it's an open standard Apple
   explicitly pitched for iPhone↔Android. It needs **no router and no server** and is
   high-bandwidth — strictly better than shared-Wi-Fi mDNS *if* cross-vendor interop
   holds up (it's v1 on Apple's side; a 2-device HW test is mandatory before trusting it).
   It exposes IP sockets, so our `NightMessage` protocol rides on it unchanged.
2. **BLE is the only link that needs literally nothing** — no Wi-Fi, no router, no
   server, works in a field. Its low bandwidth stops mattering once we ship IDs (below).
3. Everything else universal enough is single-vendor (Multipeer/Wi-Fi Direct/AWDL) or a
   third-party dep (Nearby Connections).

**Design consequence:** put the transport behind a small interface
(`NightTransport`: advertise, discover, connect, send-frame, on-frame) and implement
adapters incrementally — **mDNS+TCP first** (works today), then **Wi-Fi Aware** (best,
iOS26+/Android8+), then **BLE** (universal). The state machine never changes.

### The optimization that makes low-bandwidth transports (and GitHub) practical: ship IDs, not questions

Both apps **bundle the same corpus** (Apple SQLite, Android JSON) built from the same
shared data — with **stable question IDs**. So the host's `.night` message should carry
the **round plan + a list of question IDs** (a few hundred bytes) instead of the full
question objects (a "Works" night is ~40 KB of JSON). Each device resolves the IDs
against its own local corpus (`Corpus.byId`, which already exists on both). This:
- shrinks the start-of-night payload **~100×** → BLE transfers in a blink and a GitHub
  gist easily fits;
- shrinks the **canonical wire schema** to just the plan + `[id]` + the tiny pacing/
  answer messages — we no longer have to canonicalize the whole `Question` across
  platforms (the hardest part of interop just disappears);
- keeps a full-object fallback for any id a peer is missing (corpus drift), sent only
  on demand.

**Caveat:** requires **question-id parity** across the Apple and Android corpora. They
derive from the same `docs/DATA-CONTRACT.md` build, so ids should match — this must be
verified (a shared golden-id test), and it's the single most important interop
precondition.

---

## Local play — the interop analysis (for the mDNS+TCP baseline)

### Discovery: DNS-SD is already interoperable ✅

Apple advertises a Bonjour service `_tidbits-night._tcp` (`NWListener.Service` /
`NWBrowser`). **Bonjour and Android's `NsdManager` are both DNS-SD over mDNS** — the
same wire protocol — so an Android device can discover an Apple host on the same
service type and vice versa. No change needed to the service type.

**Caveat (load-bearing):** Apple's `NWParameters.includePeerToPeer = true` uses
**AWDL** (Apple Wireless Direct Link), which is Apple-proprietary — Android cannot
join an AWDL peer link. Cross-platform discovery therefore requires **both devices
on the same infrastructure Wi-Fi** (a normal router), where standard mDNS reaches
everyone. Android↔Android is also plain-LAN. (Apple↔Apple keeps AWDL as a bonus.)

### Transport: the TLS-PSK mismatch forces plain TCP + app-layer crypto ⚠️

Apple secures the socket with **`TLS_PSK_WITH_AES_128_GCM_SHA256`** (a GCM PSK
cipher suite; PSK derived `SHA256("tidbits-night-v1:<CODE>")`). **Android's native
TLS stack (Conscrypt) does not support any GCM PSK suite** — only the legacy CBC/
3DES/RC4 PSK suites, via the **deprecated** `PSKKeyManager`. So Android literally
cannot complete Apple's handshake, and matching a shared CBC-PSK suite would mean
downgrading Apple to a weaker, also-awkward-to-configure cipher.

**Decision: drop TLS on the wire; move confidentiality + auth to the app layer,**
keyed by the same room code, using primitives BOTH platforms have natively:

- **Framing** stays exactly as Apple's today: `4-byte big-endian length + body`.
- **Body** = `AES-256-GCM(key, nonce, plaintextJSON)`, serialized as
  `12-byte nonce ‖ ciphertext ‖ 16-byte tag`.
  - Key = `SHA256("tidbits-night-v1:" + CODE)` — **the exact derivation Apple
    already computes** for the PSK, reused as the AES key.
  - Apple: `CryptoKit.AES.GCM`. Android: `javax.crypto.Cipher("AES/GCM/NoPadding")`.
    Both first-party, no dependencies.
- A wrong room code → GCM tag fails to verify → the frame is rejected. That is the
  same "only a device that can read the code pairs" guarantee TLS-PSK gave, achieved
  in ~15 lines of native crypto on each side.

This is arguably *more* portable and no less safe than TLS-PSK for a LAN game.

### Canonical wire schema (the other interop requirement)

The `.night` message ships `plan: NightPlan` + `questions: [Question]`. For a Kotlin
client to render an Apple host's night (and vice versa), the JSON must be **canonical
and shared**, not each platform's private `Codable`/`@Serializable` shape. This doc's
sibling `docs/NIGHT-WIRE-SCHEMA.md` (to be written alongside the code) pins the exact
JSON for `NightMessage`, `NightPlan`, `NightRound`, `NightPlayer`, and a compact
`WireQuestion`. Android maps its `Question` ↔ `WireQuestion`; the Apple migration
does the same for its `Question`.

### What Apple has to change for interop

The Apple networking code is **build-verified only, not yet two-device-verified** —
so migrating it now is cheap:

1. `NightTransport.parameters` — drop `NWProtocolTLS`; use a plain-TCP `NWParameters`.
2. `NightTransport.encode` / `NightFramer` — wrap/unwrap the body in `AES.GCM` using
   `RoomCode.presharedKey(for:)` (already exists) as the symmetric key.
3. `Question` / `NightPlan` — encode/decode the canonical `WireQuestion` schema.

Host/client state machines, room codes, rejoin-by-device — all unchanged.

> **Open decision for the owner:** migrate Apple fully to this v2 (one protocol
> everywhere, true cross-platform) **or** keep Apple's TLS-PSK for Apple↔Apple and
> add v2 as a second listener for cross-platform (dual-stack, more code). Recommend
> **full migration** — TLS-PSK bought little over app-layer AES-GCM here and the
> single protocol is far simpler to keep honest. Android is being built to v2 now.

---

## Remote play — serverless options (Phase 2)

For players NOT on the same Wi-Fi, you need NAT traversal or a rendezvous. Native-
only rules out the obvious tool:

- **WebRTC is out.** Neither the iOS nor the Android SDK ships WebRTC; it needs
  `libwebrtc` (third-party) **and** STUN/TURN servers for NAT traversal. Fails both
  the "native APIs only" and "no server" tests.

That leaves **GitHub as a serverless data plane**, reusing the identical
`NightMessage` state machine with a GitHub "transport" swapping in for the socket:

- **R1 — GitHub Gist as shared state (recommended if we do remote at all).** The
  host writes the night state (plan, questions, current index, phase, standings) to
  a **Gist** keyed by the room code; clients **poll** it and POST their answers as
  gist edits / comments. Host-paced trivia tolerates 2–5 s latency, so polling is
  fine. Native HTTP only (`URLSession` / `OkHttp`).
  - Auth: writing a gist needs a token. Use **GitHub OAuth Device Flow** (native:
    show a code, poll the token endpoint) so the *host* signs in with their own
    GitHub account — no embedded secret, no server. Clients can read a public gist
    unauthenticated.
  - Limits: authenticated REST is 5000 req/hr — ample for one host + a few pollers.
  - Caveats to accept: (1) using gists as a live data channel is unconventional —
    keep volume low and payloads small; (2) the host needs a GitHub account; (3) it
    is polling, not push, so a few seconds of lag.
- **R2 — GitHub as signaling for direct P2P.** Exchange public `IP:port` via a gist,
  then TCP hole-punch. Fragile: discovering your own public address and punching TCP
  through symmetric NATs is unreliable without STUN/TURN (a server). Not recommended.

**Recommendation:** ship **local** first (it's the actual Trivia Night). Keep remote
as a documented Phase-2 that reuses the same messages over an R1 GitHub transport,
behind a clear "needs a GitHub sign-in, adds a few seconds of lag" note.

---

## Build order

1. **Transport-agnostic core (Android), in progress:** `net/NightProtocol.kt`
   (messages + room-code key + AES-GCM + 4-byte framing), a `NightTransport` interface,
   and the **ID-based night** (ship plan + `[id]`, resolve via `Corpus.byId`). Host/
   client state machine + `LiveNight` bridge to `GameState`. UI (Host / Join). This is
   the part that never changes across transports.
2. **Transport adapter #1 — mDNS + TCP** (`NsdManager` + `Socket`). Works on every
   iOS/Android version → ship Android↔Android first (2-device HW test is the gate;
   emulators can't mDNS-peer). Then the **Apple v2 migration** (owner decision above:
   drop TLS-PSK → AES-GCM, id-based night) unlocks Apple↔Android on one router.
3. **Verify id parity** (`docs/DATA-CONTRACT.md`): a golden test asserting the same
   question has the same id in the Apple SQLite corpus and the Android JSON corpus —
   the precondition for shipping IDs. Pin `docs/NIGHT-WIRE-SCHEMA.md`.
4. **Transport adapter #2 — Wi-Fi Aware** (`WiFiAware` on iOS 26, `WifiAwareManager` on
   Android) → best cross-platform path, no router. Same state machine.
5. **Transport adapter #3 — BLE** (Core Bluetooth ↔ Android BLE) → the "works with no
   Wi-Fi at all" universal fallback.
6. **Remote (optional):** R1 GitHub-Gist transport behind the same `NightMessage`.

## House rules that apply

- No third-party libraries on either platform — Apple frameworks / Android SDK only.
  (AES-GCM, DNS-SD, sockets, and GitHub REST are all first-party.)
- Same verb, native idiom (`cross-platform-parity-discipline`): "host / join a night"
  is identical; the transport and crypto are each platform's native primitives.
- Trust model is unchanged: friendly game, host trusts self-reported scores.
