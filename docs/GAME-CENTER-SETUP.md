# Game Center — Setup & Wiring Checklist

What the app already does in code, and the App Store Connect (ASC) + Xcode steps
**you** must do so the leaderboards and achievements actually appear. The IDs
below must match `Core/Services/GameCenterManager.swift` **verbatim**.

## What the app already does (code — done)

- **Entitlement**: `com.apple.developer.game-center` (TidbitsTrivia.entitlements).
- **Authentication** at launch (`GameCenterManager.authenticate()`), and it now
  **presents the sign-in sheet** GameKit hands back when the player isn't signed
  in (iOS + tvOS).
- **Leaderboard submission** on game-end (shared `RecordsStore`):
  - Classic high score → `tidbits.classic.high`
  - Daily streak → `tidbits.daily.streak`
- **Achievement reporting** on game-end (derived from the player's records):
  - `tidbits.ach.firstgame`, `tidbits.ach.perfect`, `tidbits.ach.century`,
    `tidbits.ach.streak7`, `tidbits.ach.streak30`, `tidbits.ach.fullpie`,
    `tidbits.ach.sharp`.
- **Dashboard**: Settings → "Leaderboards & Achievements" opens the Game Center
  dashboard; the **access point** badge shows on menus and hides during a game.

All of the above are **safe no-ops until the player authenticates**, which can't
happen until the steps below are complete in ASC.

## Step 1 — Xcode capability (once)

Automatic signing usually adds this on first archive, but confirm:
1. Xcode → target **TidbitsTrivia** → **Signing & Capabilities**.
2. Ensure **Game Center** is listed (it reads from the entitlement). If not,
   **+ Capability → Game Center**.
3. Archive once so Xcode registers the capability on the App ID in the developer
   portal.

## Step 2 — Create the leaderboards in App Store Connect

ASC → your app → **Features → Game Center → Leaderboards → +**. Create two
**Classic** leaderboards. The **Leaderboard ID** field MUST equal the id exactly.

| Leaderboard ID | Reference name | Score format | Sort | Notes |
|---|---|---|---|---|
| `tidbits.classic.high` | Classic High Score | Integer | High to Low | Best single Classic-mode score |
| `tidbits.daily.streak` | Daily Streak | Integer | High to Low | Longest current daily streak |

For each: add at least one localization (English) with a display name + score
format suffix (e.g. "points", "days"), and an image (512×512, required by review).

## Step 3 — Create the achievements

ASC → **Features → Game Center → Achievements → +**. The **Achievement ID** MUST
equal the id exactly. Points across all achievements must total ≤ 1000.

| Achievement ID | Title | Description | Points | Hidden |
|---|---|---|---|---|
| `tidbits.ach.firstgame` | First Tidbit | Play your first game. | 10 | No |
| `tidbits.ach.perfect` | Flawless | Finish a round of 7+ questions with 100% accuracy. | 25 | No |
| `tidbits.ach.century` | Centurion | Answer 100 questions correctly. | 25 | No |
| `tidbits.ach.streak7` | On a Roll | Keep a 7-day daily streak. | 25 | No |
| `tidbits.ach.streak30` | Devoted | Keep a 30-day daily streak. | 50 | No |
| `tidbits.ach.fullpie` | Renaissance | Earn a knowledge wedge in all seven domains. | 50 | No |
| `tidbits.ach.sharp` | Sharpshooter | Win a Stake round where every confidence chip landed. | 25 | No |

`century`, `streak7`, `streak30`, and `fullpie` report **partial progress**, so
they fill gradually; the others unlock at 100%. Each needs an English
localization (title + both pre/earned descriptions) and a 512×512 image.

## Step 4 — Test with a Sandbox account

1. On the device: **Settings → Game Center** → sign in with a **Sandbox Apple
   ID** (created in ASC → Users and Access → Sandbox), or use a TestFlight build
   (TestFlight uses the production Game Center, sandbox for unreleased config).
2. Launch the app — the Game Center sign-in sheet should appear; the access
   point badge appears on the home screen.
3. Play a Classic game and a Daily → open Settings → "Leaderboards &
   Achievements" → confirm your score posted and "First Tidbit" unlocked.
4. `GKAchievement.resetAchievements()` / leaderboard score deletion in ASC reset
   test state.

## Notes / gotchas

- **Leaderboard/achievement config is per-app and reviewed with the build** — it
  goes live when the app version is approved. In sandbox/TestFlight it works
  before release.
- The **same Game Center config serves iOS AND tvOS** (one App ID, Decision 013)
  — no separate setup for the TV app.
- If a score/achievement doesn't appear: the #1 cause is an **ID mismatch**
  between ASC and `GameCenterManager` — they are case-sensitive and exact.
- Android has **no Game Center** (it would use Google Play Games later) — these
  rows are Apple-only in `PARITY.md`.
