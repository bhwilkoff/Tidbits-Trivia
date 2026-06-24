# Game Center — Setup & Wiring (full field reference)

Everything needed to stand up Game Center in App Store Connect (ASC). The code
side is **done and shipping**; this doc is the owner checklist — every field,
every ID, and which image goes where. **IDs must match
`Core/Services/GameCenterManager.swift` verbatim (case-sensitive).**

All images live in `tools/branding/gamecenter/` (regenerate with
`tools/branding/make_leaderboard.py` + `make_achievements.py`). Every image is
**512×512, RGB, no transparency** — exactly Apple's spec.

---

## 0. What the app already does (code — done)

- Entitlement `com.apple.developer.game-center`.
- Authentication at launch, and it **presents the sign-in sheet** when needed.
- **Leaderboards** submitted on game-end (classic high + daily streak).
- **9 achievements** reported from the shared `RecordsStore`.
- **Dashboard** (Settings → "Leaderboards & Achievements") + **access point**
  (shown on menus, hidden in a game).
- **Challenges**: the app registers a challenge listener and, when a player taps
  "Play" on a challenge, launches Classic. (Enable "challengeable" in ASC — §4.)

All safe no-ops until a player authenticates.

---

## 1. Xcode capability (once)

Target **TidbitsTrivia** → **Signing & Capabilities** → confirm **Game Center**
is listed (reads from the entitlement). Archive once so it registers on the App
ID. The same config serves **iOS and tvOS** (one App ID, Decision 013).

---

## 2. Leaderboards (×2)

ASC → app → **Features → Game Center → Leaderboards → +**. For each, four screens:

### Screen flow (same for both)
| Screen | Field | Value |
|---|---|---|
| Choose Type | — | **Classic Leaderboard** |
| Add Leaderboard | Reference Name | (internal — see table) |
| | **Leaderboard ID** | (exact — see table) |
| Choose Score Format | Score Format | **Integer (1, 100, 0, -5, 999)** |
| | Score Range | leave blank |
| | Score Submission Type | **Best Score** |
| | Sort Order | **High to Low** ⚠️ (defaults to Low to High — change it) |

### The two leaderboards
| Reference Name | **Leaderboard ID** | Localization Display Name | Score Format Suffix | Image |
|---|---|---|---|---|
| Classic High Score | `tidbits.classic.high` | `Classic High Score` | `points` | `leaderboard-classic-high.png` (star) |
| Daily Streak | `tidbits.daily.streak` | `Longest Daily Streak` | `days` | `leaderboard-daily-streak.png` (bolt) |

### Leaderboard Localization (required — at least English)
After Create, add a localization (**English (U.S.)**):
| Field | Classic High Score | Daily Streak |
|---|---|---|
| Display Name (≤30) | `Classic High Score` | `Longest Daily Streak` |
| Description (≤120) | `Your best single Classic-mode score.` | `Your longest run of consecutive Daily Tidbits.` |
| Score Format Suffix (≤15) | `points` | `days` |
| Score Format | Integer | Integer |
| Image (512×512) | `leaderboard-classic-high.png` | `leaderboard-daily-streak.png` |

---

## 3. Achievements (×9)

ASC → **Features → Game Center → Achievements → +**. Per achievement: a create
step, then an English localization. **Points total = 285** (Apple's cap is 1000).

### Create-step fields (per row)
- **Reference Name** (internal) · **Achievement ID** (exact) · **Point Value**
- **Hidden**: No (all visible) · **Achievable More Than Once**: No

| Reference Name | **Achievement ID** | Points | Image |
|---|---|---|---|
| First Tidbit | `tidbits.ach.firstgame` | 10 | `ach-firstgame.png` (sparkle) |
| Flawless | `tidbits.ach.perfect` | 25 | `ach-perfect.png` (check) |
| Centurion | `tidbits.ach.century` | 25 | `ach-century.png` (diamond) |
| On a Roll | `tidbits.ach.streak7` | 25 | `ach-streak7.png` (flame) |
| Devoted | `tidbits.ach.streak30` | 50 | `ach-streak30.png` (crown) |
| Renaissance | `tidbits.ach.fullpie` | 50 | `ach-fullpie.png` (pie) |
| Sharpshooter | `tidbits.ach.sharp` | 25 | `ach-sharp.png` (target) |
| Explorer | `tidbits.ach.explorer` | 25 | `ach-explorer.png` (arrow) |
| Scholar | `tidbits.ach.scholar` | 50 | `ach-scholar.png` (book) |

### Achievement Localization (English (U.S.), per achievement)
| ID | Title (≤30) | Pre-earned Description (≤120) | Earned Description (≤120) |
|---|---|---|---|
| `tidbits.ach.firstgame` | `First Tidbit` | `Play your first game.` | `You played your first game.` |
| `tidbits.ach.perfect` | `Flawless` | `Finish a round of 7+ questions with 100% accuracy.` | `A perfect round — every answer right.` |
| `tidbits.ach.century` | `Centurion` | `Answer 100 questions correctly.` | `100 correct answers and counting.` |
| `tidbits.ach.streak7` | `On a Roll` | `Keep a 7-day daily streak.` | `Seven days in a row.` |
| `tidbits.ach.streak30` | `Devoted` | `Keep a 30-day daily streak.` | `Thirty days in a row — devoted.` |
| `tidbits.ach.fullpie` | `Renaissance` | `Earn a knowledge wedge in all seven domains.` | `A full pie — mastery across every domain.` |
| `tidbits.ach.sharp` | `Sharpshooter` | `Win a Stake round where every confidence chip lands.` | `Perfectly calibrated — every chip landed.` |
| `tidbits.ach.explorer` | `Explorer` | `Play ten different game modes.` | `Ten modes explored.` |
| `tidbits.ach.scholar` | `Scholar` | `Answer 1,000 questions correctly.` | `1,000 correct — a true scholar.` |

Each localization also needs the **512×512 image** from the table above.
`century`, `scholar`, `streak7`, `streak30`, `fullpie`, and `explorer` report
**partial progress** (they fill gradually); the rest unlock at 100%.

---

## 4. Challenges (enable — no extra screens)

Game Center Challenges (iOS 26) let friends challenge each other to beat a
leaderboard score or earn an achievement, async with a deadline. **The app code
is done** (it listens for challenge events and launches Classic when a challenge
is played). To turn it on:

- On each **leaderboard** and **achievement** in ASC, set it as
  **challengeable / "Enable challenges"** (the toggle in the leaderboard/
  achievement settings). That's the whole config — Apple's system UI handles
  creating, sending, and tracking the challenges.
- No separate "Challenges" section to fill out; it rides the boards/achievements
  you already created above.

---

## 5. Activities — deferred (not now)

Game Center "play together" **Activities** are a Game-Center-mediated multiplayer
matchmaking surface. We're **skipping it for launch**: Tidbits' multiplayer is
the local **Bonjour buzzer** (offline-first) plus a planned **Supabase**
cross-platform layer (Decision 020/023) — Activities would fork that story and is
Apple-only (no web/Android reach). Revisit only if a Game-Center-native "find a
remote opponent" entry point is wanted later. No ASC config, no code.

---

## 6. Test with a Sandbox account

1. Device **Settings → Game Center** → sign in with a **Sandbox Apple ID** (ASC →
   Users and Access → Sandbox), or use a TestFlight build.
2. Launch the app — the sign-in sheet appears; the access point badge shows on
   the home screen.
3. Play a Classic + a Daily → Settings → "Leaderboards & Achievements" → confirm
   the score posted and "First Tidbit" unlocked.
4. Reset test state via leaderboard score deletion in ASC /
   `GKAchievement.resetAchievements()`.

---

## 7. Image manifest (`tools/branding/gamecenter/`)

| File | Used for | Mark |
|---|---|---|
| `leaderboard-classic-high.png` | LB `tidbits.classic.high` | star |
| `leaderboard-daily-streak.png` | LB `tidbits.daily.streak` | lightning bolt |
| `ach-firstgame.png` | First Tidbit | sparkle |
| `ach-perfect.png` | Flawless | check |
| `ach-century.png` | Centurion | diamond |
| `ach-streak7.png` | On a Roll | flame |
| `ach-streak30.png` | Devoted | crown |
| `ach-fullpie.png` | Renaissance | pie |
| `ach-sharp.png` | Sharpshooter | target |
| `ach-explorer.png` | Explorer | arrow |
| `ach-scholar.png` | Scholar | book |

All are the app icon with the period swapped for the mark — 512×512 RGB, no alpha.

---

## Gotchas

- **#1 failure mode is an ID typo** between ASC and the code — exact, case-sensitive.
- Leaderboard/achievement config goes live **with the app version's review**;
  in Sandbox/TestFlight it works before release.
- Android has **no Game Center** (Google Play Games is the future analog) — these
  are Apple-only in `PARITY.md`.
