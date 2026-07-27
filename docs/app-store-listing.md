# App Store Listing — Tidbits Trivia (iOS / iPadOS / tvOS)

Paste-ready. The human pastes these into App Store Connect — never composes in
the console. Update here first, every release.

- **Bundle ID**: `com.learningischange.tidbitstrivia`
- **Primary category**: Games → Trivia · **Secondary**: Education
- **Age rating**: 4+ (no objectionable content; questions are general-knowledge)
- **Price**: Free · **In-app purchases**: Tidbits Club — $3.99/mo, $29.99/yr, or $79.99 lifetime Founding Member (see `docs/CLUB-MARKETING.md`)
- **Copyright**: © 2026 Learning Is Change
- **Support URL**: `https://tidbitstrivia.com/support.html`
- **Marketing URL**: `https://tidbitstrivia.com/`
- **Privacy Policy URL**: `https://tidbitstrivia.com/privacy.html`
- **License Agreement (EULA)**: `https://tidbitstrivia.com/terms.html` (custom EULA; auto-renew terms + per-store cancel)
- **App Privacy**: The full game collects nothing. Three OPTIONAL features collect data, all Linked + App-Functionality, NEVER tracking: sign-in (Name, User ID), leaderboards (game stats → "Other Data"), Tidbits Club (Email Address, stored as a one-way hash). Must match `PrivacyInfo.xcprivacy` + privacy.html (2026-07-23 IAP-compliance pass).

### EULA setup is PER-PLATFORM App Store Connect app record — verify on EVERY platform

**Ratchet (2026-07-25)**: tvOS was rejected — "offers auto-renewable
subscriptions but does not include a functional link to the Terms of Use
(EULA) in the app's metadata" — even though macOS's identical listing had
already passed review. This is because each Apple platform (iOS, tvOS,
macOS) has its OWN separate App Store Connect app record with its OWN
"License Agreement" setting under **App Information** — it is NOT
inherited from another platform's record, and defaults to Apple's
Standard EULA (no custom link) until explicitly changed. Passing on one
platform is not evidence the others are configured.

**Fix, required on EVERY Apple platform's App Store Connect record**
(App Store Connect → the platform's app → **App Information** → scroll to
**License Agreement**):
1. Select **Custom License Agreement** (not "Apple's Standard EULA").
2. Paste the full text of `terms.html` (App Store Connect wants the
   agreement TEXT in this field, not just a URL — copy the rendered page
   text, or paste the URL if the field accepts a link; check which the
   current UI offers and use the same approach the working macOS/iOS
   records already use, so all platforms stay identical).
3. Save, then re-submit the affected platform's build for review.

Do this for tvOS now (the active rejection), and audit iOS + macOS to
confirm both actually have it set (don't assume from "macOS passed" —
verify directly in App Store Connect, since a reviewer not flagging it
this pass isn't proof it's configured).

**Ratchet (2026-07-27): Guideline 2.1(a) — tvOS Settings, "no action
occurred when we tapped to sign in with Sign in with Apple."** Root
cause was architectural, not a one-line bug: `SettingsView_tvOS` was the
ONLY tvOS screen using system `Form`/`List`/`NavigationStack` instead of
this app's hand-rolled `TVTheme`/`TVRecordsCard`/custom-`ButtonStyle`
idiom every other tvOS screen uses — the SwiftUI `SignInWithAppleButton`
(which wraps a UIKit `ASAuthorizationAppleIDButton` in a representable)
embedded in a `Form` row can have its Siri Remote select click swallowed
by the row's own selection handling, and the `onCompletion` handler only
matched `.success`, so a failed/cancelled auth (very plausible on a
review device without an Apple ID signed into the TV) failed completely
silently — indistinguishable from "nothing happened" either way. Fixed
by rebuilding the page from scratch in the app's real tvOS idiom (no
Form/List/NavigationStack) and replacing the SwiftUI wrapper with a
plain `Button` that drives `ASAuthorizationController` directly via a
coordinator (`TVAppleSignInCoordinator`), handling BOTH success and
failure and surfacing `identity.authError` visibly (mirroring the
already-correct macOS `SettingsView_macOS` pattern, which iOS's
`ProfileView` was ALSO missing — worth the same fix there if iOS ever
sees a similar report). Also fixed the reported "dark text on dark
background" / "looks like a webpage" complaint as part of the same
rewrite (explicit `TVTheme.text`/`textSoft` everywhere, never inherited
`.primary`/`.secondary`), and made signed-in vs signed-out an
unmistakable visual difference (a filled mint checkmark-seal badge vs.
the real white Apple-HIG sign-in pill) per the reviewer's own note.
`TIDBITS_SETTINGS=1` env hook added for headless-simulator screenshot
verification (this dev box has no GUI Simulator window).

## App Name (≤30 chars)
`Tidbits: Wikipedia Trivia` (25)

## Subtitle (≤30 chars)
`Learn something every day` (25)

## Promotional text (≤170 chars)
Real trivia built from Wikipedia — thousands of questions across history,
science, geography, the arts and more. Play the daily, keep your streak, learn
as you go.

## Keywords (≤100 chars, comma-separated, no spaces)
`trivia,quiz,wikipedia,daily,knowledge,learning,history,science,geography,brain,facts,questions,party`

## Description (≤4000 chars)
Tidbits turns the whole of Wikipedia into a trivia game — and unlike most quiz
apps, every question is built from real, sourced facts, with a "learn the fact"
card after each one so you walk away knowing something new.

WHY TIDBITS IS DIFFERENT
• Real facts, not recycled questions. Over 100,000 questions, generated and
  fact-checked from Wikipedia and Wikidata — and they never repeat until you've
  seen them all.
• 22 kinds of questions. Not just "which of these is right" — identify the
  subject from a clue, fill in the blank, put events in order, find the odd one
  out, pick the biggest or the earliest, and more. The variety keeps you
  thinking, not pattern-matching.
• Learn as you play. Every question ends with the fact and a link to read more.
  Miss one? It quietly comes back later, so the game teaches as it tests.

WAYS TO PLAY
• Daily Tidbit — the same seven questions for everyone, every day. Build a
  streak.
• Classic, Time Attack, and Survival modes.
• Eight categories: History, Science, Geography, Arts & Lit, Film & TV, Music,
  Sports, and a Mixed Bag.
• Pass & Play — hand the phone around for 2–4 player trivia night, no second
  device needed.
• Create a quiz from ANY topic — type "jazz" or "volcanoes" or your hometown and
  Tidbits builds a quiz from Wikipedia on the spot.

BUILT TO RESPECT YOU
• Works fully offline — the question bank lives on your device.
• No ads. No energy meters. No "pay to keep your streak." No dark patterns.
• The full game is free — every question, every mode.

TIDBITS CLUB (optional)
Go deeper with an optional membership: Ranked Seasons, a Knowledge Atlas that
maps what you know by domain, a Story Archive of every fact you've learned, and
multi-week Expeditions. Buy once — you're a member on every device you sign in
on. Monthly, yearly, or a one-time Founding Member purchase. The core game
always stays free.

Tidbits is also on the web, Apple TV, Mac, Windows, and Android — same game,
your streak and favorites at home on each.

## What's New (v1.0)
The first release of Tidbits — thousands of Wikipedia-built questions, the Daily
Tidbit, four modes, nine categories, pass-and-play trivia night, and
create-a-quiz from any topic. Learn something every day.

## tvOS notes
Same listing; add the **Top Shelf image** (1920×720 / 2320×720) and the
**layered App Icon** (landscape layers — square fails actool on clean builds).
Apple TV screenshots are 3840×2160.
