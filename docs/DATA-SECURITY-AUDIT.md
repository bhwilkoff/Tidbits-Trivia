# Data security audit — who can read what

**Audited 2026-09-10** after the owner asked: *"No person/team should know what
anyone else has responded with, nor should they ever know the right answer
before it is revealed."* Re-prove any change with `python3 tools/rules_probe.py`,
which checks 23 reads and writes against the **deployed** rules and exits
non-zero if one misbehaves. A rules file in the repo is not a rules file in
production.

## The one mistake that caused all of it

**An RTDB `.read` granted at a container cascades to every descendant and cannot
be revoked deeper.** A single `auth != null` on a room root therefore hands every
signed-in player everything under it. That is how, before this audit, any pub
table could read every other table's answers *and* the host's phone-remote PIN.

Grant reads on the specific children that are public. Where a client needs one
field of a private node, grant that leaf — reads cascade **down, never up**, which
is why `control/id` can be readable while `control` is not.

## Every root

| Root | Read | Why |
|---|---|---|
| `live/$code` | **no root read** | the container is private; each child grants its own |
| `live/$code/meta`, `pub`, `scores`, `teams`, `media` | any signed-in player | this is what the room *is* — the question, the standings, the roster, the host's clip |
| `live/$code/answers` | **host only** | the host streams every submission to score |
| `live/$code/answers/$qid/$uid` | that table only | a table may see what it said, and nothing else |
| `live/$code/control` | **host only** | it carries the phone remote's **PIN** — the keys to the show |
| `live/$code/control/id` | any signed-in player | a remote resumes its command counter; the PIN stays hidden |
| `duels/$id` | **the two named players only** | the node carries the question set *with its answers* |
| `playersPrivate/$uid`, `pushTokens/$uid`, `dailyLog/$key` | owner only | private by construction |
| `entitlements/$key` | verified owner only | purchase state |
| `emailOwners/$key` | **nobody** | no `.read` at all; rules still evaluate it server-side, so email addresses never leave |
| `players/$key` | any signed-in player | the portable public profile — name, avatar, rating |
| `dailyBoard`, `standings`, `quizzes/$id` | public | leaderboards and shared-quiz links, public by design |
| `rooms/$roomId`, `queue` | any signed-in player | a player must read a Quick Match room *before* deciding to join it |

## What the rules cannot fix, and why that is still safe

**A live event is host-scored, and this is the strong guarantee:** the correct
answer is never sent to any player before the reveal. Not hidden in the page —
never sent. Verified by sweeping a real web joiner mid-question (DOM,
localStorage, sessionStorage, every `window` global, the resource list, and the
room read with the joiner's own credentials) and finding nothing, then revealing
and finding it — see `scratchpad/e2e_leak.py` and LIVE-ROOM-CONTRACT.

**The self-scored modes are different, and honestly so.** An async duel, a Quick
Match and a shared quiz are scored *on the device*, because there is no server to
score them (Decision: $0 ongoing cost, serverless). The questions therefore reach
the device with their answers, and a determined player with developer tools could
read them early. The rules narrow *who* gets that payload — a duel is now readable
only by its two players — but they cannot put an answer on a device and
simultaneously keep it from that device. Closing that gap needs server-side
scoring, which is a product decision with a running cost, not a rules change.

Quick Match rooms stay readable by any signed-in player on purpose: a player is
handed a room id by the queue and must read the room to decide whether to join,
before they are in its roster.

## Known coverage gap

The duel read rule was proven with real participant tokens against the live
database, exercising the same REST reads the apps make. The **in-app** duel flow
was not re-driven on a device afterwards, because duels have never had a fleet
harness or a launch hook. Worth adding before the next change to that rule.
