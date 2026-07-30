# Windows 10/11 — Tidbits Trivia Design Doc (BINDING)

**Status:** BINDING spec for the sixth platform (research complete
2026-07-05, see `WINDOWS-RESEARCH.md`; verdict: GO at ~$0). The app
is **not built yet** — this doc governs the build. Cite rule numbers
in proposals/commits ("per WINDOWS-DESIGN §6.2"), and **fix the doc
first** when it conflicts with a feature. Companion: `WINDOWS-
PLAYBOOK.md` (the build/test/ship pipeline + first-class-Windows how-to).

**Stack (settled by research):** Avalonia UI **v12** (.NET 9, C#, XAML,
MIT) + **FluentAvalonia** for WinUI-accurate Win11 controls. Rendered
with Skia (own controls, not WinUI peers) — which is exactly why it
**cross-builds from macOS**. Persistence: SQLite (via `sqlite-net` or
EF Core) — the SwiftData/Room analog. Shared backend: the existing
**Firebase RTDB `live/{code}` data plane**, consumed by a **C# client
twin** of `firebase.js` / the Swift `FirebaseRTDB`.

> Windows earns its place because Tidbits' marquee is **Tidbits Live**
> — a lean-back, big-screen, host-run experience, and Windows laptops
> + projectors are the dominant pub/venue hardware. This is a
> **host-first** platform. (Consumer game rides along; parity, native
> idiom.)

---

## §0 — Architecture blockers (read FIRST; the compile/structure traps)

0.1 **Core is a C# port, not shared Swift.** ~60–70% of the app is
platform-agnostic logic (models, RTDB REST client, wire types,
game/queue/scoring/Elo, the Live host session, the corpus consumer).
It is **re-implemented in C#** in a `Tidbits.Core` class library — the
same relationship Android (Kotlin) and web (JS) have to the contract.
**No Swift is shared or bridged.** The contract (`DATA-CONTRACT.md`,
the RTDB room schema, wire types) is the source of truth both sides
conform to. Golden-vector tests (mirror `run_golden.sh`) keep the C#
wire types byte-compatible with the Apple/Kotlin/JS twins.

0.2 **The Win32 interop seam is the `#if os()` analog.** Mica-via-DWM,
taskbar `ITaskbarList3`, global `RegisterHotKey`, and the
`WM_NCHITTEST`→`HTMAXBUTTON` snap fix all need the HWND
(`TopLevel.TryGetPlatformHandle()`). Put ALL of it behind ONE
`Win32HostInterop` helper in a Windows-guarded file
(`OperatingSystem.IsWindows()` guards + a `net9.0-windows` TFM path).
`Tidbits.Core` NEVER references it — Core stays OS-agnostic so it
compiles for the headless test host and the macOS dev head.

0.3 **JIT self-contained publish, NOT Native AOT.** `dotnet publish -r
win-x64 --self-contained` cross-builds from Apple Silicon; **Native
AOT does not cross-OS** and would force a Windows build box. Keep AOT
out of the default pipeline (a CI-only experiment at most).

0.4 **Package identity is required for the good parts.** Toasts, jump
lists, startup task, and `tidbitstrivia://` protocol activation all
need MSIX/sparse-package identity or they throw `NO_PACKAGE`. Ship a
**sparse package** for sideload + a **full MSIX** for the Store (same
identity → identical behavior). An unpackaged raw `.exe` is dev-only.

0.5 **Develop against the Avalonia macOS head; verify via headless PNG
+ Windows CI.** Avalonia runs natively on this Mac — iterate the UI
there. Gate "done" on a `Avalonia.Headless` PNG (`Read` it) AND a
`windows-latest` CI run. "Compiles" and "renders on the Mac head" are
not "correct on Windows" (Mica/chrome/snap are Win-only — §6, §8).

---

## §1 — What Windows is

1.1 A **host/emcee cockpit + consumer game**, in ONE Avalonia app,
Fluent-themed for Windows 11 (graceful on Windows 10). Host mode is
the reason the platform exists; the consumer game is parity.

1.2 **Design principles (identical to the sibling platforms; idioms
diverge):** density from removing chrome; six-level type ramp; brand
`#FF5C35` for CTAs; learning-first (every question a door). The
**inversions** vs the Mac: pointer + **keyboard-first** (Windows users
run the show from the keyboard), Alt-mnemonic menu bar, taskbar/tray
presence, system light/dark + accent, Mica materials.

1.3 **First-class, not a port (the bar):** if a Windows user would say
"this is clearly a cross-platform port," it fails §8.2. The tells of
first-class: Mica window base, real Win11 caption, projector on a
second monitor with hot-plug survival, taskbar progress = the round
timer, global hotkeys, toast notifications, snap-layout participation,
remembered per-monitor geometry.

---

## §2 — The shell (window model)

2.1 **Consumer shell = FluentAvalonia `NavigationView`** (the WinUI
idiom): a left nav pane (Play · Records · Create · Tidbits Live) that
auto-collapses to a hamburger at narrow widths. NOT the macOS
`NavigationSplitView` reused, NOT a tab bar. One content frame.

2.2 **Settings is a NavigationView footer item** (gear), opening a
Settings page — the Windows idiom (there is no macOS `⌘,` Settings
scene). Sign-in lives here AND as a Records banner (mirror the macOS
R-REC fix). Windows has no crash analog, but **do** verify sign-in is
reachable in ≤2 clicks from launch.

2.3 **Host mode REPLACES the window content** (like macOS "game
replaces window root"): starting/joining a Live night swaps the shell
for the cockpit — never an overlay over the nav (its chrome bleeds).
The projector is a SEPARATE top-level window (§6.3).

2.4 **Window chrome:** extend into the title bar
(`ExtendClientAreaToDecorationsHint`), Mica backdrop
(`TransparencyLevelHint="Mica"` + transparent background + translucent
panels), follow `ActualThemeVariant`. **Verify on the pinned build**
(§0.5, §8.5) — some Avalonia 12 previews black-window on Mica.

---

## §3 — Consumer game (parity, keyboard-first)

3.1 **The game replaces the shell content** while playing (Esc / a Quit
affordance returns). ONE game engine (the C# Core port) — never a
second engine (§7.5).

3.2 **Keyboard-first:** number keys pick MCQ options, Enter continues,
Esc quits, arrows where a slider/stepper applies — mirrors the tvOS/
macOS keyboard maps. Every interactive control is Tab-reachable with a
visible system-accent focus ring.

3.3 **Picture rounds** route through ONE image helper (decoded cache +
capped `HttpClient`), never bare per-frame network image controls —
the Windows analog of the macOS `ImagePipeline` rule. Decode to a
consistent color space (avoid the grayscale-as-white-box class).

3.4 **Results = a scrollable recap** (score, accuracy, streak, "tidbits
to remember"), Fluent cards; the primary action (Play again) is a
single accent button, not a stretched full-width control (Windows
buttons size to content — the `CompactButtonStyle` lesson from macOS).

---

## §4 — Records (dashboard, not a ledger)

4.1 **R-REC-1 holds on Windows:** Records is a **dashboard** — streak +
lifetime → **recent games bounded to 3 + "See all"** → your knowledge
→ calibration → personal bests → facts to review. "See all" is a light
Fluent `DataGrid`/list, **never** a wall of cards. Do not port an
inline-dump. (Same rule as iOS §5.3–5.6 / macOS §4.1.)

4.2 **Sign-in banner when signed out** (mirrors the macOS Records fix)
— "Sign in to sync your records," routing to Settings sign-in.

---

## §5 — Design system (Fluent, brand-forward)

5.1 **Shared tokens, Windows expression.** Reuse the palette values
(`--color-primary #FF5C35`, accent `#0047FF`, surface, ink, border)
as Avalonia `ThemeVariant` resource dictionaries (light + dark). Brand
drives CTAs/active states; the **system accent** drives OS chrome only
(focus rings, selection) so the app belongs on the machine without
diluting the brand.

5.2 **The `chunkyCard` analog** is a reusable Avalonia `ControlTheme`
(rounded rect, 2.5px border, own shadow — never hand-add shadow
padding at call sites, per macOS §7.9). Reuse it for game options,
records cards, cockpit panels.

5.3 **Typography = the same six levels** (L1 page title → L6 tabular),
mapped to Fluent type ramp / explicit sizes. Big-screen/projector text
sizes by **viewport fraction + min scale**, never fixed pt (the macOS
scale-to-fit fix — a projector at 100% vs a 150% laptop makes fixed pt
wrong).

5.4 **Buttons size to content** (Fluent default). A full-width button
is ONLY a genuine single primary CTA below content — never a control
sitting next to another control in a row (the exact macOS "malformed
button" class; do not reintroduce it).

---

## §6 — Tidbits Live (the marquee — host cockpit + projector + join)

6.1 **Same backend, C# client.** The cockpit publishes `LiveRoom.Pub`
to RTDB `live/{code}`; phone/web/other-platform joiners render it —
byte-identical wire types (§0.1). Full parity with the macOS host:
rounds/questions, reveal, scoring, answer distribution, hold/break,
skip/jump, tie-break, CSV export, standings, the premium waves
(A authoring, B AV/show, C submission/scoring, D venue, E standings).

6.2 **The cockpit** (host laptop): a keyboard-run control surface.
Space=reveal, ←/→=prev/next, digits=jump, Esc=big-screen hold; an
Alt-mnemonic menu bar (File/Game/Live/View/Help); **taskbar progress =
the round timer / teams-answered** so a host with the cockpit
minimized still sees state; **global hotkeys** (`RegisterHotKey`) so
Reveal/Next fire even when the projector or a slideshow has focus.
Buttons size to content (§5.4).

6.3 **The projector (big-screen) = a SEPARATE chromeless top-level
window** on the second monitor: pick the non-primary `Screen`, set
`Position = screen.Bounds.Position` THEN `WindowState.FullScreen`,
`SystemDecorations="None"`, blank cursor. **MUST survive hot-plug** —
projectors connect/disconnect mid-night; on display change, re-query
`Screens` and fall back to the primary (or a "no projector" slide),
never vanish off-screen. Remember the chosen monitor. All big-screen
text scales by viewport fraction (§5.3).

5.5 **The brand CTA is PINNED; an accent button never sits on an accent
surface.** FluentAvalonia derives a lighter accent for the dark theme, so a
`Classes="accent"` button washes out to salmon-with-black-text while any
hard-coded `#FF5C35` beside it stays saturated — two adjacent CTAs disagreeing.
`Button.accent` pins the brand token (+ white) in both themes; Fluent's derived
accent still drives focus rings and selection, which IS correct there. And on a
coral surface the accent button is invisible — use the inverse treatment (white
chip, coral label), as the Daily hero row does. This applies to EVERY accent
surface, not just buttons — a switched-on `ToggleSwitch` washed out the same
way until it was pinned too.

5.6 **Settings is `FASettingsExpander` rows**, not bold `TextBlock` headers over
`StackPanel`s — Header + Description + a Footer control per row is the Windows 11
Settings shape. Status messages use `FAInfoBar`. Any row carrying an ACCOUNT
affordance ships `IsExpanded="True"`: sign-in hidden behind a chevron reads as
"this app has no account", which is exactly what the iPhone got wrong.
(FluentAvalonia 3 prefixes these `FA…`; the unprefixed WinUI names do not resolve.)

6.3a **The projector must never hijack the only display.** Auto-
fullscreen is correct ONLY when a non-primary `Screen` exists. With a
single monitor, open a normal **decorated, resizable** window the host
can drag onto the projector themselves — a chromeless fullscreen
window on the primary display covers the cockpit with no title bar,
no taskbar entry, and no way out. Always `ShowInTaskbar`, and always
bind **Esc to leave fullscreen** so the big screen is never a trap.

6.3b **Cockpit control rows WRAP.** The transport (back/reveal/next/
skip/lock) and night-management (tie-break/merge/export/print/
projector/end) groups are a dozen buttons; in a non-wrapping
`StackPanel` they clip or collide the moment the window is anything
but maximised. Use `WrapPanel` per group so they reflow onto another
line. A control the host cannot reach mid-night is a broken night.

6.4 **Join** is unchanged for players (phones hit
`tidbitstrivia.com/live/CODE`); the cockpit shows the join QR + code.
Windows also **registers `tidbitstrivia://` + the https join link** so
a shared link opens the Windows app into a **deep-link inbox** (never
mutate the router directly — the cross-platform inbox rule).

6.5 **Toasts** (host): "Team 4 joined," "all teams answered — reveal?",
timer expired — via `DesktopNotifications.Avalonia`.

---

## §7 — Anti-patterns (never)

7.1 A resized macOS/iOS layout, or reusing `NavigationSplitView`
instead of the Fluent `NavigationView` (§2.1). 7.2 Host cockpit as an
overlay over the nav instead of replacing window content (§2.3). 7.3
A second game engine or a re-derived RTDB pipeline instead of the C#
Core port + shared contract (§0.1, §3.1). 7.4 Native AOT / any step
that forces a Windows build machine into the default pipeline (§0.3).
7.5 Bare per-frame network image control for picture art (§3.3). 7.6
A Records inline dump instead of the bounded dashboard (§4.1). 7.7
Full-width button next to another control in a row (§5.4). 7.8
Hand-added shadow padding at a card call site (§5.2). 7.9 Fixed-pt
big-screen text (§5.3). 7.10 Projector window that vanishes when the
display is unplugged (§6.3), or goes fullscreen-chromeless on a
single-monitor machine (§6.3a). 7.13 A non-wrapping cockpit control
row (§6.3b). 7.14 A detail pane that stays blank until the user
clicks the nav — the landing surface renders on load, never as a
side effect of `SelectionChanged` (§2.1). 7.11 Win32 interop leaking into
`Tidbits.Core` (§0.2). 7.12 Shipping "done" on the macOS Avalonia head
without a headless PNG + `windows-latest` CI check (§0.5, §8).

---

## §8 — The tests (before any surface ships)

8.1 **Competent-designer test** — rebuildable from a paragraph? 8.2
**Windows-idiom test** — Mica/caption, keyboard+Alt-menus, taskbar/
tray, projector — or is it a ported Mac window? 8.3 **Cross-build
test** — does `dotnet publish -r win-x64 --self-contained` succeed from
the Mac (no AOT, no Windows-only dep pulled into Core)? 8.4 **Parity**
— same verb as the other platforms, native idiom; PARITY.md row
updated. 8.5 **Headless-PNG test** — an `[AvaloniaFact]` renders the
surface to PNG (`Read` it) at cockpit + projector sizes and both theme
variants. 8.6 **Real-Windows test** — `windows-latest` CI builds, runs
the headless capture, and (for Mica/chrome/snap) a desktop screenshot;
artifacts checked. 8.7 **Contract test** — C# wire types pass the
golden vectors against the Apple/Kotlin/JS twins.

---

## Open owner decisions (from research; non-blocking to start)

1. **Distribution:** default is **both** — free Microsoft Store (MSIX,
   auto-signed, no SmartScreen, $0) + Velopack/GitHub Releases
   (unsigned initially). Confirm appetite for the Store MSIX + review.
2. **Signing spend:** default **$0** (unsigned + Store). ~$10/mo Azure
   Artifact Signing is a later optional upgrade for unsigned-free direct
   download — decide when there's an audience.
3. **Scope of first slice:** recommend **host-first** — cockpit +
   projector + join (the marquee, and the reason Windows exists) before
   the consumer game, so the platform proves its unique value early.
