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

Sequenced so each wave is **serverless and shippable** until Wave D/E, which need owner
decisions. Every wave = "same verb, native idiom" across the platforms the feature
touches (most are macOS host + big screen; join-side pieces fan to iOS/tvOS/Android/web).

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
- **Wave D — Venue business & monetization** 🔒 (needs decisions): pricing/player-caps,
  **white-label depth**, **sponsor kit**, **lead capture + export**, **recurring-series
  scheduling** (recurring is serverless; the rest need the monetization stance).
- **Wave E — The network moat** 🔒 (needs a backend decision): **persistent team
  accounts + cross-venue/season leaderboards**, **multi-venue org→hosts**, **analytics
  dashboard**, **retention layer** (badges/streaks/shareable profiles), **venue
  directory**.

---

## Decisions for Ben (gate Waves D & E)

1. **Backend or serverless?** Cross-venue/season leaderboards, lead capture, multi-venue,
   host networks, and cross-event analytics all need a network backend. Tidbits is
   serverless today (per-ecosystem sync + Firebase RTDB for live rooms). This is the
   single biggest fork — it unlocks the Buzztime/Sporcle moat (Wave E) but is real
   infrastructure.
2. **Monetization stance.** Is Tidbits Live a paid venue product? If so, which model —
   **per-venue subscription** ($199–299/mo, Buzztime), **per-event activation**
   (SpeedQuizzing), or **per-host SaaS tier** ($25–100/mo)? And does it carry
   **sponsor/ads** + **lead capture**? This shapes Wave D.
3. **Show-format ambition.** How far into named game-show boards (Jeopardy/Feud/Wheel) do
   we go? (Phase-C in the dossier; big build, wide appeal.)
4. **Already decided by the research** (no further input needed): **music = BYO-clip
   only**, never a bundled catalog (licensing stays with the venue); **SFX = safe to
   bundle**; **paper = a first-class format**, not a fallback.

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
