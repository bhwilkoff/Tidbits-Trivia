# Game Modes, Interaction Methods & Bar-Trivia Formats — Research & Design

> **Status:** Research + proposal. NOT yet binding UI. A mode graduates to
> implementation only after it passes the **learning-orientation four-question
> test** (recorded in Part D) and earns a `DECISIONS.md` entry. This doc is the
> source material the build order draws from.
>
> **Companions:** `ROADMAP.md` (already names phone-as-buzzer as gap #4 and
> async-first multiplayer), `DECISIONS.md` (022 anti-patterns · 023 multiplayer
> build order · 024 Wikidata moat · 025 corpus-is-4-option-MCQ · 021 tvOS
> lean-back · 013 universal Apple target · 017 tvOS persistence),
> `QUESTION-QUALITY.md`, `PARITY.md`.

## Why this doc exists

The user asked us to deeply research (1) phone-as-buzzer / second-screen
interaction between a phone and the Apple TV, (2) the full space of quiz
question types and interaction methods, and (3) **every major type of "bar
trivia" game**, so Tidbits can build its own learning-first "home version" of
each — playable **solo, same-room with friends, or virtually**.

The structure:

- **Part A** — Bar-trivia & digital-quiz format catalog (the formats themselves)
- **Part B** — Quiz question & interaction-type catalog (the mechanics)
- **Part C** — Phone-as-buzzer / second-screen architecture research (the plumbing)
- **Part D** — **Tidbits' home versions** — proposed modes, each run through the
  learning-orientation four-question test, mapped to corpus needs and play context
- **Part E** — The single highest-leverage corpus enrichment (unlocks 7 formats)
- **Part F** — Architecture recommendation (phased: Apple-native local → web-room)
- **Part G** — Phased build order, PARITY implications, decisions to log

**Everything is filtered through the mission** (`DECISIONS.md` 022): human
**learning**, no dark patterns — no energy/lives, no cash/gambling, no
pay-to-restore, no X/Twitter; **async survives better than real-time-only**
(023); today's corpus is **4-option MCQ from Wikipedia/Wikidata** (025), and a
format stays 4-option-only *unless it earns custom UI + data*.

---

# Part A — Bar Trivia & Digital Quiz Formats

*Foundation research. Covers (A) live bar/pub trivia formats and their canonical
round archetypes, and (B) the digital/home games they inspired — with an
**Innovation Hook** per format mapped to a learning-first, async-preferred app on
a 4-option Wikipedia corpus.*

## A1. The Classic UK / Irish Pub Quiz

**Origin.** A British institution; the modern format was popularized in 1976 by
Sharon Burns and Tom Porter, built to draw customers into pubs on slow weeknights
[Source: Wikipedia/en.wikipedia.org/wiki/Pub_quiz; Source: Orange Jelly].

**Structure.** The "Goldilocks" quiz: **5–6 rounds of 8–10 questions**, ~90–120
min, ~5–10 min/round — typically four read-aloud rounds plus a picture/handout
round and a music round. The quizmaster reads each question **twice** with a
~30-second warning before closing a round [Source: Orange Jelly; Source: Craufurd
Arms; Source: PsyCat Games].

**The marking swap (defining ritual).** At round's end, teams **swap sheets with
a neighbouring table** and mark each other's papers as the host calls answers —
explicitly "to avoid accusations of cheating." Standard scoring is **1 point per
correct answer** [Source: Orange Jelly; Source: Wikipedia; Source: The UK Rules].

**Half-time & the picture round.** A mid-point break (commercial: back to the bar;
social: reset the room) anchored by the **picture round** — a printed handout of
photos to identify (faces, logos, landmarks, album covers, cropped images), often
distributed at the start and worked on throughout [Source: Instant Quizzes; Source:
Bubble Tree Quizzes].

**The "joker" doubler.** Each team may play a **joker** once per night, declared
before a round, **doubling their score for that round** — a strategy layer about
which round you back yourself on [Source: JustPrintables; Source: Prospect Hospice].

**Teams/prizes.** Team size typically capped at **six**; prizes are a small cash
pot, a bar tab, or vouchers, plus a novelty **"booby prize"** for last; a **rolling
jackpot** accumulates week to week until won [Source: Wikipedia; Source: Orange
Jelly]. Ireland's "table quiz" is usually a **charity fundraiser**, **teams of
four** [Source: The UK Rules; Source: Quiz Ireland].

> **Innovation Hook.** The load-bearing idea is the **round as a unit of pacing
> and theme** — a session should be chaptered into a few themed rounds with an
> arc, not an undifferentiated MCQ stream. The **marking swap** is a peer-learning
> ritual worth an async echo (after answering, show what a friend or the crowd
> answered, so you learn from others' reasoning). The **joker doubler** is a clean,
> honest confidence mechanic (only ever *adds* points). The **rolling jackpot**
> clashes with the no-gambling mission — replace its "keep coming back" job with a
> durable streak of *learning*, never cash.

## A2. US Bar Trivia Leagues

*Corporate landscape:* **Sporcle, Inc.** owns **Sporcle Live** and **Stump!
Trivia** (consolidated as "Sporcle Events," 2021). **Trivia Mafia** and **Last
Call Trivia** are independent. **King Trivia ↔ Pour House** share infrastructure
in CA but **no official merger was announced** — treat as inference [Source:
Wikipedia/Sporcle; Source: TriviaNearMe; Source: King Trivia].

**Geeks Who Drink** — the largest US live operator (~1,100 venues, ~3M
players/yr). **8 rounds × 8 questions**, ~2 hrs; signature **music round (R2)** +
**all-audio movie/TV round (R7)**; the **"Joker"** doubles one round of your choice
(adds only, no Jeopardy-style final). Team cap **6** [Source: GWD FAQ; Source: The QG].

**Sporcle Live** — **two one-hour games back-to-back**; scoring assigns a value
**1–10 to each answer, each usable once** (max 55); **all-or-nothing final** (wager
0–20, *wrong subtracts*) [Source: Sporcle Blog].

**Stump! Trivia** — four "quarters" of 4 wagered questions; **per-question
confidence** (1/3/5/7 then 2/4/6/8, each once); **"Call Your Shot" final** (wager up
to 15); a **descending-clue halftime** (10 down to 2) [Source: Sporcle Blog].

**Trivia Mafia** — old-school **pen-and-paper**, 2 halves × 4 rounds × 5 Qs; a
**Mega Round** confidence layer (assign 5/4/3/2/1); strict no-phones ("Use your
noodle. Not your Google.") [Source: Trivia Mafia Host Handbook].

**King Trivia** — **7 rounds** + a special non-trivia round; **"Double or
Nothing"** doubles a round's points only if *every* question in it is correct
[Source: kingtrivia.com].

**Pour House** — 4 rounds + halftime + Final; **assign-your-own-points** (1/3/5/7/9,
each once, wrong = 0 — you can't lose points); signature **6-4-2 progressive-clue
ladder** (answer from clue 1 = 6 pts, clue 2 = 4, clue 3 = 2); a variable self-set
Final ("Perfect 21" = a flawless night) [Source: Pour House Rules-FAQ].

**Last Call** — 6 rounds × 3 + bonus/half/final; **self-directed wagering**
(distribute 1/3/6 then 2/5/7; wrong loses nothing); a **5-part all-or-nothing
Final** (any miss loses all); a hidden Theme Round worth +2 [Source: Last Call Trivia].

| Company | Structure | Scoring | Final wager | Signature |
|---|---|---|---|---|
| Geeks Who Drink | 8 × 8 | 8/round (music+R8 doubled) | **No** — "Joker" doubles a round (adds only) | Audio identity (R2+R7) |
| Sporcle Live | 2× one-hour games | Assign 1–10 once (55 max) | 0–20, wrong subtracts | Two full games/night |
| Stump! Trivia | 4 quarters × 4 | 1/3/5/7, 2/4/6/8 | "Call Your Shot" ≤15 | Descending-clue halftime |
| Trivia Mafia | 2 halves × 4×5 | Mega Round 5/4/3/2/1 | none | Mega + no-phones |
| King Trivia | 7 rounds + special | Points/correct | n/a | Round Double-or-Nothing |
| Pour House | 4 rounds + half + Final | Assign 1/3/5/7/9 once | Variable self-set (can bet 0) | 6-4-2 clue ladder |
| Last Call | 6 × 3 + bonus/half/final | 1/3/6, 2/5/7 | 5-part all-or-nothing | Music-as-timer; hidden Theme |

**The canonical American night:** 6–8 rounds (or 6 short ~3-Q mini-rounds), ~2
hours, a **music round and picture round as fixtures**, a **halftime**, and a
**final wager** — either all-or-nothing or assign-your-points.

> **Innovation Hook.** The leagues' best invention is the
> **confidence-allocation scoring layer** ("assign 1/3/5/7/9 once each, you can't
> lose points"). This is a **metacognition/calibration exercise in a game
> costume**, and it maps perfectly onto a 4-option MCQ corpus with zero gambling.
> The **6-4-2 progressive-clue ladder** is a superb built-in **hint scaffold**.
> **Avoid** the strict all-or-nothing finals (Sporcle's "wrong subtracts," Last
> Call's "any miss loses all") — loss-aversion under a learning mission is a dark
> pattern; prefer adds-only (GWD's Joker, Pour House's "can bet 0").

## A3. Canonical Round Archetypes

| Round | Mechanic | Why it's fun / social dynamic |
|---|---|---|
| General knowledge | Mixed-topic Q&A read aloud | The democratic core — everyone contributes one fact |
| Multiple choice | 3–4 lettered options | Lowers the floor; sparks "I'm between B and C" debate |
| Picture / visual | Handout: logos, faces, landmarks | Quiet heads-down collaboration; the interval anchor |
| Music / name-that-tune | Song intros, finish-the-lyric | Loudest, most joyful round |
| Audio (non-music) | Sound effects, movie quotes, themes | Sensory variety; big "aha" reactions |
| Wipeout / all-or-nothing | One wrong = zero for the round; blanks not penalized | Pure nerve — "do we risk the 6th answer?" |
| Lightning / speed | ~20 Qs vs a 3–4 min clock | Adrenaline + division of labour |
| Lists / enumeration | "Name as many X" | Tests breadth not depth |
| True / false | 20 quick statements | Fast; 50/50 keeps weak teams alive |
| Connections / link | Answers share a hidden link, clues revealed one at a time | The cerebral highlight; rewards calling it early |
| Themed | Whole round on one topic | The table's specialist shines |
| Higher-or-lower / closest-wins | Numeric estimate; nearest wins | Educated guessing; the canonical tie-breaker |
| Final wager | Reveal category, bet points | The climactic gut-check; trailing teams can leapfrog |

**Details worth keeping:** *Wipeout's* strategic core is **knowing when to stop**
(no penalty for a blank). *Connections/link* uses a **declining-points ladder**.
*Closest-wins* works precisely because "it's unlikely anyone knows the exact
number." *Final-wager* practice: bet the **minimum or maximum, rarely between**
[Source: QuizVault; Source: Towards Data Science].

> **Innovation Hooks (per type, for a 4-option Wikipedia corpus):** General
> knowledge/MCQ — the baseline "round." Picture — Wikipedia is image-rich; an
> "identify this from Commons" round is directly buildable. Music/audio — hardest
> to source (licensing); a *future* mode. **Wipeout — convert the *thrill* to
> "streak the round" (bonus for a clean sweep, no penalty for stopping)** to keep
> the tension without loss-aversion. Lightning — opt-in, never the only path.
> Lists — maps to Sporcle "sweep the set." Connections — the declining-clue ladder
> *is* a hint scaffold (best non-MCQ mode). Closest-wins — clean numeric
> calibration from infobox numbers. Final wager — keep as **adds-only / can-bet-zero**.

## A4. Digital / Home Games (mechanics + what worked or failed)

**Jackbox (Fibbage, Trivia Murder Party, YDKJ, Quiplash).** Host on one shared
screen shows a **four-letter room code**; players join at **jackbox.tv** in a
browser — no install, no account. The **TV is the shared stage; the phone is the
private input** (critical for bluffing). **Fibbage** is the standout: a true-but-
unbelievable fact has a word blanked; you **type a fake answer to fool others**;
all lies + the truth are shown; you score for spotting the truth *and* for fooling
others. **Trivia Murder Party** keeps eliminated players as **ghosts who can still
win** (no true elimination) [Source: jackboxgames.com; Source: digitalcitizen.life].

> **Hook.** **Room-code, no-install join is the gold standard for same-room play**
> — and it's web-native (our canonical platform). **Borrow Fibbage's "write the
> decoy" as an active-recall mode** (invent a plausible wrong answer before the
> options appear — human-written decoys could even improve the corpus). **Borrow
> TMP's no-elimination comeback** (a wrong answer branches into a teaching moment,
> never removal).

**Kahoot!** Host shows a **PIN**; players join from a phone browser. **Speed-based
scoring** (faster correct = more points) turns a quiz into a race; lobby music +
countdown jingle + a **podium** manufacture a shared "heartbeat." 8M+ teachers,
~50% of US K-12 [Source: grokipedia/Kahoot; Source: k12dive].

> **Hook.** **Speed scoring is double-edged for a learning mission** (it rewards
> fast guessing). Make speed **optional and visible**: default "reflection mode"
> (no timer, points for correctness + reading the *why*) beside an opt-in rapid
> mode. Borrow the live leaderboard/podium + synchronized music for same-room, but
> ground points in *learning behaviors*, not pure speed.

**HQ Trivia (the cautionary tale).** A **live synchronous** mobile game show at
scheduled times; 12 MCQs, ~10s each, **one wrong = out**, winners **split a cash
pool**. Peaked at **2.3M concurrent** (Feb 2018), then died: the **prize-split
death spiral** (a final prize of **$5 split among 523 players**), unsustainable
economics, **appointment fatigue**, and elimination that shrank engagement. Shut
down Feb 2020 [Source: techcrunch; Source: money.com; Source: cbr.com].

> **Hook (mostly "what NOT to do").** **Cash prizes are the poison pill** —
> validates the no-cash mission. **Don't make synchronicity mandatory** — favor
> async-first with optional "live rounds." **One-wrong-and-out is a dark pattern**
> — do the inverse (a wrong answer = a teaching moment). The salvageable idea is
> the **shared, dramatic daily moment** — capture it as an **async daily round**
> everyone attempts on their own schedule.

**Trivia Crack.** **Async turn-based**; a **category wheel**; three-in-a-row earns
a **Crown** to win a character; collect all six. Aggressive F2P **energy/spins**
system is its #1 complaint in 2026 reviews [Source: Wikipedia/Trivia Crack;
Source: mobiledevmemo].

> **Hook.** **Keep the wheel, delete the energy gate.** **Reframe crown-collection
> as keepable *mastery*** (a streak across distinct topics that's yours to keep) —
> turns a zero-sum *theft* loop into growth. Async challenge-a-friend is the right
> multiplayer primitive — share via a **direct invite link, not a feed post**.

**QuizUp.** **Real-time 1v1** across thousands of narrow topics; its standout is
**XP/levels tracked separately *per topic*** (you weren't "a trivia player," you
were great at *Game of Thrones*). Died because real-time 1v1 is **expensive and
fragile** (always-on servers, live population per topic) and UGC moderation at
1,200+ topics is a perpetual cost; servers offline March 2021 [Source:
productmint; Source: Wikipedia/QuizUp].

> **Hook (the single best idea for a learning app).** **Per-topic leveling is a
> real map of what you know** ("Level 18 Astronomy, Level 3 Renaissance Art") —
> personal knowledge cartography, fully solo. A Wikipedia corpus supports thousands
> of followable topics. **Invert every failure:** go **async not real-time**
> (cheaper, no clock anxiety); a **curated Wikipedia corpus** delivers the breadth
> *without* the UGC-moderation liability; keep it cheap (static corpus, no
> always-on servers).

**Sporcle.** **Typed-enumeration**: name all X (presidents, countries, elements)
into one box against a countdown; the **fill-grid is the scoreboard** ("38/45");
scoring is **never all-or-nothing**; missed items revealed in red at the end. 2M+
user quizzes, 6B+ plays [Source: Wikipedia/Sporcle].

> **Hook.** **"Sweep the set" rounds (MCQ-native)** — a themed set as rapid-fire
> MCQ with a **persistent fill-grid**; the completionist pull works whether tapped
> or typed. **Beat-your-own-score** (no opponent, no streak anxiety). **The "what
> you missed" reveal is the learning moment** (missed item + correct answer + a
> cited one-line fact). Make any timer optional/never punitive.

**LearnedLeague (the best with-friends mechanic).** **Async daily**: six questions
before a deadline; you and a paired opponent face the same six. The signature: on
**defense** you **assign point values to your opponent's six** — exactly one 3, two
2s, two 1s, one 0 — where the value = how many points they score *if correct*. So
you put your **0 on what they'll nail and your 3 on what they'll MISS** —
**defending points by betting on their failures**. "You can lose a match in which
you answer more questions correctly." Skill-tier "Rundles" with promotion/relegation
[Source: Wikipedia/LearnedLeague; Source: learnedleague.com].

> **Hook.** **Defensive wagering adapted to MCQ** — daily ~6 MCQs; you assign
> 3/2/2/1/1/0 to a friend's copy, betting which they'll get wrong (MCQ sharpens it:
> you reason about whether they'll fall for a *specific distractor*). Zero dark
> patterns, async-native. **Promotion/relegation without leaderbophobia** —
> small skill-matched cohorts, gentle seasonal movement, no streak-loss penalty.

**NYT Connections (+ Only Connect).** A **4×4 grid of 16 tiles** into **four hidden
groups of four**; correct groups lock; win before four mistakes; difficulty by
color; built so **more connections appear than exist** (overlap traps — MARS =
planet *or* candy). 9M+ daily players. **Only Connect's** wall **gets harder as you
solve** and awards a separate point for *naming* the connection [Source: Wikipedia/
Connections; Source: Wikipedia/Only Connect].

> **Hook (strongest non-MCQ mode candidate).** **Tiles become facts/entities** — 16
> answers → 4 groups by hidden link, mined from **shared Wikipedia categories /
> Wikidata `instance-of`** (16 people → "Nobel Physics," "Assassinated US
> Presidents," "Composed an opera," "Element named after them" — Marie Curie in two
> = an engineered overlap trap). Keep "one away"; on reveal **show the link + a
> cited Wikipedia why** (the differentiator NYT lacks). Solo daily async puzzle;
> async co-op deliberation with friends.

**Wits & Wagers.** Every question has a **numeric answer**; all players secretly
guess; guesses are laid out and players **bet on which is closest without going
over**. **You don't need to know the answer — you need to read who knows it**
[Source: Wikipedia/Wits and Wagers].

> **Hook.** **"Confidence wager" on an MCQ** (stake confidence across options) = a
> calibration exercise. **Async "guess the crowd"** — bet on which answer the crowd
> *thought* right vs what *is* right. Outlier reward = reward for justified
> contrarianism (critical thinking over herd-following).

**Smart10.** Every question has **exactly 10 valid answers**; on your turn name one
or **pass to bank** what you've collected; **wrong loses all markers from this
round** [Source: de.wikipedia.org/Smart_10].

> **Hook.** **"List mode"** — "name N of 10 / pick-all-that-apply"; more correct =
> more credit, one wrong forfeits *this question's* round credit. **Voluntary stop
> = respecting agency** (bank and walk away; only unbanked round progress is ever
> lost, never accumulated mastery).

**Trivial Pursuit.** A circular "pie" of **six colored wedges** earned by answering
in six genus categories; collect all six to win [Source: Wikipedia/Trivial Pursuit].

> **Hook (best async progression scaffold).** **Six wedges = six knowledge
> domains** — collect a wedge per domain at a small mastery threshold: a visible,
> motivating "pie" rewarding *breadth*. Durable and personal, never a streak that
> resets. **The breadth incentive fights corpus bias** — the pie only completes
> when *every* color is filled, nudging learners toward avoided subjects.

### Cross-cutting lessons (what the failures teach)

1. **Cash + mandatory-live killed HQ** → validates no-gambling, async-first.
2. **Real-time-only + UGC moderation killed QuizUp** → a curated static Wikipedia
   corpus, played async, sidesteps both cost centers while keeping per-topic leveling.
3. **Energy/spins are Trivia Crack's #1 complaint** → "no energy/lives" is a
   *differentiator*, not a limitation.
4. **The most learning-aligned mechanics are generative** — Fibbage's "write the
   decoy" and LearnedLeague's "predict what they'll miss" both turn passive answer-
   *selection* into active fact-*reasoning*.
5. **Confidence-allocation scoring is everywhere in live trivia** and is
   metacognition in disguise — adopt the *adds-only* variants, reject *wrong-
   subtracts / lose-it-all* as loss-aversion.

*Accuracy flags carried from research: Trivia Crack mascots are Tito/Albert/Bonzo/
Hector/Pop/Tina + Andy. Smart10 designers are Steinwender & Reiser. QuizUp servers
shut down March 24, 2021. King Trivia↔Pour House is inference, not a confirmed
merger.*

---

# Part B — Quiz Question & Interaction-Type Catalog

*The mechanics, evaluated against the learning mission, the 4-option MCQ corpus,
and cross-platform parity. Per-type detail; the synthesis table is at the end.*

**Corpus legend:** **Yes** = rides current 4-option MCQ as-is · **+meta** = needs a
derivable field (difficulty, category, numeric value, aliases, blanked statement) ·
**Rich** = needs genuinely new structured/media data or curation.

1. **Standard 4-option MCQ (baseline).** Recognition memory + discrimination;
   value is mediocre *unless paired with the why*. Corpus: **Yes** — this *is* the
   corpus. tvOS: four focusable cards, 29pt floor.

2. **Buzz-in / first-to-answer.** Retrieval speed + risk calibration ("do I know
   this fast enough to commit?"). **Multiplayer-only** (degenerates to a timer
   solo). Phone-as-buzzer is the natural idiom; TV is the shared display. Corpus:
   **Yes**, but needs **real-time infra** (the gate, not the data).

3. **Wager / confidence betting.** **Metacognition / confidence calibration —
   arguably the highest learning-value mechanic here.** Strong solo *and* a
   comeback mechanic in multiplayer. Corpus: **Yes** — a pure meta-layer over any
   MCQ. **High value, near-zero data cost.** Framing must be points/calibration,
   never cash/lives.

4. **Confidence ladder / lifelines (Millionaire).** Risk/reward + resource
   management. Corpus: **+meta** (difficulty rating; 50:50 needs distractor
   "wrongness" ranking). Lifelines avoid the dark-pattern trap only if there's no
   purchase/timer-pressure to buy more.

5. **Type-the-answer (free text).** **Free recall — the deepest retrieval mode,
   highest learning value** (the testing effect is strongest for production). Cost:
   frustration from a typo/alias rejection. **tvOS text entry is miserable** (the
   parity wall). Corpus: **+meta** (Wikidata aliases / `also known as` give a
   ready accepted-answers set). Web/phone first; tvOS via phone-as-keyboard or skip.

6. **True/False rapid-fire.** Fast fact verification; value rises sharply if false
   statements are **plausible misconceptions**, not random negations. **Binary =
   ideal TV input.** Corpus: **+meta** (synthesize statements from fact + distractor
   — same garbling/leak risk class the distractor work already fought).

7. **"Closest to" / numeric estimation.** **Quantitative reasoning, estimation,
   anchoring — a distinct, underserved skill** that accepts partial knowledge.
   Dial/stepper is **TV-friendly** (no keyboard). Corpus: **+meta** (Wikidata
   numeric facts — population, elevation, dates). **Among the best ROI enrichments.**

8. **Ordering / ranking / sequencing.** **Relational/comparative reasoning** (a
   timeline/size-rank engages structural knowledge); partial-credit scoring avoids
   all-or-nothing. Drag on phone/web; **insert-into-position via focus** on tvOS.
   Corpus: **+meta** (orderable attribute — reuses #7's numeric extraction).

9. **Odd-one-out.** **Categorization / feature abstraction**; naming *why* is a
   depth multiplier. **Zero new UI** (four cards) if you skip the name-the-trait
   follow-up. Corpus: **+meta** (set of three sharing a property + one decoy via
   Wikidata `instance of`). One of the cheapest *new* formats; the outlier must be
   unambiguous.

10. **Connections / grouping wall.** **Multi-hypothesis categorization under
    interference** (the overlap traps are the genius). Corpus: **Rich** — needs 4
    mutually-exclusive groups + deliberate traps; hard to auto-generate cleanly
    without ambiguity. **Marquee daily puzzle, not a core corpus mode.**

11. **Matching pairs.** **Associative recall** (paired-associate learning — a
    proven study format); easy to validate (1:1 relations). Corpus: **+meta**
    (country→capital, author→book, element→symbol via Wikidata). Lower-risk than
    Connections; study-aligned.

12. **List / enumeration (Sporcle).** **Exhaustive free recall** ("I forgot one!"
    is memorable learning). **tvOS text-entry wall.** Corpus: **Rich** (complete
    enumerable sets + alias coverage). Web/phone first.

13. **Bluffing / fake-answer (Fibbage).** **Generative reasoning + theory of mind**
    — you must understand the fact to fake it convincingly (one of the highest-value
    social mechanics). **Multiplayer-only.** Phones are private input; TV is the
    reveal stage. Corpus: **+meta** (reshape a fact into a blanked statement; *less*
    manufactured data than MCQ since players generate the decoys). Needs real-time infra.

14. **Picture / image ID.** **Visual recognition** (a different memory channel);
    progressive-reveal adds hypothesis-under-uncertainty. **Images shine on tvOS at
    10ft.** Corpus: **+meta** (Wikidata `image (P18)` + Commons — the answer entity
    often already has a canonical image). **The content type that finally plays to
    tvOS's strengths.** Honor the image-fallback policy + attribution.

15. **Audio / music ID.** **Auditory recognition.** Corpus: **Rich** — **weakest
    Wikipedia fit** (licensing; Commons has only narrow free audio: pronunciations,
    public-domain classical, birdsong). Deprioritize unless a licensed source appears.

16. **Category steal / Jeopardy board.** Retrieval + **strategic board selection +
    risk management**; the category grid scaffolds knowledge by domain. **tvOS is
    the perfect canvas** (the category×value grid at 10ft is the living-room
    experience — TV is the *best* platform here). Corpus: **+meta** (category tag +
    value/difficulty); steal/wager need real-time infra.

17. **Head-to-head duel (1v1).** Same retrieval + performance pressure. **The async
    "ghost" variant is the key insight: competitive multiplayer with NO real-time
    server** — record one player's answers+timing, replay as an opponent. Corpus:
    **Yes**. **Among the cheapest paths to "multiplayer."**

18. **Co-op / team.** **Collaborative reasoning + articulation** (explaining your
    reasoning is itself powerful learning — the teaching effect). No losers — fits
    the ethos beautifully. Same-room needs only **one shared screen + discussion**
    (lowest-tech multiplayer). Corpus: **Yes** — a social wrapper over any type.

19. **Survival / sudden-death.** Sustained accuracy + pressure. Corpus: **+meta**
    (difficulty for escalation). **Mission caution:** "one mistake ends it" can tip
    toward punishing/addictive — frame as a *challenge mode* with a clear retry + a
    learning recap, never a lives-economy. *(Tidbits already ships this carefully.)*

20. **"This or That" binary speed.** Rapid pairwise comparison; with comparative
    prompts (older/bigger) it's genuine relational reasoning at speed. **The most
    TV-friendly input of all** (D-pad left/right). Corpus: **Yes** (real-vs-fake) /
    **+meta** (bigger/older reuses #7's numeric facts). **Low data cost, best TV
    ergonomics.**

21. **Wisdom-of-crowd (predict the majority — Family Feud / Wits & Wagers).**
    **Social cognition / modeling the group** + estimation. **The "predict the
    crowd" variant is uniquely corpus-native** — it needs **no new content**, just
    the **answer-distribution telemetry** the app could already collect ("X% of
    players picked this"). Corpus: **Yes** (telemetry). **One of the highest-ROI
    ideas in the catalog** — new social/metacognitive skill, zero content authoring,
    and the distribution reveal enriches the *base* MCQ.

### Synthesis table

| # | Type | Corpus | Solo | Shines MP | Learning | Complexity |
|---|---|---|---|---|---|---|
| 1 | Standard MCQ | Yes | ✅ | ok | L–M | L |
| 2 | Buzz-in | Yes (+RT) | ❌ | ✅ | L–M | H (real-time) |
| 3 | **Wager / confidence** | **Yes** | ✅ | ✅ | **H** | **L** |
| 4 | Confidence ladder | +meta | ✅ | ✅ | M | M |
| 5 | Type-the-answer | +meta | ✅ | ok | **H** | M (TV wall) |
| 6 | True/False rapid | +meta | ✅ | ✅ | M | M |
| 7 | **Closest-to / numeric** | +meta | ✅ | ✅ | **H** | M |
| 8 | Ordering / ranking | +meta | ✅ | ✅ | **H** | M |
| 9 | Odd-one-out | +meta | ✅ | ✅ | M–H | L–M |
| 10 | Connections wall | Rich | ✅ | ✅ | **H** | H |
| 11 | Matching pairs | +meta | ✅ | ✅ | M–H | M |
| 12 | List / enumeration | Rich | ✅ | ✅ | **H** | M–H (TV) |
| 13 | **Bluffing (Fibbage)** | +meta | ❌ | ✅ | **H** | H (RT) |
| 14 | Picture / image ID | +meta | ✅ | ✅ | M–H | M |
| 15 | Audio / music ID | Rich | ✅ | ✅ | M | H (licensing) |
| 16 | Jeopardy board | +meta | ✅ | ✅ | M–H | M–H (+RT steal) |
| 17 | **Head-to-head (async ghost)** | **Yes** | ❌ | ✅ | L–M | **L (async)** |
| 18 | **Co-op / team** | **Yes** | ❌ | ✅ | **H** | **L (same-room)** |
| 19 | Survival | +meta | ✅ | ✅ | L–M | L |
| 20 | **This-or-That binary** | Yes/+meta | ✅ | ✅ | M | **L** |
| 21 | **Wisdom-of-crowd (predict)** | **Yes (telem)** | ✅* | ✅ | **H** | L–M |

\* Solo wisdom-of-crowd works once answer-distribution telemetry exists.

**Two structural truths shaping the build order:**

- **Real-time multiplayer infra is the true gate, not data.** Buzz-in (#2), live
  Jeopardy steal (#16), Fibbage (#13) ride near-corpus data but need a low-latency
  authoritative server. Until that exists, prefer **synchronized-answer** modes
  (everyone answers every item — #20, #6, #18) and **async** modes (#17 ghost, #21
  predict) that need no live server.
- **The Wikidata numeric/image/alias enrichment is the highest-leverage corpus
  investment.** One build-time pass that, per answer entity, emits *numeric facts +
  units, Commons image + license, and Wikidata aliases* unlocks **#5, #7, #8, #11,
  #14, #20, and Wits & Wagers — seven formats from one enrichment** (Part E).

---

# Part C — Phone-as-Buzzer / Second-Screen Architecture

*Same-room (local) and remote/virtual play across tvOS, iOS, Android, and Web.
Current as of the iOS 26 / tvOS 26 era. Jackbox/Kahoot protocol detail is from
independent reverse-engineering and flagged as such.*

## C0. The headline finding

Two fundamentally different architectures — **not competitors so much as
different products:**

1. **Apple-native local (P2P, no server)** — iPhones talk directly to the Apple TV
   over the LAN. Lowest latency, fully offline, but **requires the app installed on
   every buzzer**, is **Apple-only**, and caps at small groups. Apple just
   **deprecated** the obvious framework (MultipeerConnectivity) and points to
   Network.framework + Bonjour [Source: Apple Developer Forums/thread/776069].
2. **Server-mediated room-code / web-client (Jackbox/Kahoot model)** — the TV shows
   a code, players join from **any phone browser at a URL with no install**, and a
   realtime backend relays buzzes. **Inherently cross-platform**, works **same-room
   AND remote**, the only model that survives a heterogeneous living room.

**Critical constraint: tvOS has no WKWebView / web view** — you cannot render
HTML/JS in a tvOS app [Source: BPXL Craft/medium.com/bpxl-craft/apple-tv-a-world-
without-webkit]. So **when the host is an Apple TV, the host must be a native app**
— which Tidbits already is. It only affects the *phones*, which use a browser
regardless of host.

## C1. Apple-native local (same room, no server)

- **MultipeerConnectivity** — Wi-Fi + Bluetooth P2P; tvOS-supported (TV as host,
  iPhones as peers); **max 8 incl. host**; good latency. **HIGH deprecation risk** —
  Apple DTS: "Xcode 27 beta has formally deprecated Multipeer Connectivity… consider
  moving to Network framework." Historically flaky on betas. **Do not start here**
  [Source: Apple Developer Forums/776069, /25049; Source: Apple docs/
  kMCSessionMaximumNumberOfPeers].
- **Network.framework + Bonjour (Apple's recommended local path).** tvOS host
  publishes a Bonjour service via `NWListener`; phones discover via `NWBrowser`,
  open `NWConnection`s — a true **client/server** model (better fit than
  MultipeerConnectivity's symmetric mesh). **No peer cap**; flow control;
  **TLS-PSK** security derived from a short room code; peer-to-peer Wi-Fi is opt-in.
  Gotcha: on tvOS use `receive(minimumIncompleteLength:maximumLength:)` (raw receive
  callbacks can fire only on close). **Best Apple-native local option** [Source:
  Apple Developer Forums/776069; Source: ASCIIwwdc WWDC19 S713; Source: Ben Dodson].
- **GameController / GameKit — wrong tool.** `GCVirtualController` emits *local*
  touch input, not network messages (and tvOS has no touchscreen). `GKMatch` routes
  through **Game Center servers** (not local) and requires Game Center sign-in. Skip.
- **DeviceDiscoveryUI — elegant but one device only.** System pairing UI + encrypted
  Network.framework connection, **avoids the local-network prompt** — but **one
  device at a time**, Apple TV 4K only, same bundle ID. Perfect for a *single*
  companion remote; rules itself out for multi-player buzzing [Source: Ben Dodson;
  Source: Apple docs/devicediscoveryui].
- **Local-network privacy prompt** (`NSLocalNetworkUsageDescription`, iOS 14+) hits
  both Multipeer and Bonjour on the iPhone — budget for the prompt + a user-visible
  denial error (iOS 18 made it flaky) [Source: Apple Developer Forums/766133].
- **Continuity / AirPlay / Handoff / SharePlay — not a buzzer transport** (media-
  sync, not a low-latency input channel).
- **Android-TV parallel:** Android's analog is **Nearby Connections** (BLE +
  Bluetooth + Wi-Fi, offline) — but it's Android/iOS, **not web**, and **not
  interoperable with Apple's stack**. So local P2P fragments per-ecosystem and never
  reaches the browser — reinforcing that **only the server-mediated web model is
  truly unifying** [Source: Google for Developers/nearby].

## C2. Server-mediated (same-room AND remote, no install)

**How Jackbox/Kahoot work** — three roles: a **shared screen + host** (holds
authoritative state), a **controller** (any phone browser at jackbox.tv / kahoot.it,
no install), and a **relay** (Jackbox's Ecast WebSocket service; Kahoot's CometD/
Bayeux tier). Rooms are sharded; a short code/PIN is the routing key. **The one
weakness: no host migration — the room dies if the host app closes** [Source:
github.com/InvoxiPlayGames/johnbox; Source: deepwiki/kahoot-api]. *(Protocol
internals are reverse-engineered; Kahoot's scale figures are first-party.)*

**Why inherently cross-platform:** the controller is "any device with a modern
browser + a WebSocket" — zero install, no per-OS build, no NAT/discovery problem
(the room code replaces P2P hole-punching).

**Realtime backend options for this project** (Supabase is planned; Cloudflare
Workers/Durable Objects available). They sit at opposite ends of one axis:
**Supabase Realtime is a pub/sub *relay* (no per-room authoritative compute); a
Durable Object is a per-room single-threaded *arbiter*** — and for a buzzer, that
distinction is the whole ballgame.

| Dimension | Supabase Realtime | Cloudflare Durable Objects |
|---|---|---|
| Latency | Broadcast ~<50 ms, server-mediated | Edge WS, DO near co-located players |
| Concurrency | Free 200/100 msg-s; Pro 500/500; no-cap 10k/2.5k | No per-DO WS cap; scale = # of rooms |
| Cost @ few-hundred rooms | Past Free; needs no-cap Pro/Team | $5/mo; idle rooms **hibernate ~free** |
| **Authoritative buzz-ordering** | **Weak** — relay, no ordering guarantee | **Strong** — single-threaded object *is* the arbiter |
| Op complexity to start | Lower (managed SDK, Presence) | Write the DO room class |

A Durable Object is "globally-unique, single-threaded… naturally suitable for
authoritative decision-making" — two buzzes can never be processed truly
simultaneously; the object sees a strict order and stamps "first" deterministically.
**WebSocket Hibernation** evicts idle rooms from memory while clients stay connected
(duration billing stops) — idle lobbies are ~free [Source: Cloudflare docs/durable-
objects]. **PartyKit** (acquired by Cloudflare) is an ergonomic DX layer over the
same model.

**Fairness / "who buzzed first":** **one clock, server-side stamps** — never compare
client timestamps (unsynchronized, spoofable). Add **RTT compensation** (estimate
true-tap = arrival − one-way delay) so a slower-connection player whose finger was
actually faster still wins; target **sub-100 ms** (below human "we tapped together"
perception). Kahoot literally carries clock-offset/lag fields in its handshake for
this [Source: Quizado/quizado.com/buzzer-app-for-trivia; Source: Kahoot handshake gist].

## C3. Cross-platform parity matrix

| Host \ Players | iPhone | Android | Web/laptop |
|---|---|---|---|
| **Apple TV** | native P2P *or* web-room | web-room only | web-room only |
| **Android TV** | web-room only | Nearby *or* web-room | web-room only |
| **Web screen** | web-room only | web-room only | web-room only |

The matrix collapses to one truth: **the web-room model is the only cell that fills
every box.** Local P2P fragments three ways (Apple Network.framework, Android Nearby,
nothing for the browser) and never interoperates. The web app we already ship
becomes the buzzer client — a new view in the existing web app, not a new product.
The web-room is **same-room and remote for free** (the relay is in the cloud; no
STUN/TURN/hole-punching).

## C4. Master comparison

| Approach | Latency | Max players | Same-room | Remote | Needs install | Cross-platform | Offline | tvOS host |
|---|---|---|---|---|---|---|---|---|
| MultipeerConnectivity | Very low | 8 incl host | ✅ | ❌ | ✅ Apple app | ❌ Apple | ✅ | ✅ (**deprecated**) |
| **Network.framework + Bonjour** | Very low | No cap (LAN) | ✅ | ❌ | ✅ Apple app | ❌ Apple | ✅ | ✅ |
| DeviceDiscoveryUI | Very low | **1 device** | ✅ | ❌ | ✅ same bundle | ❌ Apple, 4K | ✅ | ✅ |
| GKMatch | Med (relay) | dozens | ⚠️ relayed | ✅ | ✅ + GC | ❌ Apple | ❌ | ✅ (buggy) |
| Android Nearby | Very low | many | ✅ | ❌ | ✅ Android app | ❌ no web | ✅ | ❌ |
| **Supabase Realtime (web-room)** | ~<50ms + net | hundreds+ | ✅ | ✅ | ❌ browser | ✅ universal | ❌ | ✅ native host |
| **Cloudflare DO (web-room)** | edge + net | hundreds+/room | ✅ | ✅ | ❌ browser | ✅ universal | ❌ | ✅ native host |

## C5. Recommendation — phased, offline-floor-first

**Heed the project's own doctrine (023): async > real-time for survivability.** A
real-time buzzer is fragile (host migration impossible; dark when the internet is
down — which conflicts with Tidbits' offline-bundled-corpus identity). So the buzzer
is **additive, never load-bearing**:

- **Phase 0 (already true):** Solo / pass-and-play on the bundled corpus works
  **fully offline, no companion device.** The survivable baseline; must never regress.
- **Phase 1 — MVP, same-room, Apple-native, no server:** **Network.framework +
  Bonjour + TLS-PSK**, room code on the TV. Real "phones as buzzers" for the common
  case (everyone Apple, same room) with **zero backend cost, full offline, lowest
  latency**, no third-party Swift packages (the tvOS host is a native WebSocket/
  NWConnection client). PARITY note: **Apple-only, same-room-only** — Android's
  Nearby is the parallel native path if an Android TV host ships.
- **Phase 2 — scale + cross-platform + remote, web-room:** add the **Cloudflare
  Durable Object web-room** so any phone browser joins `tidbits.tv/<code>` (no
  install; iPhone/Android/laptop; same-room or remote). Server timestamps + RTT
  compensation = fair sub-100 ms ordering. The host detects connectivity: **online →
  web-room (universal); offline or all-Apple-same-room → Phase 1 local fallback.**
- **Skip:** MultipeerConnectivity (deprecated, 8-cap), GKMatch (relayed + sign-in),
  GCVirtualController (touch, not transport), SharePlay/AirPlay (media-sync), raw
  Workers without DO (no arbiter), Supabase-Broadcast-as-sole-arbiter (no ordering
  guarantee — only viable with a bolt-on Edge-Function arbiter, which a DO gives free).

**Why Cloudflare DO over Supabase for Phase 2** (though Supabase is planned
elsewhere): for a buzzer *specifically*, authoritative "who-was-first" is exactly
what a single-threaded DO provides natively, idle rooms hibernate to ~zero, and
20:1 WS billing makes tiny buzzes negligible. Keep Supabase for auth/sync/the shared
data plane; add a DO Worker for the realtime room. (Supabase Realtime + an Edge-
Function arbiter is a workable second choice — just don't rely on Broadcast ordering.)

**Key UX flows:** TV shows a short **room code + a QR** encoding `tidbits.tv/<code>`
(QR for speed, code as the across-room/stream fallback — both Jackbox and Kahoot
keep the readable code canonical); the same code derives the TLS-PSK in local mode.
Reconnection keys to room-code + a player identity token, not the socket (a slept
phone rejoins its seat with score intact). Host migration: none in the relay model —
make it graceful (host drop = "game paused," all real progress in the offline-
capable local store so nothing is *lost*).

**Gotchas:** tvOS has no web view (host always native); tvOS local-network
entitlement + the iOS `NSLocalNetworkUsageDescription` prompt on the Phase-1 path;
tvOS background/suspension drops listeners (pause, don't crash); clock sync is always
server-authoritative; NAT/remote is a non-issue for the web-room, unsolved for P2P
(which is why P2P stays same-room only).

*Caveat: confirm load-bearing API attributes against the live Xcode 27 headers
before coding; Jackbox/Kahoot protocol internals can change without notice.*

---

# Part D — Tidbits' Home Versions (the proposal)

The synthesis. We take the most learning-aligned mechanics from Parts A–B and design
Tidbits' own "home version" of each, organized by **play context**. Every proposed
mode is run through the **learning-orientation four-question test**
(`learning-orientation-design`): **(1) deepens understanding? (2) invites
participation? (3) supports agency? (4) clarity over cleverness?** A "no" to any is a
redesign signal — recorded honestly below.

**Design throughline (what makes a Tidbits mode a *Tidbits* mode):** every mode ends
each question on the **"Learn the fact" reveal** (already shipped — the literal
embodiment of the mission, `ROADMAP` #3), and every "wrong" is a **door to a fact,
never a punishment**. That single rule is how borrowed bar-trivia mechanics keep
passing question (1).

## D1. Solo modes (offline, no companion — the survivable baseline)

These ride the **bundled corpus**, need **no network**, and never regress Phase 0.

| Mode (ancestor) | What it is | 4-question test | Corpus |
|---|---|---|---|
| **Stake** — confidence allocation *(Pour House / LearnedLeague / Wits & Wagers)* | Across a round of ~6 MCQs, allocate confidence points (e.g. 3/2/2/1/1/0, **adds-only, you can never go negative**) before answering. Misjudging costs *relative* score, never punishes. | (1) ✅ forces "how sure am I, really?" — calibration is the deepest meta-skill (2) ✅ your judgment *is* the input (3) ✅ teaches self-knowledge you keep (4) ✅ a scoring layer over existing MCQ. **All yes → ship-candidate #1.** | **Yes** |
| **Sweep** — fill-the-set *(Sporcle)* | A themed set ("all 8 planets," "post-1900 presidents") as rapid-fire MCQ with a persistent **fill-grid (37/45)**; beat **your own** best; end on a **miss-reveal** (every missed item + cited fact). | (1) ✅ the miss-reveal is the learning moment (2) ✅ you pick the set/topic (3) ✅ vs yourself, no opponent dependency (4) ✅ MCQ + a grid. **All yes.** | **Yes** (sets from Wikipedia categories) |
| **Closest Call** — numeric estimation *(higher-lower / Price-is-Right)* | A numeric answer (year, population, elevation); dial a number; scored by **proximity**, accepting partial knowledge. | (1) ✅ a *new* cognitive skill (estimation/anchoring) (2) ✅ reasoning-from-priors is the contribution (3) ✅ builds quantitative intuition (4) ⚠️ needs a dial UI + numeric data — simple, but new. **Yes, gated on Part E enrichment.** | **+meta** (Wikidata numbers) |
| **The Pie** — breadth progression *(Trivial Pursuit)* | Earn one **wedge per knowledge domain** at a small mastery threshold; a visible, durable "pie" that **only completes when every domain is filled** — nudging you toward subjects you avoid. | (1) ✅ structured breadth (2) ✅ you choose your path through it (3) ✅ durable, personal, never resets (4) ✅ a progress map over existing records. **All yes** — a meta-progression that *fights corpus bias.* | **Yes** |
| **Topic Levels** — knowledge cartography *(QuizUp)* | XP/levels tracked **per Wikipedia topic**, not globally — "Level 18 Astronomy, Level 3 Renaissance Art." A real map of what you know. | (1) ✅ surfaces *where* your knowledge is (2) ✅ follow the topics *you* care about (3) ✅ the opposite of an opaque "for you" feed — it exposes the domain's structure (the skill's canonical example) (4) ✅ per-topic counters. **All yes.** | **Yes** (topic tags) |

**Solo, but *Rich data* — the marquee daily puzzle:**

- **Link Wall** — the Connections home version *(NYT Connections / Only Connect).*
  16 fact-tiles → 4 hidden groups by a Wikipedia/Wikidata link; keep **"one away"**;
  on reveal **show the link + a cited "why"** (the differentiator NYT lacks);
  optional Only-Connect-style "name the connection" follow-up. **4-question test: all
  yes, and the highest-ceiling learning puzzle here** — but **Corpus: Rich** (curated
  4×4 groups + engineered overlap traps; ambiguity is the failure mode the distractor
  work already taught us to fear). **Reserve as a flagship daily, after Part E**, with
  human/LLM-assisted curation. Pairs with `ROADMAP` #10 (daily intersection grid).

## D2. Same-room modes (tvOS host + phones; Apple-native local MVP → web-room)

The living-room gap `ROADMAP` #4 names. **Lowest-tech first** (no buzz infra), then
the buzzer.

| Mode (ancestor) | What it is | 4-question test | Infra |
|---|---|---|---|
| **Couch Co-op** — team play *(pub-quiz team / co-op)* | One TV, the couch is a team; **discuss out loud, one device submits** (or majority vote). No losers. | (1) ✅ **articulating your reasoning to the room is the teaching effect** (2) ✅ everyone contributes (3) ✅ builds collaborative reasoning (4) ✅ needs only a shared screen + a submit control — **no buzz infra at all**. **All yes → the cheapest same-room mode; build first.** | None (shared screen) |
| **Buzz Night** — the living-room show *(Jackbox/Kahoot/Jeopardy buzz)* | TV is the stage + scoreboard; **phones are buzzers**; first-correct scores; a wrong buzz opens it to others. Teams or individuals. End every question on the shared **Learn-the-fact** reveal. | (1) ⚠️ speed pressure can crowd out reflection — **mitigate: the reveal + "now you know" keeps the fact, and a wrong buzz is a teaching moment not an elimination** (2) ✅ everyone buzzes (3) ⚠️ rewards fluency over depth — **keep it one mode among many, never the default** (4) ⚠️ needs real-time infra — Part C Phase 1. **Conditional yes** with those guardrails. | Network.framework (Phase 1) → web-room (Phase 2) |
| **Decoy** — write-the-bluff *(Fibbage)* | A blanked fact; each phone **privately types a plausible fake**; all fakes + the truth shuffle onto the TV; everyone votes; score for spotting truth **and** for fooling others. | (1) ✅ **you must understand the fact to fake it convincingly** — generative recall, the highest-value social mechanic (2) ✅ players author the decoys (3) ✅ reasoning about plausibility builds real knowledge (4) ⚠️ needs private phone input + reveal + voting + a "you typed the real answer" guard. **Yes — flagship to build toward** once same-room infra exists. Bonus: human decoys could *improve the corpus*. | Phase 1/2 (private input) |
| **Predict the Couch** — wisdom-of-crowd *(Family Feud / Wits & Wagers)* | After answering, guess **what the room (or all players) picked**; the animated **distribution reveal** on the TV is the payoff. | (1) ✅ modeling the group is a distinct skill; the "X% picked this" reveal teaches (2) ✅ your prediction is the input (3) ✅ critical-thinking-over-herd (outlier-correct earns more) (4) ✅ reuses **answer-distribution telemetry** (Part E) — no new content. **All yes; very high ROI.** | None solo (telemetry); shared screen same-room |

## D3. Virtual / async modes (survivability-first multiplayer — 023)

No live server; the model that *outlived* its real-time competitors.

| Mode (ancestor) | What it is | 4-question test | Infra |
|---|---|---|---|
| **Ghost Duel** — async head-to-head *(QuizUp, reimagined)* | Race a friend's **recorded run** (their answers + timing replayed as an opponent). Same questions, asynchronous. | (1) ➖ neutral on understanding (same MCQ) but (2) ✅ social participation (3) ✅ no clock-anxiety, no always-on dependency (4) ✅ **competitive multiplayer with NO real-time server** — just record/replay. **Yes — the cheapest path to PvP.** | Stored run (no live server) |
| **Daily Six + Defense** — defensive wager *(LearnedLeague)* | A shared **async daily of ~6 MCQs**; you also **assign 3/2/2/1/1/0 to a friend's copy**, betting which they'll *miss* (and which *distractor* fools them). Compare next day. | (1) ✅ predicting a friend's miss requires modeling *their* knowledge *and* the distractors — deep (2) ✅ the wager is pure judgment (3) ✅ async, humane, no FOMO; solo variant bets the *crowd* aggregate (4) ⚠️ a richer scoring/pairing layer, but no live infra. **Yes — the best with-friends mechanic in the catalog.** | Async pairing (no live server) |
| **League Ladder** — gentle seasons *(LearnedLeague Rundles)* | Small **skill-matched cohorts** (~25), gentle seasonal promotion/relegation, **no streak-loss penalty**. | (1) ➖ wraps other modes (2) ✅ belonging to a cohort (3) ✅ matched difficulty keeps you in your zone (4) ✅ a standings layer. **Yes** — but only *after* the modes it wraps exist. Watch the dark-pattern line: movement is gentle, nothing punishes absence. | Async standings |

## D4. The slate at a glance (recommended order)

1. **Stake** (solo confidence) — rides corpus, highest learning value, ship first.
2. **Predict the Couch / Crowd** (solo + same-room) — needs answer telemetry (Part E
   prerequisite), zero content authoring, enriches base MCQ.
3. **Couch Co-op** (same-room) — no infra; the cheapest living-room mode.
4. **Sweep** (solo) — corpus sets from Wikipedia categories; beat-your-own-score.
5. **Closest Call** + **This-or-That** (solo/same-room) — both unlocked by Part E
   numeric enrichment; best TV ergonomics.
6. **Ghost Duel** (async) — competitive feel, no real-time server.
7. **Daily Six + Defense** (async) — the marquee with-friends mechanic.
8. **Buzz Night** + **Decoy** (same-room real-time) — gated on Part C Phase 1 infra.
9. **Link Wall** (daily puzzle) + **The Pie** / **Topic Levels** (meta-progression) —
   flagship + long-horizon retention.

**Modes that FAILED the test (recorded so we don't relitigate):** anything with a
**cash wager**, **lives/energy**, **pay-to-restore**, **mandatory-live scheduling**,
or **true elimination** fails question (1) or (3) outright (HQ/Trivia-Crack lessons;
`DECISIONS` 022). The borrowed mechanics survive only in their *adds-only,
async-tolerant, wrong-is-a-door* forms.

---

# Part E — The one corpus enrichment that unlocks seven modes

The single highest-leverage corpus investment is **a build-time Wikidata enrichment
pass** that, per answer entity, emits:

- **Numeric facts + units** (`P1082` population, `P2046` area, elevation, mass,
  inception/birth/death dates) → unlocks **Closest Call (#7)**, **Ordering (#8)**,
  **This-or-That bigger/older (#20)**, and Wits & Wagers.
- **Commons image + license** (`P18`) → unlocks **Picture ID (#14)** — the content
  type that finally plays to tvOS's strengths. Honor the existing image-fallback +
  attribution discipline.
- **Wikidata aliases / `also known as`** → unlocks **Type-the-answer (#5)** and
  **Matching pairs (#11)** with a ready accepted-answers set, and improves base-MCQ
  answer-equivalence matching (`ROADMAP` #9, the table-stakes alias gap).

Plus a **telemetry stream** (per-option answer counts) — *not content* — that unlocks
**Predict the Crowd (#21)** and the "X% of players picked this" reveal.

**Seven formats from one pass.** This is the corpus work to prioritize over any
single bespoke mode — and it sits squarely inside the existing Wikidata moat
(`DECISIONS` 024) and the "every type is a 4-option MCQ unless it earns custom
data" rule (025). Each new field is **additive** to the published corpus (the
`shared-data-plane-contract` evolution rule), so all four clients consume it without
a pipeline rewrite.

---

# Part F — Architecture recommendation (condensed)

- **Solo + async modes need no realtime infra** — build them on the existing shared
  corpus + records store, fully offline. This is most of the slate (D1, D3, half of D2).
- **Same-room real-time (Buzz Night, Decoy)** follows Part C's phased path:
  **Phase 1 Apple-native local** (Network.framework + Bonjour + TLS-PSK; no server,
  offline, Apple-only same-room) → **Phase 2 web-room** (Cloudflare Durable Object;
  `tidbits.tv/<code>`, universal, same-room + remote). The host detects connectivity
  and picks the transport; the offline local store is always the source of truth so a
  dropped room loses nothing.
- **Reuse, don't rebuild:** the buzzer client is a **new view in the web app we
  already ship** (the canonical link target); the tvOS host stays a **native app**
  (no web view on tvOS) using only Apple frameworks (`URLSessionWebSocketTask` /
  `NWConnection`) — honoring "no third-party Swift packages."

---

# Part G — Build order, PARITY & decisions to log

**Recommended next steps (smallest learning-valuable slices first):**

1. **Ship `Stake` (solo confidence mode)** — the cleanest all-yes mode; pure scoring
   layer over the existing corpus; mirror across all four engines (web/iOS/tvOS/
   Android) per `DECISIONS` 025's "type lives in the corpus" discipline... *or*, since
   Stake is a *scoring/meta* layer not a question type, as a client-side mode wrapper.
   Decide and log.
2. **Start answer-distribution telemetry** (privacy-respecting, aggregate counts) →
   prerequisite for `Predict the Crowd` and the "% picked" reveal.
3. **Build `Couch Co-op`** — the no-infra same-room mode; proves the living-room verb.
4. **Run the Part E Wikidata enrichment pass** — unlocks the numeric/image/alias modes.
5. **Then** the real-time same-room infra (Part C Phase 1) for `Buzz Night` / `Decoy`.

**PARITY implications:** add rows for each shipped mode (`Stake`, `Sweep`,
`Closest Call`, `Couch Co-op`, `Buzz Night`, `Decoy`, `Predict the Crowd`, `Ghost
Duel`, `Daily Six + Defense`, `Link Wall`). Same-room buzzer parity is **honest about
asymmetry**: Phase 1 is Apple-only/same-room (⏳ Android via Nearby; web via web-room
in Phase 2). The web-room phase is the universal cell.

**DECISIONS to log when these graduate from proposal to build:**
- *Confidence/wager modes are adds-only — never negative, never cash* (extends 022).
- *Phone-as-buzzer transport is phased: Apple-native local (Bonjour/PSK) MVP → web-room
  (Cloudflare Durable Object) for cross-platform/remote; offline local store is always
  source of truth* (extends 023).
- *The Wikidata numeric/image/alias enrichment is one additive corpus pass* (extends
  024/025 and the data contract).

**Open questions for the user / future sessions:**
- Which mode to build *first*? (Recommendation: `Stake`, then `Couch Co-op`.)
- Is the real-time same-room buzzer worth the Phase-1 Apple-native build now, or do we
  go straight to the universal web-room when the realtime backend is stood up?
- Does `Link Wall` (the curated daily Connections puzzle) justify LLM-assisted set
  curation, or stay fully auto-generated (and accept easier puzzles)?
