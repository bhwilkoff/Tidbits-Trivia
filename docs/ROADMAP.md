# Tidbits Trivia — Competitive Roadmap

> Distilled from market research across ~16 trivia/quiz apps (Trivia Crack,
> HQ Trivia, QuizUp, Kahoot, Quizizz, Sporcle, LearnedLeague, Jackbox,
> Jeopardy titles, Wikitrivia, Connections, Immaculate Grid, Duolingo).
> The single strategic finding: **for a Wikipedia-sourced app the product
> is the validation/filtering layer, not the data source.** Anyone can hit
> the API; the moat is turning a firehose of true-but-misleading triples
> into fun, unambiguous, single-answer questions (see QUESTION-QUALITY.md).

## Positioning (the wedge no incumbent owns)

**"Accurate, fair, learning-forward Wikipedia trivia."** Auto-generated
trivia exists but nobody has solved quality control at consumer scale, and
the market's *universal* complaint is monetization aggression (energy,
gacha, ad walls, pay-to-restore-streak). A clean reputation — no energy, no
cash prizes, ad-light, every question a learning door — is itself a
differentiator.

## Table stakes (must-have or we look broken)

| # | Feature | Status |
|---|---|---|
| 1 | Instant solo loop, no setup | ✅ iOS |
| 2 | MCQ + countdown + speed scoring | ✅ iOS |
| 3 | Category / topic selection | ✅ iOS |
| 4 | Daily challenge | ✅ iOS (deterministic daily set) |
| 5 | Streaks + personal stats | ✅ iOS (records + daily streak) |
| 6 | Leaderboards / ladder | ⏳ Game Center wired, config pending |
| 7 | Friend play + shareable result | ⏳ ShareLink ✅; friend play Phase 2 |
| 8 | Four loading states done well | ✅ iOS |
| 9 | Answer-validation accepts equivalents | ⏳ needs alias/redirect layer |

## Differentiators (ranked by impact) — the build order

1. **Daily Wikipedia puzzle + streak + spoiler-free shareable result.**
   Highest-leverage retention mechanic of the era (Connections, Wordle,
   Immaculate Grid all prove it; free to operate). *v1 has the daily +
   streak + share; the spoiler-free emoji-grid share is Phase 2.*
2. **The rigorous question-validation pipeline (THE MOAT).** Wikidata
   SPARQL spine + date-property whitelisting + precision checks + sanity
   bounds + alias/redirect answer-matching. *v1 ships the template + gate
   skeleton; Wikidata layer is the top corpus priority.*
3. **"Learn the fact" tap-through after every question.** Unique to a
   Wikipedia source; the literal embodiment of the mission. *✅ shipped.*
4. **tvOS living-room mode, zero-install phone-as-buzzer, short room code.**
   The biggest open market gap (Jackbox proves the join model; the TV-brand
   incumbents abandoned local play). *Phase 2 — tvOS milestone.*
5. **Async friend challenges + promotion/relegation league ladder.** Async
   is the survivability-proven multiplayer model; ladders lift return ~25%
   (Duolingo). *Phase 2/3.*
6. **Type-the-answer (active recall) mode.** Most learning-aligned; Sporcle
   proves it's loved. Needs alias/redirect matching. *Phase 3.*
7. **Curated quality tiers (Vital Articles / sitelink-popularity).** Solves
   obscurity + vandalism in one move. *Corpus pipeline.*
8. **LearnedLeague-style defense/wager twist** in competitive matches.
   Rare, under-copied; outcome ≠ raw score. *Phase 3.*
9. **Region/language-aware rotation that never repeats.** Neutralizes
   Jackbox's two biggest complaints. *v1 has never-repeat; localization later.*
10. **Immaculate-Grid-style daily intersection grid** over two Wikidata
    facets. Proven viral, highly shareable. *Phase 3 (needs Wikidata).*

## Multiplayer model decision

Async > synchronous for survivability (the two real-time-only apps died).
Build order: **local pass-and-play → Game Center async head-to-head & groups
→ tvOS living-room with phone-as-buzzer → cross-platform online via Supabase.**
Same-room and remote should be the SAME mechanic (Jackbox's lesson). See
DECISIONS 023.

## Game modes, interaction methods & bar-trivia formats

**Deep research + the proposed slate of Tidbits "home versions" live in
`docs/GAME-MODES-RESEARCH.md`** — a full catalog of (A) bar/pub-trivia formats,
(B) quiz question/interaction types, and (C) phone-as-buzzer / second-screen
architecture, plus Part D: each proposed mode run through the learning-orientation
four-question test. Headline findings:
- **Phone-as-buzzer is phased:** Apple-native local (Network.framework + Bonjour +
  TLS-PSK; offline, no server, Apple-only same-room) as the MVP → a universal
  **web-room** (Cloudflare Durable Object; `tidbits.tv/<code>`, any phone browser,
  same-room *and* remote). tvOS has no web view, so the host is always native; only
  phones are browsers.
- **One Wikidata enrichment pass (numeric + Commons image + aliases) unlocks SEVEN
  formats** (Closest-to, Ordering, This-or-That, Picture ID, Type-the-answer,
  Matching, Wits & Wagers) — the highest-leverage corpus investment.
- **Recommended first modes** (all-yes on the test, ride the current corpus):
  **Stake** (adds-only confidence allocation), **Couch Co-op** (no-infra same-room),
  **Predict the Crowd** (needs answer-distribution telemetry). Marquee daily:
  **Link Wall** (a cited-why Connections home version).

## Anti-patterns we will NOT build (every one is a documented 1-star driver)

Cash-prize-split economics · energy/lives gating (esp. in a paid tier) ·
paywalling previously-free features · ad walls between matches · appointment-
only live shows with nothing between · pay-to-restore-streak · manufactured
near-misses / FOMO / variable-reward compulsion loops decoupled from learning.
(See DECISIONS 022 and SCRATCHPAD "Out of scope.")

## Monetization (decided early — QuizUp shut down at 80M users with no plan)

Clean and non-manipulative: a one-time or low flat subscription for
convenience/cosmetic perks (extra create-a-quiz saves, themes, deeper
stats) — never content-gating, never energy. Live in-person/pub-quiz events
are a possible third leg later (Sporcle's moat). *Not in v1; logged here so
the decision isn't deferred into a crisis.*
