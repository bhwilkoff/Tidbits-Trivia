# Player Identity Contract — the portable Tidbits profile

The wire contract for the **shared, cross-platform player identity** that spans solo play
AND live events. One profile so a cross-venue leaderboard can span an iPhone + Android +
web pub crowd; each platform signs in through its **own native system** and links to this
shared `uid`. Runs on the **$0 data plane** (Firebase RTDB Spark — no card, never bills;
see `docs/TIDBITS-LIVE-PREMIUM-BACKLOG.md` §M). Swift source of truth:
`Core/Networking/PlayerProfile.swift`. Web (`js/`) + Android (`FirebaseNet.kt`) mirror
these EXACT keys.

## Paths (two roots, split by sensitivity)

RTDB read rules **cascade and cannot be revoked deeper**, so public and private data must
live under separate roots — you can't hide a subnode beneath a publicly-readable profile.

| Path | Read | Write | Holds |
|---|---|---|---|
| `players/{uid}` | anyone signed-in (leaderboards) | owner only | display name, avatar seed, rating, streak, aggregate stats |
| `playersPrivate/{uid}` | owner only | owner only | opt-in email, linked native IDs, venue place-graph |
| `standings/{season}/{venue}/{uid}` | anyone signed-in | owner only | one leaderboard row (name snapshot, score, nights) |

## `players/{uid}` (public profile)

```json
{
  "name": "Quiz Khalifa",             // chosen DISPLAY name, not real identity
  "createdAt": 1720051200000,
  "avatarSeed": "a7f3…",              // seed → generated avatar art
  "rating":  { "value": 1042.0, "games": 23, "provisional": false },
  "streak":  { "current": 9, "longest": 21, "lastPlayedDay": "2026-07-04", "freezes": 1 },
  "stats":   { "gamesPlayed": 61, "questionsAnswered": 488, "correct": 331,
               "liveNights": 3, "venuesVisited": 2 }
}
```

- **Rating** — Elo-style, updated by EVERY game (solo + live; live weighted higher).
  Provisional until `games` ≥ 15 (honest cold-start, stable long-term). Start 1000.
- **Streak** — cross-context: a solo game OR a live night keeps it. Forgiving (freezes +
  restartable); a live night grants a freeze. *Never punishing.*
- **Stats** — the deep-stats surface + leaderboard tie-breakers. `venuesVisited` is a
  count; the venue *list* is private.

## `playersPrivate/{uid}` (owner-only)

```json
{
  "email": null,                      // opt-in ONLY (lead capture); never harvested
  "appleUserID": "001234.…",          // Sign in with Apple
  "gameCenterID": "G:123…",           // Game Center player (Apple)
  "playGamesID": "p1234…",            // Google Play Games (Android)
  "googleUserID": "1078…",            // Google Sign-In (Android/web)
  "venues": ["omalleys-sf", "…"]      // place graph — where/when you play (sensitive)
}
```

## `standings/{season}/{venue}/{uid}` (leaderboard write)

Each device writes its **final** score once per event (write-batching keeps us far under
Spark caps). A GitHub Actions cron reads these + `players/` names via REST, ranks, and
publishes static JSON — **clients read the JSON, never this subtree live** (§M).

```json
{ "name": "Quiz Khalifa", "score": 34, "nights": 4, "updatedAt": 1720051200000 }
```

## Platform-native identity mapping ("same identity, native idiom")

The shared `uid` is a Firebase **anonymous** auth uid (free, no card, unlimited). Native
sign-in **links** to it via `linkWithCredential`; the native player id is stored in
`playersPrivate`. Native achievements/friends/leaderboards stay on the OS service; the
shared profile carries the portable rating/streak/venues.

| Platform | Account | Social / achievements | Sync |
|---|---|---|---|
| Apple (iOS/iPadOS/macOS/tvOS) | Sign in with Apple → `appleUserID` | **Game Center** (`GameCenterManager` already wired) → `gameCenterID` | CloudKit private DB |
| Android | Google Sign-In / Credential Manager → `googleUserID` | **Google Play Games** → `playGamesID` | Firebase |
| Web | federated (Apple/Google) + passkeys | — | Firebase |

The authoritative **cross-venue** leaderboard lives on the shared plane and **renders in
native-styled UI per platform** (Game-Center-flavored on Apple, Play-Games-flavored on
Android) — never one generic account screen reused across platforms.

## Cross-device claim & account recovery (durable identity)

**The gap:** anonymous uids are per-install/browser and disposable — they survive a
device's own sessions (Keychain / IndexedDB / SDK cache) but do NOT roam across devices,
and a cleared web session (incognito, cleared data, new browser/machine) orphans the
profile at `players/{old_uid}`. Both "bring my records to a new device" and "recover a
lost web session" have the same fix.

**Mechanism — promote the anon account with a federated sign-in.** Firebase
`linkWithCredential(Apple|Google)` on an anonymous user upgrades the **same uid** to a
permanent, credential-linked account (all records preserved, no migration). Then
`signInWithCredential` with that credential on any other device returns the **same uid** →
the same `players/{uid}`. One durable identity that roams AND survives session loss.

**Owner decisions (2026-07-04):** **sign-in only** (Apple + Google; no transfer code —
records are durable only via an account); **auto-merge, lossless** on conflict.

**Flows:**
- *Web → mobile:* web "Save my progress" → Sign in → anon `players/uid_web` becomes
  permanent. Mobile signs in with the same account → same uid → records appear.
- *Lost session:* signed-in users sign in again → same uid → restored. Anonymous-only
  profiles are unrecoverable by design (hence the "Save your progress" prompt).

**Merge (`mergeProfiles(local, account)`) — deterministic, order-independent, lossless.**
When the credential is already tied to a different uid *with data* (`credential-already-in-use`),
sign into that account, combine, write back to the **account uid** (the survivor), then
best-effort delete the loser's `players/{uid}`:
- `name`: prefer the non-default name (not `Player NNNN`); else the account's.
- `createdAt`: **min** (earliest). `avatarSeed`: the account's (stable identity).
- `rating`: `value = max`, `games = sum`, `provisional = games < 15`.
- `streak`: `current`/`lastPlayedDay` from whichever has the **later** `lastPlayedDay`;
  `longest = max`; `freezes = max`.
- `stats`: `gamesPlayed`/`questionsAnswered`/`correct`/`liveNights` = **sum**;
  `venuesVisited` = size of the unioned private venue list.
- private: `email` = first non-null; native IDs (appleUserID/gameCenterID/playGamesID/
  googleUserID) = union; `venues` = union.

**Per-platform sign-in (native idiom, over the shared merge):**
- **Apple:** Sign in with Apple (`ASAuthorizationController`) → Firebase
  `OAuthProvider("apple.com")` credential → link/sign-in. (Google also offered.)
- **Android:** Google Sign-In via **Credential Manager** → `GoogleAuthProvider` credential.
- **Web:** Firebase `linkWithPopup` / `signInWithPopup` (Apple + Google providers).

**UX:** a "Save your progress" / Sign-in button on every profile surface for anonymous
users; once signed in it shows "Signed in as …". A merge shows a quiet "Combined your
profiles" note. **$0:** federated auth is free/unlimited on Spark — no new billing surface.

## Security rules (`database.rules.json`)

- **`players/{uid}`** — public read (leaderboard display), write gated on `auth.uid == $uid`,
  must have `name` + `createdAt`.
- **`playersPrivate/{uid}`** — read AND write gated on `auth.uid == $uid` (owner-only).
- **`standings/{season}/{venue}/{uid}`** — public read, owner-only write, must have
  `name` + `score`.

## Evolution

Additive-only: never repurpose a key; add new optional ones. No PII beyond opt-in. Every
bulk read is static JSON (§M); the live plane carries only small owner-scoped writes, so
Spark's 100-connection / 10 GB-egress ceilings are never in play. **No card on the infra
account, ever — a metered bill is then physically impossible.**
