---
name: autonomous-fleet-testing
description: Build or extend automation that drives REAL devices (iOS, iPadOS, tvOS, macOS, Android, Windows, web) and grades the app from the screen rather than from its own logs. Invoke when writing a device harness or scenario runner, when a test suite passes while the product is visibly broken, when a check might be blind, when a surface cannot be reached by automation, when sharing a device bench between agent sessions, or when calibrating screenshot/OCR thresholds.
---

# Autonomous testing across a fleet of real devices

Full method: `docs/AUTONOMOUS-FLEET-TESTING.md`. This fleet's operating manual:
`docs/DEVICE-QA-SUITE.md`. Cross-session bench sharing: `docs/DEVICE-LEASE.md`.

## The doctrine

**The app's claim is never evidence. The screen is.** Asserting
`viewModel.state == .loaded` proves the view model and nothing about whether a human
sees anything. Drive the real app on real hardware, photograph the glass, read the
photograph.

## The failure that keeps coming back

**A check that cannot see its input must fail loudly, never return "clean."** This is
the single most repeated bug in this rig's history and it always arrives in a new
disguise:

- A suppressed stderr turned a broken toolchain into an empty result that read as data.
- A probe "passed" because the command errored out entirely, so the warning being
  grepped for never appeared.
- A metric that structurally could not distinguish "used" from "ignored" reported clean.
- A test file created after project generation ran **0 tests** and reported green.
- A gate matched its own explanatory comment.

Before trusting any checker:

1. **Ship a test that proves it can fail** — feed it known-bad input, assert rejection.
2. **Run a known-good control through it** before believing its silence.
3. **Never `2>/dev/null` a diagnostic command.**
4. **Count, don't just match** — a frame yielding fewer than N OCR lines is unreadable,
   not empty.

## Coverage is reachability

A surface nothing can drive is untested **and reads as a pass**. Measure it
(`tools/hook_coverage.py`), then close the gaps with env-gated entry hooks that no-op
in production: `SIMCTL_CHILD_*` / `devicectl --environment-variables` on Apple,
`am start --es` extras on Android, query params on web, env vars on Windows.

Two traps: **quote adb extras** (an unquoted space silently destroys every extra after
the first), and **install the DEBUG Android build** — release builds no-op the hooks,
every scenario lands on Home, and every scenario passes.

Always ship a `SKIP_ONBOARD` hook; a first-run modal blocks every capture while the
screenshots still look like the app is being driven.

## Grade the wire and the glass separately

For anything networked, check the shared backend state *and* the screenshots. **When
they disagree, that is the finding** — correct-on-wire/blank-on-glass is a rendering
bug; correct-on-glass/absent-on-wire means the client is faking it locally.

Expect the early runs of any new harness to be mostly harness faults. One 9-host matrix
found 2 real product bugs against 11 harness faults, six of which made a working app
look broken.

## Calibrate; never copy a threshold

A threshold ported from another project is a guess wearing a number's clothes. A 0.010
clip threshold copied between two apps called three correctly-rendered headings clipped
on every frame. Calibrate against a real capture from the device that will be judged,
and record the calibration next to the constant.

## Fleet hygiene

- **Reset before each test** and label the device with the scenario (`devreset.py`).
- **One simulator/emulator at a time** — parallel boots wedge both.
- **Lease devices** (`devlease.py`) if two agent sessions share a bench; never steal a
  live lease, reclaim only when the owning pid is dead.
- **The simulator is lenient in ways hardware is not** — tvOS permits Application
  Support writes that crash with EPERM on device.

## Windows specifics

- **SSH lands in session 0** — a phantom desktop, `MainWindowHandle == 0`, nothing
  visible on the real screen. The interactive desktop needs a scheduled task with an
  `Interactive` principal (`tools/winbox.py`).
- **Headless Skia renders the real UI to PNG on any OS**, which is what makes a $0
  pipeline possible; **but `windows-latest` CI is the actual box.** "Renders on the Mac"
  is never "correct on Windows."
- **`CopyPixels` returns each bitmap's native format** — a captured frame is RGBA, a
  decoded PNG is BGRA. Normalize before comparing or the gate reports false drift.

## When a surface cannot be automated

Some surfaces are closed (an iMessage extension: no `simctl` tap primitive, and
XCUITest drives only your own app). Do not leave it manual — that makes the one
unautomatable surface also the one with no observable output.

**Build a debug-only harness app that hosts the real view types** — the same view
files, not copies — rendering any screen chosen by an env var at exact device size.
That yields repeatable captures, store screenshots, and a regression signal from the
real UI. Do **not** composite fake surrounding chrome: that is a picture of an app that
does not exist.

## Look at the output

Rendering real content is a content audit. Store screenshots of five real questions
exposed that four shared one template — tracing to a selection bug where
`ORDER BY id LIMIT N` sliced one generator's output instead of sampling. A live
gameplay bug, found by looking at a picture.

## Drive to the degenerate outcome

The tie, the zero, the empty list, the cold quit, the last item. Happy-path suites miss
whole classes — a finished-round screen that only ever showed the last question
survived a full suite because nothing ever finished a round.
