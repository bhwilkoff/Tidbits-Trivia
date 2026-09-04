# Autonomous testing across a fleet of real devices

How an agent drives six platforms — iOS, iPadOS, tvOS, macOS, Android, Windows — plus
the web, on **real hardware**, and grades what it sees rather than what the app claims.

`docs/DEVICE-QA-SUITE.md` is the operating manual for *this* repo's fleet: which
devices, which scenarios, how to run them. **This document is the method** — the part
that transfers to any app, and the part that was expensive to learn.

---

## 0. The doctrine

**The app's claim is never evidence. The screen is.**

Every shortcut away from this produces a suite that passes while the product is broken.
A test that asserts `viewModel.state == .loaded` proves the view model; it proves
nothing about whether a human sees a question. Drive the real app on real hardware,
photograph the glass, and read the photograph.

Three corollaries, each of which cost real time to learn:

**An instrument must say when it is blind.** A check that cannot see its input must
die, not report clean. This is the single most repeated failure in this repo's history,
and it recurs in new disguises constantly — see §2, which is the longest section here
for a reason.

**A green build tells you almost nothing.** Every one of the four App Store blockers in
`docs/APPLE-SUBMISSION-CLI.md` compiled, archived, and signed green. They failed at
upload. The same is true of UI: the tvOS Application Support write that crashes on
device passes on the simulator.

**Drive to the degenerate outcome, not just the happy path.** The tie, the zero score,
the empty list, the cold quit, the last question. Happy-path suites miss whole bug
classes; a finished-round screen that only ever showed the last question survived a
full test suite because nothing ever finished a round.

---

## 1. Architecture: a shared spine, honest seams

```
tools/devharness.py     ← OCR, grading, artifact paths, the blind-instrument guard
   ├── ios_run.py       ← devicectl: install, launch with env, screenshot
   ├── atv_run.py       ← devicectl over the network + Companion wake
   ├── adb_run.py       ← adb: force-stop, am start with extras, exec-out screencap
   ├── mac_run.py       ← the app runs on this Mac; capture by WINDOW ID (and by PID)
   ├── win_run.py  ──┐
   │                 └── winbox.py  ← SSH to a real Windows box
   └── web_run.py   ──── webdrive.py ← Chrome DevTools Protocol, stdlib only

above them, deciding WHAT to photograph and keeping the bench sane:
   qa_suite.py       ← the matrix; probes reachability, SHELLS OUT to each runner
   play_loop.py      ← coverage as state, so each lap does work the last did not
   multiplayer_run.py / night_matrix.py  ← one room across every device; wire + glass
   devlease.py / devreset.py / hook_coverage.py  ← who owns a device, what state
                                                   it is in, what can be reached
```

**Orchestrators shell out; they do not import.** `qa_suite.py` runs each runner as
a subprocess with a timeout, so one hung device or one crashed runner cannot take
the sweep down — the cost of a wedged Apple TV should be one SKIP, not a lost
night.

**Put in the spine only what is genuinely platform-agnostic**: OCR, text grading,
threshold logic, artifact layout, the blind-instrument guard. A lesson learned on one
device then reaches all of them.

**Keep device plumbing out of it.** Waking an Apple TV over Companion, unlocking a
Pixel over adb, and giving up on a locked iPad are not one operation wearing three
hats. Forcing them into a common abstraction produces a lowest-common-denominator
harness that cannot express what any single platform needs. The seam is honest:
*shared judgement, separate hands.*

The counter-example is instructive. A sibling project runs three hand-written harnesses
that share nothing but an OCR binary, and pays for it — its iOS harness has no wake, no
alive probe and no retry ladder, because the tvOS resilience was never back-ported.

---

## 2. The blind instrument — the failure that keeps coming back

A check that cannot see its input must **fail loudly**, never return "clean". This
sounds obvious and is violated constantly, because a broken instrument and a passing
test look identical from the outside.

Real instances from this repo, all different disguises of one bug:

| What happened | What it looked like |
|---|---|
| `xcode-select` pointed at CommandLineTools, so `xcodebuild -showBuildSettings` errored and stderr was suppressed | "`DEBUG` is defined in neither configuration" — a confident, wrong conclusion |
| `actool --stickers-icon-role app` rejected the flag outright, so the warning being grepped for never appeared | "that role accepts the icon" — a **false positive from a crashed command** |
| A single-entry asset catalog never reports "unassigned children" | "the entry was accepted" — the metric could not distinguish used from ignored |
| A test file created after `xcodegen` ran wasn't in the target | Suite passed having run **0 tests** |
| A gate grepped for its own explanatory comment | Passed on the warning about the thing it was warning about |
| OCR crop used bottom-left origin against a top-left `GetWindowRect` | Kept the wrong half of the screen, silently |
| An answer-leak check used `textutil`, which cannot extract PDF text, so it searched compressed bytes | "No answers leaked" from **both** files — including the one that is supposed to contain them |
| A linker fix carried `platformFilter: macOS`, which xcodegen writes to the pbxproj as `maccatalyst`, filtering it back out | `BUILD SUCCEEDED` and the framework still absent from `otool -L` |

**The defenses, in order of value:**

1. **Assert the check can fail.** Ship a test that feeds the checker known-bad input
   and asserts it *rejects*. `MessagesDiagnosticTests.theScannerCanActuallyFail` exists
   for exactly this.
2. **Verify the tool works before trusting its silence.** Run a known-good control
   through it. The icon investigation only became productive after a control case
   (`iphone 60x45`, known to compile) revealed the test harness disagreed with the real
   build — the harness was missing two actool flags.
3. **Never suppress stderr on a diagnostic command.** `2>/dev/null` turned a broken
   toolchain into an empty result that read as data.
4. **Count, don't just match.** `tools/atv_see.sh` refuses to return a frame whose OCR
   yields fewer than N lines — a locked or sleeping device yields zero, a real screen
   yields many. Line count is resolution-independent; byte size is not.
5. **Read the artefact, not the banner that produced it.** `BUILD SUCCEEDED` did not
   mean the framework was linked; `otool -L` did. `codesign -d --entitlements` is what
   answers "is this entitlement shipped", not the project file that requests it.
6. **Distrust the result that arrives already looking like a pass.** Both of the rows
   above were caught by asking why the *negative control* also passed. A check that
   cannot produce its expected failure has not been run.

---

## 3. Reaching a surface: hooks are coverage

**A surface nothing can drive is untested, and it reads as a pass.**
`tools/hook_coverage.py` measures which surfaces the harness can actually reach per
platform. It went from 12 unreachable to 0 — and every one of those 12 was silently
counted as fine before it existed.

Give the app **env-gated entry points** that are no-ops in production, so any screen
can be opened directly:

| Platform | Mechanism |
|---|---|
| iOS / tvOS / macOS | `SIMCTL_CHILD_*` env, or `devicectl ... --environment-variables` |
| Android | `am start --es KEY VALUE` extras, gated on `BuildConfig.DEBUG` |
| Web | routes read at boot, plus a CDP driver when a scenario must type or click |
| Windows | environment variables read at startup |

Two hard-won details:

**Quote your adb extras.** An unquoted space destroyed every extra after the first, and
the resulting truncated banner was dismissed as cosmetic for hours. `tools/adb_run.py`
now routes everything through a `_q()` helper.

**Android QA hooks must be `BuildConfig.DEBUG`-gated *and you must install the debug
build*.** Against a release build the hooks silently no-op, every scenario lands on
Home, and **every scenario passes**. That is a whole suite reporting green while
testing nothing.

**Dismiss the onboarding.** A first-run modal blocks every capture, and screenshots
taken "behind" it look like the app is being driven when nothing is being driven. Ship
a `SKIP_ONBOARD` hook.

**A hook must be able to create the PRECONDITION, not just open the screen.** A buzz
button that only renders when a host publishes `buzz == true` is unphotographable until
something can make a host do that — it shipped, built green, and had never been seen. The
hook that unblocked it was on the *host* side, not the screen's. Ask of every element:
what state must exist for this to render, and can the harness produce that state?

**Where the platform blocks scripting, put the seam at the platform edge.** A modal file
panel is not scriptable, so the function that *returns the panel's answer* takes the
harness's answer instead when one is supplied — one seam, no-op in production, and the
whole path either side of it stays real. Two traps came with it: under a sandbox a path
the harness invented was never granted, so a bare filename must resolve inside the app's
own container; and the operation must be assertable from the artefact it produced (§10),
not from the app's report of it.

**Own the whole run, not just the launch.** Reset each device to a known state before a
scenario and label it with what it is testing (an env-driven on-screen banner costs a
shipped build nothing). A device left mid-round by the previous scenario produces results
that look exactly like bugs, and a bench of six identical-looking screens tells you
nothing about what is under test.

---

## 4. Grading: the wire and the glass are different witnesses

For anything networked, grade **both**:

- **The wire** — the shared backend state (here, Firebase RTDB `live/{code}`). Truth,
  independent of any client.
- **The glass** — screenshots. What a human actually sees.

**When they disagree, that IS the finding.** A room that is correct on the wire and
blank on the glass is a rendering bug; correct on the glass and absent from the wire
means the client is faking it locally. Either way, one witness alone would have
reported success.

The 9-host Trivia Night matrix (`tools/night_matrix.py`) graded every platform hosting
and every other platform joining. It found **2 genuine product bugs against 11 harness
faults** — and six of those harness faults made a working app look broken. Budget for
that ratio: most of what a new fleet harness reports at first is the harness.

---

## 5. Calibrate thresholds; never copy them

A threshold ported from another project is a guess wearing a number's clothes.

A clipping threshold of `0.010` copied from a sibling app called three correctly
rendered headings clipped on every frame, because this app's gutter sits at
x = 0.0099–0.0116 on that iPad. Every threshold is calibrated **against a real capture
from the device it will judge**, and the calibration is recorded next to the constant.

---

## 6. Fleet hygiene

**Reset before each test, and say what you are testing.** Devices left in a previous
scenario's state produce results that look like bugs. `tools/devreset.py` returns each
device to a known, empty state; the harness labels the device with the scenario name so
a glance at the bench says what is under test.

**Boot exactly one simulator or emulator at a time.** Parallel boots wedge both.

**Lease devices across sessions.** Two agent sessions on one bench will fight, and the
symptom is bizarre non-reproducible failures. `tools/devlease.py` writes
`~/.device-lease/<device>.json` with owner, pid, task and TTL. The rule that makes it
safe: **never steal a live lease** — reclaim only when the owning pid is dead.

**The simulator is lenient in ways hardware is not.** tvOS permits Application Support
writes on the simulator and crashes with EPERM on device. Anything touching the
filesystem, entitlements, or sync needs a real-device check before "done."

---

## 7. Windows: the platform with no free VM

The constraint that shapes everything: **there is no free Windows VM, and the dev box
is an arm64 Mac.**

**Two complementary rigs, and both are needed:**

1. **Headless Skia** (`Avalonia.Headless` + `UseSkia()`) renders the real UI to PNG
   in-process **on the Mac**. This is what makes a $0 pipeline real, and it is why the
   framework choice was Avalonia rather than WinUI — WinUI cannot do this.
2. **`windows-latest` CI is the actual box.** "Renders on the Mac head" is never
   "correct on Windows": Mica, chrome, DPAPI, Win32 interop and LibVLC natives are
   Windows-only. Gate on CI, and refresh visual baselines *captured on Windows*.

**A real Windows machine over SSH lands in session 0.** Services session — a phantom
1024×768 desktop, `MainWindowHandle == 0`, and nothing you launch is visible on the
actual screen. Reaching the interactive desktop needs a **scheduled task with an
`Interactive` principal**. `tools/winbox.py` encapsulates this; without it you drive an
invisible desktop and photograph nothing.

**`CopyPixels` returns each bitmap's native format.** A captured frame is RGBA; a
PNG-decoded file is BGRA. Compare them without normalizing and the visual gate reports
drift that does not exist — a false failure, which trains everyone to ignore the gate.

---

## 8. When a surface genuinely cannot be automated

Some surfaces are closed. An iMessage extension lives inside Messages: `simctl` has no
tap primitive and XCUITest drives only your own app. The honest first response was a
script that staged a simulator and left four screenshots to a human.

That was worse than it looked. **It made the one surface with no automation also the
one surface with no observable output** — a UI regression there was invisible to
everything.

The fix generalizes: **build a harness app that hosts the real view types.** A separate
debug-only target compiles *the same view files* — not copies — and renders any screen
selected by an env var, at exact device size. That gives repeatable captures, store
screenshots, and a regression signal, all from the real UI.

What it must **not** do is fake the surrounding chrome. Compositing a fake conversation
around the views would produce a picture of an app that does not exist — fine as a
mock, unacceptable as evidence or as a store screenshot.

---

## 9. Rendering real content is a content audit

The iMessage store screenshots rendered five real questions and exposed that **four
shared one template, two word-for-word identical**. Measuring rather than reseeding
found the pack was 57.8% one question shape against 9.5% in the corpus: the selection
used `ORDER BY id LIMIT N`, and corpus ids cluster by the generator that produced them,
so it was slicing one generator's output rather than sampling.

That was a live gameplay bug — every round was mostly one puzzle — found by looking at
a screenshot.

**Look at the output.** Not the assertion about the output.

---

## 10. Assert the artefact, not the app's opinion of it

Where a feature produces a file — a PDF, an export, a report — grade the file. The app
saying "exported" is the same class of evidence as `state == .loaded`.

Printing was the last untested item on an owner's list, and the behaviour was already
covered by unit tests: pagination pinned, no answers on the team sheet. What no test
touched was **the button a host actually presses**. Driving it and then reading the
resulting PDF (`pdftotext`) found the honest evidence: "Answer:" appears ten times in
the host's pack and zero times in the team's sheet, at 34,617 and 12,499 bytes over the
page counts the receipt claimed.

Three rules fall out of it:

- **Round-trip through the real edge.** The export scenarios assert the bytes on disk;
  the import scenarios read back exactly what the exports wrote. Together that is a trip
  through the *panels*, which is what a user touches — the parser already had tests.
- **If the extraction tool is missing or wrong, FAIL.** The first version used a tool
  that cannot read PDF text at all, so it searched compressed bytes and cleared both
  files, including the one that must contain answers. See §2: the result that proved it
  broken was the one that looked like a pass.
- **Reading the artefact finds product bugs, not just test bugs.** The first failing
  assertion here turned out to be about window height: the export receipt sat below the
  fold, so the check was really measuring the window. A confirmation a host must scroll
  to find cannot tell them the export worked, and the fix was to the app.

**An assertion that depends on scroll position is asserting the window size.** Either
pin the window, or assert something that cannot move — the file, the bytes, the wire.

---

## 11. Efficiency: use the cheapest tier that can answer the question

Real hardware is the truth and also the slowest thing available. The point of the tiers
is not speed for its own sake — it is that using the wrong tier produces a green result
that does not mean what it looks like.

| The question | Cheapest honest tier |
|---|---|
| Is the shared logic right? | Unit tests + cross-stack golden vectors |
| Does this UI render at all? | Headless render to PNG (Skia, `@Preview`/Roborazzi, DOM shim) |
| Does every screen open? | Simulator / emulator sweep |
| Does a human see it on the product? | **Real hardware, photographed** |
| Does it survive hardware you do not own? | A device-farm Robo run, physical devices only |
| Does the SHIPPED binary do it? | Read the binary: link table, entitlements, the artefact |

Four economies that made the loop affordable:

- **Coverage is state, not a sample.** An earlier loop re-ran the same five smoke
  scenarios every tick, and the owner was right to kill it: it was a tripwire wearing a
  loop's clothes. Recording per-(platform, surface) when it was last verified, then
  taking never-run cells first and stalest next, gives the loop an *end condition*
  instead of a cadence.
- **Long matrices need a ledger.** A full host matrix is ~8 runs at ~8 minutes — longer
  than any one sitting or background task survives. Append each result; a re-run skips
  what already passed. Anything that cannot be resumed will be abandoned half-done.
- **Batch where the platform allows and isolate where it does not.** The Mac and web
  runners take `--only a,b,c` and amortize one launch; device runners take one scenario
  at a time because a wedged device must not poison the next result. OCR is batched 20
  files per process for the same reason — launch cost, not correctness.
- **Probe reachability, never assume it.** A device that is off is a SKIP, and the probe
  must agree with its own evidence string. A serial matched as a fragment once returned
  False while printing "adb ok", and because SKIPs are quiet the Pixel simply went
  untested with nothing said.

---

## 12. Checklist for a new app

1. `devharness.py` equivalent first — OCR, grading, artifact paths, blind-instrument
   guard. Everything else hangs off it.
2. Env-gated entry hooks on every platform, from the first screen.
3. `hook_coverage.py` equivalent, so unreachable surfaces are *visible* rather than
   silently green.
4. A lease file if more than one agent session will ever touch the bench.
5. Calibrate every threshold on a real capture from the real device.
6. Grade the wire and the glass separately for anything networked.
7. A test that proves each checker can fail.
8. Grade artefacts (files, wire state) rather than app reports wherever a feature
   produces one.
9. Decide the tier ladder up front, and record which question each tier is allowed to
   answer.
10. Wire the store submission the same way — see `docs/APPLE-SUBMISSION-CLI.md`.
