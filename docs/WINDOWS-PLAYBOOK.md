# Windows Tidbits — Build/Test/Ship Playbook ($0, from a Mac)

**Companion to `WINDOWS-DESIGN.md`** (the binding spec) and
`WINDOWS-RESEARCH.md` (the evidence). This is the **HOW**: the exact
$0 toolchain, the observability harness that lets us SEE the Windows
UI from this Mac, the first-class-Windows implementation recipes, and
the CI/distribution pipeline. All commands run on this Apple Silicon
Mac unless marked _(CI)_.

---

## 1. Toolchain (all free, all on the Mac)

```bash
brew install --cask dotnet-sdk        # .NET 9 SDK (free); `dotnet --version`
dotnet new install Avalonia.Templates # Avalonia project templates
```
- **Avalonia 12** (pin an exact patch — §7 of the design doc: Mica is a
  moving target). **FluentAvalonia** for WinUI-accurate controls.
- Editor: VS Code + the C# Dev Kit (free), or Rider (JetBrains, paid —
  optional).
- **No Windows machine, no Visual Studio, no Xcode-equivalent needed to
  build.** The Skia renderer is why (design §0).

### Cross-build a runnable Windows binary (from the Mac)
```bash
dotnet publish src/Tidbits.Windows/Tidbits.Windows.csproj \
  -c Release -r win-x64 --self-contained \
  -p:PublishSingleFile=true            # JIT, NOT AOT (§0.3)
# → bin/Release/net9.0/win-x64/publish/Tidbits.exe  (won't run on the Mac;
#   validate via headless PNG + windows-latest CI, §3–§4)
```

### Repo layout (sibling to `android/`, mirrors the universal-target idea)
```
windows/
├── Tidbits.sln
├── src/
│   ├── Tidbits.Core/         # C# port: models, RTDB client, wire types,
│   │                         #   game/queue/scoring/Elo, Live host session.
│   │                         #   OS-agnostic — NO Avalonia, NO Win32.
│   ├── Tidbits.App/          # Avalonia UI: shell, consumer game, cockpit,
│   │                         #   projector, records, settings (XAML + VMs)
│   └── Tidbits.Windows/      # net9.0-windows head: Win32HostInterop,
│                             #   packaging, entry point
└── tests/
    └── Tidbits.HeadlessTests/ # [AvaloniaFact] PNG-capture + golden-vector
```

---

## 2. The Core C# port (the ~60–70%)

Port, don't bridge (design §0.1). Source of truth = `DATA-CONTRACT.md`
+ the RTDB room schema + the existing Swift/Kotlin/JS twins.

- **RTDB client:** a C# twin of `firebase.js` / Swift `FirebaseRTDB` —
  REST over `HttpClient` (anon auth token refresh, `.json?auth=`, ETag,
  `PUT`/`PATCH`/streaming via SSE `EventSource` equivalent). No Firebase
  SDK (parity with the no-SDK Apple client).
- **Wire types:** `record` types with `System.Text.Json`; **golden-vector
  tests** (mirror `run_golden.sh`) assert byte-compatibility with the
  other clients (design §8.7).
- **Game/scoring/Elo/queue + Live host session:** direct port of the
  shared logic; unit-tested headless (no UI).
- **Persistence:** SQLite (`sqlite-net-pcl` or EF Core) for records/
  streaks/missed-facts — the SwiftData/Room analog.

---

## 3. Observability — SEE the Windows UI from the Mac (the unlock)

This is the spine that the macOS work lacked. `Avalonia.Headless`
renders the **real** UI to a PNG on the Mac, pixel-faithful to Windows
(Skia is OS-independent; only native window chrome differs).

```csharp
// tests/Tidbits.HeadlessTests/Snapshots.cs
using Avalonia; using Avalonia.Headless;
// one-time per project:
[assembly: AvaloniaTestApplication(typeof(TestAppBuilder))]
public class TestAppBuilder {
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<Tidbits.App.App>()
            .UseSkia()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions {
                UseHeadlessDrawing = false   // false => REAL Skia pixels (load-bearing)
            });
}

public class Snapshots {
    [AvaloniaTheory]
    [InlineData("cockpit", 1280, 800, "Dark")]
    [InlineData("projector", 1920, 1080, "Dark")]
    [InlineData("consumer-game", 1100, 760, "Light")]
    public void Capture(string screen, int w, int h, string theme) {
        var win = new Window { Width = w, Height = h,
            RequestedThemeVariant = theme == "Dark" ? ThemeVariant.Dark : ThemeVariant.Light,
            Content = ScreenFactory.Make(screen) };   // env-hook style, like APP_START_*
        win.Show();
        win.CaptureRenderedFrame().Save($"artifacts/{screen}-{theme}.png");
    }
}
```
```bash
dotnet test tests/Tidbits.HeadlessTests   # writes artifacts/*.png on the Mac
# then Read the PNGs to verify design — the loop the macOS ImageRenderer couldn't do
```
- **Doubles as visual-regression:** commit baseline PNGs; diff new
  captures with a tolerance to catch layout drift.
- **What it does NOT show:** native Win11 title bar, Mica, OS font
  substitution, snap flyout — those need real Windows (§4).

---

## 4. Real-Windows confirmation (free CI) _(CI)_

`windows-latest` is **unlimited-free on our public repo**. Two captures:
headless PNG (deterministic) + a desktop screenshot (real chrome/Mica).

```yaml
# .github/workflows/windows-build.yml
name: Windows build + snapshots
on: { workflow_dispatch: {}, push: { paths: ['windows/**'] } }
jobs:
  build:
    runs-on: windows-latest              # free on public repos
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: '9.0.x' }
      - run: dotnet test windows/tests/Tidbits.HeadlessTests   # golden + PNG on Windows
      - run: dotnet publish windows/src/Tidbits.Windows -c Release -r win-x64 --self-contained
      # optional: launch the exe + PowerShell CopyFromScreen for a real-chrome shot
      - uses: actions/upload-artifact@v4
        with: { name: snapshots, path: '**/artifacts/*.png' }
```
- Download the artifact → `Read` the PNGs → verify Mica/caption/snap that
  headless can't show. This is the "done" gate (design §8.6).

---

## 5. First-class-Windows recipes (the point of the platform)

All HWND interop lives in ONE Windows-guarded `Win32HostInterop` (design
§0.2). Sketches:

### 5.1 Mica + Win11 caption
```xml
<Window xmlns="https://github.com/avaloniaui"
        TransparencyLevelHint="Mica" Background="Transparent"
        ExtendClientAreaToDecorationsHint="True">
  <!-- panels use theme-variant brushes WITH ALPHA so Mica shows through -->
</Window>
```
Fallback if the pinned build black-windows on Mica: DWM interop —
`DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, DWMSBT_MAINWINDOW)`.
**VERIFY on CI screenshot before committing to the look** (design §8.5).

### 5.2 Projector on the second monitor (the Live core, §6.3)
```csharp
var target = Screens.All.FirstOrDefault(s => !s.IsPrimary) ?? Screens.Primary;
var big = new ProjectorWindow { SystemDecorations = SystemDecorations.None };
big.Position = target.Bounds.Position;      // THEN fullscreen (order matters)
big.WindowState = WindowState.FullScreen;
big.Show();
// hot-plug survival:
Screens.Changed += (_, _) => Reproject(big);  // re-pick screen; fall back to primary, never vanish
```

### 5.3 Taskbar progress = the round timer (§6.2)
`ITaskbarList3.SetProgressValue(hwnd, elapsed, duration)` each tick;
`SetProgressState(TBPF_NORMAL/PAUSED)` on hold. Emcee sees the timer on
a minimized cockpit.

### 5.4 Global hotkeys (§6.2)
`RegisterHotKey(hwnd, id, mods, vk)` for Reveal/Next; pump `WM_HOTKEY`
via an Avalonia `Win32` message hook. Works when the projector/another
app has focus — essential for a running show.

### 5.5 Toasts (§6.5)
`DesktopNotifications.Avalonia` — register `INotificationManager` in the
AppBuilder; `Show(new Notification { Title=..., Body=... })`. Needs
package identity (§0.4).

### 5.6 Keyboard cockpit + Alt-menus (§3.2, §6.2)
Access keys via `_` in menu headers; `HotKeyManager.SetHotKey` /
`KeyGesture` for Space=reveal, ←/→=prev/next, digits=jump, Esc=hold.
Keep the system-accent focus ring visible.

---

## 6. Publishing — the channel decision (which store, and how)

**THE RECOMMENDATION: Microsoft Store as the primary channel, GitHub
Releases + winget as the $0 direct channel alongside it.** Rationale
below; game storefronts (Steam/itch.io) are a *later, consumer-only*
option, not the host/venue path.

### 6.1 Channel matrix (all Mac-authored; CI does the Windows steps)

| Channel | Cost | Signing / SmartScreen | Auto-update | Best for | Verdict |
|---|---|---|---|---|---|
| **Microsoft Store (MSIX)** | **$0** (reg fee waived 2025) | **MS signs it → NO SmartScreen** | Store-managed | Broadest reach, trust, discoverability | **PRIMARY** |
| **GitHub Releases + Velopack** | $0 | Unsigned → SmartScreen until rep builds (or add Azure signing) | Velopack delta self-update | Direct download, fast iteration, beta channel | **SECONDARY (pair w/ Store)** |
| **winget** (`winget install`) | $0 | Points at your GitHub installer (inherits its signing) | via the referenced installer | Power users, IT, scriptable installs | **ADD — free, easy** |
| **Website direct** (tidbitstrivia.com) | $0 | Same as GitHub installer | via Velopack | Venue operators, link from web app | Yes (same artifact) |
| **Steam** (Steamworks) | **$100 one-time**, recoupable after $1k rev; **30% cut** | Steam handles it | Steam client | *Consumer game*, games audience | Later/optional, consumer-only |
| **itch.io** | $0 to publish; you set rev split | itch app handles it | itch app | *Consumer game*, indie audience | Later/optional, consumer-only |

### 6.2 Why Microsoft Store is the right primary path

- **It kills the signing problem for free.** Registration fee is waived
  (start at `storedeveloper.microsoft.com`, ID-verify), and **Microsoft
  signs the package** — users see **no SmartScreen "unknown publisher"
  warning** and you never buy or renew a cert. This is the single
  biggest reason to go Store-primary: it's the only $0 path that also
  removes the trust warning.
- **Discoverability + auto-update** are built in — a venue owner can
  search "Tidbits" in the Store, and updates flow without our infra.
- **Submission reality (2026):** the Store's MSIX submission is a
  **periodic semi-manual step** (Partner Center web upload; the VS
  "automate store submissions" feature was removed in VS 2026, and the
  programmatic submission API covers MSI/EXE better than MSIX). Fine for
  a desktop app shipping every few weeks — package MSIX on the free
  `windows-latest` runner, then upload to Partner Center. (Alternatively
  the Store accepts **unpackaged MSI/EXE** apps by pointing at a stable
  installer URL + the MSI/EXE submission API — but MSIX is what gets the
  auto-signing/no-SmartScreen benefit, so prefer MSIX for the Store.)

### 6.3 Why ALSO ship GitHub Releases + winget (the $0 direct channel)

Store review adds latency and MSIX sandboxing; the direct channel gives
control + speed and reaches users who don't use the Store:
1. GitHub Actions: `dotnet publish -r win-x64 --self-contained` _(CI)_.
2. **Velopack** `vpk pack` → installer + delta updates + self-updating
   app _(CI, free Windows runner)_.
3. Publish assets to **GitHub Releases** (the update feed — $0 hosting);
   app self-updates via Velopack `UpdateManager`.
4. **winget manifest** (a YAML PR to `microsoft/winget-pkgs`, or
   `wingetcreate` — **free, no Windows PC needed**) pointing at the
   GitHub Release installer, so `winget install Tidbits.TidbitsTrivia`
   works for power users / IT / scripted venue setups.
- SmartScreen applies to this channel until reputation builds — the Store
  channel is the "no warning" path; this is the "full control" path.

### 6.4 The signing question (only relevant to the direct channel)

The Store channel needs no signing (MS does it). For the **direct**
channel, in cost order: **ship unsigned** ($0, SmartScreen tax) →
**Azure Artifact Signing ~$9.99/mo** (cloud, no token,
`azure/trusted-signing-action`, US individual qualifies; removes
SmartScreen; pipeline unchanged — just add a sign step) → **avoid**
OV/EV certs ($200–685/yr + mailed FIPS dongle, no better outcome; EV's
instant-SmartScreen pass was removed in 2024). **Never self-sign** (hard-
blocked, worse than unsigned).

### 6.5 Game storefronts (consumer mode only, later)

Tidbits is a game, so **Steam** and **itch.io** are legitimate channels
*for the consumer game* — but NOT for the host/venue app, and not needed
initially. **Steam** = $100 one-time (recoupable after $1k revenue) +
30% cut, but a huge built-in games audience + it handles
signing/updates. **itch.io** = free to publish, you set the revenue
split, indie-game audience. Consider these only if/when the consumer
game is a monetization focus; the host/venue marquee ships via Store +
direct.

### 6.6 Bottom line

- **Host/venue app (the marquee):** Microsoft Store (MSIX, $0, no
  SmartScreen) + GitHub Releases/Velopack + winget + a website download
  link. All $0.
- **Consumer game:** same Store + direct channels; optionally add
  itch.io ($0) and later Steam ($100) for the games audience.
- **Start with:** Store + GitHub Releases/Velopack in parallel from day
  one of shipping — same build artifact, two channels, $0.

---

## 7. Bootstrap sequence (to first running slice — host-first)

1. **Scaffold** `windows/` (solution + 4 projects §1) + the headless
   test project + the `windows-build.yml` CI. Commit; confirm CI green.
2. **Core port, thin:** wire types + RTDB read client + golden-vector
   test passing against the existing vectors (§2). This proves the
   contract twin before any UI.
3. **Projector window** (§5.2) rendering a static `LiveRoom.Pub` from a
   fixture → headless PNG at 1920×1080 → `Read`. First visual proof.
4. **Cockpit shell** (Mica, keyboard map, taskbar timer) publishing to a
   test `live/CODE` → verify a phone/web joiner sees it (real end-to-end
   parity, the macOS↔web pattern).
5. **Consumer game** (parity) — engine port + game view + records
   dashboard (§3, §4).
6. **Package** (sparse + MSIX), Velopack, first GitHub Release.
7. Each step: headless PNG + `windows-latest` CI + PARITY.md row.

**Definition of done for the platform:** a host runs a full night from a
Windows laptop with a projector on the second screen, players join from
phones, and the consumer game + records reach parity — verified by PNG +
CI, shipped via a $0 channel.

---

## 8. Cost ledger (honest)

| Item | Cost |
|---|---|
| .NET SDK, Avalonia, FluentAvalonia, Velopack | $0 (MIT/free) |
| Build from Mac + `windows-latest` CI (public repo) | $0 |
| Headless PNG observability | $0 |
| GitHub Releases (update feed) | $0 |
| Microsoft Store registration + signing | $0 (fee waived, Store signs) |
| **Ship-unsigned direct download** | **$0** (SmartScreen UX tax) |
| _Optional:_ Azure Artifact Signing (no SmartScreen, direct dl) | ~$10/mo |
| _Avoid:_ OV/EV certs (+ mailed FIPS dongle) | $200–685/yr |

**Steady-state $0 is achievable.** The only non-$0 option worth
considering later is ~$10/mo Azure signing, and only to remove the
SmartScreen prompt on direct downloads — deferrable and pipeline-
compatible.
