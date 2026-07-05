# Windows 10/11 Tidbits — Feasibility Research (working notes)

**Status:** RESEARCH COMPLETE (2026-07-05) — verdict **GO** at ~$0.
Deliverables written: `WINDOWS-DESIGN.md` (binding design doc) +
`WINDOWS-PLAYBOOK.md` (the $0 build/test/ship pipeline + first-class-
Windows recipes). Next phase (owner greenlight): scaffold `windows/`
and build the host-first slice per the playbook §7 bootstrap sequence.

## The ask (owner, 2026-07-05)

A native Windows 10/11 version of the app with **full Tidbits Live
parity**, that:
- is a **first-class native Windows experience**, not a Mac port;
- is **developed entirely from this Mac** (Claude Code) — owner has no
  modern local Windows PC;
- is **tested/observed via cloud machines or Mac-runnable CLI** that
  Claude can fully drive;
- costs **as close to $0 as possible**.

## Working hypothesis (to verify with the research streams)

**Stack: Avalonia UI (.NET 9/C#, XAML).** It is the one native-looking
desktop framework whose Windows x64 binary can be **cross-built from
macOS** with the free `dotnet` CLI (`dotnet publish -r win-x64
--self-contained`) — no Windows machine needed to BUILD. MAUI/WinUI,
Uno's Windows head, and Flutter-Windows all REQUIRE Windows to build;
Tauri/Electron are WebView, not native controls.

**Observability unlock: Avalonia.Headless** renders the REAL UI to a
PNG on any OS (macOS included) with no display server — this is the
answer to "owner can't see a Windows screen." It's the Windows analog
of the offscreen-PNG sim discipline, except it actually works headless
(the macOS `ImageRenderer` snapshot did not).

**Reuse: the shared data plane, not the Swift code.** Windows is a new
CLIENT of the same Firebase RTDB `live/{code}` contract + the published
corpus — a C# twin of `firebase.js` / the Swift `FirebaseRTDB` client,
exactly as Android (Kotlin) and web (JS) are separate clients of one
backend. ~0% UI reuse, but the contract + wire types + game logic port
cleanly to C#.

**Cost floor (to quantify): code signing.** Everything else (dotnet,
Avalonia MIT, GitHub Actions free tier, Wine, GitHub Releases) is $0.
An unsigned .exe trips SmartScreen "unknown publisher." The research
stream is pricing the cheapest legitimate signing (Azure Trusted
Signing / SignPath-for-OSS) vs the $0 ship-unsigned fallback.

## Research streams (4 parallel agents, launched 2026-07-05)

1. **Framework + build-from-Mac** — verify Avalonia cross-build from
   macOS actually works; rank vs MAUI/Uno/Flutter/Tauri. → **DONE ✅**
2. **Testing/observability at $0** — Avalonia.Headless PNG capture,
   GitHub Actions windows runners, Wine on Mac, free cloud Windows. →
   **DONE ✅**
3. **First-class Windows 11 UX** — Fluent/Mica, multi-monitor projector
   (the Live need), toasts, taskbar, snap layouts, MSIX identity. →
   **DONE ✅**
4. **Distribution + signing at $0** — MSIX/exe/installer, Store fee,
   the SmartScreen/signing cost reality, Velopack auto-update. →
   **DONE ✅**

## Findings

### Stream 1 — Framework (VERDICT: Avalonia UI v12, MIT) ✅

- **Cross-build from macOS CONFIRMED REAL.** `dotnet publish -r win-x64
  -c Release --self-contained` runs on Apple Silicon and emits a working
  Windows `.exe`. Works because Avalonia draws its own Fluent-themed
  controls with **SkiaSharp** (not OS-native peers) — no Windows SDK / C++
  toolchain needed. Native libs (Skia) restore as per-RID NuGet assets.
- **Native look:** built-in **FluentTheme** styled as Windows 11, auto
  light/dark to match system, updates the native Win11 title bar. Controls
  are Fluent-*styled Avalonia-drawn* (pixel-faithful), not literal WinUI —
  the closest achievable in a Mac-buildable stack. Production users:
  JetBrains, Autodesk, Devolutions. Real multi-window + a **Screens API**
  (per-monitor) — covers the Live projector need.
- **Disqualified (all REQUIRE a Windows build machine):** .NET MAUI
  (WinUI3), Uno's WinUI head (needs Windows SDK WinMD), Flutter-Windows
  (needs VS2022 + Windows SDK). **Tauri** = WebView fallback that could
  reuse our JS web app (experimental cross-build). **Electron** = Wine/
  Docker hack, avoid.
- **DECISIVE gotchas:** (1) **Native AOT does NOT cross-OS** — for the
  Mac-only workflow stay on **JIT self-contained** publish; do AOT only in
  Windows CI if ever wanted. (2) Can't sign/package or run the win-x64
  build ON the Mac. **Mitigation + key insight:** Avalonia also runs
  natively on macOS — **develop/iterate against the app's macOS desktop
  head on this Mac**, then cross-publish win-x64 for release + CI-validate.

### Stream 2 — Testing/observability (VERDICT: Avalonia.Headless → PNG) ✅

- **THE observability unlock:** `Avalonia.Headless` + `.UseSkia()` +
  `AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false }` →
  `window.CaptureRenderedFrame().Save("x.png")` renders the **real** UI
  (control tree, layout, styling, bindings, Skia pixels) to a PNG **on
  macOS, no display server, $0.** Because Avalonia's Skia renderer is
  OS-independent, **a PNG captured on the Mac is pixel-representative of
  Windows** (except native window chrome/OS font substitution). This is
  the offline-PNG-sim discipline, and unlike the macOS `ImageRenderer` it
  ACTUALLY works headless. Packages: `Avalonia.Headless` +
  `Avalonia.Headless.XUnit`/`.NUnit`; `[AvaloniaFact]`/`[AvaloniaTest]`.
  Doubles as a **visual-regression harness** (baseline-PNG diff). Wire an
  `APP_START_*`-style env hook so a test drives any screen/state → PNG.
- **Real-Windows confirmation ($0):** **GitHub Actions `windows-latest`
  is UNLIMITED-free for PUBLIC repos** (Tidbits is public) — run the same
  headless capture there + optionally a real-desktop PowerShell screenshot
  of the launched `.exe`, upload as artifacts. (Private-repo free tier:
  ~1,000 Windows min/mo since Windows counts 2×.)
- **Wine on Mac:** skip for design verification — double translation
  (x86→Wine→Rosetta) + Skia/GPU is Wine's weak spot; unreliable pixels.
  Smoke-test only. (Whisky discontinued 4/2025; free wrapper now
  "Sikarugir"; CrossOver is paid.)
- **Free cloud Windows VMs:** none are permanently free. Azure's
  12-month B1S trial is a rare live-RDP escape hatch only — **violates the
  $0-ongoing guardrail after 12 months**, so not part of the steady loop.
  GitHub Actions is the truly-$0 real-Windows path.

**Observability loop (settled):** Mac-local `dotnet test` → headless PNG →
`Read` the PNG (fast design loop, pixel-faithful) → `windows-latest` CI for
the real compiled-Windows confirmation before shipping. **This removes the
"can't see a Windows screen" blocker entirely.**

### Stream 3 — First-class Windows 11 UX ✅

- **Two upstream gating decisions:** (A) **Package identity** (MSIX or
  *sparse package with external location*) is REQUIRED for toasts, jump
  lists, startup task, protocol activation — an unpackaged exe throws
  `NO_PACKAGE`. Plan: **sparse package for sideload + full MSIX for Store**
  (same identity). (B) **Pin the Avalonia build carefully** — some v12
  previews have a Mica **black-window** bug (#21082) and v12 replaced
  `ExtendClientAreaChromeHints` with `WindowDecorations` (breaking; broke
  some DWM animations). **Verify Mica + custom chrome on the exact pinned
  build before committing to the look** (2026 moving target); fallback is
  Win32 `DwmSetWindowAttribute(SYSTEMBACKDROP_TYPE)` via HWND.
- **Highest-leverage dep: `FluentAvalonia`** — WinUI-accurate controls
  (NavigationView, ContentDialog, InfoBar, Win11 caption buttons), much
  closer to real WinUI 3 than base FluentTheme.
- **Fluent look (MUST):** Mica on the window base (`TransparencyLevelHint
  ="Mica"` + `Background="Transparent"` + translucent panels), Acrylic for
  transient flyouts; custom Win11 title bar via
  `ExtendClientAreaToDecorationsHint`; follow system light/dark
  (`ActualThemeVariant`); system accent via `PlatformSettings.GetColor
  Values()` for chrome ONLY (keep brand `#FF5C35` for CTAs).
- **Multi-monitor projector (MUST — the Live core):** `TopLevel.Screens`
  API (`Screens.All/Primary/ScreenFromPoint`). Cockpit = main Window on
  primary; big-screen = a **second chromeless Window** — set `Position =
  targetScreen.Bounds.Position` FIRST, then `WindowState.FullScreen`.
  **Handle projector hot-plug** (connects/disconnects mid-night → fall back
  to primary, never vanish off-screen); remember chosen monitor; size
  big-screen type by **viewport fraction, not fixed pt** (mirrors the macOS
  scale-to-fit fix). Maps 1:1 to the macOS cockpit + big-screen model.
- **Toasts (MUST host):** `DesktopNotifications.Avalonia` (community,
  low-friction, auto AppUserModelID) recommended over WinAppSDK
  `AppNotificationManager`. Uses: "Team 4 joined," "all teams answered —
  reveal?," duel challenge, Daily.
- **Taskbar (SHOULD):** Win32 `ITaskbarList3` via HWND — **taskbar
  progress = round-timer / teams-answered** (native + genuinely useful for
  an emcee glancing at a minimized cockpit); jump list "Start a Live
  Night / Resume"; overlay badge.
- **Global hotkeys (MUST host):** Avalonia's are in-app only; P/Invoke
  Win32 `RegisterHotKey`+`WM_HOTKEY` so **Reveal/Next work even when the
  projector or another app has focus** — essential for a running show.
- **Keyboard-first (MUST):** access keys (`_File`, `_Reveal`), in-app
  accelerators (Space=reveal, ←/→=prev/next, digits=jump team, Esc=hold),
  full Alt-menu bar (File/Game/Live/View/Help), visible focus ring.
- **Window mgmt (MUST):** Snap Layouts are free with the standard maximize
  button — with custom chrome, verify the hover flyout still fires; else
  add `WM_NCHITTEST`→`HTMAXBUTTON`. Remember + validate window geometry
  against connected screens on restore. Per-monitor DPI (projector often
  100% while laptop 150% — test both).
- **The interop seam:** ONE `Win32HostInterop` helper off
  `TryGetPlatformHandle()` (HWND) for DWM backdrop, taskbar, RegisterHotKey,
  snap hit-test — Windows-guarded, mirrors the Apple `#if os()` seam so the
  shared game/RTDB core stays clean.
- **Build order:** Wave 1 native-at-all (Mica+chrome, projector+hot-plug,
  identity, keyboard cockpit, geometry+snap) → Wave 2 designed-for-Windows
  (toasts, taskbar progress=timer, global hotkeys, tray, `tidbitstrivia://`
  protocol into a deep-link inbox) → Wave 3 polish (thumbnail transport,
  overlay badge, startup task, file assoc, FluentAvalonia migration).
- **VERIFY empirically before committing:** (1) Mica+custom chrome on the
  pinned Avalonia build; (2) Snap Layouts through Avalonia's drawn caption.

### Stream 4 — Distribution + signing (the only real cost) ✅

- **$0 auto-update pipeline is real:** GitHub Actions (free Windows
  runner) → **Velopack** (`vpk pack`: installer + delta updates +
  self-updating app, MIT, the maintained Squirrel successor) → **GitHub
  Releases** as the update feed. No server, no hosting bill, Mac-driven.
- **Cost floor is code signing.** Three legitimate resolutions:
  - **Microsoft Store — now genuinely $0 AND no SmartScreen.** Individual
    registration fee (was $19) is **waived** since late 2025 (start at
    `storedeveloper.microsoft.com`, ID + selfie verification). **The Store
    re-signs your MSIX**, so users never see SmartScreen and you never buy
    a cert. Trade-offs: must package **MSIX** (do it on the free Windows
    runner — `MakeMsix` cross-platform is imperfect), Store review, sandbox
    model, Store-mediated updates (lose Velopack delta in-Store).
  - **Ship unsigned via Velopack/GitHub — $0 with a UX tax.** Every
    direct-download user hits the Defender SmartScreen "unknown publisher"
    blue box (More info → Run anyway) until file reputation accrues. Fine
    for beta/technical; a conversion drag for consumers. **Self-signed is
    WORSE than unsigned** (hard-blocked) — never do it.
  - **Azure Artifact Signing (formerly Trusted Signing) — ~$9.99/mo, the
    recommended paid path if we want direct-download without SmartScreen.**
    Cloud (no hardware token), CI-friendly (`azure/trusted-signing-action`
    + `dotnet sign`), **a US-based self-employed individual now qualifies**
    (3-yr business-history requirement dropped). Reputation ties to the
    validated identity across all signed binaries. ~$120/yr all-in.
  - **SignPath OSS free** — Tidbits **likely does NOT qualify** (commercial
    intent + proprietary corpus/apps fail the "no proprietary component"
    bar). **OV/EV certs** ($200–685/yr + mailed FIPS dongle) — avoid; EV's
    instant-SmartScreen pass was removed in 2024, so they buy nothing extra.

## FEASIBILITY VERDICT — GO (fully feasible at ~$0, from this Mac)

**Every hard constraint is satisfiable:**
- ✅ **Native Windows, not a port:** Avalonia UI v12 + FluentAvalonia →
  real Win11 Fluent look; the Windows-first affordances (Mica, projector
  via Screens API, taskbar-progress timer, global hotkeys, keyboard cockpit,
  toasts) make it first-class, not a resized Mac app.
- ✅ **Built entirely from the Mac:** `dotnet publish -r win-x64
  --self-contained` (JIT, not AOT) cross-builds from Apple Silicon; develop
  against the Avalonia **macOS head** locally.
- ✅ **Testable/observable without a Windows PC:** `Avalonia.Headless` →
  pixel-faithful **PNG on the Mac** (the observability unlock the macOS work
  lacked) + free `windows-latest` CI (unlimited on our public repo) for the
  real-Windows confirmation.
- ✅ **~$0:** dotnet/Avalonia/Velopack/GitHub Actions/GitHub Releases all
  free. **Two genuinely-$0 distribution answers:** Microsoft Store (free +
  auto-signed, no SmartScreen) OR ship-unsigned. Optional ~$10/mo Azure
  signing only if we want unsigned-free direct download — deferrable.
- ✅ **Full Tidbits Live parity:** Windows is a new **C# client of the
  shared RTDB `live/{code}` data plane** (twin of firebase.js / Swift
  client) — the cockpit + big-screen + join flow all map to Avalonia
  multi-window; no backend change.

**Effort shape:** ~60–70% is a **C# port of Core** (models, RTDB REST
client, wire types, game/queue/scoring/Elo logic, the Live host session) —
mechanical, testable headless. The other ~30% is the **Avalonia Fluent
shell** (consumer game + host cockpit + projector) — new, but PNG-verifiable.

**Recommended $0 stance for the owner decision (below):** ship-unsigned via
Velopack/GitHub Releases for the beta audience (holds the $0 line, pipeline
unchanged when we add signing), and pursue the **free Microsoft Store**
channel in parallel for the no-SmartScreen path. Defer Azure signing until
there's an audience to justify $120/yr.

## Resolved / remaining owner decisions

- **Distribution:** RESOLVED direction — **both**: free Microsoft Store
  (MSIX, auto-signed, $0) + Velopack/GitHub Releases (unsigned initially).
  Owner only needs to confirm appetite for the Store's MSIX + review.
- **Signing spend:** default **$0 (unsigned + Store)**; ~$10/mo Azure is a
  later, optional upgrade — owner decides when there's an audience.
- **Still to verify empirically (in build, not research):** Mica + custom
  chrome + Snap Layouts on the exact pinned Avalonia 12 build.

## Open questions for the owner

- Distribution target: Microsoft Store (~one-time fee) vs GitHub
  Releases sideload ($0)? Affects MSIX identity + toast notifications.
- Acceptable to ship **unsigned** initially (SmartScreen warning) to
  hold the $0 line, signing later once there's an audience?
