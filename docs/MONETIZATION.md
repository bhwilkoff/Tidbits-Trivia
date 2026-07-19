# Tidbits Trivia — Monetization Strategy

**Status: ADOPTED — owner decisions made 2026-07-19 (§8). Decision 047.** Authored 2026-07-19 from two
research passes: a pricing-landscape survey of ~35 consumer trivia apps, host
tools, and venue networks; and a six-platform IAP/legal mechanics pass. Supersedes
the "decide the paywall later" posture in `docs/TIDBITS-LIVE-PREMIUM-BACKLOG.md`
§Strategy (which was correct at the time — the features now exist, so the decision
is live). Companion: `docs/EVENT-TRIVIA-COMPETITIVE.md` (market map).

Governed by the eight owner rules stated 2026-07-19. Each section names the rule
it serves.

---

## 1. The structural gap (rule 4)

Every vendor in the category monetizes **exactly one side of the room.**

| Who pays | Who charges them | Axis |
|---|---|---|
| The player | Trivia Crack, Trivia Star, Sway, Quizzland, Sporcle app, NYT | lives/energy, or time-based sub |
| The host / venue | Crowdpurr, Kahoot, Slido, AhaSlides, Quizado, Trivnow, Water Cooler | participant cap, host seats, events/mo, venue count |
| The venue (full service) | Sporcle Live, Geeks Who Drink, King Trivia, Buzztime | per night, per attendee, tablet count |

**Nobody bridges them.** The tell is Sporcle: the only company owning both a
consumer trivia subscription ($3.99/mo) *and* a national bar-trivia network
($3/player/night) — run as two unconnected businesses. Players at a Sporcle Live
bar play free and are never converted into app subscribers.

A 40-person bar night is **40 qualified installs of a trivia app**, delivered by
someone who is already paying a human $200 to make those people play trivia. No
one captures this.

### The economic fact that decides our model

- Venues pay hosts **$150–250/night**; venues **make $2,000–4,000** off a trivia night.
- A documented NYC P&L: $175 event fee → **$340 net profit** on ~40 players.
- Therefore **the software is a rounding error against the labor** — a $79/mo pack
  subscription is ~4% of what a venue spends on hosting.

**Conclusion: charging for host software is capturing the least valuable, most
price-resented 4% of the transaction.** The complaint quotes cluster exactly
there ("wildly overpriced" — Kahoot; "$149 and I've not seen the value" —
Crowdpurr; "price gouging" — Wayground).

---

## 2. The model (rules 4, 5, 8)

> ### Hosting is free. Forever. Unlimited players.
> ### Tidbits Club is for players — $29.99/yr.
> ### Venues buy Club passes in bulk and give them away as prizes.

Three sentences. That is the whole model (rule 5).

**Why this is defensible, not just cheap:** giving the host tool away costs us
~$0 (Firebase Spark + GitHub Pages, §5) while deleting the entire revenue basis
of Crowdpurr, Kahoot, Quizado, Trivnow, Slido, and AhaSlides. They cannot follow
us — host software *is* their business. For us it is customer acquisition. Every
night a host runs is 40 people installing a trivia app and creating an identity.

**Why the venue still pays us — and is happy to.** Not a software fee. A **prize
budget**. Venues already buy prizes (bar tabs, gift cards, merch). A Club pass is
a better prize than a $10 tab: it costs the venue less, it lasts a year, and it
brings the winner back next week with a standing to defend. The host's spend is
denominated in **player value, not software seats** — a line item venues already
have and never resent.

This is the two-sided axis nobody occupies (rule 4).

### What it is NOT

- ❌ Not a participant cap. The near-universal formula, and the most complained about.
- ❌ Not per-host-seat. Where the "wildly overpriced" quotes concentrate — a bar
  with two rotating emcees pays double for one weekly night.
- ❌ Not per-event credits. Nickel-and-dimes the occasional host.
- ❌ Not lives / energy / consumables. The highest user-hatred-per-dollar model
  in the category, and it fails rule 1 outright.

---

## 3. What is free forever (rule 1)

**R-MON-1 — the free tier is never reduced *after go-live*.** From launch day
forward, nothing free may move behind the paywall, ever.

> **Why:** Sporcle's defining complaint is that previously-free stats went behind
> a subscription. That single act generates more anger than the price.
>
> **Scope correction (owner, 2026-07-19):** this rule binds *from go-live
> forward*, not today. **We have not launched, so there are no users to take
> anything from — we are DRAWING the initial line, not moving it.** Any
> already-built feature may therefore be assigned to Club at launch. The earlier
> "premium must be net-new only" reading was over-strict and is withdrawn.
>
> **How to apply:** decide the line ONCE, before go-live, and treat it as frozen
> afterward. That makes the pre-launch scoping decision unusually high-stakes —
> it is the only moment this is cheap to get right.

Free forever, on every platform:

- **Daily Tidbits** and the daily archive
- **All game modes** — Quick Play, Closest Call, Ordering, Stake, Versus CPU
- **Records, streaks, personal bests, per-game answer detail**
- **Creating quizzes**, pass-and-play, local Trivia Night
- **Hosting Tidbits Live** — unlimited players, unlimited events, unlimited venues,
  every round type, big screen, tie-break engine, offline + printable fallback
- **Joining any event**, from any platform, with no account
- **Online Quick Match, duels, friends, cross-venue standings** (all shipped free)

This is the NYT Games shape: **Wordle stays free forever; the archive and the
depth are the subscription.** NYT and Sporcle are the two vendors in the entire
survey with pure time-based pricing and the least pricing rage — and NYT's
free-forever core is why.

---

## 4. What Tidbits Club is (rules 1, 5, 8)

**Club is "get better," not "play more."** It never gates play; it adds a layer
that only means something if you play a lot. This is the learning charter as a
business model — the premium tier is literally the *learning* tier.

> **The slate lives in §4a below.** An earlier five-pillar draft was cut: the
> owner judged it too thin (*"the ones we have outlined hardly seem like
> features at all"*), and a research pass found **three of the five collided with
> features already shipped free** — "practice your misses" is literally
> `dueReview()` on all four platforms with an opt-out toggle (PARITY row 214),
> and Topic Levels / The Pie / defendable titles are free too. It was partly
> re-selling what we already give away.

---

## 4a. Tidbits Club — the real slate (revised 2026-07-19)

Replaces the five pillars above. Two things forced the revision: the owner judged
the original slate too thin, and a research pass found that **three of the five
collided with features already shipped free** — "practice your misses" is
literally `dueReview()` on all four platforms with an opt-out toggle (PARITY row
214), and Topic Levels / The Pie / defendable titles are free too. The old slate
was partly re-selling what we already give away.

### The line — one test

> **Would a player with 5 hours of play notice this is gated?**
> If yes, it's **free**. If it only becomes legible at 50+ hours, it's **Club**.

That single test satisfies both hard constraints at once: a casual player never
feels cheated (rule 1), and a trivia obsessive sees an obvious reason to pay. It
is the same boundary Chess.com found — the free tier is genuinely fine for casual
play, and the ceiling only bites when you are trying to *improve*.

**Free forever, and it should feel lavish:** the daily + its archive, every core
mode, unlimited play, records with per-game answer detail, streaks, personal
bests, Elo, friends, duels, quick match, create-a-quiz, pass-and-play, the
cross-venue leaderboard, and **all hosting**. That is already a more generous
free tier than any product in the research.

> **The tension worth naming.** Our free tier is already rich in exactly the
> categories everyone else charges for — full records ≈ Chess.com Diamond,
> streaks ≈ Duolingo Super, standings ≈ Strava paid, daily archive ≈ NYT paid.
> **So the tier cannot be carried by analytics, because the strongest premium
> pattern in the research is largely already given away.** It has to be carried
> by *new verbs*. That is why the slate below leads with gameplay.

> **And the failure mode to avoid:** Sporcle Orange sells ads-off + stats +
> cosmetics and sits at **2.1/5**. Five analytics screens reads as Sporcle. Four
> new ways to play reads as NYT.

### The pitch, in one sentence

**"Ranked seasons, a multi-week campaign, a map of everything you know, and a
permanent library of every fact you've learned."**

Seasons + Expedition are the *play* reason. Atlas + Archive are the *keep*
reason. That is a materially different proposition from a stats page.

### Pillar 1 — New gameplay *(the anchor; the owner's "brand-new extensions")*

| Feature | What it is |
|---|---|
| **Ranked Seasons** ⭐ | Three-month arcs: placement, tiers, promotion **and demotion**, permanent season history. The only feature that creates a recurring, calendar-driven reason to return — and it ties solo play to live nights under one identity, which no competitor can match. Shaped as a battle pass: the free track levels by playing and **shows you the Club track you'd have earned** |
| **Expedition** ⭐ | A multi-week structured campaign through a domain ("The 20th Century") — stages, a map, a completion certificate. **This is what turns a session game into a pursuit**, and it's the clearest "this is a real feature" on the list |
| **Weak-spot Arena** | A round generated entirely from your own miss history, with a visible "closed the gap" payoff. The legitimate deeper layer above the free spaced review |
| **Survival ladder** | Escalating difficulty on the shipped ratings; one life; leaderboard by depth reached |
| **Marathon** | A 200-question graded endurance run with a permanent scorecard, played across sessions |
| **Time Machine** | A single decade, played as a themed run with period framing |
| **Draft** | Pick your categories before a head-to-head; your opponent picks theirs. A strategy layer over knowledge |
| **Speed drills** | Trains recall *latency*, charted over time |
| **Link Wall** (SOLO-BACKLOG M6) | The NYT-Connections-style puzzle: 16 fact-tiles, 4 hidden groups, reveal shows the link **and a cited why**. A *second* daily — **Daily Tidbits stays free and untouched** |

Note these are meaningless without a play history, which is exactly why gating
them passes the 5-hour test.

### Pillar 2 — Retrospection: your record, interpreted

Free gives you *your record*; Club gives you *your history interpreted* — the
distinction Strava draws between "here is your run" and "here is your fitness
curve." Genuinely new computation, not a lock on stored data.

| Feature | What it adds |
|---|---|
| **Knowledge Atlas** ⭐ | Accuracy by domain *and sub-domain* on a 12-month trajectory — what's rising, what's decaying. Free Topic Levels + Pie untouched |
| **Decay radar** | Flags topics you were strong in six months ago and have quietly lost — and schedules them back |
| **Retention curve** | Measured re-recall at 1wk / 1mo / 6mo. *Did the fact actually stick?* No trivia app answers this |
| **Calibration report** | Extends the free Stake tally into over/under-confidence by domain: where you bluff, where you underrate yourself |
| **Miss autopsy** | Clusters your wrong answers by **why** — era, geography, category adjacency, distractor type — not just by category |
| **Question percentile** | "You got this; 12% of players did," from the shipped answer-distribution telemetry |
| **Year in Review** | An annual shareable retrospective. Cheap, and Duolingo's share cards drove enormous organic reach |

### Pillar 3 — The library: the corpus as *your* collection

Free *plays* questions; Club *keeps* them. The NYT-archive pattern, and the most
on-brand idea available for a product whose whole thesis is that the tidbit is
the point.

| Feature | What it adds |
|---|---|
| **Story Archive** ⭐ | Every "story behind the answer" you've unlocked — kept forever, searchable, browsable by domain |
| **Deep dives** | Long-form cited companion pieces for facts you've met |
| **Curated packs** ⭐ | Regularly published themed sets, guest-authored and seasonal. **The only item that delivers fresh perceived value every month without new engineering** — the Anki/AnKing lesson: people pay for curation on top of a free tool |
| **Source trails** | Every fact links to its citation plus a web of related facts you've seen |
| **Annotated daily** | The daily, plus commentary on why each distractor is tempting |
| **Fact notebook** | Your own notes on any fact, resurfaced when it returns |

### Pillar 4 — Social & competitive

| Feature | Evidence |
|---|---|
| **Leagues** | 30-person weekly flights with promotion/demotion. Duolingo: **+17% learning time, 3× highly-engaged users.** Needs population — consider free-with-Club-perks rather than fully gated |
| **Friend streaks** | Mutual daily accountability. **+22% completion** — the highest leverage per unit of engineering in the entire research pass |
| **Rivalries** | Auto-designated nemeses at your level, persistent head-to-head record |
| **Club tournaments** | Scheduled brackets, standings, titles |
| **Filtered leaderboards** | Friends / venue / region / domain. **Filters, never rows** |
| **Streak insurance + Rest Days** | Bankable freezes and *scheduled rest that doesn't break the streak*. Selling forgiveness measurably increases engagement |

> **Structural rule, from Strava's 2020 mistake:** never paywall something whose
> value depends on free users participating. The leaderboard keeps every row for
> free players. Hollowing out the board to sell it back would destroy the moat.

### Pillar 5 — Personalization & identity

**Adaptive difficulty** (targets your ~75% success band per domain) · **Saved
custom mixes** · **Creator analytics** (for questions you wrote: plays, real
difficulty, distractor effectiveness) · **Club identity** (Founding Member badge,
season-history display — Lichess-style: pure status, zero competitive advantage).

### The anchor eight (if the launch set must be smaller)

Ordered by how likely a subscriber is to *name* them as the reason they paid:

1. **Ranked Seasons** — the only feature creating a recurring, calendar-driven
   return, and it ties solo play to live nights under one identity.
2. **Knowledge Atlas** — the flagship "what do I actually know."
3. **Story Archive** — the NYT-archive move; the most on-brand idea available.
4. **Expedition** — the substantial *new gameplay*; turns a session game into a
   pursuit.
5. **Leagues** — best-evidenced engagement mechanic found (+17% learning time,
   3× highly-engaged users). Needs population — consider free-with-Club-perks.
6. **Weak-spot Arena** — the honest deeper layer above free spaced review.
7. **Curated packs** — the only item delivering fresh value monthly *without new
   engineering*.
8. **Link Wall** — the marquee new puzzle; already designed in SOLO-BACKLOG M6.

### Two things the research advises AGAINST

- **An AI tutor/explainer as the tier anchor.** Duolingo Max — their most
  technically impressive build — is **9% of subscribers and publicly
  "underperforming lofty expectations."** Chess.com's AI coach is called
  "confusing." Meanwhile Duolingo's *cheap* mechanics (streaks, leagues) carry
  ~91% of subscribers. Do not build the trivia equivalent of Video Call with Lily.
- **Consumables, lives, or energy.** Highest hatred-per-dollar in the category and
  a direct contradiction of the learning charter (also barred by DECISIONS 022).

### Settled 2026-07-19 (owner)

- **Host Library stays FREE.** It sits inside "hosting is free forever." The promise
  is the more valuable asset than the feature.
- **Stake and Wager are MERGED into one mode**, taking the best of each rather than
  shipping two modes that feel like one. See §4b.

---

## 4b. Conviction — the merged Stake/Wager mode (owner-directed 2026-07-19)

Stake (shipped, free) and a proposed LearnedLeague-style Wager both monetize the same
insight — *knowing what you know* — so they merge into ONE mode rather than two that
feel like one.

**What each contributed.** Stake brings the **adds-only** economy (spend confidence
chips: Sure ×2 / Likely ×3 / Hunch ×3; correct earns, wrong earns nothing, **never
negative**) — the charter-safe framing that makes calibration a lesson instead of a
punishment. Wager brings **the point values matter competitively**, and LearnedLeague's
genuinely great idea: **you assign the values to your OPPONENT.**

**Conviction** = you commit a confidence level before each answer, and in head-to-head
play you also **assign your opponent's point values** (3/2/2/1/1/0 across their six),
scouting them from their public domain profile.

Why this is the strongest mode in the slate:

- **It makes async feel like a person is in the room.** You spend real thought on a
  specific named human hours before they wake up and play — social presence produced
  from a database row, with zero live connection. This is the answer to "make global
  play feel alive at $0."
- **It rewards modeling another mind**, which passes the learning-orientation test
  emphatically — better than any mode currently shipped.
- **It is quietly the best anti-cheat we have.** If your opponent assigns 0 points to
  the question you'd need to look up, cheating on it earns nothing. Designing the
  reward out beats trying to detect the behavior.
- **It makes the domain profile load-bearing** rather than decorative — the same move
  LearnedLeague makes by publishing per-category history.

**Free vs Club:** playing Conviction is **free** (it needs an opponent — see R-MON-4).
Club gets the **scouting dossier** (their domain profile, visualized) and the
**post-match calibration autopsy**.

---

### Price (decided 2026-07-19)

**$29.99/yr, or $3.99/mo.** One price, one entitlement, six platforms.

- Below NYT Games ($39.99–50/yr) and Sporcle in-app ($59.99/yr).
- **Venue pack: 10 Club passes for $99** (~$10/pass vs $29.99 retail). Cheaper
  per night than every host tool in §1, and it's a prize, not a fee.

### Founding Member lifetime — $79.99, launch window only

Owner decision: ship a lifetime unlock **alongside** the subscription. The risk
is real and named — a lifetime tier cannibalizes exactly the committed users
worth the most over time, which cuts against rule 8. Three constraints keep that
contained, and they are **part of the decision, not optional polish**:

1. **Genuinely time-limited.** Available for the first **90 days** after go-live,
   then withdrawn and never re-offered. If it is ever brought back, it stops
   being a launch instrument and becomes the default price of the product.
2. **Priced at $79.99, not $59.99** — a ~2.7-year breakeven against the annual.
   Buyers past that point are a loss only if they'd otherwise have stayed
   subscribed longer, and at 2.7 years they are the most committed cohort anyway.
3. **Carries a Founding Member badge** on the shared profile. Identity value
   costs us $0 and is a large part of what the cohort is actually buying.

**Mechanically the cheapest thing in the plan.** A non-consumable is exactly what
Apple's Universal Purchase restores across iOS/iPadOS/macOS/tvOS for free, and it
is the one product shape that needs no renewal state machine. Shipping it at
launch also de-risks the subscription: if renewal handling proves fiddly at $0,
the lifetime path is already proven and live.

**Review at day 90.** If lifetime take-up dominates annual, that is evidence the
annual price is wrong, not that lifetime should continue.

---

## 4c. Global multiplayer at $0 (owner-directed 2026-07-19)

### The correction that unlocks this

I initially told the owner that global multiplayer collided with the $0 guardrail,
because Firebase Spark caps at ~100 **simultaneous connections** app-wide. That was
too pessimistic and the framing was wrong.

Firebase defines a simultaneous connection as *"one mobile device, browser tab, or
server app connected to the database"* — i.e. a **persistent socket**. Stateless REST
calls are not that. **⚠️ Honest caveat: Firebase's public limits page does not state
the REST exclusion in so many words** — it is strongly implied by the definition rather
than documented outright. But the architecture does not rest on that inference: **this
app already runs entirely on REST** (the Windows/Apple clients are `HttpClient`-only,
"no SDK"), and the shipped Wave E leaderboard already does write → hourly cron →
static JSON → clients read the JSON, never the live DB.

So the budget splits into two very different economies:

| | Sockets (SDK/SSE) | REST + static JSON |
|---|---|---|
| Ceiling | **~100 concurrent, worldwide** | 1 GB stored, 10 GB/mo egress |
| Practical | ~25 concurrent rooms | millions of ops/month |
| Use for | **in-person Live nights only** | **everything global** |

### Two proposed rules

**R-NET-1 — Sockets are rationed; REST is abundant.** Persistent connections are
reserved for in-person Tidbits Live / Trivia Night rooms (free forever). Every global,
worldwide or ranked feature is REST-write + cron-aggregate + static-JSON-read. **No
global feature may open a socket.**

**R-NET-2 — The hourly cron is the league office.** `leaderboard.yml` already runs
hourly. It becomes the commissioner: matchmaking, pairing, scoring, promotion and
relegation, and anomaly detection. Pairing computed by cron costs zero connections and
zero dollars — and it is how LearnedLeague actually operates.

### The build order

| # | Ship | Why first |
|---|---|---|
| 1 | **The Daily Six** — everyone worldwide gets the SAME six questions daily; cron ranks and publishes | Cheapest global feature that exists (no pairing to compute), reuses the shipped cron pipeline nearly verbatim, and everything else attaches to it |
| 2 | **Push notifications** ("the appointment") | Async lives or dies on the return trigger. Build the urgency engine *before* the things that need urgency. **⚠️ Verify FCM's free tier before building — three modes depend on it** |
| 3 | **Rundles** — ~25–30 player cohorts, 25-day seasons, promotion/relegation | Turns a meaningless global rank into a bounded, winnable, named-rival narrative. The retention engine. Duolingo: a 30-person flight motivates where a global board doesn't |
| 4 | **Domain profile + Conviction duels** (§4b) | The profile is prerequisite infrastructure; Conviction is what makes async feel like a person |
| 5 | **Global Ghost Race** — race a *recorded* run from a real human, bundled into static JSON | **The ethical cold-start fix.** Instant "someone to play" at any hour, from real human data — no synthetic opponents wearing human names (Decision 038 stays intact). Ship it BEFORE there's a population |
| 6 | **Knowledge Opposite** — match by profile *complement*, not rating twin | **The differentiator.** Research found essentially no prior art for domain-profile matchmaking in trivia. Unclaimed territory |

Also cheap and additive on top of #1: **Nations** (per-capita country boards, pure
aggregation), a **live ticker** ("1,847 people played today's Six" — past tense, always
true), and **Glicko-2 in the cron** (RD handles irregular players; batch update over a
rating period is the algorithm's native mode, which is exactly an hourly Action).

### R-MON-4 — The Population Rule

> **Never gate a seat; gate the view from the seat.** If a feature's quality depends on
> how many other people are in it, **it is free.** Club buys what you can enjoy alone.
>
> **Playing, ranking, and being ranked are always free. Understanding, scouting,
> archiving, curating, and configuring are Club.**

This supersedes "filters, never rows" — correct for leaderboards, but insufficient
here. **A thinner leaderboard is merely less interesting; a thinner matchmaking pool is
broken.** It is also exactly the Chess.com line (they paywall Lessons, unlimited
Puzzles, Game Review and Coach — the *analysis* layer, atop free play and rating), and
the precise inverse of Strava's 2020 error.

| Free forever | Club |
|---|---|
| Daily Six + global rank | Daily Six autopsy, per-question percentile, calibration |
| A rundle seat, every season | Rundle history archive, opponent scouting |
| Conviction duels vs anyone | Pre-match scouting dossier |
| Knowledge Opposite / Draft & Ban matchmaking | Post-match domain autopsy, Knowledge Atlas |
| Ghosts, Nations, Territory, tournament entry, guild membership | Founding/curating a guild, custom Club tournaments |
| Rivalry head-to-head records | Rivalry deep analytics |

**Specific warning:** do **not** put a Club-only division at the *top* of the main
ladder. That structurally caps free players and makes the free ladder a demo — Strava's
mistake in a new costume. Run Club competition **parallel** (a Club Invitational
alongside the main season) so nobody's ladder is capped; Club members simply have more
to do. The venue packs and Founding Members are well-suited to seeding those early so
they don't feel empty.

### Anti-cheat at $0 (people can google when unobserved)

Commercial proctoring (webcam, lockdown browsers) is hostile, costly, and fails the
charter. **LearnedLeague runs an honor code at 35,800+ members** — culture scales
further than software here. Four free layers:

1. **An explicit honor code** at Ranked opt-in, restated each season, in the app's voice.
2. **Structural friction** — short per-question timers; answers publish only after the
   daily window closes (the `live/{code}` design already withholds until reveal).
3. **Statistical anomaly detection in the cron** — free, because the cron already reads
   everything. Flag fast-correct answers on questions with low global accuracy; the
   Daily Six gives the difficulty baseline for nothing.
4. **Design the reward out** — Conviction's opponent-assigned values mean a
   0-point question is worthless to cheat on.

**Enforcement is graduated and quiet:** rating-freeze and an unranked pool, never public
shaming. *Wrong is a door.*

### What we honestly CANNOT afford — say so plainly

- **Sustained live head-to-head vs strangers worldwide.** ~100 sockets app-wide is ~50
  simultaneous live matches *for the planet*, and those sockets belong to in-person Live
  nights — the strategic wedge. Global realtime would cannibalize it.
- **Live global tournaments** beyond ~60 simultaneous players.
- **Live chat and realtime presence.** Spectating can be approximated with 30-second
  static-JSON polling; live chat cannot and should be cut.
- **Any "online now" count or green dot.** Not merely unaffordable — **dishonest** under
  the charter. Say *"1,847 played today,"* which is true and says more.

**The one place to spend the socket budget:** a **Season Finale Hour** — once per
season, ~60 connections, the top of each rundle, genuinely live. Rare, precious, and
affordable *because* it is rare. Needs an explicit socket budget and a
spectate-via-static-JSON overflow path.

> **Precedent worth noting:** Decision 023 already recorded that the two realtime-only
> trivia apps researched (HQ, QuizUp) died, while the async/league apps (Trivia Crack,
> LearnedLeague) survived. This is not a compromise architecture — it is the one that
> has actually sustained competitive trivia communities.

### ⚠️ Doc conflict to resolve before building any Club-gated mode

**Decision 022** says monetization is *"convenience/cosmetic — never content-gating."*
**Decision 047** reframes Club as the learning tier, and the slate (Knowledge Atlas,
Story Archive, Expedition) is closer to content than convenience. 047 is later and
governs, but the texts read as inconsistent. Per *"fix the doc first, then fix the
feature,"* amend 022 to point at 047 **before** shipping a Club-gated mode.

---

## 5. Cost to run: $0 ongoing (rule 3)

| Component | Cost | Ceiling behavior |
|---|---|---|
| Firebase RTDB (Spark) | $0 | Hard-stops, never bills |
| Cloudflare Worker (webhook → entitlement) | $0 | 100k req/day, no card |
| Merchant of Record (Paddle / Lemon Squeezy) | $0 base, 5% + $0.50/sale | Purely variable |
| GitHub Pages | $0 | — |
| Microsoft Partner Center | $0 | Registration fee removed 2025 |

**Fixed ongoing cost: $99/yr — the Apple Developer membership already carried.**
Everything else is $0 or purely variable. No metered service is ever enabled
(no Firebase Blaze), consistent with the standing guardrail.

---

## 6. Payments per platform (rule 2)

### The two rules that constrain everything

**Apple Guideline 3.1.3(b)** permits unlocking a purchase made on your website —
*"provided those items are also available as in-app purchases within the app."*
There is no compliant "web-only, apps just unlock it" model. **StoreKit IAP is
mandatory on iOS/macOS/tvOS.**

**Apple Guideline 3.1.1** bans unlocking via *"license keys, augmented reality
markers, QR codes, cryptocurrencies…"* — so:

**R-MON-2 — entitlement is unlocked by account sign-in only.** Never a code,
key, coupon, voucher, or QR the user redeems in-app.

> **Why:** 3.1.1 explicitly prohibits those mechanisms. Our `sha256(verified
> email)` identity spine is already the compliant shape; the risk is someone
> later adding a well-meaning "have a code? paste it here" field and converting
> a compliant app into a rejection.
>
> **How to apply:** venue prize passes are redeemed by **signing in**, not by
> typing a code. The venue assigns a pass to an email; the player signs in and
> it's simply there.

### Fees and mechanics

| Platform | Mechanism | Fee | Notes |
|---|---|---|---|
| iOS / iPadOS / macOS / tvOS | StoreKit 2, **required** | 15% (Small Business Program) | **Universal Purchase = all four are one platform.** Same bundle ID, one IAP product, restores across all. Zero extra work. |
| Android | Play Billing | **10%** service + 5% billing = 15% | Play's base is now the lowest of the three. Consumption-only is *explicitly allowed* — Play does not require us to sell IAP at all. |
| Windows | Microsoft Store IAP, **required** | 12% | Product type is **Game** (verified: Store ID `9NRKS9LDRCWC`, "MSIX or PWA game"). Policy 10.8.1 forces MS commerce and **forbids link-out**. |
| Web | Merchant of Record | 5% + $0.50 | Best margin by far. MoR handles EU VAT / US nexus — worth ~2pts over raw Stripe to avoid filing in ~45 states. |

**Apple Small Business Program: enroll now.** Free, takes effect 15 days after
fiscal-month approval, and turns year-one subscription commission from 30% → 15%.
There is no reason to wait for a product.

**Do not model margin on the US link-out staying at 0%.** It is a live litigation
artifact — SCOTUS granted cert June 2026, argument Oct–Dec 2026, ruling ~June 2027.
Treat today's 0% as upside, assume it reverts to 12–27%.

---

## 7. Entitlement architecture (rules 2, 3)

Verified in code: RTDB rules already enforce `auth.token.email_verified === true`
plus an `emailOwners/{key}` ownership proof. The `sha256(verified email)` spine is
enforced **server-side by rules**, not merely client-side. Entitlement rides it.

**Two classes of entitlement, and they must not be treated alike:**

**Class A — locally provable, authoritative, works offline.** StoreKit 2
(`Transaction.currentEntitlements`, JWS-verified on device), Play (RSA-signed
`Purchase`), Microsoft (`StoreContext`). Each store cryptographically attests the
purchase to the device. *If the local store says entitled, you are entitled* —
never gate this behind a network read.

**Class B — remote assertion, needs a trusted writer.** The web purchase. The
device has no proof, only a claim in a database.

```
isEntitled = localStoreEntitlement        // Class A — offline, authoritative
          || remoteEntitlement(myHash)    // Class B — requires verified sign-in
```

**R-MON-3 — clients never write to `entitlements/`.** A Cloudflare Worker
(holding the MoR webhook secret + a Firebase admin credential) is the sole writer.

> **Why:** `players/{key}` is world-readable and owner-writable by design — it's
> a game profile. An `isPro` flag written by the client is trivially forged by
> anyone with the RTDB URL. `entitlements/` needs `".write": false` for every
> client and read scoped to the requesting hash.

```
entitlements/{sha256(email)} = { tier, sources: ["web","apple","play","msstore"], since, ver }
```

**Cross-store mirroring: don't, at first.** Each store's purchase unlocks its own
ecosystem (Apple's universal purchase already covers four platforms); the **web
purchase is the universal one**. This is clean, secure, and an honest incentive:
*buy on the web, get everything* — which is also our best margin. Revisit only if
users actually ask.

**Family Sharing caveat:** if enabled, one Apple purchase entitles up to 6 people.
Either accept it (generous, on-brand) or gate the mirror on
`transaction.ownershipType == .purchased`. Decide before shipping.

**Fraud, honestly:** account sharing is the only leak that matters at scale, and
every no-server product accepts it. Chasing it costs more than it saves and makes
the product worse for honest households. Signature forgery is infeasible; binary
patching on rooted devices costs one sale from someone who was never paying.

---

## 8. Decisions — 2026-07-19

*Items 1–3 are owner decisions. Items 4–5 are defaults chosen by Claude to
unblock the build; both are cheap to reverse and flagged for owner review.*

1. **Hosting is free forever, unconditional.** ✅ No player cap, no event cap, no
   venue cap, no future "Pro host" tier. This is load-bearing: it is what
   competitors structurally cannot match, because host software *is* their
   business. Treat any later proposal to gate a hosting feature as a violation of
   this decision, not a pricing tweak.
2. **Price: $29.99/yr or $3.99/mo; venue pack 10 passes for $99.** ✅ The venue
   frame is a **prize budget**, not a software fee.
3. **Ship BOTH a subscription and a Founding Member lifetime ($79.99).** ✅ Owner
   chose both over the recommended subscription-only. The cannibalization risk is
   accepted and mitigated by three binding constraints — 90-day window, $79.99
   (not $59.99), Founding Member badge — see §4. **Day-90 review is part of the
   decision.**
4. **Windows stays categorized as a Game.** ⚙️ *Claude's default.* Follows from
   the owner's launch sequencing (build Windows sign-in, then ship all six with
   IAP) — re-categorizing would be a separate fight. 12% and no link-out accepted.
   **Owner review:** the non-game path keeps 100% and allows link-out, so if the
   Avalonia `StoreContext` spike fails, re-categorization becomes the fallback
   *and* a margin win. Worth 30 minutes before the spike, not after.
5. **Family Sharing: ON.** ⚙️ *Claude's default.* Consistent with rule 1 and the
   household framing — a trivia app is played with the people you live with. Cost
   is bounded (up to 6 people per Apple purchase); goodwill likely exceeds the
   leak. **Owner review:** turning it on later is easy; turning it *off* after
   launch takes an entitlement away from real families and would violate the
   spirit of R-MON-1. So this is the one default here that hardens on ship.

---

## 9. Go-live blockers (rule 7)

**Owner decision 2026-07-19: build Windows sign-in FIRST, then launch all six
simultaneously.** Rule 7 is honored in full — no platform ships the paywall
before the others. The consequence is that Windows sets the launch date, so #1
and #3 below are the critical path and should start first.

In dependency order:

| # | Blocker | Why it blocks |
|---|---|---|
| 1 | **Windows sign-in** — Google desktop OAuth **BUILT 2026-07-19** (loopback + PKCE, 245 tests green on `windows-latest`). Remaining: paste the Desktop OAuth client id, wire `PlayerIdentityStore` to email-key, add the Settings UI | Windows could not resolve an email-keyed entitlement. Largely unblocked. |
| 2 | **Build the Club slate** (§4a) | The tier must be substantial — a thin tier reads as Sporcle (2.1/5). This is now the **largest** item: pillar 1 alone is several new game modes. |
| 3 | **`Tidbits.Windows` IAP spike** — Avalonia + MSIX + `StoreContext` + `IInitializeWithWindow` via `TryGetPlatformHandle` | Every piece is documented; the *composition* has no public worked example. Cannot be validated on the Mac head (Decision 045). Highest-risk item in the plan. |
| 4 | Cloudflare Worker + MoR + `entitlements/` rules | Class B path (§7) |
| 5 | StoreKit 2 / Play Billing / MS Store product setup + SBP enrollment | Store-side config lead time |
| 6 | **Promo surface on the web app** (rule 6) | Must sell without degrading the free web app — additive landing + upgrade surface, never an interstitial |
| 7 | Version bump + six-channel ship | Standing convention |

**#1 and #3 are the real schedule risk.** Both are Windows, and both are only
verifiable through `windows-repl.yml` CI.

### Recommended order of work

1. **Windows sign-in** (#1) — unblocks everything else on Windows and is
   ordinary work: port the existing Apple/Google federated flow already shipped
   on web + Android into `Tidbits.Core`. Gets the riskiest platform to parity.
2. **`Tidbits.Windows` IAP spike** (#3) — do this *early and timeboxed*, because
   its failure mode changes decision 4 in §8 (re-categorize as non-game). Finding
   that out late is expensive; finding it out early is a margin win.
3. **The five Club features** (#2) — the long pole in calendar terms, and the
   only item that is pure product work. Can proceed in parallel with 1–2.
4. **Entitlement plumbing** (#4, #5) — Worker + MoR + `entitlements/` rules +
   store product config + SBP enrollment. Enroll in the Apple Small Business
   Program *now*; it has a 15-day activation lag and no downside.
5. **Web promo surface** (#6) — last, because it advertises whatever 1–4 became.
6. **Six-channel ship** (#7).

**Start #4's SBP enrollment today regardless of everything else** — it is free,
takes 15 days to activate, and halves year-one subscription commission.

---

## 10. Corrections to `docs/EVENT-TRIVIA-COMPETITIVE.md` §I

Applied 2026-07-19 from the pricing pass:

1. Quizado's **$74.99 per-event App Store option is gone** — now subscription-only,
   and the axis is **venue count** (1→3), not player count.
2. Kahoot is **not** "~$10–17/mo" — it's $19–79/mo individual, and Teams start at
   **$6,000/yr with a 25-seat minimum**. The old figure understated it ~2×.
3. Water Cooler Trivia's "~$1/participant" is confirmed — and bills **active**
   participants only, with zero feature gating. It is the only vendor in the
   entire survey with no findable pricing complaint.
