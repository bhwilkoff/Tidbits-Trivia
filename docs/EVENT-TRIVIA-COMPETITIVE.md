# Tidbits Live — Pub/Event Trivia Competitive Dossier & Feature Checklist

Research date: **2026-07-03** (multi-source, cited). Purpose: define what the
Mac-exclusive **Tidbits Live** event system must do to compete on *features*
and *design* in the pub/bar/event trivia market. This is the binding checklist
the `docs/macOS-DESIGN.md` Part A builds against.

Sources are the four research passes in this session (Crowdpurr, Quizado,
SpeedQuizzing, Buzztime, TriviaMaker, Rapid Trivia + a landscape survey of
Sporcle, QuizXpress, TriviaRat, TriviaNerd, Kahoot, AhaSlides, Geeks Who Drink,
King Trivia, etc.). URLs are in the session research artifacts.

---

## 1. The market splits three ways

1. **Self-serve host software** (our direct competitors) — Crowdpurr, **Quizado**
   (the closest: a *native Mac* bar-trivia app), SpeedQuizzing, QuizXpress,
   TriviaRat, TriviaNerd, VenueTrivia, TriviaMaker, Rapid Trivia, Bar Trivia
   (Gig Game).
2. **Repurposed classroom/corporate poll-quiz tools** — Kahoot, AhaSlides,
   Slido, Mentimeter. Hosts bend these into bar use; criticized as childish,
   individual-only, low free caps.
3. **Full-service host networks** (sell the whole night, not a tool) — Buzztime,
   Geeks Who Drink, King Trivia, Sporcle Live, Quiz Meisters.

A Mac emcee dashboard competes head-on with (1) and lets a venue bring the
operation **in-house** vs. paying (3).

---

## 2. Competitor capsules (what each is known for)

- **Quizado** — *closest competitor; native macOS app.* 6 round types (Buzzer
  Race, Everyone-Answers Speed, Everyone-Answers Knowledge, Majority Rules,
  Knockout, Wager) + 4 named show formats (Jeopardy, Family Feud, Name That
  Tune, Wheel of Fortune). Projector scoreboard with live team colors, wagers +
  penalties + tie-breaks, AI generator, per-venue subscription (€490–1,990/yr)
  **plus a per-event $74.99 App Store option.** **BUT App Store rating is
  1.0/5** — reliability + pricing complaints. **The opening: their model is
  right, their execution isn't.**
- **SpeedQuizzing** — *the speed mechanic.* Fastest-correct sliding-scale bonus
  (base + 8/7/6/5 to the four fastest), instant answer lock under a 10-sec
  timer marketed as *cheat-resistant* ("outpaces Siri"). Buzzin' fastest-finger,
  Nearest-Wins tiebreaker round, Speed Bingo. Native Win/Mac desktop app; a
  **HUB LAN router** for offline reliability. Per-activation pricing (£21).
  Anti-AI. Weak reconnect; utilitarian/dated UX.
- **Crowdpurr** — *polished, "more adult than Kahoot."* 3 playback modes (Host-
  Controlled / Automatic / Crowd-Controlled), strong Presentation View + winner
  animations, AI generation, MC/Text/Numeric/Drag-order/poll types, points
  wagering. **No native "round" object** (each round = a separate game). **No
  manual score correction** (reviewer-confirmed). Ads gated at $499/mo.
- **Buzztime** — *national cross-venue leaderboards* (its moat) + always-on
  automated network + huge catalog (Countdown trivia where points erode with
  time, QB1 live-sports prediction, poker, bingo). Subscription $199–299/mo,
  BYOD shift, on-screen DOOH advertising. Dated UX; declining venue count.
- **TriviaMaker** — *7 game-show board styles* (Jeopardy Grid, Feud List, Wheel,
  Millionaire, Tic-Tac, Hangman, Fusion), AI from PDF/text, deep theming.
  General-purpose; thinner pub live-ops.
- **Rapid Trivia** — *AI-voiceover virtual host* runs the night unattended;
  speed-weighted scoring + round multipliers (1×→4×), recurring scheduling,
  in-screen sponsor offers, ROI/profit-calculator framing.

---

> **2026-07-03 upgrade wave SHIPPED (1.6.20):** speed-bonus/fastest-finger scoring,
> free-text review + spelling leniency (Mac cockpit), host answer-lock cheating
> deterrence (all platforms), a live vote-distribution tally (poll/majority viz), and
> the big-screen SHOW system (theatrical reveal, climbing leaderboard, round-intro
> cards, winner celebration — §A8). Deferred: kick/moderate (needs a rules change),
> CSV import, recurring scheduling, analytics, tab-switch focus signal.

## 3. The master feature checklist

Legend: **[TS]** table-stakes (must-have to be credible) · **[D]** differentiator
(only some have it) · **[P]** premium/rare (few have it — opportunity). The
"Tidbits Live" column is our target: ✅ MVP · ▶︎ Phase 2 · ◇ later/optional.

### A. Event / round / question authoring
| Feature | Tier | Tidbits Live |
|---|---|---|
| Custom question editor (category/clue/answer/points) | TS | ✅ |
| Bundled/expert question library | TS | ✅ (our 20k+ Wikipedia corpus) |
| **First-class multi-round "night" structure** (named rounds, reorder, clone) | D | ✅ |
| Save/duplicate an event to re-run weekly | D | ✅ |
| AI question generation from a topic/prompt | D→TS | ✅ (we already have `DelightfulQuizGenerator`) |
| Import questions (CSV / spreadsheet) | D | ▶︎ |
| Reusable game/round templates | D | ✅ |

### B. Question & round formats
| Feature | Tier | Tidbits Live |
|---|---|---|
| MCQ / True-False / short-answer | TS | ✅ |
| Picture round (image) | TS | ✅ |
| **Audio round** (clip ID — the pub genre standard) | TS(bar) | ▶︎ |
| Video question | D | ◇ |
| **Nearest-wins / numeric estimate** (also the tie-break unit) | D | ✅ (Closest Call exists) |
| Ordering / sequence | D | ✅ (Ordering mode exists) |
| **Fastest-finger / buzzer race** (speed scoring) | D | ▶︎ |
| Wagering (bet before answering) | D | ✅ (Stake mode maps here) |
| Named show formats (Jeopardy board, Feud, Wheel) | D | ◇ (Phase 3 "show mode") |
| Poll / majority-rules | D | ▶︎ |
| Lightning / speed round | D | ▶︎ |

### C. Live host control (the emcee cockpit)
| Feature | Tier | Tidbits Live |
|---|---|---|
| Manual advance / host-paced (not auto-timer) | TS | ✅ |
| **Reveal-on-command** (hold answers/scores; "dramatic pause") | D | ✅ |
| **Mid-event editing** (fix a question/answer while running) | D | ✅ |
| **Manual score override / dispute correction** | **P** | ✅ **(our headline differentiator)** |
| **Free-text answer review + spelling leniency** (mark-as-correct) | **P** | ✅ |
| Pause / skip / re-open a question | D | ✅ |
| Live answer tally (see submissions in real time) | D | ✅ |
| Kick/moderate a team | D | ▶︎ |

### D. Player join & team management
| Feature | Tier | Tidbits Live |
|---|---|---|
| QR / short-link / PIN join, **no app download** | TS | ✅ (web join) |
| **Join via the existing Tidbits apps** (iOS/Android/web) | **P** | ✅ **(unique — we have a consumer install base)** |
| Team mode (several phones → one team on screen) | D | ✅ |
| Team name entry + display on big screen | D | ✅ |
| **Rejoin/reconnect after drop** | D | ✅ (weak spot across the field) |
| Player cap that fits a full room (100s) | TS(paid) | ✅ |

### E. Big-screen / projector presentation
| Feature | Tier | Tidbits Live |
|---|---|---|
| Dedicated big-screen output separate from host view | TS | ✅ (second window/display) |
| Live animated leaderboard + reveal HUD | D | ✅ |
| **Team names + scores legible across a loud room** (ten-foot) | TS | ✅ |
| QR-join screen on the big display | TS | ✅ |
| Venue branding (logo, colors) / white-label | D | ▶︎ |
| Audio round plays through the venue PA | TS(bar) | ▶︎ |
| Stream out to Twitch/YouTube/Zoom | P | ◇ |

### F. Scoring, leaderboards, tie-breakers
| Feature | Tier | Tidbits Live |
|---|---|---|
| Auto-scoring + running leaderboard (round + cumulative) | TS | ✅ |
| Speed-bonus scoring (faster = more) | D | ▶︎ |
| Round multipliers / point tiers | D | ✅ |
| Point wagering / penalties | D | ✅ |
| **Built-in tie-break engine** (numeric closest-wins / sudden-death prompt) | **P** | ✅ **(differentiator)** |
| Full team rankings (not just top-5) | D | ✅ |
| Anti-runaway / comeback mechanic | D | ◇ |
| Cross-venue / season-long standings network | P | ◇ (needs backend — see decision) |

### G. Reliability & integrity (biggest under-served category)
| Feature | Tier | Tidbits Live |
|---|---|---|
| **Offline / weak-Wi-Fi resilience** | P | ✅ **(Mac-native strength — lean in)** |
| **Printable answer-sheet / question pack fallback** (Wi-Fi dies) | P | ✅ |
| Graceful reconnect mid-game | D | ✅ |
| **Cheating deterrence** (answer-lock timers, tab-switch signal, brains-only tie-break) | **P** | ▶︎ **(the #1 host complaint)** |

### H. Venue monetization (mostly open territory)
| Feature | Tier | Tidbits Live |
|---|---|---|
| Sponsor logo/branding on screen | D | ▶︎ |
| **Sponsor ad-slide slots between rounds** | P | ▶︎ |
| **Lead capture** (collect player emails for the venue) | P | ◇ |
| Prize/coupon fulfillment | P | ◇ |
| Recurring-night scheduling | D | ▶︎ |
| Post-event analytics / returning-team tracking | D | ▶︎ |

### I. Pricing models observed
*(Re-verified 2026-07-19 — three figures below were wrong or stale. The full
landscape survey and the resulting strategy now live in `docs/MONETIZATION.md`.)*

Freemium + monthly subscription (dominant: **Kahoot $19–79/mo individual, Teams
from $6,000/yr at a 25-seat minimum** — the old "~$10–17" understated it ~2×;
TriviaMaker $6.99, Crowdpurr $50–500, Quizado €490–1,990/yr, **axis = venue
count, and their $74.99 per-event App Store option is GONE — subscription-only
now**); **per-participant (Water Cooler ~$1 — bills ACTIVE participants only,
gates zero features, and is the only vendor in the survey with no findable
pricing complaint)**; per-event / pay-per-quiz (VenueTrivia $5–82.50,
SpeedQuizzing £7–21/activation — the occasional-host sweet spot); full-service
per-night (host networks; Sporcle Live $3/player + $15 admin, collared
$115–225).

**The structural finding:** every vendor monetizes exactly ONE side of the room —
player OR host/venue, never both. See `docs/MONETIZATION.md` §1.

---

## 4. What hosts complain about most (our "fix-these" list)

1. **Cheating via phones** (#1) — Googling/Shazam. Deter with fast answer-lock
   timers, tab-switch/focus signals, and brains-only tie-break rounds.
2. **No manual score correction / spelling leniency** — auto-graders reject
   correct-but-misspelled answers; hosts need one-tap override + free-text
   "mark correct" review. *Almost nobody ships this well.*
3. **Tie-breaks unsupported** — tools declare a tie and leave the host to
   improvise. Ship a real tie-break engine.
4. **Free-tier caps + individual-only** — a bar needs teams and 100+ people.
5. **Hardware cost/lock-in** — buzzers ($550+) and proprietary tablets are dead
   weight. BYOD/phone is the answer.
6. **Wi-Fi fragility, no fallback** — a dead router kills a phone-join night.
7. **Too "gamey"/childish** (Kahoot's neon) — adults want a classier show.
8. **No built-in monetization / lead capture** — sponsors, prizes, emails are
   all manual today.

---

## 5. Where Tidbits wins (strategic thesis)

Three moats no competitor combines:

1. **A consumer install base to join with.** We already ship native iOS, iPadOS,
   tvOS, Android, and web Tidbits apps. Event players can join *in the app they
   may already have* (or web) — and every event is a funnel into daily Tidbits
   play + streaks. No competitor has a consumer app on the other side of the
   join QR. **This is the single biggest advantage.**
2. **A 20k+ question corpus + AI generation, already built.** Quizado/Crowdpurr
   bolt on AI; SpeedQuizzing refuses it; Buzztime hand-writes centrally. We own
   a large, curated Wikipedia-derived corpus AND `DelightfulQuizGenerator` — a
   host can spin a themed night in seconds and hand-edit it.
3. **Native-Mac quality + reliability where the field is weak.** Quizado is
   native Mac but 1.0-rated; SpeedQuizzing/Buzztime read dated. A genuinely
   polished, offline-resilient Mac emcee app (the sticker-book design language,
   ten-foot big screen, printable fallback) beats the incumbents on the two
   axes Ben named: *features and design.*

**The differentiators to build first** (all under-served, all map to host pain):
first-class **manual scoring/overrides**, a **tie-break engine**, **cheating
deterrence**, **offline/printable fallback**, and **join-via-Tidbits-apps**.

---

## 6. Proposed Tidbits Live feature set (phased)

**MVP (Phase A) — "run a real pub night end to end":**
Event builder (rounds + questions, from corpus / AI / manual) → host cockpit
(manual pacing, reveal-on-command, live tally, **manual score override**,
**free-text review**) → big-screen output (question, QR join, team leaderboard,
ten-foot legible) → phone/web/app team join with reconnect → auto-scoring +
cumulative leaderboard + **tie-break engine** → post-event recap. Offline-capable
on the Mac; **printable answer sheets** as the Wi-Fi-dead fallback.

**Phase B — depth:** audio rounds (through PA), fastest-finger speed scoring,
poll/majority round, venue branding + sponsor slides, recurring scheduling,
cheating-deterrence signals, kick/moderate, import CSV, analytics.

**Phase C — show & network:** named game-show formats (Jeopardy board / Feud /
Wheel "show mode"), lead capture + prize/coupon, cross-venue/season leaderboards
(requires a backend — a strategic decision, not a given), streaming out.

*(The full parity buildout of the existing Tidbits app on macOS proceeds in
parallel and is tracked in `docs/macOS-DESIGN.md` Part B / `PARITY.md`.)*

---

## 7. Open scope decisions (for Ben)

1. **Backend or serverless?** Cross-venue/season leaderboards (Buzztime's moat)
   and lead capture need a network backend. Tidbits is serverless today
   (per-ecosystem sync islands + Firebase for online match). Do we stay
   serverless (single-venue, local-network events + optional Firebase) or invest
   in a venue backend for cross-venue/network features?
2. **Player join surface.** Web-only join (universal, zero-install) vs. also
   deep-linking the native Tidbits apps for join. (Recommend: web join for MVP,
   app join in Phase B — the moat.)
3. **Monetization stance.** Is Tidbits Live a paid venue product (per-event vs.
   subscription) and does it carry sponsor/ads? Shapes the branding + lead-
   capture build.
4. **Show-format ambition.** How much do the Jeopardy/Feud "show mode" boards
   matter vs. a clean Tidbits-native round system? (They're TriviaMaker/Quizado's
   flash; they're also a large build.)
