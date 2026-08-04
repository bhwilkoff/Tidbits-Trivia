# The Daily's global board — the $0 global daily competition (data contract)

**Status: BUILDING (2026-07-19).** The first global-multiplayer feature from
`docs/MONETIZATION.md` §4c. It is **a layer on the existing Daily, not a second
daily** — the owner flagged that a separate "Daily Six" competed with the Daily
Tidbit for placement and purpose, so the global board folds into the one Daily
everyone already plays. Everyone worldwide already gets the **same daily set**;
this layer writes each player's result, an hourly cron ranks the field, and every
client reads static JSON — never the live DB. Rides the exact pattern the Wave E
leaderboard already proves (`tools/aggregate_leaderboard.py`).

Governed by **R-NET-1** (no global feature opens a socket — REST only) and
**R-NET-2** (the hourly cron is the league office). The Daily stays **free
forever** — playing, the streak, and your world rank are all free (**R-MON-4**);
Club buys the *autopsy* (per-question deltas over time, calibration, history).

## The deterministic set — no coordination needed

The Daily's questions are **not** stored or chosen by a server. Every client
computes the same set locally and identically:

```
Corpus.daily(day, 7)  ==  pickDaily(allIds, day, "mixed", 7)   // Decision 037, byte-identical on all 6 platforms
```

`day` is the local calendar date `YYYY-MM-DD` (same `dayKey` the shipped Daily uses on every platform). Because `pickDaily` is a pure FNV-1a-64 rank
(no RNG, order-independent), an iPhone in Tokyo and a PC in Lagos derive the same
seven ids for the same day with zero communication. This is what makes the board
free: **there is no set to distribute and no pairing to compute.**

> The Daily was already "the same set for everyone" and already play-once with a
> streak. This layer adds only the *write + ranking* on top. The Daily's count
> (7), name ("Daily Tidbit"), streak, and archive are all unchanged.

## Write path — one write per player per day

```
dailyBoard/{day}/{uid} = {
  "name":       "Quiz Khalifa",     // display-name snapshot for the board
  "avatarSeed": "a7f3…",
  "score":      540,                // sum of the seven question scores (Scoring.points)
  "correct":    5,                  // 0..7
  "marks":      "1110110",          // 7-char per-question hit string, index-aligned to the day's set
  "ms":         41200,              // total time across the set, for a future speed tiebreak
  "at":         1752940000000
}
```

- `{uid}` is the Firebase auth uid — anonymous or the account uid. One row per
  player per day; a re-submit overwrites (best-effort last-write; the client
  submits once, at completion).
- `marks` is a fixed seven-char `0/1` string aligned to `pickDaily(...,7)` order,
  so the cron can compute **per-question global accuracy** without storing the
  questions themselves.
- Payload is ~90 bytes. Even at six figures of daily players this stays far under
  the Spark egress ceiling, and the cron reads it once an hour.

## Published output — what clients read

`data/dailyboard/{day}.json` (served free/cacheable from GitHub Pages):

```
{
  "day":   "2026-07-19",
  "qids":  ["…", "…", "…", "…", "…", "…", "…"],  // the set, so a client can label them
  "n":     1847,                              // total players
  "hist":  { "0": 12, "100": 40, … },        // score → count, for LOCAL percentile
  "perQ":  [0.91, 0.62, 0.44, 0.78, 0.31, 0.55, 0.5],  // global correct-rate per question
  "top":   [ { "name": "…", "avatarSeed": "…", "score": 600, "correct": 6 }, … ]  // capped 100
}
```

`data/dailyboard/index.json = { "latest": "2026-07-19", "days": ["2026-07-19", …] }`

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
| Play the Daily; global rank + percentile; today's `top` board | The **autopsy**: which questions you got right that most people missed, your seven-question calibration, domain deltas vs the field, and the day-over-day history archive |

Club reads the **same** public JSON — the autopsy is computation over the free
data plus the player's own local history, so it adds **zero** backend cost.

## The cron (R-NET-2)

`tools/aggregate_dailyboard.py`, run hourly by `.github/workflows/dailyboard.yml`:

1. Read `dailyBoard.json` from RTDB (one REST read).
2. For each recent `day`, rank players, build the histogram + per-question accuracy.
3. Write `data/dailyboard/{day}.json` + `index.json`; commit only on change.

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

The contract is identical everywhere; each client (a) computes the set with its
existing `pickDaily`, (b) plays them through its existing game loop, (c) writes
the one row, (d) fetches the static JSON and renders rank + board. Web is the
reference implementation. Status tracked in `PARITY.md`.

## The published question set (2026-08-03)

`tools/publish_daily.py` writes `data/daily/{day}.json` — the day's seven FULL rows,
~4 KB — on the same hourly cron as the board. The web reads it instead of
downloading the 13 MB corpus just to work out which seven they are.

**It is a cache, never an authority.** `Corpus.dailyPublished()` returns null on any
doubt — a miss, a malformed file, the wrong day, the wrong count — and the caller
falls back to `loadFull()` + the local computation, which is exactly what it did
before. The published rows are produced by the SAME picker as every client (proved
byte-identical against `js/engine.js`), and the five-engine daily golden still
governs: if the published set ever diverged, the golden is what catches it.

**A three-day window, not one file.** The cron runs in UTC; a client's `dayKey()` is
its LOCAL date. Publishing a single day would 404 for everyone west of UTC for part
of every day — correct, but it would silently fall back to 13 MB and undo the point.

Measured in Chrome on a cold load: the Daily plays from **4,249 bytes** with
`Corpus.full === false` throughout.
