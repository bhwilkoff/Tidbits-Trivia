# Tidbits as an iMessage game — feasibility

**Question:** can Tidbits be played inside a direct or group iMessage conversation?

**Answer: yes, and the fit is unusually good — but only for the async half of the
product.** The engine ports for free; the timing-based modes do not port at all; and
two hard platform limits (a 5,000-character state budget and extension memory) decide
the entire architecture. There is also one live iOS 26 bug worth watching.

Researched 2026-08-31. Nothing here is built.

---

## 1. Why the fit is good

An iMessage app is an extension that puts a view in the Messages drawer and can send
**updatable** messages. `MSSession` is the mechanism: send a message tied to a
session, and the next message in that session **replaces** the previous bubble rather
than appending — the transcript shows current game state, not a wall of turns
([MSSession](https://developer.apple.com/documentation/messages/mssession)).

That is precisely the shape of a Tidbits round:

- One question is live; everyone in the thread answers it.
- A new answer updates one bubble in place.
- The scoreboard is the bubble.

Group conversations are supported natively — a thread of eight people is the same API
as a thread of two.

## 2. The two limits that decide the design

### 2.1 All state must fit in 5,000 characters

An `MSMessage` carries its payload in `url`, and exceeding the cap throws
[`MSMessageErrorCode.urlExceedsMaxSize`](https://developer.apple.com/documentation/messages/msmessageerrorcode/urlexceedsmaxsize?language=objc).
The documented limit is **5,000 characters** (empirically ~5,114). There is no
server-free way around it — the constraint exists to keep messages end-to-end
encrypted.

**Implication: never put question text in the message.** Send question *ids* plus
answers-so-far, and let each device look the questions up locally. A 5-question round
with 8 players is comfortably inside budget when ids are the corpus keys
(`src:cloze:…` style) and answers are packed indices; it is nowhere near budget if
prompts and options ride along.

This also means the corpus must be present on **every** participant's device — which
is fine, because a participant without Tidbits installed sees a fallback bubble
inviting them to install (standard iMessage app behaviour).

### 2.2 The 50MB corpus cannot live in the extension

`corpus.sqlite` is **50MB**; `assets/corpus.json` is **49MB**. App extensions run
under far tighter memory ceilings than the host app, and Apple does not document the
iMessage figure — community reports put various extension types between ~24MB and
~120MB
([1](https://developer.apple.com/forums/thread/60706),
[2](https://blog.kulman.sk/dealing-with-memory-limits-in-app-extensions/)).

This project has already been bitten by exactly this class twice on Android
(`android-corpus-oom-play-rejection`, `android-eager-json-oom-vc85` — a Play rejection
traced to a 299MB heap peak, then a repeat from eagerly parsing JSON at boot). Do not
repeat it here.

**The workable path:**

- **SQLite, never JSON.** A 50MB SQLite file read page-by-page does not load 50MB into
  RAM; a 49MB JSON parse does. The Android OOM was precisely the JSON path.
- **Share via App Group, do not duplicate.** Putting `corpus.sqlite` in the extension
  bundle would add 50MB to the app download and give the extension its own copy. The
  host app should place it in the shared App Group container once; the extension opens
  it **read-only**.
- **Consider a curated subset.** A few thousand questions across the shapes that suit
  a message thread would cut the risk to near zero and is probably the right MVP.

## 3. What ports, and what does not

| Tidbits surface | iMessage | Why |
|---|---|---|
| Daily Tidbit (same 7 for everyone) | **Excellent** | A shared daily set in a group thread is the single best fit |
| Classic MCQ | **Excellent** | Tap an option, bubble updates |
| Closest Call (numeric) | **Good** | Async guessing needs no clock |
| This-or-That, Odd-One-Out, Picture ID | **Good** | Compact drawer handles a small option set |
| Ordering / Matching / Type-answer | **Workable** | Needs `.expanded` presentation, not the compact drawer |
| Trivia Night (rounds) | **Partial** | Round structure ports; host pacing does not |
| Time Attack, Survival, speed bonus | **No** | Extensions get **no background execution** — nothing can advance a timer while the thread sits idle |
| Live host cockpit / projector | **No** | Presenter-and-room model has no analogue in a transcript |

The dividing line is simple: **anything that requires the game to advance on its own
does not work.** A message-thread game advances only when a human taps.

## 4. Identity is opaque — plan for it

`MSConversation.remoteParticipantIdentifiers` returns per-conversation UUIDs, not
names or handles, and they are not stable across reinstalls. So:

- The scoreboard shows names players type, or nothing.
- Linking to the portable identity spine (`players/{uid}`, Elo, streaks) requires a
  sign-in **inside the extension**, which is heavy for a drawer UI.
- **Recommended MVP: thread-local scores only**, with sign-in explicitly out of scope.
  See `portable-identity-spine` for what would have to be wired to change that.

## 5. The interesting move: a front door, not an island

Trivia Night and Tidbits Live already share one RTDB room (`live/{code}`), and every
platform — including the web — now hosts and joins it (verified 2026-08-31).

An iMessage bubble could **carry that room code**. Then:

- iPhone friends play in the thread.
- Android and web friends open `tidbitstrivia.com/live/CODE` and join the *same* game.

That turns the iMessage app into a distribution surface for the existing
cross-platform backend rather than a seventh island to maintain. It also sidesteps the
5,000-character budget for anything ambitious: the message carries a code, and the
room carries the state.

## 5b. Two things that only surfaced on device

Both were invisible to any amount of local testing, and both are the kind of detail
that decides whether this works at all.

**`MSMessage.url` must be a universal link.** A custom scheme (`tidbits://round?…`)
is accepted at send time and then **silently stripped in transit** — the recipient's
message arrives with `url` nil. Nothing errors; the bubble renders perfectly with its
image, caption and scoreline, and every tap opens the start screen as though no round
were attached. Use an https URL on a domain the app claims as an associated domain
(`https://tidbitstrivia.com/r?…`), which also gives a thread member without the app a
working tap instead of a dead one.

**`insertMessage:` only stages; `sendMessage:` sends.** `insert` puts the message in
the Messages input field and the player must press the send arrow — five extra
deliberate sends per round each. `sendMessage:` (iOS 11+) sends directly, subject to
Apple's condition: *"The app must be visible and have had a recent touch interaction
since either last launch or last send"*, which tapping an answer satisfies. Note that
the secondary sources are **wrong** on this — they state programmatic sending is
impossible with "no workaround", describing iOS 10 before `sendMessage:` existed. The
SDK header contradicts them; read
`Messages.framework/Headers/MSConversation.h` rather than the articles.

A message per turn remains inherent — no server, no background execution, the message
IS the transport. `MSSession` is what keeps that to one updating bubble instead of one
per answer.

## 6. Risks

1. **Memory.** The top risk, with two prior incidents in this codebase. Mitigated by
   SQLite-via-App-Group and a curated subset.
2. ~~**iOS 26 relaunch bug.**~~ **RESOLVED 2026-09-01 — it does not affect this app.**
   Tested on a real iOS 26 iPad and iPhone: tapping the bubble opens the extension
   reliably, repeatedly. The forum report
   ([thread 799779](https://developer.apple.com/forums/thread/799779)) does not
   reproduce here. This was the risk that could have made the whole feature
   non-viable, and it is closed by evidence rather than by Apple confirming a fix.
3. **Apple's investment.** iMessage apps have received little attention since their
   iOS 10 launch. The framework is alive and shipping, but this is not a platform to
   bet a roadmap on.
4. **Review and assets.** The extension ships inside the existing iOS app (same
   submission), but needs its own iMessage icon set and Messages screenshots.

## 7. What it would actually cost

**Reused for free** — `Core/` is genuinely platform-agnostic: models, the shape-routing
engine, scoring, corpus access. Only two files import UIKit
(`Services/GameCenterManager.swift`, `Services/Haptics.swift`) and both are already
the kind of thing guarded per-platform.

**New work:**
- A Messages extension target (none exists today — the project is a single app target).
- `MSMessagesAppViewController` with compact + expanded presentations.
- A compact state codec for the 5,000-character budget, with a golden test — the wire
  format is a compatibility surface the moment two app versions are in one thread.
- App Group plumbing so the extension reads the corpus without duplicating it.
- An iMessage icon set and store screenshots.

**Suggested MVP:** Daily Tidbit in a thread — one shared set of 7, MCQ only,
thread-local scores, curated question subset. It exercises every hard part (session
updates, state codec, corpus access, group play) with none of the optional
complexity.

---

**Bottom line:** technically feasible and a natural extension of the async half of
Tidbits. The engine is free; the constraints are real but well understood; the honest
blocker to check first is the iOS 26 relaunch bug, because it breaks exactly the
interaction the whole idea rests on.
