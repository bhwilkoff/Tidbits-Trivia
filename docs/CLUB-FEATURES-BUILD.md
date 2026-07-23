# Tidbits Club — the FEATURE build (running checklist)

**This is the sequel to `docs/CLUB-MONETIZATION-BUILD.md`.** That doc got the
*paywall* code-complete on all 6 platforms (entitlement spine + purchase code +
paywall UI). This doc tracks the **actual Club-exclusive features** — the reasons
a player would ever choose to pay. As of 2026-07-22 the spine exists and **zero
features are built.** That is the work.

## The frame (do not re-litigate — Decision 047, `MONETIZATION.md §4a`)

- **Club is "get better," not "play more."** It never gates core play. It adds a
  layer. R-MON-1 (never reduce the free tier after go-live) is binding.
- **Lead with new gameplay VERBS, not analytics.** Research finding worth not
  re-deriving: "five analytics screens reads as Sporcle (2.1★); four new ways to
  play reads as NYT." Our free tier is already rich in exactly what everyone else
  charges for (records/streaks/standings/archive), so the tier must be carried by
  *new verbs*, not a lock on stored data.
- **The line — one test:** *would a player with 5 hours of play notice this is
  gated?* Yes → free. Only legible at 50+ hrs → Club. Most Club features are
  **meaningless without a play history**, which is exactly why gating them passes
  the test and never cheats a casual player.
- **We are not upselling.** No dark patterns, no "upgrade to continue." A player
  converts only if they personally see value. Every gated surface shows a genuine
  preview of the value, never a nag.
- **$0 ongoing infra** (R-NET-1/2). Client-side computation first; RTDB REST +
  hourly-cron + static-JSON for anything shared; never a persistent socket for a
  global feature.

## Gating + verification convention (all platforms)

- One gate: `EntitlementStore.isClub` (Apple) / `Entitlement.isClub` (Android) /
  `entitlement.isClub` (web) / `EntitlementStore.IsClub` (Windows). Already wired.
- **Pre-launch there are no real purchases**, so every feature is verified behind a
  **debug entitlement override**: `TIDBITS_CLUB=1` (Apple env / `SIMCTL_CHILD_`),
  `?club=1` or `localStorage.tidbitsClubDebug` (web), a BuildConfig/DEBUG flag
  (Android), an env/DEBUG flag (Windows). Add the override to each platform's
  entitlement store the first time a feature needs it (once, then reused).
- **A gated feature always renders a real preview + an honest "what you get" panel
  for non-members**, linking to the existing paywall — never a blank wall.
- Verify per the repo rule: run it (sim / headless PNG / emulator) and observe,
  don't just compile. Update `PARITY.md` + this tracker in the same change set.

## Build order (self-contained + $0 first; backend-heavy last)

Front-loaded so momentum features (pure client-side, observable, no owner setup)
ship first; season/cron infrastructure is last.

| # | Feature | Pillar | Shape | Status |
|---|---|---|---|---|
| 1 | **Weak-Spot Arena** | 1 gameplay | client-only: round from your own miss history | **DONE on all 6 platforms** |
| 2 | **Story Archive** | 3 library | client-only: keep every unlocked "story behind the answer", searchable | **DONE on all 6 platforms** |
| 3 | **Marathon** | 1 gameplay | client-only: 200-q graded endurance, cross-session scorecard | **DONE on all 6 platforms** |
| 4 | **Knowledge Atlas** | 2 retrospect | client-only: accuracy by domain/sub-domain over 12mo, every domain tappable into a round | **DONE on all 6 platforms** |
| 5 | **Friend Streaks** | 4 social | light RTDB (reuses friends): mutual daily accountability | todo |
| 6 | **Link Wall** | 1 gameplay | client-only: NYT-Connections-style 2nd daily (Daily stays free) | todo |
| 7 | **Expedition** | 1 gameplay | client-only: multi-week structured campaign, map + certificate | todo |
| 8 | **Ranked Seasons** | 1 gameplay | RTDB + hourly cron: 3-month arcs, tiers, promo/demotion | todo |

Also on deck to **research** (a parallel loop lane, low-cost): fresh incentive
ideas that deepen daily use + delight (see §Research log). The slate above is not
frozen — research may reorder or add.

**Reorder + owner-decision flag (2026-07-22):** Features 1–4 (all "you alone"
features) shipped cleanly. **Features 5 (Friend Streaks) and 8 (Ranked Seasons) are
SOCIAL — their value depends on other people participating, so R-MON-4 (the
Population Rule) says do NOT fully gate the seat; the monetization doc itself flags
them "free-with-Club-perks rather than fully gated."** Building them as pure
Club-exclusives would violate R-MON-4 and is an **owner-level free/Club-split
decision** (what's the free base vs the Club perk?). **These are DEFERRED pending an
owner call.** Proceeding instead with the remaining **clean single-player** features
that pass R-MON-4 without a split: **Expedition (next), then Link Wall** (Link Wall
also carries a content-generation risk — a quality Connections-style group generator
over the corpus — flagged). Build order is now: 5→**Expedition**, 6→**Link Wall**,
then owner-gated: Friend Streaks, Ranked Seasons.

## Feature 5 — Expedition (design spec)

**One line:** a multi-week **structured campaign** through a single domain ("The
20th Century", "World Geography") — ordered stages, a visible map/path, and a
completion certificate. Turns a session game into a *pursuit* (Pillar 1 ⭐;
MONETIZATION §4a — "the clearest 'this is a real feature' on the list").

**Four-question test (passed 2026-07-22):** deepens understanding (a *structured
progression* through a domain — stages build toward mastery, not random rounds —
which is how real learning is scaffolded); invites participation (you choose which
expedition to undertake and pace it across weeks — your commitment is the input);
supports agency (a completion **certificate** is an earned mastery marker you own,
and the map shows how far you've come on your own steam); clarity (a plain ordered
list of stages + a progress path; each stage is a normal round — no opaque
mechanic).

**Structure (assemble from existing pieces — no new game engine):**
- An **Expedition** = an ordered list of **stages** (say 6–10). Each stage is a
  themed round the EXISTING engine already plays (a category/difficulty-filtered
  `.classic`/`.ladder`/mixed round, or a specific mode), with a stage title +
  a pass bar (e.g. "get 6/10 to advance"). Stages unlock in order.
- A few curated Expeditions defined in data/code (domain-scoped: e.g. "The 20th
  Century" pulls history questions across decades; "Around the World" walks
  continents). Start with 2–3 hand-defined ones; the shape must allow adding more
  without a client change (a small JSON/struct list).
- **Persistence** (mirror the Marathon pattern — a resumable model): an
  `ExpeditionProgress` per expedition {expeditionID, currentStageIndex, per-stage
  pass/score, startedAt}. You play a stage, pass → advance; you can leave and come
  back over days/weeks. On completing the last stage → a permanent
  `ExpeditionCertificate` (domain, date, score) shown in a "Completed" shelf.

**Surface:**
- Entry: a Club-marked **Expeditions** destination (its own card — it's a
  commitment, like Marathon). Lists available expeditions with progress ("Stage 3
  of 8"), plus a Completed/certificates shelf.
- An expedition detail = the **map/path** of stages (locked/current/done), tap the
  current stage → play it; on pass, the next unlocks with a beat of celebration.
- Empty/first-run: "Pick an expedition — a guided journey through a subject, one
  stage at a time, at your own pace."
- Non-member: a real preview (the map of an expedition + its first stage described)
  → paywall, never a blank wall. (First stage playable-as-teaser is an option to
  discuss; default to preview-not-play to keep it simple and honest.)

**Gating:** Club-only (single-player, passes R-MON-4 — no one else needed). Reuse
the `TIDBITS_CLUB=1` debug override. Do NOT create a new game engine — stages route
into the existing launch path with a filter + a pass bar.

**Apple reference = canonical.** The load-bearing shared pieces: the Expedition
DATA shape (portable across platforms) + the resume/certificate persistence
(mirror Marathon). Get both right on Apple first.

---

## Per-feature × per-platform status matrix

Legend: ✅ done+verified · 🔨 in progress · ⏳ queued · 🚫 n/a (with reason)

| Feature | web | iOS/iPadOS | macOS | tvOS | Android | Windows |
|---|---|---|---|---|---|---|
| 1 Weak-Spot Arena | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2 Story Archive | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 3 Marathon | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4 Knowledge Atlas | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 5 Expedition | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| — Friend Streaks (deferred: owner free/Club split, R-MON-4) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 6 Link Wall | ✅ | ✅ | ⏳ | ⏳ | ⏳ | ⏳ |
| 7 Expedition | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 8 Ranked Seasons | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |

> Note: the `.weakSpot` GameMode + `WeakSpotArena` generator live in the shared Apple
> `Core/`, so macOS/tvOS already COMPILE it — only their per-platform Home entry point +
> Club gating remain (small). iOS is the full reference.
>
> Note: `.marathon` + `Marathon`/`MarathonRun`/`MarathonScore` (Core/Store,
> Core/Models) are shared Apple `Core/`, so macOS/tvOS already COMPILE them (both
> gates verified BUILD SUCCEEDED) — only their per-platform Home entry point + a
> Records-equivalent history surface remain. iOS is the full reference, including
> the resume-across-sessions mechanic other platforms mirror.
>
> Note: `KnowledgeAtlas` (Core/Store) is a pure derivation of the same
> `GameRecord.categoryID/correct/total/date` rows `ProgressMath`/`DomainProgress`
> already read for the free Topic Levels/Pie — no new persistence, no `@Model`.
> **The category taxonomy (`TriviaCategory.all`) is FLAT — 8 categories, no
> sub-domains/parent groups** — so the Atlas operates at the category level only;
> "sub-domain drill" from the design spec is not applicable until the taxonomy
> gains a hierarchy. Month-bucketing uses each GAME's date for all of its answers
> (`AnswerDetail` carries no per-answer timestamp). macOS/tvOS already COMPILE the
> Core service (BUILD SUCCEEDED); only their per-platform Records surface remains.
> iOS is the full reference. Debug hook: `TIDBITS_ATLAS=1`.
>
> Note: Expedition's data shape (`Expedition`/`ExpeditionStage`, Core/Models/
> ExpeditionModels.swift) is a plain `static let all` catalog — 3 hand-defined
> campaigns (The 20th Century / Around the World / The Scientific Record, 7
> stages each) — plus two `@Model`s (`ExpeditionProgress` at-many-in-progress,
> `ExpeditionCertificate` permanent), both registered in the ModelContainer
> schema. NOT a new game engine: `Expeditions.startStage` filters the bundled
> corpus by the stage's `categoryID` + a DIFFICULTY BAND (the taxonomy is FLAT
> — same constraint the Knowledge Atlas hit — so stages differentiate by
> difficulty, not sub-domain) and routes into the existing `.classic` launch
> path. macOS/tvOS already COMPILE the Core service + models (BUILD SUCCEEDED);
> only their per-platform Home entry point + map surface remain. iOS is the
> full reference: an Expeditions destination reachable by everyone (the list +
> an expedition's stage map are a real preview; only the Play tap is Club-gated
> → `ClubPaywallView`, never a blank wall), a stage pass unlocks the next +
> persists across relaunch (hardware-verified via SQLite inspection, mirroring
> Marathon), and the last stage passing writes a permanent certificate + clears
> progress (also SQLite-confirmed). Debug hooks: `TIDBITS_EXPEDITION=1` (open
> the list) + `TIDBITS_EXPEDITION_FORCE_PASS=1` (a stage always records as a
> pass regardless of score — autopilot always submits option 0, so it can't
> reliably clear a real pass bar) + two verification-only hooks added because
> this dev box has no GUI Simulator window to tap through:
> `TIDBITS_EXPEDITION_MAP=<id>` (open straight to a map) and
> `TIDBITS_EXPEDITION_AUTOPLAY=<id>:<stageIndex>` (launch straight into a
> stage's play).
>
> Note: Android's `data/KnowledgeAtlas.kt` mirrors the Apple/web math exactly
> (sampleFloor 8 / strongThreshold 0.70 / decayDelta 0.12) over `Store.records()` —
> pure derivation, no new persistence. Unlike web/Apple, Android's `Store.Rec` has
> carried a game-level epoch (`at`) since the original Records-history feature, so
> no additive timestamp change was needed; a record with a missing/zero `at` is
> treated as older than the trailing-12-month window (same as any record that old)
> and keeps feeding the free lifetime Pie/Levels untouched. Records → Knowledge
> Atlas card (Pops.pink) → `KnowledgeAtlasScreen`; every domain row taps into
> `Route.Game(Mode.CLASSIC, Category)`, the same launch path Quick Play uses; decay
> rows carry their own "Shore it up" round. Reused `tidbits_club_debug`. Windows is
> next: `Tidbits.Core`'s `GameRecord` already has a `Date` field (`DateTime.UtcNow`
> default) mirroring Android's `at` — port the same pure-derivation math over
> `GameData`'s stored records, no schema change needed there either.
>
> Note: Android's `data/Expeditions.kt` mirrors the Apple/web catalog exactly —
> the SAME 3 seven-stage campaigns (The 20th Century / Around the World / The
> Scientific Record), `questionCount`=10 / `passBar`=6, difficulty bands per
> stage over the real per-question `Question.difficulty` field (no separate
> overlay needed — Android's classic corpus rows already carry a genuine 1-5
> difficulty). `Expeditions.startStage` pulls a difficulty-banded set from
> `Corpus.pull(categoryId, …)`, relaxing to the whole category pool if the band
> comes up thin (never-empty, mirrors Ladder's difficulty filtering).
> Persistence is a `Store.expeditionProgress()` SharedPreferences JSON object
> keyed by expeditionId (several campaigns in progress at once, mirroring
> Apple's per-expeditionID rows / web's MAP) + a separate
> `expeditionCertificates` JSON array. A stage plays as a normal `Mode.CLASSIC`
> round with a `custom` question list (`GameState.end()` needed NO
> special-casing — a stage genuinely writes an ordinary `GameRecord`/misses/
> telemetry, unlike Marathon which deliberately skips that write); only the
> RESULT screen is special-cased in `GameScreen` (`Route.Game.expeditionId` +
> `expeditionStageIndex`), calling `Expeditions.recordStageResult` once on
> `GamePhase.FINISHED` and rendering a dedicated pass/fail/certificate beat
> (`ExpeditionStageResultScreen`) instead of the default `ResultsScreen`. Mint
> Club `ExpeditionsCard` on Home (always opens the hub, never the paywall
> directly — hub + map are curated content reachable by everyone, matching
> Apple/web); `ExpeditionsHubScreen` (campaign list + certificates shelf) and
> `ExpeditionMapScreen` (locked/current/done stage path) render fully for
> non-members too; only the map's "Play" button is Club-gated → the existing
> `ClubPaywallScreen`. Debug: reused `tidbits_club_debug` + a new DEBUG-only
> `expedition_force_pass` intent extra (`Expeditions.debugForcePass`, mirrors
> Apple's `TIDBITS_EXPEDITION_FORCE_PASS` — autopilot can't reliably clear a
> real pass bar either). assembleDebug BUILD SUCCESSFUL; emulator-verified: a
> REAL (non-forced) round scored 1/10 → "NOT QUITE — Needed 6 of 10... you got
> 1" → Try Again → stage did NOT advance (SharedPreferences-confirmed,
> `currentStageIndex` stayed 0); the force-pass hook drove a full 7-stage
> completion → certificate written (`totalScore`/`stagesCompleted`) with the
> progress row DELETED in the same SharedPreferences edit; both the
> in-progress failed campaign and the completed certificate survived TWO cold
> `am force-stop` relaunches, and two campaigns (one failed-and-stuck, one
> completed) stayed independent throughout; non-member hub/map rendered as a
> full preview and tapping Play routed to `ClubPaywallScreen`. No version
> bump.

---

## Feature 1 — Weak-Spot Arena (design spec)

**One line:** a Club round built entirely from *your own* misses — the legitimate
deeper layer above the free spaced-review weave (`dueReview()`, PARITY 214).

**Four-question test (passed 2026-07-22):** deepens understanding (re-teaches your
gaps with the story-behind-the-answer); invites participation (the round is
*authored by your play history*); supports agency (measured by a visible "gaps
closed" tally, it makes you more knowledgeable, not more dependent); clarity (each
question shows *why* it's here — "missed 2 weeks ago, ×3" — never an opaque model).

**Data source (local, per device — the miss store each platform already keeps):**
- Apple: SwiftData `MissedFact` (`questionID, missCount, lastSeen, resolved,
  question`). `RecordsStore.dueReview` already fetches unresolved misses
  most-missed + oldest-first.
- Web / Android / Windows: their existing miss/again stores (audit each; the
  spaced-review weave exists on all four so a miss list exists somewhere).

**Generation (transparent, not a model):** take unresolved misses, sort by
`missCount` desc then `lastSeen` asc (oldest gap first), take up to 10. If fewer
than a floor (say 4), fill the remainder from the *domains* you miss most (weakest
categories) so the round is always playable — and label those as "shoring up
[domain]" so it stays honest. Each item carries a reason string.

**Play:** reuse the existing engine (`startCustom(mode:.weakSpot, category:.named
("mixed"), questions:)` on Apple; the equivalent custom-question entry elsewhere).
Standard MCQ shell. Per-question: show the small "why you're seeing this" reason.
On a correct answer to a previously-missed question, that miss **resolves**
(already the engine's behavior via `resolveMiss` on re-ask-correct) → increment a
**gaps-closed** counter.

**Result screen:** headline = "You closed N gaps." Show which facts moved from
missed → known, and how many remain. This is the payoff and the reason to return.

**Gating:** Club-only. Non-members see the mode card with a real explanation +
one sample ("Here's a fact you missed — Club turns your misses into a round") and
a link to the paywall. Members launch it.

**Entry point per platform:** it is a *mode*, so it lives with the other modes but
visually marked Club (a small "Club" chip). Apple: add `.weakSpot` to `GameMode`
(NOT in `playableModes`' free Customize grid — a dedicated Club row/section on
Home). Empty state when the player has ~no misses yet: "Play a few rounds first —
your misses become your arena."

**Apple reference = the canonical implementation.** Other platforms mirror its
behavior in their native idiom (same verb, native idiom).

---

## Feature 2 — Story Archive (design spec)

**One line:** Club keeps every "story behind the answer" you've ever unlocked —
a permanent, searchable, browsable library of the facts you've met. The corpus as
*your* collection (Pillar 3 ⭐, the NYT-archive pattern; MONETIZATION §4a).

**The load-bearing constraint (R-MON-1 — do not violate):** the story
(`Question.explanation`) is shown FREE in the moment, after you answer, on every
platform. Story Archive does **not** gate or remove that. It ADDS a surface that
does not exist for free users at all — free users see each story once, in passing;
Club members get the persistent, searchable, revisitable *library* of everything
they've seen. Additive, never subtractive. (This is why it passes the line test: a
5-hour player has a thin archive; the value only compounds at 50+ hours.)

**Four-question test (passed 2026-07-22):** deepens understanding (revisiting +
connecting facts you've learned is textbook spaced retrieval; the library makes the
corpus a place you *study*, not just play); invites participation (you curate it by
what you play; add a lightweight **favorite** ⭐ and it becomes your own collection —
a co-authored result, not a passive feed); supports agency (a reference you *own* and
can search offline — makes you more capable independently); clarity (a plain
searchable list/grid → tap → read the story; no opaque model, no "for you" surface —
expose the domain structure via filters, per the skill).

**Data source (local, per device):** the set of DISTINCT questions the player has
encountered — derivable from the already-persisted per-answer detail
(`AnswerDetail`/`GameRecord` qids on Apple; the equivalent seen/answered records on
web/Android/Windows). Join each qid → the corpus row for its `explanation` (story),
`prompt`, `correctAnswer`, and category/domain. If a platform doesn't persist a seen
qid set, add one additively (a small append-on-answer store), keyed by qid, cheap.
Whether "seen" = answered (right or wrong) or "unlocked = answered correctly" is a
design call: default to **any question you've answered** (you met the fact either
way), and MARK which ones you got right — that's more honest and more useful.

**The surface (Club-gated, new):**
- Entry point: a **Story Archive** row/section in Records (Records is the dashboard,
  R-REC-1 — the archive is a "see all" destination off it), Club-marked.
- A searchable, filterable list/grid of story cards: the fact, the answer, its domain,
  the date you met it, a right/wrong marker, and a **favorite** toggle.
- **Search** by text (prompt/answer/story) + **filter** by domain and by
  favorited/missed. The web's URL-state superpower applies (`#/archive?domain=…`).
- Tap a card → read the full story (`explanation`) + a link to re-ask that question
  (routes into a 1-question drill or the Weak-Spot engine). Closes the loop back to
  play.
- Empty state (member, nothing seen yet): "Play a few rounds — the stories you unlock
  are kept here forever."
- Non-member: a real preview (their most recent story, or a sample) + the honest
  "Club keeps every story you unlock, searchable forever" panel → existing paywall.
  Never a wall on the in-moment story itself.

**Favorite ⭐ (the participation lever):** a per-qid favorite flag (local; syncs later
via the existing per-ecosystem sync if present). Favorites get their own filter. Keep
it dead simple — a heart/star on the card. (A full "fact notebook" with your own notes
is a separate Pillar-3 item; note it as a fast-follow, don't build it here.)

**Apple reference = canonical.** Other platforms mirror the behavior (same verb,
native idiom). Reuse the Weak-Spot debug override (`TIDBITS_CLUB=1` etc.) to verify.

---

## Feature 3 — Marathon (design spec)

**One line:** a long, graded, **resume-across-sessions** endurance run (200 questions)
with a permanent per-domain scorecard — a personal challenge you own and measurably
improve on (Pillar 1; MONETIZATION §4a).

**The tension named + resolved (learning-orientation):** a raw endurance run leans
"play more," and Club is "get *better*, not play more." So the value is NOT the
volume — it's the **graded, per-domain scorecard** and the **comparison to your past
marathons**. Marathon is framed as a measured mastery challenge, not a grind:
- Deepen understanding? YES — 200 questions is broad cross-domain exposure, and the
  per-domain result tells you where you're strong/weak (a map, not a score).
- Invite participation? YES — you pace it yourself across sessions (resume), and the
  scorecard compares against your own prior runs — your history is the input.
- Support agency? YES — a personal best you own; the domain breakdown points you at
  what to shore up next (links back to Weak-Spot Arena / Story Archive).
- Clarity? YES — 200 questions, graded, resumable, a plain scorecard. No opaque model.

**Line test:** a 5-hour player won't undertake a 200-Q resumable marathon; it's
legible only to a committed player. Clean Club.

**The new mechanic (this is what makes it a real feature, not a long Classic):**
**resume across sessions.** Persist an in-progress run so the player can leave and
come back. Each platform adds a small persisted `MarathonRun` (current index, the
answers/score so far, the fixed 200-question id list + a seed so the SAME questions
resume, startedAt). On launch, if an unfinished run exists, offer **Resume** or
**Start over**. On finish, write a permanent `MarathonScore` (score, correct/total,
per-domain breakdown, date, duration) and clear the in-progress run.

**Generation:** 200 questions from the corpus (mixed by default; optionally a chosen
domain), drawn by a stored seed so a resume is deterministic. Graded: correct/total +
a difficulty-weighted score (reuse the existing difficulty overlay if present).

**Surface:**
- Entry: a Club-marked **Marathon** card (its own, distinct from the quick modes —
  it's a commitment, not a 2-minute round). Shows Resume state if a run is in
  progress ("Question 84 of 200 — resume?").
- Play: reuse the engine's question-run loop; a persistent progress indicator
  (84/200) and periodic save (every answer persists, so a crash/quit never loses
  progress). No clock pressure (it's endurance, not speed) — or a generous per-Q clock.
- Result / scorecard: score + correct/total + **per-domain accuracy bars** + how it
  compares to your best prior marathon ("+6% vs your last run"). A permanent
  **Marathon history** list (past runs) off Records.
- Empty/first-run: "A 200-question test of everything. Play it across as many
  sittings as you like — we'll keep your place."
- Non-member: a real preview (the pitch + a sample of the domain-scorecard idea) →
  paywall, never a blank wall.

**Gating:** Club-only. Reuse the `TIDBITS_CLUB=1` etc. debug override. Do NOT let the
`.marathon` mode leak into the free Customize grid / remembered / random default
(same exclusion the prior two features needed on every platform).

**Apple reference = canonical.** Others mirror the behavior (same verb, native idiom).
The load-bearing shared piece is the resume persistence — get it right on Apple first.

---

## Feature 4 — Knowledge Atlas (design spec)

**One line:** your accuracy by domain *and sub-domain* on a 12-month trajectory —
what's rising, what's decaying — with every domain tappable into a round that shores
it up. Your record, *interpreted* (Pillar 2 ⭐; MONETIZATION §4a).

**The trap to avoid (research finding):** "five analytics screens reads as Sporcle
(2.1★)." So Knowledge Atlas must NOT be a passive dashboard. The rule for this
feature: **every number is a door.** Tapping a weak or decaying domain launches a
targeted round (reuse the Weak-Spot engine / a domain-filtered round). It interprets
AND acts. That is what keeps it "get better," not a stats wall.

**Four-question test (passed 2026-07-22):** deepens understanding (a map of what you
know shows the SHAPE of your knowledge, not just a score — and names sub-domains you'd
never have articulated); invites participation (you act on it — tap a decaying domain
→ play it; you choose what to shore up); supports agency (it points you at your own
next step and hands you the round to take it — the opposite of a passive readout);
clarity (plain bars + a simple up/down trajectory arrow; NO opaque "mastery score"
black box — show the accuracy and the sample size).

**Data source (local):** the persisted per-answer history (`AnswerDetail`/`GameRecord`
on Apple — each carries categoryID + correct + the record's date; the equivalents on
web/Android/Windows). Bucket answers by **domain** (and sub-domain where the corpus
has one — check the category taxonomy) × **month** for the trailing 12 months. Compute
per-domain accuracy, sample size, and a trajectory (this-quarter vs prior-quarter
delta). Everything is a transparent count — no model.
- **Decay radar** (a sub-view of the same data): domains you were strong in 6+ months
  ago and have since declined → surfaced with a "shore it up" round button. Honest
  about sample size (don't flag a domain with 3 answers).

**Surface:**
- Entry: a Club-marked **Knowledge Atlas** destination off Records (R-REC-1 "see all";
  Records already has free Topic Levels / The Pie — Atlas is the deeper 12-month
  interpreted layer, and must NOT gate or duplicate those free surfaces).
- The atlas: a scannable list/grid of domains, each with accuracy, sample size, a
  trajectory arrow (▲▼ + delta), and a tap target → a round in that domain. A
  sub-domain drill-down where the taxonomy supports it. A **Decay radar** section.
- Empty/thin state: "Play across a few domains and your Atlas fills in — it needs a
  few weeks of history to show a trajectory." (honest about needing history — which
  is exactly why it passes the line test.)
- Non-member: a real preview (their single strongest + weakest domain, or a sample) +
  the honest "Club maps everything you know and where it's drifting" panel → paywall,
  never a blank wall.

**NOT in scope here (separate Pillar-2 fast-follows, note them):** Retention curve,
Calibration report (the Stake tally already exists free), Miss autopsy, Year in Review.
Knowledge Atlas + Decay radar is the anchor; keep it focused.

**Gating:** Club-only; reuse the `TIDBITS_CLUB=1` debug override. No mode/engine change
needed beyond the "tap a domain → launch a domain-filtered round" hook (reuse existing
category-filtered launch).

**Apple reference = canonical.** Others mirror (same verb, native idiom).

---

## Feature 6 — Link Wall (design spec + STAGED build)

**One line:** a NYT-Connections-style daily puzzle — 16 fact-tiles, 4 hidden groups
of 4; solving reveals each group's link + a cited why. A **second daily** (Pillar 1;
Daily Tidbits stays FREE and untouched — Link Wall is the Club daily).

**Four-question test (passed 2026-07-22):** deepens understanding (grouping forces
you to find the *connections between* facts, a higher-order skill than recall);
invites participation (you form the hypotheses — the whole game is your judgment);
supports agency (a daily habit that trains pattern-finding you keep); clarity (a plain
16-tile grid, pick 4, submit — the rules are self-evident). Passes cleanly; single-
player so R-MON-4 is fine.

**THE RISK (why this is staged):** good Connections puzzles are normally *hand-crafted*
by editors — the fun is fair **misdirection** (a tile that plausibly fits two groups).
Auto-generating that WELL from a trivia corpus is hard. So this feature is built in TWO
stages, and stage 2 only proceeds if stage 1's quality is real:

### Stage 1 (FIRST — a scoped prototype, Apple Core only): the generator + a quality gate
- Build the generator in Swift `Core/` over the corpus's EXISTING STRUCTURED RELATION
  DATA (the sets that already back matching/oddoneout/enumerate: country→capital/
  currency, element→symbol, book→author, country→continent, continent→countries,
  planets, elements, oceans, …). A puzzle = pick 4 relation-sets that each yield 4
  clean members → 4 groups of 4 → 16 tiles, shuffled. Each group carries a themed
  label + a cited why (from the corpus source fields).
- **Deterministic daily seed** (reuse the `DailyPick` hash-rank so everyone gets the
  SAME Link Wall each day — needed for a shareable, fair Club daily), plus difficulty
  ordering (yellow easiest → purple hardest, the Connections convention) if derivable.
- **The quality gate:** GENERATE ~8 real puzzles and HONESTLY ASSESS them: are the 4
  groups each unambiguously themed? Are there accidental cross-group collisions that
  make it unsolvable or unfair? Is it too trivially easy (zero overlap) to be fun?
  Write the verdict. **If the puzzles are clean + solvable + at least mildly
  interesting → proceed to Stage 2. If they're trivially easy or unfair → STOP and
  flag: this needs either a smarter generator or a curated puzzle set (an owner call).**
  v1 does NOT need editorial-grade misdirection — "clean, fair, themed daily grouping"
  is the bar; be honest about where it lands.

### Stage 2 (ONLY if Stage 1's quality passes): the full feature across 6 platforms
- The play surface: a 16-tile grid, select 4 → submit, N mistakes allowed (4, the
  Connections convention), "one away" feedback, solved groups collapse to a labeled
  row, reveal shows each link + cited why. A daily result (guesses used, shareable
  grid of colored squares — the Wordle/Connections share pattern, huge organic reach).
  Club-gated; a second daily entry (the free Daily is untouched). Same verb, native
  idiom; the generator is portable (mirror the relation-set + seed logic per platform,
  or generate once and publish a daily JSON — decide in Stage 2 based on cost).

**If Stage 1 fails the gate:** record the finding here, flag the curated-vs-generated
decision for the owner, and move on (do NOT ship a weak daily — memory
`quality-over-volume-steer`).

### Stage 1 RESULT (2026-07-22) — gate NOT passed; bounded fix in progress
Built `Core/Store/LinkWall.swift` (BUILD SUCCEEDED, Core-only, dormant/not wired).
Generated 8 real daily puzzles for judging. **Verdict: the MECHANISM is sound** —
deterministic day→theme→block via `DailyPick`, exact-collision rejection, difficulty
ordering (yellow→purple), cited "why"; the **element-symbol theme is flawless every
time**, proving the approach works. **But 4/8 puzzles shipped a mislabeled/wrong tile**,
concentrated in 3 generic themes whose `match.json` pools were built for the Matching
mode (decoys don't need to be clean there, but Link Wall's labeled-group promise
exposes them):
- **`capital`**: mixes modern sovereign capitals with US state capitals (Little Rock),
  UK county towns (Truro), and historical/dynastic seats (Edo, Puhar, Kutaisi) — and a
  disputed-territory sensitivity (Gilgit). ~60%+ of blocks impure.
- **`author`**: labels religious texts / founding documents (Genesis, UDHR) as "novels".
- **`director`**: labels TV series (Top of the Pops) as "films".
- `currency`: one bad entry ("bimetallism" = a policy, not a currency).
- **Repetition**: sports/history themes each have ONE source block → always the same 4
  tiles; two themes already repeated within 8 samples.
- **Near-dup**: the exact-string collision guard missed "Declaration of Independence"
  vs "Declaration of Independence signed" (same referent, two tiles).
**Fix (Stage 1.5, scoped — NOT a rebuild):** an allowlist/filter layer over the
capital/author/director pools (exclude subnational + historical-polity capitals,
non-novel written works, TV series) before they enter `themeTable`; patch the currency
entry; tighten the collision guard to catch substring/near-duplicates; downweight
singleton themes (<3 candidate blocks) in the daily ranking. Re-sample 8, re-judge.
**Only then** decide Stage 2. All fixes live in `LinkWall.swift` — do NOT edit
`match.json` (it serves the Matching mode correctly as-is).

### Stage 1.5 + 1.6 RESULT (2026-07-22) — content gate PASSED
Applied the scoped fixes in `LinkWall.swift` (BUILD SUCCEEDED, still Core-only):
- `capital` + `currency` + `composer`: the impure themes are pooled-and-recombined
  from an allowlist of clean pairs (145 sovereign countries / 43 real classical works)
  into synthetic 4-tile blocks — per-block filtering alone would've killed them (0–1 of
  60 blocks were 4-for-4 clean). `author` + `director`: denylist + `isRealBook`/
  `isRealFilm`. Relabels: "Classical Compositions"→"Composers & Their Works",
  "Classic Novels"→"Books & Their Authors". Collision guard now catches near-dups
  (substring/prefix). Singleton themes downweighted (k=10) so they surface ~1.2 of 4
  slots (was ~3.1). Also fixed a type-checker-timeout expression.
- **A fresh 8-puzzle sample is now 100% content-clean — 0 broken groups across ALL
  themes** (was 4/8 in Stage 1). Every tile is real + correctly attributed.

**Two KNOWN LIMITATIONS (corpus-depth, not code — an OWNER decision, see below):**
1. **Thin clean pools repeat.** World Capitals = 9 synthetic chunks (39 clean pairs);
   Composers = 10 (43 works). Exact repeats surface ~every 1–2 weeks on a daily cadence
   (one already did within 8 samples). The 20 sports/history themes are **hard
   singletons** (1 block each) → identical 4 tiles whenever picked.
2. **The clean pools skew obscure** (capitals like Lobamba; works like *Nabucco*) — fair
   and teachable via the reveal, but not the recognizable-tile *delight* of a
   hand-crafted NYT Connections.

### Stage 2 — STAGED AGAIN (iOS-reference-first, then hold for an OWNER decision)
Unlike Features 1–5 (fanned out to 6 platforms once validated), Link Wall's repetition/
obscurity ceiling is a genuine **curated-vs-generated PRODUCT decision** only the owner
can make. So: build the **iOS play surface first** on the (content-clean) generator so there's a
real, playable, judge-able feature (DONE, commit 21fa143) — then continue the fan-out.

**Decision update (2026-07-22): fan-out RESUMED, not held.** The play surface + generator
are **direction-agnostic** — they work identically whether the puzzle source stays
generated, gets corpus-enriched, or becomes a curated set. So completing Feature 6 to
6-platform parity does NOT pre-empt the owner's choice; only the puzzle CONTENT source is
affected, and it's swappable under the same surface. Fanning out now (web → Android →
Windows → macOS/tvOS). **The curated-vs-generated + repetition/obscurity question is a
CONTENT-ENHANCEMENT decision for the owner, NOT a ship blocker:** (a) ship the
auto-generated daily as-is (accept the ~1–2 week repeat cadence; obscure-but-teachable
tiles actually fit Tidbits' learning thesis), (b) enrich the corpus (add clean
capital/composer/sports pairs — additively, helps Matching too), or (c) commission a
curated puzzle set (the real NYT model). All three reuse the shipped surface + generator.

---

## Deferred (need an owner decision before building)

- **Friend Streaks** (Pillar 4) & **Ranked Seasons** (Pillar 1) — SOCIAL; value depends
  on population, so R-MON-4 says don't fully gate the seat. **Owner call needed: what's
  the free base vs the Club perk?** (e.g. streaks free / streak-insurance + rivalry
  Club; ranked play free / a parallel Club Invitational + defendable titles Club.) Until
  then, unbuildable without risking an R-MON-1/R-MON-4 violation.
- **Research proposals** (see below) — Night Recap / Home Turf / Set Workshop etc. are
  owner-review items; the top-3 (esp. Night Recap for the pub-Live regular) are strong
  candidates to fold in after the anchor set.

---

## Research log (additional incentive ideas)

*(populated by the research lane; owner-facing proposals land here before they
enter the build order.)*

### 2026-07-22 — Additional incentive proposals (research pass)

**Brief:** find *additional* Club-worthy layers — beyond Features 1–8 and the full
§4a/§4c slate — that make daily players and **pub-Live regulars** genuinely *want*
to subscribe. Every idea below is re-derived to fit the anti-passive, learning-first,
$0 ethos; anything colliding with a shipped-free feature or the existing slate was
killed (see §Rejected). None re-propose an existing item.

**Framing note the owner should hold onto:** the monetization thesis (§2) is that a
host night = *40 qualified installs the venue already paid to assemble.* The
pub-Live regular is therefore the **strategically most valuable and currently
weakest-served** Club segment — so four of the seven proposals target them, and all
four obey R-MON-4 by gating *the view from the seat* (interpreting / archiving /
prepping your own history), never the seat. For that segment "interpret the seat"
is the correct Club shape and is **not** the "five analytics screens = Sporcle"
trap, because each is welded to the live *event* the player actually attends, not a
generic stats page.

---

#### Proposal A — **Night Recap** ⭐ *(the flagship pub idea)*

**Pitch:** the morning after a Tidbits Live night, Club turns the room's own answer
data into a personal autopsy — how you did *versus the table*, your standout
category, and the questions you nailed that most of the room missed.

- **Delights:** the Tidbits Live regular.
- **Four-question test:** *Understanding* — you learn where your knowledge beat/lagged
  a real room, not just a score. *Participation* — it's built from *your* night and
  *your* answers, nobody else's. *Agency* — it tells you what to shore up before next
  week; you leave more capable. *Clarity* — plain "you got Q7; 8% of the room did,"
  no opaque model.
- **Line test:** a 5-hr player has been to ~0–1 nights and sees only final standings
  (free) — invisible to them. Legible only after a stack of nights → **Club. Pass.**
- **Population Rule:** the standings *seat* stays free; Club buys the *interpretation*
  of the room you were already in. Clean R-MON-4 pass — it's the live-night twin of
  the already-blessed Daily-Six autopsy.
- **$0 feasibility:** **client-only.** The room already writes `live/{code}/answers/{qid}/{uid}`
  and the join client already reads the roster (social-graph capture proves this). The
  recap is computed on-device from data the client saw during the night; nothing new
  is stored or served.
- **Build cost:** **S–M.** One new results-adjacent surface per consumer platform
  (web/iOS/iPadOS/Android + macOS/Windows read the shared Core aggregation; tvOS 🚫
  lean-back). Core aggregation logic written once (Swift/Kotlin/JS/C#).
- **Builds on:** `live/{code}` answer plane, the shipped per-question answer-distribution
  telemetry (F4), social-graph co-player capture, the "How did you know that?" reflection
  pattern.

#### Proposal B — **Home Turf** ⭐ *(venue almanac + warm-up-for-tonight)*

**Pitch:** a private dossier of each venue you play — your record there, your best/worst
category *at that venue*, recurring rivals — plus a **Warm-Up round** generated before a
scheduled night from that venue's category tendencies crossed with your own weak spots.

- **Delights:** the Tidbits Live regular (and it's a genuine *verb* — you play the warm-up,
  you don't just read a chart).
- **Four-question test:** *Understanding* — you learn a venue's tendencies and your gaps
  against them. *Participation* — you *prep*; you choose to study, the tool doesn't answer
  for you. *Agency* — you walk in ready, more capable, not dependent. *Clarity* — the warm-up
  labels every question ("this venue leans Film & TV; you're -12% there").
- **Line test:** meaningless below a handful of repeat visits to the same venue → **Club. Pass.**
- **Population Rule:** attending and the cross-venue board stay free; Club buys the *prep and
  the interpretation* of your own venue history. Pass.
- **$0 feasibility:** **client-only.** Reuses the Wave-D recurring-series schedule
  (`LiveEvent.weekday`) for the "before tonight" trigger and the shipped Weak-Spot generator
  for the round; venue history aggregates the player's own `standings/{season}/{venueKey}`
  writes + questions seen. No backend.
- **Build cost:** **M.** Almanac view + warm-up entry per consumer platform; the warm-up
  round itself is the Weak-Spot engine re-parameterised by venue-domain weighting (mostly
  Core reuse).
- **Builds on:** Wave-D recurring scheduling, Weak-Spot Arena generator (Feature 1),
  `standings/{venueKey}` writes, Knowledge-Atlas domain math (Feature 4).

#### Proposal C — **Venue Passport** *(the Untappd/Letterboxd move for pub trivia)*

**Pitch:** a stamped, map-anchored archive of every venue and city you've played a Tidbits
Live night at — an identity artifact you carry between nights ("14 venues, 3 cities, a
7-night streak at The Anchor").

- **Delights:** the Tidbits Live regular.
- **Four-question test:** *Understanding* — weak/indirect (breadth-of-play awareness). *Participation*
  — yes, it's *your* record of where you've been. *Agency* — self-expression / identity, the
  Founding-Member-badge and avatar precedent. *Clarity* — one stamp per venue, dead simple.
  (Honest read: this leans on the charter's *identity* allowance more than its *learning*
  spine — it's the weakest of the four on Q1, kept because pub-regular identity is exactly
  what carries between venues and costs $0.)
- **Line test:** a casual with one venue visit sees nothing; the collection only means
  something across many nights → **Club. Pass.**
- **Population Rule:** attendance and the board are free; the *curated archive* of your own
  attendance is Club. Pass.
- **$0 feasibility:** **client-only** (aggregates the player's own `standings/{venueKey}`
  history); an optional cron-published venue-name/city map could enrich stamps but isn't
  required for v1.
- **Build cost:** **S–M.** A collection/passport view per platform; no new engine.
  Inspired by Untappd venue check-ins and the Letterboxd diary — re-derived as *knowledge
  provenance*, not consumption bragging.
- **Builds on:** `standings/{season}/{venueKey}`, Levelable Badges pattern, Club identity.

#### Proposal D — **Table Chemistry** *(scout your own real table)*

**Pitch:** for the people you've actually played live nights with (already captured, free),
Club shows how their public domain profiles *complement* yours — who covers your weak
categories — so you can build a stronger team next week.

- **Delights:** the Tidbits Live regular + the social daily player.
- **Four-question test:** *Understanding* — you learn the *shape* of your own and your friends'
  knowledge, not just a rank. *Participation* — you decide who to team with; it informs, never
  auto-picks. *Agency* — you become a better team-builder. *Clarity* — a plain complementarity
  read ("Sam is +18% History where you're -15%"), from public profiles only.
- **Line test:** needs a real table of repeat co-players → **Club. Pass.**
- **Population Rule:** adding friends and the friends board stay free; the *complementarity
  interpretation* is Club. Pass. (Distinct from the slate's *Knowledge Opposite*, which is
  free *matchmaking* against strangers — this analyses your existing real-world table.)
- **$0 feasibility:** **client-only.** Reads already-public `players/{uid}` domain profiles for
  friends the player already added; pure on-device computation.
- **Build cost:** **S–M.** A section on the friends surface per consumer platform; Core
  complementarity math written once.
- **Builds on:** social-graph friend list (private bucket), public domain profiles, the
  Knowledge-Opposite complementarity metric (reused, inverted from matchmaking to retrospection).

#### Proposal E — **Name That Question** *(a genuinely new gameplay verb, honoring "lead with verbs")*

**Pitch:** reverse trivia — you're shown the *answer* + its cited fact and must produce the
*question*: pick which of four questions this fact answers, or (harder) recall it. A round
that trains how facts *connect* to questions.

- **Delights:** the casual daily player (a fresh mode) and, secondarily, creators (it teaches
  question construction).
- **Four-question test:** *Understanding* — reverse-mapping forces deeper encoding than
  recognition; it's a known retrieval-practice win. *Participation* — you *construct*, you don't
  select from a menu. *Agency* — you get better at seeing what makes a fair question. *Clarity*
  — the reveal shows the canonical question + why the near-misses don't fit.
- **Line test:** a casual would happily play it at hour 1 — **so on its own it fails the line
  test and would have to be free.** It qualifies as Club **only** as a *Club-difficulty / ranked*
  layer over a free base, OR bundled as depth in a paid mode. **Flag for owner:** decide whether
  this ships free (a new verb strengthens the whole app) with a Club *ranked* skin, or is held as
  a Club marquee. Recommend **free base + Club ranked** — consistent with R-MON-4 logic applied to
  modes.
- **Population Rule:** solo, no seat dependency — n/a. Pass.
- **$0 feasibility:** **client-only.** Reuses the corpus's existing explanation/answer text and
  the 4-option MCQ surface; the distractor questions come from sibling corpus rows.
- **Build cost:** **M.** A new mode across all 6 (the mode-plumbing is well-trodden — 20+ shipped
  types); the only new asset is a question-stem inversion done at build time, like `picture.json`.
- **Builds on:** the shared corpus + explanations, the multi-type mode engine, `gen_*` build-time
  overlay pattern.

#### Proposal F — **Trace: Connect the Facts** *(a second new verb; the most on-brand)*

**Pitch:** given two entities ("Marie Curie" → "the Manhattan Project"), build the shortest chain
of *true* relations linking them, drawn from the corpus's Wikidata relation graph — the "web of
related facts" made playable.

- **Delights:** the casual daily player; the curiosity-driven learner the charter is written for.
- **Four-question test:** *Understanding* — you actively discover how knowledge *connects*, the
  deepest form of the "tidbit is the point" thesis. *Participation* — you build the bridge; there's
  no single fed answer. *Agency* — you leave seeing the corpus as a graph, not a list. *Clarity* —
  each hop shows its cited relation.
- **Line test:** genuinely novel and satisfying at any hour — **same caveat as E:** on its own a
  casual would notice it gated, so ship the base free and gate a **Club daily Trace + hardest
  chains + your solve archive.** Recommend **free base + Club depth.**
- **Population Rule:** solo — n/a. Pass.
- **$0 feasibility:** **build-time static JSON** (hand-verifiable chains generated offline, exactly
  like `order.json`/`match.json`), client plays the puzzle. No runtime backend, no LLM. (Live
  arbitrary pathfinding over the sparse graph is *not* required for v1 and is the part to avoid.)
- **Build cost:** **M–L.** New puzzle UI per platform (a chain-builder, more custom than an MCQ) +
  a build-time chain generator. The generator is the real work; the client is a reorder/select
  surface.
- **Builds on:** the ~2,850 Wikidata structured questions + `enrich.json` relations (the moat),
  the build-time overlay pattern, Link Wall's tile idiom (adjacent, not duplicate — Link Wall
  *groups*, Trace *chains*).

#### Proposal G — **Set Workshop** *(the creator's craft coach — serves the thinnest segment)*

**Pitch:** before you publish a quiz you wrote, Club lints it — flags a give-away distractor, a
near-duplicate pair, a lopsided category mix, and predicts each question's real difficulty — so you
learn to *author better*, not just author.

- **Delights:** the creator.
- **Four-question test:** *Understanding* — the creator learns what makes a fair, hard, clean
  question. *Participation* — it critiques *their* set and they revise; it never rewrites for them.
  *Agency* — they become a better setter, tool-independent. *Clarity* — every flag is a plain,
  actionable reason, not a score.
- **Line test:** invisible until you've written real sets — **Club. Pass.** (And distinct from the
  slate's *Creator analytics*, which is *post-hoc play stats*; this is *pre-publish craft*.)
- **Population Rule:** solo authoring — n/a. Pass.
- **$0 feasibility:** **client-only.** Reuses the shipped Create quality gates / `diversify`
  round-robin caps + the `difficulty.json` overlay + answer-telemetry heuristics — all already
  on-device. No LLM at runtime (the "predict difficulty" is the existing pageview-derived model,
  not a generative call).
- **Build cost:** **S–M.** A review panel bolted onto the existing Create flow per platform; the
  lint logic is largely the Create engine's existing checks surfaced to the user.
- **Builds on:** Create diversity caps + quality gates, `difficulty.json`, F4 answer telemetry,
  saved sets. This is the `mobile-first-density` "expose the structure of the domain" move applied
  to authoring.

---

### Recommended top 3 to fold into the build order next

1. **Night Recap (A)** — highest strategic leverage. It converts the *exact* person the
   monetization model is built around (the host-delivered install), it's the cheapest to build
   (client-only over data the room already produced), and it's the pub twin of an already-blessed
   pattern (Daily-Six autopsy). **This is the single best idea for the pub-Live regular.**
2. **Home Turf (B)** — gives the pub regular a *recurring, appointment-shaped* reason to open the
   app between nights (prep for tonight), and it's a *verb*, not analytics. Reuses the Weak-Spot
   engine + Wave-D scheduling, so most of it already exists.
3. **Set Workshop (G)** — serves the creator, the thinnest-served of the three segments, with a
   real learning payoff and near-total reuse of the shipped Create engine. Cheap, on-charter, and
   it rounds out segment coverage (A+B are pub; this is creator).

**Why these three over the two new verbs (E/F):** E and F are the most exciting *gameplay*, but
both fail the line test *as gated features* (a casual would notice) and are best shipped as
**free base modes with a Club ranked/depth layer** — which makes them a mode-roadmap decision, not
a clean Club-exclusive to slot in now. A/B/G are unambiguously Club-legible and $0. If the owner
wants a marquee *new verb* for the Club story, **Trace (F)** is the most on-brand thing in this
whole doc — recommend it as the next *free* verb with a Club depth layer, not as a gated exclusive.

**Pub-segment call-out (the weakest-served today):** A, B, C, D are all pub-Live-regular features,
all $0, all R-MON-4-clean. Shipping even A + B alone would take the pub regular from *"Club has
nothing for me"* to *"Club remembers my nights, preps me for the next one, and tells me how I
really did"* — which is the identity-across-venues story the strategy doc (§2, portable identity)
says is the whole point.

### Rejected / near-misses (recorded so they aren't re-litigated)

- **Spot the Fake / Fibbage-style "which fact is fabricated"** — REJECT. A learning-first brand
  whose proudest metric is *retention* must not risk a plausible fabricated "fact" sticking. The
  very thing we're good at works against us. Fails Q1 in spirit.
- **Ghost of You (race your own past run, live replay)** — near-miss REJECT. "Compete vs. your past
  self" already ships **free** (PARITY §3b); a live-ghost skin is thin and borderline on the line
  test. Fold any polish into the free feature.
- **Flashcard / Anki export of your misses** — REJECT as a tier anchor. Spaced review (`dueReview`)
  is free; export is a thin convenience, not a 50-hr-legible layer.
- **"On This Day" date-themed daily** — near-miss. Competes with the free Daily for
  placement/purpose (the same trap that folded "Daily Six" into the Daily); also overlaps *Annotated
  daily* on the slate. Hold.
- **Trivia Diary (annotated timeline of all play)** — near-miss, merged. Overlaps *Fact notebook*
  (per-fact notes) and *Venue Passport* (attendance). The distinctly-valuable slice (venue/place
  identity) is captured better by Proposal C.

## Log
- **2026-07-22** — doc created; build order set; Feature 1 (Weak-Spot Arena) spec
  written + four-question test passed. Apple reference implementation delegated to a
  sequential Sonnet agent. Next: verify + commit Apple, then mirror web → Android →
  Windows → tvOS/macOS, then Feature 2.
- **2026-07-22** — Android mirror shipped (1.6.48/vc70): `data/WeakSpotArena.kt`
  (Android mirror of the generator) reads `Store.missDetails()` — the existing
  SharedPreferences `missed` JSON map (`{id:{n,t}}`, additive `t`=lastSeen field
  added to the prior `{id:count}` shape, read back-compat) — same
  floor(4)/fill(8)/cap(10) + reason strings, using `DateUtils.getRelativeTimeSpanString`
  for "Missed {relative}". `Mode.WEAK_SPOT` added to the enum, excluded from
  `playableModes`/Quick-Play-remember/Surprise-Me. Home gets its own
  `WeakSpotCard` (member → build+launch; non-member → CLUB chip + real/static
  preview → existing `ClubPaywallScreen`); empty state is a Material `AlertDialog`
  built BEFORE navigating to the game route (round is pre-built, unlike Apple's
  build-inside-the-game-container). Debug override:
  `Entitlement.setDebugForceClub` gated on `BuildConfig.DEBUG`, toggled via an
  Intent extra (`adb shell am start … --ez tidbits_club_debug true`), persisted in
  SharedPreferences. Emulator-verified end to end (member card, non-member
  chip+preview+paywall route, empty-state dialog, a real round built from 10 seeded
  misses, the "Missed 1 minute ago · ×1" reason caption in-play, and the "You closed
  N gaps" result card). **Separate finding, not fixed here (out of scope for this
  feature):** `Corpus.load` (`data/Tidbits.kt`) parses the full 42MB `corpus.json`
  via `Json.parseToJsonElement` and OOMs on a stock (non-`largeHeap`) emulator heap
  (192MB growth limit) — silently swallowed by the caller's `runCatching`, so any
  game mode (not just Weak-Spot) shows the generic "No questions yet" error. Worth a
  follow-up (`android:largeHeap` and/or a streaming parse) since the corpus has
  grown well past what a default heap safely holds.
- **2026-07-22** — macOS + tvOS mirrors shipped. Both ride the shared Apple
  `Core/` generator verbatim (`WeakSpotArena.build`, `GameEngine.startCustom`,
  `EntitlementStore.isClub`) — only per-platform Home entry + gameplay/results
  presentation were new. **macOS** (`HomeView_macOS.swift`): a `weakSpotCard`
  row between Trivia Night and Online Multiplayer (member → launch via the
  existing `onPlay`; non-member → CLUB chip + real preview line →
  `ClubPaywallView_macOS` `.sheet`); `GameContainerView_macOS.swift` builds the
  round in `.task`/`replay()`, shows the "Play a few rounds first" empty state
  under the floor, and passes `weakSpotGapsClosed` into `ResultsView_macOS`'s
  new "You closed N gaps" card; `GameView_macOS.swift` shows the per-question
  reason caption. **tvOS** (`ContentView_tvOS.swift`): a focusable
  `weakSpotHero` (new `TVWeakSpotHeroStyle`, mirroring `TVNightHeroStyle`)
  between the Trivia Night and Online Multiplayer heroes; `TVGameContainer` in
  `GameView_tvOS.swift` mirrors the same build/empty-state/replay logic (a
  ten-foot custom empty state, dark-first), `TVGamePlayView` shows the reason
  caption, `TVResultsView` shows the gaps-closed card. **Found + fixed while
  verifying "never a remembered/random default":** three free Customize/Live
  mode pickers didn't exclude `.weakSpot` from their `GameMode.allCases` lists
  — `CustomizeSheet_macOS` (`MacHomeSheets_macOS.swift`), the Tidbits Live
  round-format picker (`MacLiveBuilder_macOS.swift`), and the tvOS
  `TVCustomizePicker` (`ContentView_tvOS.swift`) — all now filter it out, same
  as iOS's `playableModes`. Both platforms **BUILD SUCCEEDED**
  (`CODE_SIGNING_ALLOWED=NO`, Xcode 27/Xcode-beta); macOS visually verified
  with `TIDBITS_CLUB=1` (the Weak-Spot Arena card renders correctly, Club
  copy hidden for a member) via a direct-binary launch + screenshot; tvOS
  visually verified at the top of Home (Quick Play/Daily/Trivia Night render
  correctly under the same env) but the `weakSpotHero` itself sits below the
  fold and this sandbox has no Simulator.app GUI / remote-input tool to
  scroll headlessly — code-reviewed instead.
- **2026-07-22** — **Windows mirror shipped (1.6.48/89) — Feature 1 DONE on all 6
  platforms.** `Tidbits.Core/Store/WeakSpotArena.cs` is a pure C# port of the
  generator (floor 4 / fill-target 8 / cap 10, same reason strings, `RecordsStore`
  already had `MissedFact.LastSeen` from day one so no back-compat shim was
  needed); reads `RecordsStore.Missed` (already `!Resolved`, most-missed +
  oldest-first) and tops up via the existing `DomainProgress.Summarize` +
  `CorpusDatabase.Questions`. `GameMode.WeakSpot` added to the enum (Id
  `"weakSpot"`, title/blurb/count/perQuestion set explicitly in every switch) —
  never added to `PlayView`'s `Offered` array, so it's automatically excluded
  from the free Customize grid, Surprise-Me, and the Quick-Play-remembered
  default (that array IS Windows's `playableModes` filter). `GameEngine.StartCustom`
  grew an optional `reasons` parameter (`WeakSpotReasons` dict + a `CurrentReason`
  computed property) — every other `StartCustom` call site (QuickMatch, Create,
  Leaderboard rematch, Party) is unaffected. `GameViewModel` grew
  `WeakSpotGapsClosed`/`HasWeakSpotGapsClosed`/headline+subtitle properties,
  computed the same way as the Apple reference: true-miss question IDs are those
  whose reason starts with "Missed" (not "Shoring up"), intersected with
  correctly-answered questions in the finished summary. `EntitlementStore.IsClub`
  now ORs in a new `DebugHooks.ForceClub` (`TIDBITS_CLUB=1`, mirroring the Apple/
  Android debug override) alongside the existing cached/remote read. Home
  (`PlayView`) gets a `WeakSpotPanel` card between Trivia Night and Pass & Play —
  member: "Play" launches straight in; non-member: a CLUB chip + a real preview
  line from `WeakSpotArena.PreviewLine` when a local miss exists, else an honest
  static line, opening the existing `ClubPaywallView` in a `FAContentDialog` (the
  app's established modal idiom) — never a blank wall. Below the 2-question
  playable floor, an `FAContentDialog` shows "Play a few rounds first — your
  misses become your arena." before ever navigating to the game surface (built
  BEFORE launch, same shape as the Android dialog-before-navigate pattern).
  `GameView.axaml` shows the reason caption above the prompt and a "You closed N
  gaps" card right after the scorecard. 300/300 headless tests green (7 new
  `WeakSpotArenaTests` for the generator, 2 `WeakSpotResultsSnapshot` render tests
  for the reason caption + gaps-closed payoff, 2 `HomeSnapshot` member/non-member
  card renders, 1 `EntitlementStoreTests` for the `TIDBITS_CLUB` override) —
  screenshots confirm the card, chip, preview line, in-play reason, and "You
  closed 2 gaps" recap all render correctly. Gated on `windows-latest` CI
  (`windows-repl.yml`) per the standing Windows verification rule.
- **2026-07-22** — **Story Archive (Feature 2) shipped on iOS — the Apple
  reference.** New additive SwiftData model `SeenStory` (`Core/Models/PlayerRecord.swift`):
  qid, prompt, correctAnswer, `story` (a captured copy of `Question.explanation`
  — the free in-moment reveal itself is untouched, R-MON-1), categoryID,
  firstSeen/lastSeen, everCorrect, favorite, plus the same optionsJoined/
  correctIndex/sourceTitle/templateID/difficulty fields `MissedFact` carries so
  a story can rebuild a full `Question` for "Re-ask this." Upserted by qid in
  `RecordsStore.record(_:in:)` for every answered question (right or wrong) —
  the SAME centralized write path every platform already uses, registered in
  the `ModelContainer` schema (`TidbitsTriviaApp.makeModelContainer`).
  `Core/Store/StoryArchive.swift` is the transparent read side: `previewLine`
  (most-recent story, mirrors `WeakSpotArena.previewLine`), `count`,
  `toggleFavorite(qid:)`, and `search(_:text:domain:filter:)` — plain substring
  + predicate filtering, no ranking model. iOS: a Club-marked "Story Archive"
  row on Records (R-REC-1's "see all" pattern) — members open
  `StoryArchiveView` (`.searchable` + filter chips All/Favorites/Missed/Got it
  + domain chips derived from the player's actual seen domains + story cards
  with a favorite star and right/wrong marker); non-members get the existing
  `ClubPaywallView` (already listed Story Archive as a pillar) with a REAL
  preview line pulled from the player's own most recent story, never a blank
  wall. Tapping a card opens the full story + a "Re-ask this" 1-question drill
  that reuses `GameEngine.startCustom` on a throwaway `GameEngine()` instance
  (mirrors `DuelGameContainer`'s exact pattern in `ProfileView.swift`) — it does
  NOT write a new `GameRecord` (a single-question drill isn't a "game," same
  judgment call Duels already made). Debug: reused `DebugHooks.forceClub`
  (`TIDBITS_CLUB=1`) unchanged, plus one new small hook
  (`TIDBITS_STORY_ARCHIVE=1`) to auto-open the archive sheet for screenshot
  verification — same idiom as the existing `TIDBITS_CUSTOMIZE`/
  `TIDBITS_DAILY_ARCHIVE` flags. iOS/macOS/tvOS all **BUILD SUCCEEDED**
  (macOS/tvOS only compile the shared Core + guard the iOS-only surface with
  `#if os(iOS)` — their own Records entry points are a later pass, per the
  build order). iOS runtime-verified on sim: seeded real data via
  `TIDBITS_AUTOPLAY=classic:mixed` + `TIDBITS_AUTOPILOT=1` (a genuine 10-question
  Classic round, confirming the free story reveal still fires mid-game), then
  screenshotted the Story Archive with 4 real story cards (domain tags,
  right/wrong markers, relative timestamps, search bar), the domain-chip row
  correctly limited to domains actually present (History/Geography/Film & TV),
  the Records-dashboard card showing a genuine preview line for a non-member,
  and the non-member tap-through landing on the existing paywall (never blank).
  Not tap-tested (no UI-automation tool in this sandbox): the favorite-star
  toggle and the "Re-ask this" drill — both code-reviewed against
  already-verified sibling patterns (`MissedFact.question` reconstruction,
  `DuelGameContainer`'s engine-drill shape) rather than observed live.
- **2026-07-22** — **Story Archive (Feature 2) shipped on Android (1.6.48→1.6.49,
  vc70→71).** `data/Tidbits.kt`'s `Store` grows a `stories` SharedPreferences JSON
  map (mirror of the `missed` map's shape): `SeenStory` freezes qid, prompt,
  answer, `story` (`Question.explanation` captured at answer-time — the free
  in-moment reveal is untouched, R-MON-1), categoryId, the joined-options +
  correctIndex needed to rebuild a playable `Question` for "Re-ask this," first/
  lastSeen, everCorrect, favorite. `Store.recordSeen(...)` is called from
  `GameState.end()` right next to `recordMisses`/`recordTelemetry` — the SAME
  centralized per-answer write path every platform uses. New
  `data/StoryArchive.kt` is the transparent read side (mirror of iOS's
  `StoryArchive.swift` / web's `StoryArchive` in `store.js`): `list` (most-recent
  first), `domainsSeen` (only domains actually played), `search(text, domain,
  filter)` (plain substring + predicate, no ranking), `count`, `previewLine`.
  Records screen gets a Club-marked `StoryArchiveCard` (blue `ChunkyCard`,
  `AutoStories` icon, mirror of the Weak-Spot `WeakSpotCard` pattern) placed
  right after the "See all N games" row; members open the new `StoryArchiveScreen`
  (`OutlinedTextField` search + `FilterChip`/`FlowRow` status + domain filters +
  a `LazyColumn` of story cards with stable `qid` keys, domain tag, relative
  timestamp, right/wrong icon, favorite star); non-members get a real preview
  card (their own most recent story, or an honest static line) + the "Club keeps
  every story you unlock, searchable forever" panel → the existing
  `ClubPaywallScreen` — never a blank wall. Tapping a card opens a
  `ModalBottomSheet` with the full story, a favorite toggle, and (when the
  frozen options reduce to a playable ≥2-option MCQ) "Re-ask this," which routes
  through the same custom-question `Route.Game(Mode.CLASSIC, ..., custom =
  listOf(q))` launch path Duels/Create already use — no new game-launch
  plumbing. Reused the existing `BuildConfig.DEBUG`-gated
  `Entitlement.setDebugForceClub` override; no new debug hook needed.
  `assembleDebug` **BUILD SUCCESSFUL**. Emulator-verified end to end on a
  temporary `android:largeHeap="true"` manifest flag (reverted before
  finishing, per the known `Corpus.load` OOM logged in the Weak-Spot Arena
  entry above): played a 10-question Classic round (2 correct / 8 missed) to
  seed the archive, confirmed the Records card's member subtitle ("10 stories
  collected — searchable, forever"), opened the archive and confirmed card
  rendering, the Missed filter, a domain filter, both filters composed
  together, the favorite star toggle + the Favorites filter reflecting it, the
  detail sheet, and "Re-ask this" launching a genuine 1-question drill whose
  reveal still shows the free story text (R-MON-1 intact). Also confirmed the
  non-member path: CLUB chip + a real preview line pulled from the player's
  own most recent story, tapping through to the existing `ClubPaywallScreen`
  (which already listed Story Archive as a pillar) rather than a blank wall.
- **2026-07-22** — **Story Archive (Feature 2) shipped on Windows (1.6.48→1.6.49)
  — feature now COMPLETE on all 6 platforms.** `Tidbits.Core/Models/PlayerRecord.cs`
  gains `SeenStory` (mirrors `MissedFact`'s shape/persistence idiom): qid, prompt,
  answer, `Story` (`Question.Explanation` captured at answer-time — the free
  in-moment reveal is untouched, R-MON-1), categoryId, the SOH-joined options +
  correctIndex needed to rebuild a playable `Question` for "Re-ask this,"
  first/lastSeen, everCorrect, favorite. `RecordsStore.Record(...)` upserts one
  per answered question (right or wrong) in the SAME loop that already writes
  misses/telemetry; `ToggleFavorite(qid)` persists the star; `ResetAll()` clears
  it with the rest. New `Tidbits.Core/Store/StoryArchive.cs` is the pure,
  UI-agnostic read side (mirror of iOS/Android/web's `StoryArchive`):
  `PreviewLine`, `Count`, `Search(stories, text, domain, filter)` — plain
  substring + predicate, no ranking model. Records dashboard gets a Club-marked
  "STORY ARCHIVE" card (code-behind-built, mirrors `PlayView`'s Weak-Spot card
  exactly — CLUB chip + real/honest preview for non-members → the existing
  `ClubPaywallView` in an `FAContentDialog`, never a blank wall) placed right
  after "See all N games." New `StoryArchiveUi.cs` (pure static builders —
  chips/results-list/story-card/detail, mirrors `ClubPaywallUi`'s
  headless-testable split) + `StoryArchiveDialog.cs` (the stateful wiring: one
  `FAContentDialog` whose Content swaps between the list and a story's detail,
  deliberately avoiding a nested second dialog — the macOS mirror hit a real
  "one sheet per window" bug doing that — and keeping the search `TextBox` +
  filter/domain chips alive across rebuilds so typing never loses focus/caret).
  Tapping a card opens the detail view (favorite toggle, full story, and — when
  the frozen options reduce to a playable 4-option MCQ — "Re-ask this," which
  launches a 1-question Classic drill as an overlay on `RecordsView`'s new
  `ReaskHost` `ContentControl`, mirroring `LeaderboardView`'s `DuelGameHost`
  rather than a nested dialog). Reused `DebugHooks.ForceClub`/`TIDBITS_CLUB=1`;
  no new debug hook needed. `dotnet test` (Mac head, headless Skia): 319
  passed / 1 skipped (pre-existing LibVLC arch skip) / 0 failed — 17 new tests
  covering the seen-store upsert/OR/reset semantics, search/filter/domain
  predicates, the Records card in both member and non-member states, and the
  archive's empty/no-results/list/chips/detail rendering. PNGs verified
  (`records-story-archive-member.png`, `records-story-archive-non-member.png`,
  `story-archive-empty.png`, `story-archive-list.png`,
  `story-archive-detail.png`) — card copy, CLUB gating, story cards (domain,
  right/wrong dot, favorite star), and the detail/re-ask button all render as
  expected. `windows-latest` CI to be gated post-push.
- **2026-07-22** — **Marathon (Feature 3) shipped on Android (1.6.50/vc72 —
  version NOT bumped this pass, per the owner's cross-platform-alignment note).**
  New `data/Marathon.kt`: `MarathonAnswerRecord`/`MarathonRun`/`MarathonDomainStat`/
  `MarathonScore` data classes + the `Marathon` object (`inProgress`/`startNew`/
  `resumeQuestions`/`record`/`finish`/`history`/`previewLine`), mirroring Apple's
  `Marathon.swift` / web's `Marathon` in `store.js`. The 200 ids are drawn ONCE from
  a fresh UUID seed via the SAME `stableSeed` rank-and-slice `Corpus.daily` already
  uses for the Daily (`marathon:<seed>:<id>`, smallest-rank-first) — a resume always
  continues into the identical, never-regenerated set. `Store` (`data/Tidbits.kt`)
  grows `marathonRun()`/`saveMarathonRun()`/`clearMarathonRun()`/`marathonHistory()`/
  `appendMarathonScore()` (SharedPreferences JSON, mirror of the `missed`/`stories`
  map shape); `resetAllRecords()` clears both new keys. `Mode.MARATHON` added
  (45s/Q, count=200 nominal), excluded from `playableModes`/remembered-selection/
  Surprise-Me in `QuickPlay.kt`. `GameState` grows `marathonOffset` (so
  `progressLabel` shows the true "84 / 200" position, not the resumed session's
  local index) and `rebuildMarathon()` (swaps in a fresh run's questions for
  "Start a new Marathon," mirror of `rebuildWeakSpot`); `end()` skips its entire
  GameRecord/telemetry/misses/seenStory/identity write block for
  `Mode.MARATHON` — deliberate, a session slice of a multi-session run would
  misreport lifetime stats, mirroring the Apple/web reference exactly. `GameScreen`
  (`ui/AppRoot.kt`) resolves-or-creates the run before `game.start()`, persists
  EVERY answer immediately via a `LaunchedEffect(game.answered.size)` (not gated on
  `advance()`/phase change — verified this fires during the REVEAL phase, well
  before "Finished" ever renders), and writes the permanent `MarathonScore` +
  clears the run the instant `currentIndex >= total`. Home gets a teal
  `MarathonCard` (RESUME chip + CLUB chip mirroring `WeakSpotCard`'s pattern; tap
  routes to an AlertDialog Resume/Start-Over when a run exists, else launches
  straight in) and Records gets a `MarathonHistoryCard` (mirrors `StoryArchiveCard`)
  opening a new `MarathonHistoryScreen` (list + `ModalBottomSheet` historical
  detail, reusing a shared `MarathonResultCard` for both the just-finished and
  historical views). Debug: reused `Entitlement.setDebugForceClub`/
  `tidbits_club_debug`; new `Marathon.debugLengthOverride` (`BuildConfig.DEBUG`-
  gated) set from a `marathon_len` Intent extra in `MainActivity`
  (`adb shell am start … --ei marathon_len 6`) shortens a run for testing —
  production always sees 200.
  **`assembleDebug` BUILD SUCCESSFUL.** Emulator-verified end to end on a single
  `emulator-5554`: Home card states (fresh / resume / last-run-%), the debug
  `marathon_len` override, per-answer persistence confirmed via
  `adb shell run-as … cat shared_prefs/tidbits.xml` showing `currentIndex`/results
  updated BEFORE the reveal's "Next" was ever tapped, a REAL `am force-stop`
  mid-run + cold relaunch resuming into the exact SAME stored id list at the
  correct offset, full completion → inline scorecard (score, correct/total,
  duration, "Your first Marathon" / "+N% vs last run" comparison, per-domain
  accuracy bars using `categoryIcon` per R-ICON-1) → `marathonScores` written +
  `marathonRun` cleared → confirmed via SharedPreferences that NO `records` entry
  was written for the Marathon mode, and Marathon History (list + detail sheet,
  historical view correctly hides Play-Again/See-History) both from the post-game
  link and from Records.
  **Caught and fixed a real bug during this verification pass** (not a hypothetical):
  the post-finish scorecard's original "See Marathon history" wiring pushed
  `Route.MarathonHistory` onto the shared `backStack` while `Route.Game` was still
  logically current underneath. Because this app's router composes only the
  single current route at a time, that push tore down `GameScreen`'s `remember`
  state (the finished `MarathonScore`, the now-cleared `marathonRun`); popping
  back re-entered the Marathon branch fresh, found no run in Store (already
  cleared by `finish()`), and silently started a brand-new 200-question run —
  reproduced live on-device (screenshotted at "1 / 200" after backing out of a
  finished run's history link). Fixed by making "See Marathon history" a LOCAL
  overlay boolean inside `GameScreen` (rendering `MarathonHistoryScreen` in place)
  instead of a route push, so the scorecard's composition — and its state — is
  never torn down. Re-verified the exact repro sequence afterward: See Marathon
  history → Back now returns to the identical scorecard, confirmed via
  SharedPreferences that `marathonRun` stays absent and `marathonScores` still
  holds exactly one entry. The Records-initiated and Home-initiated navigations to
  `Route.MarathonHistory` (no live Game route underneath) do not have this failure
  mode and were left as ordinary route pushes.
- **2026-07-22** — **Marathon (Feature 3) shipped on Windows — feature now
  COMPLETE on all 6 platforms.** Version NOT bumped this pass (owner's
  cross-platform-alignment note). New `Tidbits.Core/Models/MarathonModels.cs`:
  `MarathonAnswerRecord`/`MarathonRun` (seed, ordered question-id list,
  `CurrentIndex`, `Results`, started/lastPlayed)/`MarathonDomainStat`/
  `MarathonScore`, held directly as nested types in `RecordsData` (a single
  nullable `MarathonRun?` slot + a `List<MarathonScore>` history) — no
  SOH-joined-string workaround needed, unlike `SeenStory`'s options string,
  since System.Text.Json serializes nested lists natively. New
  `Tidbits.Core/Store/Marathon.cs` (pure, mirrors Apple's `Marathon.swift` /
  Android's `Marathon.kt`): `StartNew`/`ResumeIds`/`Record`/`Finish`/
  `InProgress`/`History`/`PreviewLine`, plus `RunLength` reading
  `TIDBITS_MARATHON_LEN` (production always 200; this only ever narrows it).
  The 200 ids are drawn ONCE via the SAME `StableSeed`/`Utf8Ordinal`
  rank-and-slice `DailyPick` uses for the Daily (`marathon:<seed>:<id>`,
  smallest-rank-first) — a resume rebuilds the identical, never-regenerated
  set. `RecordsStore` grows `SaveMarathonRun`/`FinishMarathon`
  (`ResetAll` clears both). `GameMode.Marathon` added (45s/Q — generous,
  never a tight clock — `QuestionCount => Marathon.RunLength`), excluded from
  `PlayView`'s `Offered` array (never a free Customize/Surprise-Me/remembered
  pick, same exclusion `WeakSpot` needed). `GameEngine.StartCustom` grows a
  `marathonOffset` parameter (mirrors the existing `reasons` dictionary
  parameter's pattern) feeding a new `MarathonOffset` + `MarathonProgressLabel`
  ("84 / 200", clamped so it never overflows to e.g. "5 / 4" once the round's
  last `Advance()` has run) — the HUD's true cross-session position, rendered
  in `GameView`'s header. `GameViewModel` grows a `marathonRun` constructor
  parameter: `OnEngineChanged` persists every new `Engine.Answered` entry to
  the run immediately (a crash/quit never loses progress) and, the instant
  `CurrentIndex >= Total`, writes the permanent `MarathonScore` via
  `Marathon.Finish` and DELIBERATELY SKIPS the generic
  `_records.Record(Engine.Summary)` path — Marathon writes NO GameRecord /
  miss / seen-story, since a partial-session slice would misreport lifetime
  stats (verified: `records.Games`/`Missed`/`Seen` all stay empty after a full
  run in the new headless test). `GameView.axaml`'s Finished panel now branches
  on a new `IsMarathonRun` flag: the generic session-scoped recap
  (`!IsMarathonRun`) is unchanged; Marathon's own permanent scorecard
  (`IsMarathonRun`) renders via a NEW static builder, `MarathonUi.cs`
  (`BuildScorecard`/`BuildHistoryDetail`/`BuildHistoryList`, mirrors
  `StoryArchiveUi`'s headless-testable split) — score, "+N% vs your last run"
  (or "Your first Marathon"), a 3-stat row, and per-domain `ProgressBar`
  accuracy bars — so the just-finished recap and a past run's read-only detail
  (`MarathonHistoryDialog.cs`, list↔detail swap in one `FAContentDialog`,
  mirrors `StoryArchiveDialog`) share exactly one implementation. `PlayView`
  gets a teal-accented Club-marked "MARATHON" card (mirrors the Weak-Spot
  card's builder pattern) showing a RESUME chip + "Question N of Total — tap to
  resume" when a run is in progress, a Resume/Start-Over `FAContentDialog`
  choice, and — non-members — a real "Geography 91% · History 64%" preview
  pitch (Marathon is Club-only end to end, so unlike Weak-Spot/Story Archive
  there's no free-tier sample to draw from; the pitch is an honest static
  illustration instead, matching the Apple reference). `RecordsView` gets its
  own "MARATHON HISTORY" card (R-REC-1) alongside the Story Archive card,
  independent of the in-scorecard "See Marathon history" link. Reused
  `EntitlementStore.IsClub`/`TIDBITS_CLUB=1`; `Marathon.RunLength`'s
  `TIDBITS_MARATHON_LEN` env var is the debug shorten (mirrors Android's
  `marathon_len` Intent extra / Apple's env var of the same name) — a run can
  be played to completion in a test in a handful of questions; production
  code paths never set it, so real runs always see 200.
  **`dotnet test` (Mac head, headless Skia): 335 passed / 1 skipped
  (pre-existing LibVLC arch skip) / 0 failed, 336 total (+17)** — covering
  `RunLength`/env-shorten, seed-determinism (re-deriving the same rank-and-slice
  independently reproduces the exact id order), `StartNew` overwriting a stale
  run in its single slot, `ResumeIds`'s clamp, `Record`'s persist-immediately
  guarantee (a FRESH `RecordsStore` over the same file sees the update),
  `Finish`'s score/domain-breakdown math + the no-GameRecord/miss/seen-story
  assertion, `History` ordering, `PreviewLine`, the Home card in fresh/resume/
  non-member states, the HUD offset label, and the Records card + history
  list/detail rendering. PNGs verified (`home-marathon-member-fresh.png`,
  `home-marathon-member-resume.png` — RESUME chip + "Question 6 of 10", 
  `home-marathon-non-member.png`, `marathon-hud-resume.png` — HUD reads
  "9 / 10" mid-run, `marathon-scorecard.png` — MARATHON COMPLETE / score /
  comparison / domain bars / History-count stat, `records-marathon-history-
  member.png`, `records-marathon-history-non-member.png`,
  `marathon-history-empty.png`, `marathon-history-list.png`,
  `marathon-history-detail.png` — "+25% vs your last run"). Caught and fixed a
  real bug during this pass: the scorecard's stats-row "Marathons" count and
  "vs last run" comparison initially read `Services.GameData.Shared.Value.
  Records` (the global app singleton) instead of the `RecordsStore` the
  `GameViewModel` was actually constructed with — harmless in production
  (same singleton) but wrong the instant a caller (a test, or any future
  multi-profile path) injects a different store; a headless test caught it
  immediately (`Marathons: 0` instead of `1`). Fixed by exposing
  `GameViewModel.Records` and reading that in `GameView`'s
  `RebuildMarathonResult` instead. `windows-latest` CI to be gated post-push.
- **2026-07-22** — **Knowledge Atlas (Feature 4) shipped on Windows — feature now
  COMPLETE on all 6 platforms.** Version NOT bumped (owner's cross-platform-
  alignment note; still 1.6.51). PURE DERIVATION: new `Tidbits.Core/Store/
  KnowledgeAtlas.cs` computes everything from the SAME `GameRecord.CategoryId/
  Correct/Total/Date` rows the free Topic Levels/Pie already read
  (`ProgressMath.DomainIds`) — no new persistence, no schema change, mirrors
  Apple's `KnowledgeAtlas.swift` / Android's `KnowledgeAtlas.kt` constant-for-
  constant (`SampleFloor` 8, `StrongThreshold` 0.70, `DecayDelta` 0.12).
  `Domains`/`DecayRadar`/`PreviewLine`, month-bucketed off each GAME's `Date`
  (per-answer timestamps don't exist, same granularity as the other ports).
  The anti-Sporcle guard: every domain row in `KnowledgeAtlasUi.BuildDomainRow`
  is a full-row `Button` that launches a real Classic round in that domain
  (`engine.Start(GameMode.Classic, category)`, the same launch path Quick Play
  uses) via a new `AtlasHost` overlay on the Records dashboard (mirrors
  `ReaskHost`'s "no nested dialog" pattern) — interprets AND acts, never a
  passive stats wall. Decay radar rows carry their own "Shore it up" button.
  `KnowledgeAtlasDialog` (FAContentDialog) + a Club-marked Records card
  (CLUB chip + real strongest/weakest preview → `ClubPaywallView` for
  non-members, never a blank wall) — same code-behind idiom as the Story
  Archive/Marathon History cards (reads `GameData.Shared.Value`, not the VM).
  Reused `TIDBITS_CLUB`/`DebugHooks.ForceClub`.

  `dotnet test` (Mac head, headless Skia): 357 passed / 1 skipped (pre-existing
  LibVLC arch skip) / 0 failed, 358 total (+22) on a clean run — covering
  trailing-12-month cutoff, sample-floor withholding (both the per-domain
  quarter read and the decay radar's two windows), trajectory-delta sign +
  the decay threshold, domain sort order, decay-radar sort-by-steepest-drop,
  and the honest single-/dual-domain preview-line phrasing, plus headless
  renders of the Records card (member/non-member) and `KnowledgeAtlasUi`
  (empty state, one domain row with its trajectory badge, one decay row +
  "Shore it up", and the full atlas with both sections together). PNGs
  verified: `records-knowledge-atlas-member.png`, `records-knowledge-atlas-
  non-member.png`, `knowledge-atlas-empty.png`, `knowledge-atlas-domain-
  row.png`, `knowledge-atlas-decay-row.png`, `knowledge-atlas-full.png`.
  **Known pre-existing flake, NOT introduced by this change**: re-running the
  full suite intermittently (~1 in 3 runs) fails 5 `EntitlementStoreTests`
  cases with `TIDBITS_CLUB` reading `true` instead of `false` — a process-
  wide env-var race between this suite's (and `StoryArchiveSnapshot`'s/
  `MarathonHistorySnapshot`'s/`HomeSnapshot`'s) `Environment.SetEnvironmentVariable`
  toggling inside `[AvaloniaFact]` tests running concurrently with
  `EntitlementStoreTests`' plain `[Fact]`s. Confirmed pre-existing (reproduces
  with a clean re-run, same 5 tests, same assertion) and out of this feature's
  scope to fix (would mean adding `[Collection]` serialization to
  `EntitlementStoreTests.cs` and every sibling Club-feature test file) —
  flagged here rather than silently worked around. `windows-latest` CI to be
  gated post-push.
- **2026-07-22** — **Expedition (Feature 5) shipped on web (mirror of the Apple
  reference, dd9e3ff).** `js/store.js` gets `Expeditions`: the SAME 3
  hand-defined 7-stage campaigns as Apple (The 20th Century/history, Around
  the World/geography, The Scientific Record/science — each stage a
  category+difficulty-band pair, `questionCount:10`/`passBar:6` throughout,
  byte-aligned to `ExpeditionModels.swift`), `named`/`stage`/`available`/
  `progress` reads, `startStage(expeditionOrId, stageIndex, pull)` (a fresh
  difficulty-banded pull each attempt via a caller-supplied `pull` — same
  framework-free-of-Corpus pattern as `WeakSpotArena.build`/`Marathon.startNew`
  — relaxing to the whole category pool if the band comes up thin), and
  `recordStageResult` (pass advances `currentStageIndex`; the LAST stage
  passing writes a certificate to `tidbits.expeditionCertificates` and deletes
  the progress row). Persistence mirrors Marathon's shape but as a MAP, not a
  singleton (several campaigns may be in progress at once):
  `tidbits.expeditionProgress` = `{expeditionId: {currentStageIndex,
  stageResults:[{stage,pass,score,total}], startedAt, lastPlayedAt}}`;
  `tidbits.expeditionCertificates` = `[{expeditionId, domain, title,
  completedAt, totalScore, stagesCompleted}]` (both keys added to
  `Store.resetAll`). A stage plays as a normal `'classic'` round via the
  EXISTING launch path (`startExpeditionStage` → `startGame('classic',
  catById(stage.categoryId), {custom, expeditionId, expeditionStageIndex})`)
  — `Game._persist()` still writes its GameRecord (a stage IS a real round,
  feeding Records/spaced-review/Story Archive/Knowledge Atlas honestly), and
  `Game._end()` additionally calls `Expeditions.recordStageResult`, landing in
  `game._expeditionOutcome` for a NEW `renderExpeditionStageResult()` screen
  (pass → "Continue"/next-stage-unlocked or, on the final stage, a
  certificate card + "Done"; fail → "Try Again" relaunches the SAME stage with
  a fresh pull, never advances). A pink `EXPEDITIONS` Home card (`--color-pink:
  #FF5DA2`, matching the Apple pink) always opens `#/expeditions` — UNLIKE
  Weak-Spot/Marathon's card, this is never gated at the tap, because (per the
  design spec) the hub list AND an expedition's map are curated CONTENT, not
  player data, so both are a REAL preview reachable by everyone; only tapping
  Play on the current stage is Club-gated (`bindExpeditionMap` routes
  non-members to `#/club`). `#/expeditions` (hub: campaign list with
  progress-aware subtitles, domain-colored cards, + a Completed certificates
  shelf) and `#/expeditions/<id>` (map: locked/current/done stage markers,
  Play on the current stage) are both canonical, shareable URLs (mirrors
  `#/live/<code>`'s path-segment convention). `?expedition=<id>` is a new
  open convenience (boot-time redirect to the map, mirrors Apple's
  `TIDBITS_EXPEDITION_MAP` verification hook). Reused `?club=1`/
  `tidbitsClubDebug` unchanged; no new debug hook needed. No version bump
  (1.6.51 unchanged per instruction).

  node --check clean on both files. Headless-verified via the claude-in-chrome
  MCP browser (a local `python3 -m http.server` + real page loads/reloads +
  `javascript_tool` DOM/localStorage inspection — no force-pass hook was
  added; every pass/fail below is a GENUINE scored round). With `?club=1`:
  opened `#/expeditions` (3 domain-colored campaign cards, correct
  progress-aware subtitles) and a map (`#/expeditions/twentieth-century` —
  stage 1 current, stages 2–7 locked with 🔒). Drove real stage plays by
  cross-referencing each rendered question's prompt against a freshly-fetched
  `assets/corpus.json` and clicking the matching option: answered stage 1
  fully CORRECT → real 10/10 → "STAGE 1 PASSED" → `currentStageIndex`
  advanced 0→1 in `localStorage.tidbits.expeditionProgress`, and a genuine
  `location.reload()` (not just a hash change) re-rendered the map with
  stage 1 ✓/stage 2 current, confirming persistence survives a real reload.
  Also confirmed a normal `GameRecord` was written to `tidbits.records`
  (`mode:"classic"`, `categoryID:"history"`, 10 real per-question answers) —
  "a stage IS a real round." Then answered stage 2 fully WRONG → real 0/10 →
  "NOT QUITE — Needed 6 of 10 to advance — you got 0" → `currentStageIndex`
  stayed at 1 (did NOT advance) → "Try Again" relaunched stage 2 with a fresh
  question set (confirmed via the in-play "The 20th Century · Stage 2"
  caption + a different prompt). Confirmed the non-member path: the SAME
  URL without `?club=1` still rendered the full map (real preview, stage
  markers intact, no blank wall) plus the "Join Tidbits Club…" note, and
  tapping Play routed to `#/club` without starting a round; the Home card
  also always opened `#/expeditions` (never straight to the paywall) even
  as a non-member, with a CLUB chip. Verified the FULL completion path for
  real: seeded `tidbits.expeditionProgress` to stage 6 (the last stage) via
  localStorage, then played and passed stage 7 with all-correct real
  answers (7/10, still ≥ the 6 pass bar) — the result screen showed
  "EXPEDITION COMPLETE" + a certificate card ("The 20th Century — 7 stages ·
  55 correct total"), and `localStorage` confirmed
  `tidbits.expeditionCertificates` gained the entry
  (`{expeditionId:"twentieth-century", domain:"history",
  stagesCompleted:7, totalScore:55, ...}`) while
  `tidbits.expeditionProgress` lost the `twentieth-century` key in the same
  write. Confirmed the post-completion hub/map both read this correctly
  ("Completed — tap to play again", a "Completed" shelf with the
  certificate, stage 1 offered fresh for a replay). No console errors on a
  clean load. Screenshotted at 390×844 (mobile-first): the map, hub, and
  Home card all render without horizontal overflow.
