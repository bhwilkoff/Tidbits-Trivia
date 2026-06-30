# Google Play Listing — Tidbits Trivia (Android)

Paste-ready. Update here first, every release.

- **Play package (`applicationId`)**: `com.tidbitstrivia.app` · code namespace stays `com.learningischange.tidbitstrivia`
- **Pushed via API**: title, short/full description, and phone screenshots (`tools/push-play-content.py`); Data safety = no data collected. Content rating / target audience / privacy policy URL remain Console-only.
- **Category**: Trivia · **Tags**: trivia, quiz, education
- **Content rating**: Everyone (general-knowledge questions)
- **Price**: Free · **In-app purchases**: none (v1) · **Ads**: none
- **Privacy Policy URL**: `<GitHub Pages URL>/privacy.html`
- **Data Safety**: No data collected, no data shared (no account, no analytics)

## App name (≤30 chars)
`Tidbits: Wikipedia Trivia` (25)

## Short description (≤80 chars)
`Real trivia from all of Wikipedia. Play the daily, learn a fact, keep a streak.`

## Full description (≤4000 chars)
Tidbits turns the whole of Wikipedia into a trivia game — and unlike most quiz
apps, every question is built from real, sourced facts, with a "learn the fact"
card after each one so you walk away knowing something new.

WHY TIDBITS IS DIFFERENT
• Real facts, not recycled questions. Over 11,000 questions, generated and
  fact-checked from Wikipedia and Wikidata — and they never repeat until you've
  seen them all.
• 22 kinds of questions. Identify a subject from a clue, fill in the blank, put
  events in order, find the odd one out, pick the biggest or the earliest, and
  more. The variety keeps you thinking, not pattern-matching.
• Learn as you play. Every question ends with the fact and a link to read more.
  Miss one? It quietly comes back later, so the game teaches as it tests.

WAYS TO PLAY
• Daily Tidbit — the same seven questions for everyone, every day. Build a
  streak.
• Classic, Time Attack, and Survival modes.
• Eight categories: History, Science, Geography, Arts & Lit, Film & TV, Music,
  Sports, and a Mixed Bag.
• Create a quiz from ANY topic — type "jazz" or "volcanoes" or your hometown and
  Tidbits builds a quiz from Wikipedia on the spot.

BUILT TO RESPECT YOU
• Works fully offline — the question bank lives on your device.
• No ads. No energy meters. No "pay to keep your streak." No dark patterns.
• Free. The goal is to make you a little more curious, not to farm your
  attention.

Tidbits is also on the web, iPhone, iPad, and Apple TV — same game everywhere.

## Release notes (v1.0)
First release — thousands of Wikipedia-built questions, the Daily Tidbit, four
modes, eight categories, and create-a-quiz from any topic. Learn something every
day.

## Graphic assets needed (see branding/)
- App icon: 512×512 (32-bit PNG)
- Feature graphic: 1024×500
- Phone screenshots: 2–8, 16:9 or 9:16
- (Optional) 7" / 10" tablet screenshots

## Pre-launch reminders
- Personal account → closed test, 12+ testers, 14 days before production.
- Verify the AAB signer fingerprint vs assetlinks before upload (App Links).
- `versionName` stays in lockstep with the iOS marketing version; bump
  `versionCode` every upload.
