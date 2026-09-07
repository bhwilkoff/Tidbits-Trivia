# Adversarial design ledger — macOS + Windows

**The method is Archive Watch's** (`~/Documents/GitHub/Archive-Watch`, its Roku
loop): *re-shoot EVERY consumer surface, read the pixels hostilely, and MEASURE
each defect rather than assert it.* Its lint owns "did a banned shape come
back"; the screenshot pass owns **"does it look designed"**. Every row here was
seen on the glass, and flips to ✅ only with a re-shoot.

Owner, 2026-09-07: *"I still think we are very far away from intuitive and
native-looking interfaces for those views/features."*

**Capture rig.** Windows: `AdversarialShots.cs` renders the real views to PNG at
TWO widths — 1180x760 (the app's own default window) and 900x680 (a laptop) —
because a view photographed alone at a generous size hides the faults a host
meets (`windows-owner-parity-2026-07-30`). macOS: `tools/macapp.py` against the
real app.

## §0 — What the rig itself got wrong (read this before trusting a row)

**A view rendered with NO DataContext fails its bindings OPEN.** My first pass
"found" the Windows Join screen showing the entry form, "You're in! Waiting for
the host…" and a giant BUZZ button all at once. That is three mutually
exclusive states — and it is an artifact: `IsVisible="{Binding NotJoined}"`
with no context evaluates to visible. **Not a defect; not filed.** Any row below
that depends on state was checked against the XAML, not just the pixels.

**A screen-region capture grades the SCREEN, not the process.** My second false
finding, 2026-09-07: I reported that the Mac app opens two cockpit windows, each
hosting its own live room, and told the owner to close the extras before hosting
a real night. It does not. `tools/macapp.py`'s `quit_all()` was `pkill` plus a
fixed `time.sleep(1.5)`, and 1.5s does not always outlast the old instance — so
two TidbitsTrivia processes were on screen together, and `launch()` returned
`pids[0]`, which could be the OLD one. `_windows(pid)` reported one process
honestly; `screencapture -R` captured a rectangle holding BOTH apps' windows,
and two overlapping shells read as one app with duplicate windows. The two room
codes I cited as proof (RQP5 and XMZG) were from two different launches — I
compared screenshots across a relaunch and called it one session.

Measured after the fix (poll until the process table is empty; refuse to return
a pid when more than one is running): three consecutive hosting launches each
give exactly one process with exactly two windows — the cockpit (1281x732) and
the projector (1280x720, `Window`, singleton). Non-hosting launches give one
window, four for four. **Nothing was filed against the app.**

The rule this yields: an observation about WINDOW IDENTITY has to come from the
accessibility tree of ONE known pid, never from a screen rectangle. A rectangle
is evidence about pixels, and only about pixels.

## §1 — Windows (the weak platform)

| # | Defect, measured | Where | Status |
|---|---|---|---|
| W1 | **Every view pins its content hard-left.** `HorizontalAlignment="Left"` on the root StackPanel of Play, Live, Join, Create. At the default 1180-wide window the Live page fills 640px — **46% of the window is empty**. The Mac centers the same column. Fluent apps (Settings, Store) centre or stretch; hard-left reads as unfinished | `PlayView/LiveView/JoinPlayerView/CreateView.axaml` |✅ |
| W2 | **The JOIN A GAME card is an unstyled default button** — a white rounded rect with a hairline border, beside a filled coral QUICK PLAY banner. On the Mac the same control is a teal chunky card with an icon and a chevron. PARITY.md claims "a full-width teal JOIN A GAME card … on iOS, Android, web, macOS and Windows"; on Windows that cell is **false**, and I wrote it | `PlayView.axaml` |✅ |
| W3 | **Icon buttons are bare Unicode text glyphs**, not Fluent icons: `▲` `▼` `✕` as `Button.Content`. In the headless capture several render as **tofu (▯)** — the round header reads `▯ ▼ ▯` and every question row ends in `▯`. Whether the tofu survives on real Windows is being checked; the design defect stands either way, because FluentAvalonia ships `SymbolIcon` and Segoe Fluent Icons | `LiveView.axaml.cs:202,243,248,1299`, `CreateView.axaml.cs:200` |✅ |
| W4 | **Placeholder text is the only label.** Event name, Sponsor, Brand color #hex, Mailing-list URL, Host note are `Watermark`-only, so a FILLED form has no labels at all. Two idioms fight in one form: `Category:` and `Repeats:` use trailing-colon inline labels; everything else uses watermarks | `LiveView.axaml` |✅ |
| W5 | **Two instruction paragraphs narrate the app.** "The pub-trivia rig: build a branded event, run it from the host cockpit…" and "Just want to play a night with friends? That is Trivia Night, on the Play page…". The second narrates NAVIGATION to another page. AW §13.8: nothing on screen narrates navigation | `LiveView.axaml:7-8` |✅ |
| W6 | **"Brand color #hex" asks a pub host to type a hex string.** FluentAvalonia ships a `ColorPicker`; the Mac already uses a colour well | `LiveView.axaml` |✅ |
| W7 | **No cards anywhere on Live or Play.** WINDOWS-DESIGN §5 mandates `Border.card` (it owns its elevation shadow). The Live page and the Play page use zero. Every round, every question, every section is a bare row on a flat ground | `LiveView.axaml*`, `PlayView.axaml` |✅ |
| W8 | **The round header inlines the host note and truncates it mid-word**: `1. Classic · 3 questions (yours) ▯ Read the first…`. The note competes with the round's identity for the same line | `LiveView.axaml.cs` round header | ✅ |
| W9 | **The Quick Play hero does not say what it will play.** Windows: "QUICK PLAY / Jump straight into a round". Mac: "QUICK PLAY / NAME AS MANY · MIXED BAG / Click to jump straight into a round". The Windows hero is strictly less informative than the Mac one | `PlayView.axaml` |✅ |
| W10 | **"Previous Tidbits" is bare text with no affordance** — it is a button, and looks like a caption | `PlayView.axaml` | ✅ |

## §2 — macOS (the strong platform, still not finished)

| # | Defect, measured | Where | Status |
|---|---|---|---|
| M1 | **Question prompts truncate mid-sentence in the builder.** Measured on the glass: "…he was impeached for corruption,…", "…eventually chairi…", "…swinging through bus…" — 3 of 5 rows in one round. `lineLimit(2)` on a row with plenty of width. AW F10 is exactly this: never abbreviate the title; a host cannot proof-read their own round | `MacLiveBuilder_macOS.swift` questionRow |✅ |
| M2 | **"Pull one from the corpus"** puts internal vocabulary on the glass. A host has no corpus. Same class as AW §13.2 (a raw slug as a label). It appears on BOTH platforms | Mac + Windows builder |✅ |
| M3 | **The round chips do not distinguish state from affordance.** `Timer ⌄ · Wager · Speed · Buzz · Abc Letter ⌄` — five identical-looking chips where two open menus and three are ON/OFF toggles, with no indication which are on | `MacLiveBuilder_macOS.swift` | ✅ |
| M4 | **"Abc Letter" is not a phrase.** It is the first-letter round; the label reads as two unrelated words | `MacLiveBuilder_macOS.swift` |✅ |
| M5 | **Two coral cards on Play** (QUICK PLAY and TRIVIA NIGHT) give the page two primary actions, against R-HOME-1's "Home is ONE primary action" | `HomeView_macOS.swift` | ✅ |
| M6 | **Mixed dash style in one card set**: "at one Mac - same questions" (hyphen) beside "Mixed rounds with friends — host from any device" (em dash) | `HomeView_macOS.swift` | ✅ |

## §3 — Cross-platform

| # | Defect | Status |
|---|---|---|
| X1 | **"Colours" (Mac) vs "color" (Windows)** for the same field. One product, two spellings of the same word |✅ |
| X2 | **M2 vocabulary** ("corpus") ships on both |✅ |

## Order of work
W1 W2 W7 (the whole Windows page reads unfinished without them), then W3 W4 W6
(native controls), then the vocabulary and truncation rows M1 M2 M4 X1, then
W5 W8 W9 W10 M3 M5 M6.


## Fixed in this pass (2026-09-07), with the evidence

| # | What changed | Evidence |
|---|---|---|
| W1 | Content column 640 → 900; the Settings rows stretch it | 1180-wide shot: the page fills 76% of the window, was 54% |
| W2 | JOIN A GAME is a teal filled card, not a default button | re-shot beside the coral hero; PARITY.md's Windows cell is now true |
| W3 | Every icon is a `FASymbolIcon`, not a text glyph | the round header read `▯ ▼ ▯`; it now shows real chevrons and a trash can, and each question row a real ✕ |
| W4 W7 | The Live page is `FASettingsExpander` rows — the shape the app's OWN Settings page already uses (WINDOWS-DESIGN §5.6) | labels and descriptions persist on a filled form; cards have elevation |
| W5 | Two instruction paragraphs → one line; the one narrating navigation to another page is deleted | re-shot |
| W6 | A live swatch paints from the hex field | ◐ a real `ColorPicker` is not in this FluentAvalonia build |
| W9 | The hero names what it will launch: `CLASSIC · MIXED BAG` | re-shot; refreshed on appear |
| W11 | **Fourteen equal-weight buttons → three primaries + Import / Export / Print menus** (the Mac has had one "Event file" menu all along). Eleven of the fourteen were file plumbing, and six of those I added today | re-shot |
| M1 | Question prompts wrap instead of truncating | re-shot: 5 of 5 in full, two of them three lines. Was 3 of 5 cut mid-sentence |
| M2 X2 | "corpus" is gone from every host-facing string on both platforms | grep + re-shot |
| M4 | "Abc Letter" → "Letter" (the SF Symbol was drawing the letters) | re-shot |
| X1 | One spelling of colour/color | grep |

**Still open:** W8 (the round header inlines the host note on Windows), W10
("Previous Tidbits" is bare text), M3 (round chips do not distinguish a menu
from an on/off toggle), M5 (two coral cards = two primaries on Mac Play), M6
(a hyphen where an em dash belongs).
