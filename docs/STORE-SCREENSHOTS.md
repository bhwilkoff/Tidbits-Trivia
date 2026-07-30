# Store screenshots — what we show, and how we capture it

Binding for every store listing. Two halves: **§1 the screen set** (what earns a
slot and why) and **§2 the playbook** (how a capture run is driven end to end).

---

## §1 — The screen set

### R-SHOT-1: every screenshot shows a FREE feature

**No Club feature appears in any store screenshot on any platform.** Not the hub,
not Link Wall, not Marathon, not Expeditions, not the Knowledge Atlas, not the
Story Archive, and never the paywall.

*Why:* the same reasoning as R-CLUB-1 (iOS-DESIGN §5.2a). A store listing is the
first impression, and a shopper counts locks. Tidbits' actual pitch is *"the
world's best trivia app with the least amount behind a paywall"* — a listing that
leads with premium features tells the opposite story, and it is the story a
shopper believes before they ever install. The free game is the product; Club is
a layer some people buy later.

*How to apply:* capture with the Club flags OFF (never `TIDBITS_CLUB=1`) — the
capture script refuses to run if one is set. No Club *feature* may appear.

**One deliberate exception:** the Home shot shows the single quiet Club row,
because it is part of Home and cannot be scrolled out of a simulator capture.
That is acceptable — and arguably load-bearing — because the row's own copy is
*"Six optional extras for getting better. Everything else in Tidbits is free."*
It states the pitch rather than undermining it. A Club row is fine; a Club
*feature*, a lock icon, a CLUB chip or a price is not.

### R-SHOT-3: a store frame is never a random draw

**Gameplay screenshots use a screened, deterministic question set — never whatever
the corpus hands back.**

*Why:* a random draw put a Holocaust question into the Windows reveal slot — *"the
official Nazi code name for the murder of all Jews within reach"*, with three
other genocides as the wrong answers. That is the single most-viewed frame in a
listing. The corpus legitimately contains hard history; a marketing asset is not
where it belongs, and a random draw will surface it again eventually.

*How to apply:* the Windows renders (`StoreScreenshots.SafeQuestions`) exclude a
blocklist of atrocity/violence terms across prompt, options and explanation;
require a Wikipedia-lead-style explanation, because a restatement ("The elevation
of X is about 313 m.") differentiates nothing in the slot whose whole job is to
show you learn something; and take at most one question per category and per
prompt-shape, because a purely id-ordered pool produced ten near-identical "which
was born first?" questions.

**Every platform now screens.** `Core/Store/ScreenshotQuestions.swift` and its
Kotlin mirror apply the same word list and selection rules as the Windows
renders, wired behind `TIDBITS_SCREENED` (Apple) and `--ez tidbits_screened`
(Android) and set for every capture. Still eyeball a re-run — the screen is a
blocklist, not a judgement — but it is no longer a dice roll.

### R-SHOT-2: the first three slots carry the pitch

Most shoppers see three thumbnails. The order is fixed:

1. **Home / Quick Play** — one tap into a real game.
2. **A question** — the core loop, legible, no chrome.
3. **The reveal and its story** — the payoff, and what makes Tidbits a *learning*
   game rather than a quiz app. This is the differentiator; it never slips below
   slot 3.

### The canonical eight

| # | Screen | What it proves | Free? |
|---|---|---|---|
| 1 | Home — Quick Play hero | one tap to play; breadth without a wall | ✅ |
| 2 | Question in play | the core loop reads cleanly at thumbnail size | ✅ |
| 3 | Reveal + "the story behind the answer" | you *learn*, not just score | ✅ |
| 4 | Daily Tidbit | the habit — everyone gets the same 7 today | ✅ |
| 5 | Records — your knowledge by domain | progress you own, free | ✅ |
| 6 | Trivia Night | host or join a real night with friends | ✅ |
| 7 | Pass & Play / Online Multiplayer | social, on one device or against a real player | ✅ |
| 8 | Create a quiz from any topic | make your own from the whole of Wikipedia | ✅ |

### Per-platform sets

Same verbs, native idiom — and a platform never ships a screen it doesn't have.

| Platform | Screens | Notes |
|---|---|---|
| **iPhone** | 1–8 | the reference set |
| **iPad** | 1–8 | same, in the wide layout |
| **Apple TV** | 1, 2, 3, 4, 5, 6 | no Create (typing on a remote is hostile — PARITY 🚫) |
| **Mac** | 1, 2, 3, 5, 6, 8 | drops Pass & Play (a touch/couch verb) |
| **Android phone** | 1–8 | mirror of iPhone |
| **Android tablet** | 1–8 | Play requires a tablet set for tablet-eligible listings |
| **Windows** | 1, 2, 3, 5, 6, 8 | mirrors the Mac set |

### Store sizes

| Store | Slot | Pixels | Captured on |
|---|---|---|---|
| App Store | iPhone 6.9" | 1320×2868 | iPhone 17 Pro Max (iOS 26.5) |
| App Store | iPad 13" | 2064×2752 | iPad Pro 13-inch (M5) |
| App Store | Apple TV | 3840×2160 | Apple TV 4K 3rd gen |
| App Store | Mac | 2560×1600 | the Mac app, window pinned to 1280×800 @2x |
| Google Play | Phone | 1080×2400 | Pixel 9 Pro emulator |
| Google Play | Tablet | 1600×2560 | Tablet_10 emulator |
| Microsoft Store | Desktop | 1366×768 | Avalonia headless render on `windows-latest` |

Apple accepts up to 10 per slot, Play up to 8, Microsoft up to 10. Eight is the
target everywhere — enough to tell the story, few enough that every one earns it.

---

## §2 — The autonomous playbook

`tools/capture-screenshots.sh` runs a whole platform unattended. It leans on the
`DebugHooks` env family (CLAUDE.md, *"Drive the app to a known state for
screenshots"*), so no screen needs a human tap.

```bash
tools/capture-screenshots.sh ios       # iPhone 6.9"
tools/capture-screenshots.sh ipad
tools/capture-screenshots.sh tvos
tools/capture-screenshots.sh macos
tools/capture-screenshots.sh android
tools/capture-screenshots.sh android-tablet
tools/capture-screenshots.sh all       # every Apple + Android target, in order
```

Output lands in `branding/store-screenshots/<platform>/NN-name.png`, numbered in
listing order so an upload is a drag of the whole folder.

### The hooks each shot uses

| Shot | Hook set |
|---|---|
| 1 Home | *(none — cold launch)* |
| 2 Question | `TIDBITS_AUTOPLAY=classic:mixed` |
| 3 Reveal | `TIDBITS_AUTOPLAY=classic:mixed` + `TIDBITS_AUTOPILOT=1` + `TIDBITS_AUTOPILOT_STEPS=1` |
| 4 Daily | `TIDBITS_AUTOPLAY=daily:mixed` |
| 5 Records | `TIDBITS_TAB=records` + `TIDBITS_SEED_RECORDS=24` |
| 6 Trivia Night | `TIDBITS_NIGHT_SETUP=1` |
| 7 Pass & Play | `TIDBITS_PARTY=1` (Apple/Android) |
| 8 Create | `TIDBITS_AUTOCREATE=<topic>` |

`TIDBITS_AUTOPILOT_STEPS=<n>` exists for shot 3: plain autopilot advances every
0.9 s, which is far too tight to catch the reveal with a `sleep`. With `STEPS=1`
autopilot submits exactly one answer and then **stops**, parking the app on the
reveal for as long as the capture needs. `STEPS=0` parks on the unanswered
question. Both are no-ops in production.

Every run also sets `TIDBITS_NO_GAMECENTER=1` — GameKit's full-screen "Welcome to
Game Center" sheet otherwise covers the app on a signed-out simulator and every
frame comes back useless.

### Rules the script enforces

- **Never `TIDBITS_CLUB=1`** (R-SHOT-1). The script refuses to run if it is set
  in the environment.
- **Seed before Records.** An empty Records tab shows the empty state, which is
  honest but sells nothing; `TIDBITS_SEED_RECORDS` writes synthetic games only
  when the store is empty and never touches real data.
- **Verify every frame.** After each capture the script asserts the PNG is the
  expected pixel size and is not >99% one colour (which is what a splash screen,
  a black frame, or a covered window look like). A failed frame fails the run
  loudly rather than shipping a blank.
- **One simulator at a time.** Booting two wedges both (CLAUDE.md).

### Manual legs

- **Windows** renders through `windows-repl.yml` (there is no local Windows box —
  Decision 045). Run the workflow, download the artifact, drop the PNGs in
  `branding/store-screenshots/windows/`.
- **macOS** drives the real app on this Mac (there is no Mac simulator), so it
  needs a logged-in desktop session. Three things it has to get right, each
  learned from a failed run:
  1. Capture the app's **window by id** (`tools/mac_window_id.py` →
     `screencapture -l`), never a screen rectangle — a rectangle capture put the
     Android emulator window into the middle of several frames. The window owner
     is **"Tidbits"** (the display name), not the process name.
  2. Dismiss the keychain prompt the ad-hoc signature provokes. Window capture
     already keeps it out of the frame, but it steals focus.
  3. Target **2560×1600**, not 2880×1800: the window is clamped to the display's
     visible frame (872pt here, after the menu bar and Dock), so 1440×900 of
     content is unreachable without changing the user's Dock settings.

- **Windows** renders on `windows-latest` — there is no local Windows box
  (Decision 045):

  ```bash
  gh workflow run windows-repl.yml -f test_filter="FullyQualifiedName~StoreScreenshots"
  gh run download <id> -n windows-repl-artifacts -D /tmp/win
  cp /tmp/win/store/*.png branding/store-screenshots/windows/
  ```

  Every shot renders the real `MainWindow` shell, not a bare `UserControl` — a
  first attempt hosted the views directly and the content collapsed into a narrow
  left column against a huge empty field, because these views are designed to
  live inside the `FANavigationView`. And it renders at **1366×768**: at 1920×1080
  the ~760px content column beside the ~200px nav left half the frame empty.

  Re-render on Windows rather than reusing a Mac run: Skia rasterization and font
  fallback are not identical, and the listing must match what a Windows user sees.
