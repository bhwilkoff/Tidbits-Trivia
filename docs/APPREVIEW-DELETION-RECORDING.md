# App Review 5.1.1(v) — the account-deletion screen recording

App Review asked for this by name when they rejected tvOS 1.6.52 (96):

> reply to this message with a screen recording **captured on a physical device**
> that demonstrates:
> - Creating a new account or signing in with the demo account
> - Navigating to the account deletion option
> - The complete account deletion flow from initiation to confirmation

Three constraints make this an owner task, not an automatable one:

1. **Physical device.** They said it explicitly. A simulator capture is a
   known-weak substitute and invites a second round trip.
2. **tvOS.** The rejection is on the tvOS submission. macOS/iOS recordings show
   the same shared `PlayerIdentityStore.deleteAccount()`, but they are not the
   binary under review.
3. **The sign-in leg needs real credentials.** Only you can enter them.

Record it once on an Apple TV and it also covers any future iOS/macOS ask,
because the flow and the copy are identical across all three.

---

## Before you start

- Apple TV signed in to your Apple Account, running **1.6.59 (99)** from
  TestFlight (this is the build with Delete Account).
- **Use a throwaway Apple ID for the sign-in leg**, not your personal one — the
  recording ends by permanently deleting whatever account you sign in with.
- Capture: **QuickTime → File → New Movie Recording**, pick the Apple TV as the
  camera source (tvOS AirPlay-to-Mac recording), or point a phone at the TV.
  Either satisfies "captured on a physical device".
- Target length: about **90 seconds**. Do not narrate; App Review just needs to
  see the taps.

---

## The shot list

| # | What to do | What must be visible on screen |
|---|---|---|
| 1 | Launch Tidbits from the tvOS home screen | The app opening cold, so it's clearly the real build |
| 2 | Home → **Settings** (top right) | The Settings screen, **Profile** section at the top |
| 3 | Select **Sign in with Apple**, complete it with the throwaway ID | The Apple sign-in sheet, then the mint **"Signed in — records sync to every device"** badge. *This is the "creating an account" leg.* |
| 4 | Pause ~2 seconds on the signed-in profile | The player name, rating and streak — proof an account exists with data |
| 5 | Move focus down to **Delete Account** | The red-outlined **Delete Account** button and the grey line under it: *"Permanently deletes your Tidbits account and all of its data — profile, rating, streak, Daily history, standings, and friends."* |
| 6 | Press select | The confirmation dialog: **"Delete your Tidbits account?"** with the full warning and **Delete Account / Cancel** |
| 7 | Choose **Delete Account** | The button showing **"Deleting…"** |
| 8 | Hold until it finishes (2–5 s) | The mint confirmation: **"Your account was deleted. This device is signed out and starting fresh."** |
| 9 | Pause ~3 seconds, then scroll up to Profile | The profile is now a **fresh anonymous player** and the **Sign in with Apple** button is back — the account is genuinely gone, not just hidden |

Step 9 is the one reviewers most often find missing. It is the difference
between "you dismissed a dialog" and "the account was deleted."

---

## Where to put it

App Store Connect → your tvOS version → **App Review Information → Notes**.
Attach the file (or paste a link to it) and add:

> Account deletion is at Settings → Profile → Delete Account, visible whether or
> not the player has signed in — Tidbits provisions a Firebase account for every
> player at first launch, so that account is deletable too. Deleting removes the
> player profile, Daily history, leaderboard standings, push token, friends list
> and the authentication record itself, then returns the app to a new anonymous
> session. The attached recording shows the full flow on an Apple TV.

Then reply to the rejection message in Resolution Center with the same text.

---

## What is already verified (you do not need to re-prove this)

Run against the **live** database on 2026-07-29, after the rules deploy:

- `players/{key}`, `dailyLog/{key}`, `playersPrivate/{uid}`, `pushTokens/{uid}`
  all delete and read back `null`.
- `accounts:delete` succeeds, and the refresh token afterwards returns
  **`USER_NOT_FOUND`** — the credential is genuinely dead, so no session can be
  resumed.
- The `emailOwners/$key` rule now permits an owner delete (a delete writes
  `null`, which the previous rule rejected).

The only thing missing is the video itself.
