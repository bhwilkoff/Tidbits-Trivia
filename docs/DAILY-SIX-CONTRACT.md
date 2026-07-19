# Daily Six — the $0 global daily competition (data contract)

**Status: BUILDING (2026-07-19).** The first global-multiplayer feature from
`docs/MONETIZATION.md` §4c. Everyone worldwide gets the **same six questions**
each day; each player writes one result; an hourly cron ranks the field and
publishes static JSON; every client reads the JSON, never the live DB. Rides the
exact pattern the Wave E leaderboard already proves (`tools/aggregate_leaderboard.py`).

Governed by **R-NET-1** (no global feature opens a socket — REST only) and
**R-NET-2** (the hourly cron is the league office). Free forever per **R-MON-4**
(playing and being ranked is a seat; Club buys the *autopsy*).

## The deterministic set — no coordination needed

The day's six questions are **not** stored or chosen by a server. Every client
computes them locally and identically:

```
pickDaily(allIds, day, "mixed", 6)   // Decision 037, byte-identical on all 6 platforms
```

`day` is the UTC date `YYYY-MM-DD`. Because `pickDaily` is a pure FNV-1a-64 rank
(no RNG, order-independent), an iPhone in Tokyo and a PC in Lagos derive the same
six ids for the same day with zero communication. This is what makes the mode
free: **there is no set to distribute and no pairing to compute.**

> The single Daily already uses `pickDaily(ids, day, "mixed", 1)`. Daily Six is
> the same call with `count = 6`. The existing free Daily is untouched — Daily
> Six is a *second*, competitive daily surface.

## Write path — one write per player per day

```
dailySix/{day}/{uid} = {
  "name":       "Quiz Khalifa",     // display-name snapshot for the board
  "avatarSeed": "a7f3…",
  "score":      540,                // sum of the six question scores (Scoring.points)
  "correct":    5,                  // 0..6
  "marks":      "111101",           // per-question hit string, index-aligned to the day's set
  "ms":         41200,              // total time across six, for a future speed tiebreak
  "at":         1752940000000
}
```

- `{uid}` is the Firebase auth uid — anonymous or the account uid. One row per
  player per day; a re-submit overwrites (best-effort last-write; the client
  submits once, at completion).
- `marks` is a fixed six-char `0/1` string aligned to `pickDaily(...,6)` order,
  so the cron can compute **per-question global accuracy** without storing the
  questions themselves.
- Payload is ~90 bytes. Even at six figures of daily players this stays far under
  the Spark egress ceiling, and the cron reads it once an hour.

## Published output — what clients read

`data/dailysix/{day}.json` (served free/cacheable from GitHub Pages):

```
{
  "day":   "2026-07-19",
  "qids":  ["…", "…", "…", "…", "…", "…"],   // the six, so a client can label them
  "n":     1847,                              // total players
  "hist":  { "0": 12, "100": 40, … },        // score → count, for LOCAL percentile
  "perQ":  [0.91, 0.62, 0.44, 0.78, 0.31, 0.55],  // global correct-rate per question
  "top":   [ { "name": "…", "avatarSeed": "…", "score": 600, "correct": 6 }, … ]  // capped 100
}
```

`data/dailysix/index.json = { "latest": "2026-07-19", "days": ["2026-07-19", …] }`

### Why a histogram, not per-player ranks

Publishing every player's rank would bloat the file and leak a full roster. Instead
the cron publishes a **score histogram**; each client computes its own percentile
locally:

```
myPercentile = (players with a strictly lower score) / (total players) × 100
```

Exact, tiny, and privacy-preserving. The `top` array (capped at 100) carries the
visible leaderboard. A player outside the top 100 still sees "you beat 83% of
players today" from the histogram.

## Free vs Club (R-MON-4)

| Free | Club |
|---|---|
| Play the Daily Six; global rank + percentile; today's `top` board | The **autopsy**: which questions you got right that most people missed, your six-question calibration, domain deltas vs the field, and the day-over-day history archive |

Club reads the **same** public JSON — the autopsy is computation over the free
data plus the player's own local history, so it adds **zero** backend cost.

## The cron (R-NET-2)

`tools/aggregate_dailysix.py`, run hourly by `.github/workflows/dailysix.yml`:

1. Read `dailySix.json` from RTDB (one REST read).
2. For each recent `day`, rank players, build the histogram + per-question accuracy.
3. Write `data/dailysix/{day}.json` + `index.json`; commit only on change.

Only the last few days are republished (older days are frozen once the write
window closes). The aggregator accepts `--input <file>` for offline testing so the
output is verifiable on any machine without touching RTDB.

## Anti-cheat (honor-first, per §4c)

Answers are written only at completion and the board is post-hoc, so there is no
live answer feed to scrape. The cron has every result, so **statistical anomaly
detection is free**: `perQ` gives each question's difficulty, and a player who is
fast-and-correct on the lowest-accuracy questions, consistently, is the signature.
Enforcement is a quiet rating-freeze + unranked pool, never public shaming.

## Platform parity

The contract is identical everywhere; each client (a) computes the six with its
existing `pickDaily`, (b) plays them through its existing game loop, (c) writes
the one row, (d) fetches the static JSON and renders rank + board. Web is the
reference implementation. Status tracked in `PARITY.md`.
