# Tidbits Live — Premium Feature Backlog

**Purpose.** A researched, prioritized backlog of the features pub-trivia **hosts and
venues pay for**, so we can point `/loop` at it and make v1 of the macOS Tidbits Live
app as fully featured as possible. Compiled 2026-07-04 from a five-stream market survey
(platform pricing tiers, emcee authoring/run-of-show, AV & show production, player
submission & scoring, venue business & monetization). Extends
`docs/EVENT-TRIVIA-COMPETITIVE.md` (the market map) and `docs/macOS-DESIGN.md` Part A
(the binding Tidbits Live spec). Sources are cited in the research appendix at the end.

**Charter check.** The strongest market signal (Geeks Who Drink, Water Cooler Trivia,
QuizRunners) is that the moat is **curated, personality-driven content + host craft**,
not AI volume — and hosts *distrust* auto-generation. That aligns with our learning
charter: favor tools that deepen the host's craft (pacing, adjudication, the "story
behind the answer") over ones that make the host or player passive. Lead with craft;
treat AI as an assist.

---

## Strategy & the way forward (owner direction, 2026-07-04)

This backlog is **not** a plan to match competitors' tiers. Four owner principles govern
it:

1. **Different value proposition — a game you take *with you*.** Tidbits Trivia is a
   consumer trivia GAME that also hosts/joins live in-person events *from the same app,
   under one identity*. Nobody else combines a consumer game with an event platform. The
   thesis: **your play at a live Tidbits Live night feeds your personal stats, streak,
   skill rating, and per-venue standing — and between nights you keep playing solo.** One
   portable identity across every context. That "companion you carry between the trivia
   nights you attend" is the moat, and it makes the "network" features (cross-venue
   leaderboards, venue standings) *consumer retention hooks*, not just venue tooling.

2. **Build everything first; decide the paywall later.** We do NOT design around a pricing
   model. Build the full feature set — **two eventual premium surfaces, both TBD**:
   (a) *consumer premium* (individuals pay for consumer features — set still to be
   researched/defined) and (b) *host premium* (Tidbits Live features). What lands behind
   a paywall is decided *after* the features exist. **No competitor's model or feature
   set determines ours** — the market data below is landscape awareness only.

3. **$0 ongoing cost is a hard guardrail.** We build many free apps at ~$0. Infrastructure
   is allowed **only if it can run at essentially zero ongoing cost and can never silently
   accrue a metered bill.** This *reframes the old "backend vs. serverless" gate*: the
   question is not "backend?" but **"can it live within free tiers that never bill?"** —
   and for the moat features the answer is yes (the app already runs on Firebase RTDB's
   free Spark tier + GitHub Pages; Cloudflare Workers/KV/D1/R2 free tiers are additional
   headroom). *(A dedicated research pass is confirming the concrete free-tier limits and
   the exact $0 stack; findings fold into §Decisions + Wave E.)*

4. **Same identity, both directions.** The persistent player identity is the connective
   tissue: it's simultaneously the consumer game's progression system AND the venue's
   cross-venue leaderboard. Build the identity/data plane once, at $0, and both surfaces
   ride it.

**What this changes vs. the gates below:** monetization is *deferred, not blocked* —
build the *capability* (e.g., a lead-capture form, a sponsor slot, branding depth), leave
the *paywall* decision for later. The backend gate is *reframed* — Wave E is **unblocked
as long as we hold the $0-ongoing line**. A separate **consumer feature/premium backlog**
is still to be produced (research in flight) and will be appended as §L when ready.

---

## Legend

| Tag | Meaning |
|---|---|
| **TS** | Table-stakes — must-have to be credible |
| **D** | Differentiator — only some competitors have it |
| **P** | Premium/paid — what the market gates behind money (hosts/venues pay for it) |
| ✅ | Shipped in Tidbits Live already (this session or prior) |
| 🔨 | Partial — some of it exists; needs completion |
| ⬜ | New — not built |
| 🔒 | **Decision-gated** — needs an owner product call before building (see §Decisions) |

---

## The monetization map — what the market actually charges for

Ranked by how consistently a feature sits behind a paywall across Crowdpurr, Kahoot,
Slido, Mentimeter, myQuiz, Quizizz, TriviaMaker, QuizXpress, QuizWitz, Quizado, plus the
venue-network/host-company world (Buzztime, SpeedQuizzing, Sporcle, Geeks Who Drink):

1. **Participant / device capacity** — the near-universal price lever (free caps of
   10–100 climb to 1,000–5,000+). *If Tidbits Live ever charges, this is the meter.*
2. **Custom branding / white-label** (logo, colors, custom join URL, remove vendor mark)
   — mid/high tier everywhere (Crowdpurr full white-label at ~$125/mo).
3. **AI question generation** (metered credits) — we already own this.
4. **Multi-seat / multi-venue** (more hosts, more locations under one account).
5. **Data export & analytics** (results to Excel/Sheets, dashboards).
6. **Rich-media question types** (image/audio/video).
7. **Premium game mechanics** (Jeopardy/Feud boards, elimination, team-vs-team, wagering)
   — the most defensible *trivia-native* premium surface (myQuiz's top tiers).
8. **Live streaming / OBS**, **Q&A moderation**, **anti-cheating**, **sponsorship/ads**,
   **lead capture**, **SSO/enterprise**, **exclusive content packs**.

Two structural facts: (a) the **live-host world never charges the player** — it charges
the **venue** ($150–$500/event typical; $199–$299/mo per-venue subscription à la
Buzztime; $750–$3,000 for full-service) or sells **self-host-at-a-discount** to keep
venues on-network; (b) **paper packs are reportedly the fastest-growing segment** — paper
is a first-class format to design *for*, not a legacy fallback.

---

## A. Event & question authoring (the prep workspace)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| Offline pre-game question builder | Build the whole night ahead, saved to account, re-openable/editable | TS | ✅ (event builder) |
| Manual entry + AI + corpus mix | Author by hand, from the 20k corpus, or AI-generate a themed round | D→TS | ✅ |
| **Personal question library + reuse** | Every question stored, reusable/editable across future nights; "mine vs. provided" | P | ⬜ |
| **Avoid-repeats intelligence** | "Last used" date + used-in-event history + dedupe warning when a Q re-enters a set | D (unmet gap) | ⬜ |
| **Drag-to-reorder** questions & rounds | Reorder within/between rounds by drag | TS | 🔨 |
| Topic/category per round; themed rounds | Assign a theme to each round; mix formats in one night | TS | ✅ |
| Save / duplicate / **clone last week** | One-click duplicate a whole event to spin a variation | D | 🔨 |
| Reusable templates | Publish/save a game shape as a template | D | 🔨 |
| **Difficulty & category balance meter** | Visual 30/50/20 curve + category spread while authoring | D (unmet gap) | ⬜ |
| Per-question metadata | Points (fixed or decaying), penalty, answer key, host notes set at authoring | P | 🔨 |
| **CSV / spreadsheet import** | Bulk-load questions from Sheets/Excel (hosts already write there) | D | ⬜ |
| PDF/doc → questions (AI-assisted) | Extract a round from an uploaded document | P | ⬜ |
| Export quiz pack | Portable game file incl. picture questions | P | 🔨 (PDF export exists) |

## B. Question & round formats

| Feature | What it does | Signal | Status |
|---|---|---|---|
| MCQ / true-false / this-or-that / odd-one-out | Baseline choice formats | TS | ✅ |
| Type-the-answer (free text) | Typed answer, host-graded | TS | ✅ |
| Picture round (image) | Image prompt on big screen | TS | ✅ |
| Ordering / sequence | Put items in order (partial credit) | D | ✅ |
| Matching | Pair keys to values (partial credit) | D | ✅ |
| Nearest-wins / closest number | Numeric estimate; also the tiebreaker unit | D | ✅ |
| List / enumerate (name-many) | Name as many as you can | D | ✅ |
| **Audio round (name-that-tune)** | Host plays a clip; teams ID it; speed-tiered scoring | P (market-beloved; SpeedQuizzing *can't even author* audio) | ⬜ |
| **Video question** | Video clip as prompt | P | ⬜ |
| **Wager round** | Teams bet points before answering | P | 🔨 (Stake mode exists) |
| **First-letter / wordplay** | Answers share a first letter; word-chain, etc. | D | ⬜ |
| Fastest-finger / buzzer race | Only fastest correct scores; speed bonus | P | ✅ (speed-bonus) |
| Dedicated tiebreaker Q | Numeric closest-guess held in reserve | TS | ✅ (tie-break engine) |
| **Poll / majority (authored, no-answer)** | Crowd poll with live tally, no "correct" | D | 🔨 (tally viz built; no authored poll Q) |
| Named show formats (Jeopardy/Feud/Wheel) | Game-show boards | D | ⬜ 🔒 |

## C. Live host cockpit / run-of-show

| Feature | What it does | Signal | Status |
|---|---|---|---|
| Manual-advance, host-paced | Host controls the beat, not an auto-timer | TS | ✅ |
| Reveal-on-command | Hold the answer; dramatic pause; reveal on the host's beat | D | ✅ |
| **Per-question / per-round timers** | Adjustable countdown per question; on-screen | TS | ⬜ |
| **Diminishing / speed-weighted points** | Points decay over the timer (faster = more) | P | 🔨 (rank speed-bonus only) |
| Manual score override (referee) | Host adjusts any team's score; final say | **P (headline differentiator)** | ✅ |
| Free-text review + spelling leniency | Review typed answers; mark-correct; alias/fuzzy match | **P (rare)** | ✅ |
| **Mid-game editing** | Fix a typo/wrong answer key while live | D (unmet gap; hosts fear crashes) | ⬜ |
| Pause / skip / re-open a question | Full flow control | D | 🔨 |
| Live answer tally | See submissions land in real time | D | ✅ |
| **Host notes / "read this aloud"** | Presenter-only note per question | P | ⬜ |
| **"Story behind the answer" blurb** | A surprising-fact line to spark debate on reveal | D (Geeks Who Drink's whole brand) | ⬜ |
| Presenter view (host) vs. audience big screen | Two surfaces: host sees answers/controls, room sees only the reveal | **P (the flagship paid feature)** | ✅ (projector window) |

## D. AV & show production (the "show")

| Feature | What it does | Signal | Status |
|---|---|---|---|
| Animated climbing leaderboard | Rows reorder with spring as scores land; team colors | **P** | ✅ (§A8) |
| Reveal choreography | Scale-in + glow reveal, "beat of silence," score reveal | P | ✅ (§A8) |
| Round-intro cards | Full-screen "ROUND 2 · HISTORY" announcement | D | ✅ (§A8) |
| Winner celebration | Confetti/crown finale | D | ✅ (§A8) |
| **Built-in SFX / stinger board** | Correct/wrong/drumroll/countdown/round-transition sounds | P (safe to **bundle** royalty-free; closes the "run a separate soundboard" gap) | ⬜ |
| **Audio playback to venue PA** | Clean, full-level clip playback on a **selectable output device**; host points at their own MP3 folder | P (structural for audio rounds) | ⬜ |
| Looping music beds w/ auto-duck | Atmosphere loop that ducks under clip audio, then resumes | D | ⬜ |
| On-screen countdown timer | Live timer builds pressure; music-synced | TS | ⬜ |
| Big-screen chrome | Round title, question number, difficulty label, join QR | TS | 🔨 |
| **Venue branding on screens** | Logo + colors on big screen (and print) | P | 🔨 (basic) |
| **White-label depth** | Custom fonts/backgrounds/colors + custom join URL | P (clean paywall precedent) | ⬜ 🔒 |
| **Sponsor slides between rounds** | Branded interstitial / lobby logo / sponsored-question tag | P (monetization) | ⬜ 🔒 |
| Streaming out (OBS / screen-share) | Capturable presentation window for hybrid/remote | D | 🔨 (window is capturable) |
| Native low-latency streaming | In-app stream to remote players | P (metered) | ⬜ 🔒 |

> **Music licensing (build rule):** public-performance rights are the **venue's**
> obligation (ASCAP/BMI/SESAC in US; PRS/PPL in UK). Every host tool makes the host
> supply the audio (BYO-clip folder) or embeds third-party players — **none bundle a
> licensed catalog.** Tidbits Live must do the same: point at the host's own files;
> never bundle/redistribute recordings. **SFX/stingers ARE safe to bundle** (royalty-free
> libraries) — that's the low-risk audio feature to own natively.

## E. Player join & submission (digital / paper / hybrid)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| QR / short-link / PIN join, no app | Browser join, no download | TS | ✅ |
| Join via the native Tidbits apps | iOS/tvOS/Android/web join the live room | **P (unique — consumer install base)** | ✅ |
| Team mode (several phones → one team) | Multiple devices, one leaderboard row | D | 🔨 |
| Rejoin/reconnect after drop | Re-scan the code to resume | D | ✅ |
| Player/device cap for a full room (100s) | Handle a bar-sized crowd | TS(paid) | 🔨 (verify at scale) |
| **Printable answer sheets (beautiful)** | Teams write answers; host grades — paper as a *first-class* output | P (paper is the fastest-growing segment) | 🔨 (basic print exists) |
| Printable question/host pack | Questions + answer key + host script PDF | P | ✅ |
| **First-class hybrid paper + digital** | Paper "teams" are tappable leaderboard rows scored per round with the same wager/bonus rules as phone teams, merged into one standings | D (unmet gap — nobody ships this well) | 🔨 (in-room teams exist; reconcile) |
| **Paper fallback when wifi dies** | Drop to printed sheets mid-event | D (the #1 reason hosts keep paper) | 🔨 |

## F. Scoring, adjudication & tie-breaks

| Feature | What it does | Signal | Status |
|---|---|---|---|
| Auto-scoring + running leaderboard | Instant scoring, host override on top | TS | ✅ |
| Speed-bonus scoring | Faster correct = more points | P | ✅ |
| Round multipliers / point tiers | Weight rounds differently | D | 🔨 |
| Wagering / penalties | Bet points; penalty for wrong guesses | D | 🔨 |
| **Accepted-answer variants list** | Pre-load "OJ / O.J. / Simpson"; case-insensitive | P | 🔨 (alias match exists) |
| Retroactive "mark correct" for all | Accept a new variant → award everyone who gave it | D | 🔨 |
| Undo last question / live point edit | Resolve a dispute on the spot | D | 🔨 |
| Built-in tie-break engine | Numeric closest-wins / sudden-death | **P** | ✅ |
| Final wager tie-break | Standings shown, teams wager on a last Q | D | ⬜ |
| **Brains-only tie-break** | Nominated-player buzz-off, phones down | D | ⬜ |

## G. Team management & moderation

| Feature | What it does | Signal | Status |
|---|---|---|---|
| Team names on the big screen | On-screen name is the team identity | TS | ✅ |
| Edit team name/details mid-game | Rename, fix, save | TS | 🔨 |
| **Kick / remove a team** | Strip an offensive/duplicate team from standings | D | ⬜ 🔒 (needs a `meta/kicked` rules change) |
| **Answer/name moderation gate** | Approve typed answers/team names before projecting (avoid a slur on the venue screen) | P | ⬜ |
| **Team merge** | Combine two teams into one row | D (unmet gap) | ⬜ |
| Carry teams across rounds/nights | Don't rebuild the roster each game | D | 🔨 |

## H. Reliability & integrity (cheating deterrence)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| Offline / weak-wifi resilience | Websocket transport tolerates bad venue wifi; local host | P (Mac-native strength) | ✅ |
| Graceful reconnect | Dropped phone rejoins cleanly | D | ✅ |
| **Answer-lock ("pencils down")** | Host freezes answers before reveal; a late Googler is locked out | P (the #1 host complaint) | ✅ |
| **Answer-lock *timer*** | Countdown auto-locks submission (shorter = less lookup time) | D | ⬜ |
| **Tab-switch / focus signal** | Flag a player who backgrounds the join page mid-question | D (nobody in trivia ships this) | ⬜ |
| Brains-only tie-break | Phones-down deciding moment | D | ⬜ |
| Lookup-resistant question design | Connect-the-clues / "what do these share" beats single facts | D (content, not code) | 🔨 (corpus quality) |

## I. Venue business (the "run trivia as a business" layer)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| **Recurring-series scheduling** | Define venue + weekday + time once; auto-spawn each week's event pre-loaded | P (removes weekly prep) | ⬜ |
| **Multi-venue management** | Org → venues → hosts hierarchy; manager dashboard | P | ⬜ 🔒 |
| Host assignment / cohosts | Assign a host (or cohost) to each venue/night | P | ⬜ 🔒 |
| Content distribution to hosts | Push central question packs org-wide | P | ⬜ 🔒 |
| **Cross-venue / season leaderboards** | Persistent team accounts; cumulative season standings across nights & venues | **P (the Buzztime/Sporcle moat — biggest weekly-return driver)** | ⬜ 🔒 (needs a backend) |
| Achievement / passport / streaks | Badges, stamps, streaks that pull players back weekly | D | 🔨 (consumer streaks exist) |
| Venue directory / "find a game near me" | Map of venues + schedule; canonical web URL | D | ⬜ 🔒 |

## J. Monetization (sponsors, lead capture, pricing)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| **Sponsor kit** | Lobby logo, between-round ad slide, sponsored-question tag | P | ⬜ 🔒 |
| **Lead capture** | Optional required join fields (name/email) → CSV/CRM export | P (clean paid gate) | ⬜ 🔒 |
| Prizes / points ledger | Track prizes, redeemable points, giveaways | D | ⬜ 🔒 |
| Player-cap tiers / pricing | Capacity as the paywall meter | P | ⬜ 🔒 (pricing decision) |

## K. Analytics & retention

| Feature | What it does | Signal | Status |
|---|---|---|---|
| **Per-event & per-venue metrics** | Headcount, teams, new-vs-returning, avg score, best nights | P | ⬜ 🔒 |
| Season trend charts | Attendance/engagement over a season | P | ⬜ 🔒 |
| **Data export** | Results/rankings → Excel/Sheets | P (routinely gated) | ⬜ |
| Shareable team profiles | Streaks, badges, results as social-share cards | D | ⬜ 🔒 |

---

## L. Consumer game & the portable identity (the "take-it-with-you" surface)

Researched 2026-07-04 (consumer trivia landscape + portable-identity analogs). The
decisive finding, from the QuizUp & HQ Trivia post-mortems: **engagement ≠ retention in
trivia** — every loser had huge engagement and no durable retention. The fix the winners
(Duolingo, LearnedLeague, Trivia Crack) found is **layered progression that persists**.
So: *build the persistent identity/progression layer before any content-volume race.*
The unique wedge — nobody fuses a consumer game + event platform under one identity — is
mechanistically justified by Peloton's data: **friend-connected users churn at ~half the
rate, and the live event is the only surface that manufactures real friends.**

### L1 — The identity spine (build this first)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| **Portable player identity** | One profile (anon-first, claim-later) carries everything across solo + live, every device | TS (the spine) | 🔨 (per-ecosystem sync exists; no unified profile) |
| **Tidbits Rating (Elo-style)** | A single skill number updated by *every* game — solo and live; live weighted higher (real opponents). Provisional → established (~10–26 games) | D (chess Elo / LearnedLeague — strongest retention of any model) | ⬜ |
| **Two-track progression** | Separate **skill** (rating) from **loyalty/consistency** (nights, streaks, venues) so both the ringer and the regular have something to chase | D (Peloton Club) | ⬜ |
| **Anonymous-join → claim flow** | Stranger plays via QR/code in seconds; "claim your score — you placed 4th of 22" upgrades the session onto a real profile | TS | 🔨 (join exists; no claim) |

### L2 — Daily-habit loop (retention backbone; cheap to build)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| Daily challenge | One shared daily set, same for everyone (Wordle/Daily Dose) | TS | ✅ (Daily Tidbit) |
| **Cross-context streak** | One streak kept alive by a solo game **OR** a live night — makes the sparse event and daily solo *the same habit* | D (the bridge) | 🔨 (solo streak exists; not cross-context) |
| **Forgiving streak-protection** | Freeze/repair, restartable, "attending a live night auto-protects your streak" — *never* punishing (punishing streaks tank reviews) | D | ⬜ |
| Spoiler-free shareable result | Wordle-grid-style share of the daily/live result — recruits without requiring the recipient to have played | D | ⬜ |

### L3 — Progression, leagues & seasons

| Feature | What it does | Signal | Status |
|---|---|---|---|
| XP / levels | XP on every action; levels unlock harder content | D | 🔨 |
| **Leagues / divisions** | Weekly promotion/relegation cohort (Duolingo lifted completion +25%) | D | ⬜ |
| **Seasons** | Periodic reset → fresh competitive start → re-engagement spike | D | ⬜ |
| Personal records & deep stats | Longest streak, avg accuracy, best category, lifetime totals (a Sporcle-Orange-style "deep stats" surface people pay for) | D | 🔨 (Records exists) |

### L4 — Collection & cosmetics (monetization-safe, non-skill-gated)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| **Levelable badges** | Achievement badges that grind to higher tiers (Sporcle/Untappd), incl. venue-attendance badges | D | 🔨 |
| Collection layer | Trivia Crack's mascots/cards — "fun to accumulate," not skill-gated | D | ⬜ |
| Avatars / cosmetics | Optional self-expression (loved, no pay-to-win grievance) | P (safe premium) | ⬜ |
| Themed / topic packs | More content you *want* (never a gate on core content) | P (safe premium) | 🔨 (corpus/topics exist) |

### L5 — Social (the friend-manufacturing engine)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| **Async friend duels** | Challenge-a-friend turn-based (Trivia Crack's viral core loop) | D | ⬜ |
| **Persistent teams (solo ↔ live)** | The pub team is the natural social unit; carry it across solo + live | D | 🔨 (live teams only) |
| **"Add the people you played with"** | After a live night, connect the teammates/rivals you actually met (the churn-halving move) | D (the strategic payload) | ⬜ |
| Friends vs. global leaderboards | See friends' progress beside global | D | 🔨 |
| "How did you know that?" prompt | After a hard answer, invite the story — turns results into conversation (Water Cooler Trivia) | D (charter-aligned) | ⬜ |

### L6 — The solo ↔ live bridge & place graph (the moat)

| Feature | What it does | Signal | Status |
|---|---|---|---|
| **Both contexts feed the same numbers** | Solo and live update the *same* rating & streak — non-negotiable core of "one identity" | TS (the bridge) | ⬜ |
| **Per-venue standings** | "You're #3 at O'Malley's, #12 in the city" — Strava segments for trivia; nested venue→city→global so everyone has a winnable arena | D | ⬜ 💲 |
| **Defendable venue titles** | "House Champion" (top score — a KOM you can *lose*, loss-aversion return pressure) + "Regular / Local Legend" (most nights — Swarm mayorship) | D | ⬜ 💲 |
| **Venue attendance tiers/badges** | Newcomer → Regular → House Fixture, leveling (Untappd), optional venue perk | D | ⬜ 💲 |
| **Event history feed** | Each live night a permanent dated card (venue, rank, score, a standout question) — MLB "Fan History" | D | ⬜ 💲 |
| **"Trivia tourism"** | Venues-visited collection → "played 4 venues, play a 5th for Explorer" (parkrun) | D | ⬜ 💲 |

*(💲 = rides the $0 data plane in §M.)*

### L7 — Monetization-safe design rules (so a paywall is *possible* later, without resentment)

- **Design the loved primitives in, the resented ones out.** Resentment gradient (loved→hated): cosmetics ≈ themed packs > remove-ads > earnable hints > soft currency > hard-currency collection > **energy/lives walls**.
- **Never architect an energy/lives wall into the core loop** — most resented, hardest to remove later. Keep the core game free and unlimited.
- **The safe premium surfaces** (whenever you decide): remove-ads, cosmetics, themed packs, a **deep-stats/status tier** (Sporcle Orange proves people pay for stats+badges alone).
- **Monetize the host/organizer, not per-player nickel-and-diming** (Kahoot/Water Cooler model) — the person running the pub night is the natural payer; players play free.
- **Live events must never be the *only* loop or a cost center** (HQ/QuizUp died this way). Live sits *on top of* the daily solo habit and *feeds* the identity.

---

## M. The $0 data plane (architecture for the identity + moat — no ongoing cost)

Researched 2026-07-04. The moat features (§L6, §I, §K) need shared state — and it can run
at **genuine $0 ongoing** on infrastructure the app already has. The governing rule and
the design that enforces it:

**The one rule that makes "$0, never bills" enforceable:** *a credit card is the billing
switch.* No card on file → metered billing is **physically impossible**. Firebase Spark
shuts the product off at the cap; Cloudflare Free hard-errors; GitHub Pages soft-limits.
Card-free tiers are **walls, not meters**. **Policy: no payment method on any Tidbits
infra account, ever.**

**Two-plane design.** A tiny **live/write plane** (Firebase RTDB Spark — already built,
card-free, blocks at cap) for real-time rooms + small per-user writes, and a
**static/aggregate plane** (**GitHub Actions cron → static JSON on GitHub Pages** — the
exact model the repo already uses for its question corpus) for everything read by many.
Every bulk read is a cached static file; every ceiling degrades to *stale data or an
error*, never an invoice.

| Need | How, at $0 | Why it can't bill |
|---|---|---|
| **Identity / auth** | Firebase **anonymous** auth (unlimited, free) + optional `linkWithCredential` to Apple/Google for cross-device roam. Profile at `/players/{uid}`, uid-scoped rules (already the model) | Classic Auth is free, no card, no MAU meter |
| **Cross-venue / season leaderboards** | Devices write one *final* score per event to `/scores/{season}/{venue}/{uid}`. A **GitHub Actions cron** reads via RTDB REST, ranks, commits `data/leaderboard/*.json` → served static from Pages. **Clients read the JSON, not RTDB.** | Static reads are free/cacheable; one write/event stays far under Spark caps |
| **Analytics** | Compact append-only writes to `/analytics/{date}/…` (clients never read them back); nightly cron rolls up → `data/analytics/summary.json`, prunes raw. + Cloudflare Web Analytics (free) | Write-only protects egress; rollup is static |
| **Venue directory** | Curated `data/venues.json` in git, served from Pages (same DATA-CONTRACT discipline as the corpus); self-registration via a moderated Worker→D1 or GitHub-issue form + cron promote | Read-heavy reference data = textbook static file |

**Graduation plane (only if RTDB's 100-connection / 10 GB-egress ceiling ever bites):**
Cloudflare **Workers + D1 + R2** — all card-free, hard-stop, and **R2 egress is $0 on
every tier**. Move write-ingest to a Worker→D1 (100k writes/day) and serve boards from R2;
RTDB stays purely for live rooms.

**The one hard "don't": never enable Firebase Blaze.** Cloud Functions, any server-side
outbound call, a 2nd DB instance, or SMS/phone auth all force Blaze — and Blaze has **no
true hard spending cap**. Do *all* scheduled compute in **GitHub Actions** (card-free),
never Firebase Functions. This design adds **zero new billing surfaces**.

---

## The unmet-need differentiators (gaps nobody ships well — build these to win)

1. **Mid-game editing** — fix a typo/wrong key while live; hosts fear the crash-mid-game
   failure mode and no tool addresses it (§C).
2. **Avoid-repeats intelligence** — everyone has a question library; nobody helps you
   *not* reuse a question across weekly nights (§A).
3. **Visual difficulty/category balance meter** while authoring (§A).
4. **Audio-round authoring** — the category leader (SpeedQuizzing) literally can't author
   audio questions in its builder; music rounds are beloved. Own this (§B/§D).
5. **First-class hybrid paper + digital** in one leaderboard with identical scoring rules
   (§E).
6. **Curated "story behind the answer" content layer** + light host patter outline — the
   craft moat, and dead-on our charter (§C).
7. **BYOD tab-switch/focus cheating signal** — exists in exam tools, absent from trivia
   (§H).

---

## Proposed loop waves (point `/loop` at these in order)

Per owner direction (§Strategy): **build everything, defer the paywall.** All waves are
buildable now — A–C and L are serverless; D builds monetization *capability* without
wiring a paywall; E adds the portable-identity data plane at **$0 ongoing cost** (Firebase
Spark / Cloudflare free tiers, degrade-don't-bill). Every wave = "same verb, native
idiom" across the platforms the feature touches (most are macOS host + big screen;
join-side + consumer pieces fan to iOS/tvOS/Android/web).

- **Wave A — Authoring & run-of-show depth** (all serverless): question library + reuse +
  **avoid-repeats**, **drag-to-reorder**, **difficulty/category balance meter**,
  **mid-game editing**, **host notes + "story behind the answer"**, **per-question/round
  timers + on-screen countdown**, **CSV import**, complete the **wager round**.
- **Wave B — AV & show production** (all serverless): **SFX/stinger board** (bundled
  royalty-free), **audio rounds** (BYO-clip folder + selectable PA output + speed-tiered
  scoring), **video questions**, looping music beds, deeper big-screen chrome
  (round/question/difficulty labels + on-screen timer).
- **Wave C — Submission & scoring completeness** (all serverless): **first-class hybrid
  paper+digital** leaderboard, **beautiful printables**, **answer/name moderation gate**,
  **team merge**, **final-wager + brains-only tie-breaks**, **answer-lock timer**,
  optional **tab-switch focus signal**, **data export (CSV)**.
- **Wave D — Venue business & monetization *capabilities*** (serverless; build the
  capability, **defer the paywall**): **recurring-series scheduling**, **white-label
  depth**, **sponsor kit**, **lead capture + CSV export**, **data export**. No pricing or
  paywall wired — just the features, ready to gate later.
- **Wave E — Portable-identity data plane + network moat** ($0 ongoing cost; §L6 + §M):
  the connective tissue — **persistent player identity** spanning solo + live, **skill
  rating / lifetime stats**, **cross-venue & season leaderboards + per-venue standings +
  defendable titles**, **multi-venue org→hosts**, **analytics dashboard**, **venue
  directory**. Built on the §M two-plane $0 architecture (Firebase Spark writes + GitHub
  Actions cron → static JSON); degrades to stale-not-billed at any ceiling; no card, ever.
- **Wave L — Consumer game depth** (§L): the surface that makes the game worth carrying
  between nights — the **identity spine** (portable profile + Elo rating + two-track
  progression + claim flow), the **daily-habit loop** (cross-context forgiving streak,
  shareable result), **leagues/seasons**, **collection/cosmetics**, **async friend duels +
  persistent teams**, and the **"add the people you played with"** friend-manufacturing
  move. Monetization-safe by design (§L7 — no energy walls).

**Recommended lead — build the identity spine early.** The strongest research signal is
"**persistent identity/progression before the content-volume race**" (QuizUp/HQ died
without it). So the highest-leverage first build is **§L1 (identity spine) + §M ($0 data
plane) + §L2 (cross-context streak)** — it's cheap, it's the moat's foundation, and every
later feature (leaderboards, titles, leagues, host analytics) rides it. Two tracks can
then run in parallel: **host craft (A→D)** on the Mac app, and **consumer/identity (L→E)**
across all platforms — they meet at the live event, where a joined player's result flows
into their portable profile.

---

## Decisions — resolved / deferred (owner direction 2026-07-04)

1. **Backend vs. serverless → RESOLVED: build it, but only at $0 ongoing.** The gate is
   no longer "should we have a backend" but "does it stay within free tiers that never
   bill." Firebase RTDB Spark (already live) + GitHub Pages, with Cloudflare
   Workers/KV/D1/R2 free tiers as headroom, cover the moat. **Wave E is unblocked** as
   long as it holds the $0 line and degrades gracefully at a free ceiling rather than
   billing. (Concrete limits + the exact recommended stack land from the infra research.)
2. **Monetization → DEFERRED by design.** Build every feature first; decide the paywall
   after. **Two eventual premium surfaces, both TBD:** consumer premium (individuals) and
   host premium (Tidbits Live). Build monetization *capabilities* (lead-capture form,
   sponsor slot, branding depth) without wiring any paywall or pricing yet. No
   competitor's model determines ours.
3. **Consumer feature/premium set → research in flight.** A consumer-side backlog (game
   depth, progression, social, retention, portable identity) is being researched and will
   append here as **§L**. The loop should build both surfaces.
4. **Show-format ambition (Jeopardy/Feud/Wheel) → still open.** Big build, wide appeal;
   sequence it after the core waves unless prioritized.
5. **Settled by the research (no input needed):** **music = BYO-clip only** (licensing
   stays with the venue — never bundle a catalog); **SFX/stingers = safe to bundle**
   (royalty-free); **paper = a first-class format**, not a fallback.

---

## Research appendix (sources)

Full per-stream findings (with inline citations) are archived from the five research
agents that produced this backlog. Primary references by theme:

- **Pricing/tiers:** Buzztime, SpeedQuizzing, Crowdpurr, Kahoot 360, Slido, Mentimeter,
  myQuiz, Quizizz/Wayground, TriviaMaker, QuizXpress, QuizWitz, Quizado, Sporcle,
  Trivia Nation, King Trivia, Geeks Who Drink, Last Call, World Tavern (franchise).
- **Authoring/run-of-show:** SpeedQuizzing Question Manager, QuizXpress Studio, TriviaRat,
  TriviaFlow, TriviaMaker, Quizado, Geeks Who Drink, Water Cooler Trivia.
- **AV/show:** Crowdpurr (SFX/media help), SpeedQuizzing music rounds, QuizWitz, TriviaMaker
  Presenter, Sporcle Music Quiz, Presenti, Last Call audio guide, Epidemic/Mixkit (SFX),
  ASCAP/PRS (licensing).
- **Submission/scoring:** SpeedQuizzing Buzzin', Crowdpurr, QuizXpress Live, TriviaMaker
  (lenient spelling), QuizWitz, QuizRunners (paper), Pour House Trivia (rules), QuizNightHQ
  (tie-breaks), Sporcle (anti-cheat).
- **Venue business:** Buzztime, Sporcle Events/Globe league, Trivnow, World Tavern
  franchise, Crowdpurr (lead capture/white-label), TriviaBuild, Trivia Nation, ExMachina
  (monetization), CNBC/Untappd (business value).
- **Consumer game (§L):** Trivia Crack, QuizUp & HQ Trivia (post-mortems), LearnedLeague,
  Sporcle, Jackbox, Duolingo/NYT (habit/leagues/streaks), Water Cooler Trivia, Trivia
  Royale/Star (monetization). *Key: engagement ≠ retention; build persistent progression
  first; forgiving streaks; avoid energy walls.*
- **Portable identity (§L6):** parkrun (persistent barcode), chess Elo (USCF/FIDE), Strava
  (segments/KOM/Local Legends), Swarm (mayorships), Untappd (venue badge leveling), Pokémon
  GO (place graph), Kahoot (player identifier / anonymous join), MLB Ballpark (fan history),
  Peloton (two-track + friends-halve-churn). *Model: parkrun × Elo × Strava-local ×
  Peloton, via Kahoot anonymous-join/claim-later.*
- **$0 architecture (§M):** Firebase Spark limits + Blaze trap, Cloudflare
  Workers/KV/D1/R2/Pages free tiers (R2 zero-egress), GitHub Pages+Actions, Supabase/Turso/
  Deno/Val Town (fetched 2026-07-04). *Rule: no card = no bill; two-plane, static-aggregate,
  never Blaze.*
