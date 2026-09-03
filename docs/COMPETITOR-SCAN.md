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

### G1. Buzzer / fastest-finger round — CLOSED 2026-09-02, all six platforms
SpeedQuizzing's identity is speed: ten seconds an answer, and formats called
Fastest Fingers and Buzzin'. QuizXpress scores faster answers higher and can
count down points over time. Tidbits had a speed BONUS (+3/+2/+1 on correct
answers) but no format where the first team to buzz gets the question — the
single most recognisable pub-quiz mechanic we did not have.

**Shipped.** A round is marked a buzz round on the host (macOS `currentRoundIsBuzz`,
Windows `IsBuzzRound`/`BuzzRounds`); the host publishes `pub.buzz` and the
cockpit gets a buzz panel with Correct / Wrong, plus a `buzzedOut` set so a team
that got it wrong cannot buzz again on the same question. `firstBuzz(answers:
excluding:)` lives in shared Core on both stacks and resolves the winner by the
SERVER stamp (`Answer.sv`), not the client clock — a phone three seconds fast
would otherwise win every buzz in the room.

On the join clients the buzz button REPLACES the whole answer surface: a player
who can both buzz and answer gives the host two things to adjudicate and it
scores the wrong one. The payload is deliberately empty — the answer is spoken
out loud, so the wire carries only who was first.

**A `pub.buzz` reader was missed on three clients, found 2026-09-02 while
writing this entry.** tvOS had NO buzz branch at all: a Siri Remote player saw
the ordinary options during a buzz round and could submit an answer the host
would never read. And on iOS, tvOS and Android the STATUS NOTE was never taught
about the wire — it keys on `chosen`, which stays nil when a player has buzzed,
so the reveal told a player who had buzzed "No answer submitted." Web was
already correct because its note is generic. All four now say who speaks next.

The lesson, and it is the same one G2 taught in a different costume: shipping a
new field means enumerating every READER of it, not just the writer and the one
client you developed against. A round-trip that works is not coverage.

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

### G4. First-letter rounds — CLOSED 2026-09-02, all six platforms
SpeedQuizzing ships First Letter of the Answer, Sequence, Multi Tap, Nearest Wins
and Wordsnake. We had Sequence (ordering) and Nearest Wins (closest-call);
**First Letter of the Answer now ships too.** Multi Tap and Wordsnake remain
deliberately unbuilt — both are free-text word games, and our answer surface is
multiple choice on every client (see §3).

The host themes a round on a letter and every answer in it begins with that
letter. The RULE is a pure function written once per stack
(`Core/Models/LiveLetterRound.swift`, `Tidbits.Core/Networking/LiveLetterRound.cs`),
pinned by the SAME cases on both — 12 Swift tests, 13 C# tests.

**The judgement calls ARE the feature**, because six stacks have to agree on which
answers count as a "B" and a host cannot re-litigate it mid-night:

- **Leading articles do not count.** A pub quiz that announces "B" accepts "The
  Beatles", and a host who has to explain otherwise has lost the room.
- **Diacritics fold.** The host says "E" and the room writes E, so an accented
  Édith is an E. Comparing raw characters would put É in a bucket of its own and
  silently drop the question from every letter.
- **First LETTER, not first character.** "'Round Midnight" is an R; "2001" is not
  any letter at all and so belongs to no round.
- **A repeated ANSWER is never offered twice** — a round that asks for the same
  answer twice reads as a mistake even when both questions are fair.

A FLAG on the round, not a GameMode — the same reasoning as G1's `isBuzz`: it
constrains which questions a round may HOLD, not what a question IS, and GameMode
is a wire enum both stacks pin with goldens.

The builder NAMES the answers that break the theme rather than refusing the edit.
A half-built round is a normal state to be in mid-build, and a format that fights
the host is a format they abandon.

Measured against the real corpus rather than assumed: every letter A-Z can fill a
round (thinnest is X at 67 distinct answers, Q at 99), so no letter is greyed out.
Eight rows have non-Latin initials (Æ Ł Α Γ); they are excluded from every letter
rather than mis-bucketed, which is the correct failure.

The joiners render the banner from `pub.letter` so a player who joined MID-ROUND
still knows the rule instead of relying on having heard the host say it once.

### G5. Pick-a-category board — CLOSED 2026-09-02, all six platforms
QuizXpress supports Jeopardy-style rounds where players choose subject and
difficulty. **Tidbits now does too** — and it is the first format here where the
ROOM chooses what to play next; every other one marches through a list the host
fixed in advance.

Categories across, point tiers down. The rule is a pure value plus pure
transitions written once per stack (`Core/Models/LiveBoard.swift`,
`Tidbits.Core/Networking/LiveBoard.cs`), pinned by the same 12 cases on both.

**The judgement calls are the contract**, because each one decides whether a
night stalls in front of a room:

- **An unfillable cell is ABSENT, not a dead button.** A board with a cell
  nothing can fill is worse than a smaller board: the room picks it, the host has
  nothing to read, and the night stops in front of everyone.
- **Points come from the TIER, not the question.** The room sees what it is
  risking before it picks, and a later difficulty edit cannot move the board's
  promise.
- **A second click on one tile is refused.** Two host clicks must not advance the
  night twice.
- **The pick goes to the team that answered correctly, else it ROTATES.** Left
  alone it stays put and one table drives the whole board.
- **A played cell goes quiet IN PLACE.** The room reads the board as a map of
  what is left; a grid that reflows on every pick makes them re-find their column.

**Filling a board asks the corpus PER CELL.** Building from a category-level
sample is how a grid comes back with holes — a thin tier like business at 500 is
~1.5% of its own category. That trap appeared three separate times (the macOS
builder, a Windows test, the Windows builder) before it was closed in all three.

**`board` is a distinct wire Phase, not a flag.** While the grid is up there is
no live question, and publishing the previous one left it on every phone with its
answer buttons live — the room could answer a question that was no longer being
asked, and the host would score it. `pub.board` carries display names, tiers, a
positional taken list, the chooser and the totals, and deliberately NEVER the
cells' question ids: that would hand the room a map of the night's content.

Worth recording about the process: four bugs in this feature, and **not one was
found by a passing unit test**. Three came from rendering the screen and looking
at it — twice after the tests were already green — and the fourth from asking
what the OTHER clients were showing while the host's screen was correct.

### G6. No phone remote for the host  *(QuizXpress)*
QuizXpress drives the show from a presenter remote or a phone app, so the host can
walk the room. Tidbits' cockpit is keyboard + mouse at the laptop. We already have
the whole phone-join transport (`live/{code}`), so a host-role client is a
smaller job than it looks.

### G7. Several phones, one team — CLOSED 2026-09-03
Crowdpurr has an explicit team-leader model — one device answers for a physically
grouped team.

**This entry was filed against the wrong failure.** It described "a table of six
with one phone", and that case already worked: one phone joins, one phone is the
team. The break is the opposite one. Three friends at a table each open the app,
each becomes a separate team, and their night is split three ways across three
near-identical standings rows. Worth recording, because the scan sent me looking
for the wrong thing until I read what the code actually did.

The rule is a pure function written once per stack (`Core/Models/LiveTeamRoster.swift`,
`Tidbits.Core/Networking/LiveTeamRoster.cs`, plus JS and Kotlin ports), 15 Swift
and 15 C# tests on the same cases.

**The judgement calls:**

- **The same name typed differently is ONE team** — fold surrounding space, case,
  and runs of whitespace.
- **Punctuation is NOT folded.** "St. Elmo" and "St Elmo" stay two teams. Merging
  is destructive in a way splitting is not: a host can merge two rows, but cannot
  un-merge a night's scoring.
- **The display name is the LEADER's spelling.** A later joiner does not restyle
  the row the table already has.
- **The first answer by SERVER stamp stands.** A teammate cannot overwrite it —
  otherwise the loudest phone at the table wins, or a team changes its mind after
  watching the tally move.
- **A same-millisecond join breaks on uid.** Two phones can be stamped the same
  ms, and without it the leader — and so whose answer counts — would differ by
  stack and by run.
- **The leader leaving promotes the next member.** A table does not stop playing
  because one person went to the bar.
- **A uid the host has no join record for still scores for itself.** That is a
  device whose answer landed before its join did, and losing a real answer is
  worse than the duplicate the rule guards against.

**The wire needed no change.** `live/{code}/teams` already carried name and
joinedAt keyed by uid — which IS a roster member — and every client already read
that node for the night-end co-player capture. The only real gap was Android's
`liveTeams`, which read uid and name but not joinedAt, so it could not pick the
leader's spelling deterministically.

**The pattern worth carrying, because it produced four separate bugs:** when a
row stops being one thing and becomes a group, every count and lookup keyed on
its id changes meaning, and **none of them fail loudly**. In order: both hosts
awarded a table twice (and penalised it twice under negative marking) because
scoring walked answers per uid; the standings listed devices; the cockpit's
per-team answer lookup used the leader's uid and reported "no answer" for a table
whose second phone had submitted; and "N answered" counted devices, so a host
watching for "everyone is in" would read 3 from one table of three phones and
move on while two tables were still thinking.

Join surfaces (tap your table, showing its size, filling the leader's spelling)
ship on iOS, Android, web and Windows — every client where a player types a team
name.

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
