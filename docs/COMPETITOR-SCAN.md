# What rival pub-trivia tools give a host that Tidbits Live does not

**Scanned 2026-09-02.** Every "they have it" row is from the vendor's own
documentation (sources at the bottom). Every "we have it" row was checked in this
repo, not remembered — the point of the exercise is an honest gap list, and a
scan that flatters the product is worse than none.

---

## §1 — What Tidbits Live already does (verified in the code)

Worth stating first, because most of the obvious "competitor features" turned out
to be shipped, and a build list that re-proposes them wastes the effort.

| Capability | Where |
|---|---|
| Rounds in many formats (classic, type-answer, closest-call, ordering, matching, enumerate, picture ID, odd-one-out, this-or-that, stake) | `LiveBuilderView_macOS` round picker |
| Audio and video rounds, clip playback to the PA, looping music bed | Wave B, `MacLiveClips` / `LiveVideoPlayer` |
| Per-question editing, CSV import/export, event file import/export | `LiveQuestionEditor_macOS`, `LiveCSV`, `LiveEventFile` |
| Wager round, speed round, per-round timer, host prep notes | Wave A |
| Phone join by QR + 4-letter code; paper teams and phone teams in ONE ranked table | `LiveJoinPanel`, unified standings |
| Tie-break tooling ("Break a tie…", "Resolve tie") | `MacLiveHost` |
| Printing: host question pack, **team answer sheets**, final standings | `MacLivePrint` |
| Venue branding, sponsor line, mailing-list capture QR | Wave D |
| Cross-venue / season league standings with defendable titles | Wave E, `LeaderboardAPI` |
| Projector: question, reveal with vote tally + explanation, break slide, final standings | `LiveBigScreen_macOS`, `ProjectorView` (Windows) |

## §2 — The real gaps

Ranked by how often a working pub host would hit them.

**All six remaining gaps re-verified on BOTH desktops on 2026-09-02**, after G2
turned out to be a macOS-only gap that Windows already filled. Searched both
codebases for each: negative marking, first-letter formats, a category board, a
host remote and a team-leader model are absent from macOS AND Windows; the only
"buzz" hits on either side are sound-effect labels ("BYO clips: applause, buzzer,
drumroll"), not a buzzer ROUND.

### G1. No buzzer / fastest-finger round  *(SpeedQuizzing, QuizXpress)*
SpeedQuizzing's identity is speed: ten seconds an answer, and formats called
Fastest Fingers and Buzzin'. QuizXpress scores faster answers higher and can
count down points over time. Tidbits has a speed BONUS (+3/+2/+1 on correct
answers) but no format where the first team to buzz gets the question — the
single most recognisable pub-quiz mechanic we do not have.

### G2. Per-round score recap — CLOSED, and my first reading of it was wrong
QuizXpress shows intermediate and round scores between rounds; Sporcle reads
standings out between its two games; Crowdpurr's projector ranks live.

**Correction (2026-09-02):** this was written as a product gap. It was not — it
was a macOS gap. WINDOWS ALREADY HAD IT: `ShowBigScreenStandings`, a cockpit
toggle labelled "Standings on big screen", with test coverage in
`LiveHostControlsTest`. I checked §1's inventory against the macOS code and
generalised from it, which is exactly the flattering-scan error this document
opens by warning about. Both platforms now show it, and both name the round.

The lesson for the rest of this list: a gap found on one platform is a PARITY
question until the other has been read.

### G3. Negative marking — CLOSED 2026-09-02, both desktops
QuizXpress can optionally penalise a wrong answer; Tidbits only added points.
Shipped on macOS (`wrongAnswerPenalty`, a cockpit stepper) and Windows
(`WrongAnswerPenalty`, a cycling cockpit button), off by default.

The rule worth stating: only a team that ANSWERED can lose points. Silence is
declining to guess, not being wrong, and penalising it would punish the table
whose phone died. Both implementations get this from iterating the ANSWERS rather
than the teams — an accident of structure, so it is pinned by a test.

### G4. No first-letter / word-shape formats  *(SpeedQuizzing)*
SpeedQuizzing ships First Letter of the Answer, Sequence, Multi Tap, Nearest Wins
and Wordsnake. We have Sequence (ordering) and Nearest Wins (closest-call); we do
not have first-letter or word-shape rounds.

### G5. No pick-your-category board  *(QuizXpress)*
QuizXpress supports Jeopardy-style rounds where players choose subject and
difficulty. Nothing in Tidbits lets the room pick the next question.

### G6. No phone remote for the host  *(QuizXpress)*
QuizXpress drives the show from a presenter remote or a phone app, so the host can
walk the room. Tidbits' cockpit is keyboard + mouse at the laptop. We already have
the whole phone-join transport (`live/{code}`), so a host-role client is a
smaller job than it looks.

### G7. Team self-registration detail  *(Crowdpurr)*
Crowdpurr has an explicit team-leader model — one device answers for a physically
grouped team. Ours is close (a phone team is a team), but there is no notion of a
team leader or of members joining a named team, which is how a table of six with
one phone actually behaves.

## §3 — What NOT to copy

- **Ready-made question packs as the business** (SpeedQuizzing, Sporcle). Our
  corpus is the product; a marketplace is a different company.
- **Sporcle's staffed-host network.** That is an operations business, not
  software, and it contradicts the $0-ongoing-cost guardrail.
- **Crowdpurr's per-event pricing tiers.** Decision 047 has hosting free forever;
  players pay.

---

## Sources

- QuizXpress — [Features](https://www.quizxpress.com/features/), [How it works](https://www.quizxpress.com/game-show-software-how-it-works/), [QuizXpress Live](https://www.quizxpress.com/quizxpress-live/), [Studio](https://www.quizxpress.com/quizxpress-studio-trivia-maker/)
- SpeedQuizzing — [Official site](https://www.speedquizzing.com/), [How to play](https://www.speedquizzing.co.uk/play/), [App Store listing](https://apps.apple.com/us/app/speedquizzing/id409839077)
- Sporcle Live — [Pub trivia games](https://www.sporcle.com/events/games/), [What is bar trivia](https://www.sporcle.com/blog/2015/02/bar-trivia-what-is-sporcle-live/), [Pub Champions league](https://www.sporcle.com/blog/pub-champions-trivia-league-championships/)
- Crowdpurr — [Features](https://www.crowdpurr.com/features), [Trivia](https://www.crowdpurr.com/trivia), [Team Trivia explained](https://help.crowdpurr.com/en/articles/10524943-team-trivia-explained)
