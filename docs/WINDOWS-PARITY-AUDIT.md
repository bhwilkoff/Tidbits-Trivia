# Windows ← macOS parity audit playbook

**Why this exists.** The Windows app passed 400+ headless tests, a green
`windows-latest` CI run, and a per-view PNG review — and then the owner opened it
on a real PC and hit four problems inside one session (blank detail pane, 14
stacked Dailies, cockpit buttons that didn't flow, a projector that hijacked the
only display). Every one was invisible to the existing checks, because those
checks **render one view at a time, at a generous fixed size, with no
interaction, in one theme, on a machine with one monitor.**

So this playbook is not "does the code contain the feature." It is organised
around the *failure classes that actually shipped*:

| Class | What hides it | The pass that catches it |
|---|---|---|
| Feature simply absent | nobody diffed the surfaces | **A** |
| Renders only after interaction | snapshots construct the view directly | **B** |
| Clips / collides | snapshots use one comfortable width | **C** |
| Wrong in dark mode | snapshots render one theme | **D** |
| Not a native Windows idiom | no reviewer, only tests | **E** |
| Window/monitor behaviour | headless has no real `Screens` | **F** |
| Unusable by keyboard / Narrator | never exercised | **G** |

**Ground rule (Decision 045):** the Mac head is for iteration only. Every visual
claim is confirmed from `windows-repl.yml` artifacts rendered on `windows-latest`.
"Renders on the Mac" is never "correct on Windows."

**Scope rule:** parity means **same verb, native idiom** — not the same pixels
and not the same words. A macOS sheet becomes an `FAContentDialog`; ⌘N becomes
Ctrl+N; "Lock it in" may read "Submit". Divergence is only a finding when the
*capability* is missing or the Windows idiom is wrong.

---

## Pass A — Feature inventory (macOS surface → Windows counterpart)

Run the extractor, then judge each miss by capability, not wording:

```bash
python3 tools/audit_windows_parity.py            # prints per-surface verb gaps
```

For every macOS surface below, confirm the Windows counterpart exists and the
verb is reachable. Mark `n/a` with a reason for Apple-only things (Game Center,
Sign in with Apple, StoreKit) — those are deliberate, recorded in
`docs/WINDOWS-PARITY.md` "Deferred".

| macOS surface | Windows counterpart | Notes |
|---|---|---|
| `ContentView_macOS` (sidebar shell) | `MainWindow` + `FANavigationView` | §2.1 |
| `HomeView_macOS` | `PlayView` | Quick Play, Surprise me, Customize, Daily, Night, Pass & Play, Online |
| `MacHomeSheets_macOS` | (sheets/dialogs) | onboarding, customize, archive |
| `RecordsView_macOS` | `RecordsView` | dashboard rule R-REC-1 |
| `CreateView_macOS` | `CreateView` | |
| `GameView_macOS` | `GameView` | every answer shape |
| `GameContainerView_macOS` | `GameHost` in `PlayView` | game replaces the root |
| `MacLiveBuilder_macOS` | `LiveView` | round types, presets, saved events |
| `MacLiveHost_macOS` | `LiveCockpitView` | transport, timer, teams, tie-break |
| `MacLiveBigScreen_macOS` | `ProjectorView` / `ProjectorWindow` | §6.3 |
| `MacLivePrint_macOS` | print / CSV export | |
| `MacNight_macOS` | night flow in `PlayView` | |
| `MacVersus_macOS` | `VersusView` | |
| `SettingsView_macOS` | `SettingsView` | account, gameplay, data, about |
| `ClubHubView_macOS` | `ClubHub` | R-CLUB-1 one door |
| `ClubPaywallView_macOS` | `ClubPaywallView` | |
| `ExpeditionsView_macOS` | `ExpeditionsUi` / dialog | |
| `KnowledgeAtlasView_macOS` | `KnowledgeAtlasUi` / dialog | |
| `LinkWallView_macOS` | `LinkWallUi` / dialog | |
| `StoryArchiveView_macOS` | `StoryArchiveDialog` | |
| `MarathonHistoryView_macOS` | `MarathonHistoryDialog` | |

**Fails if:** a user-facing capability exists on macOS, is not Apple-only, and
has no Windows route.

---

## Pass B — Shell & navigation runtime

Not "does the view render" but "does it render **without being told to**."

1. Construct the **whole `MainWindow`** (not a view) and assert
   `ContentHost.Content` is populated with *no* interaction — `ShellLandingTest`.
2. Visit **every** nav destination and assert non-null, non-blank content.
3. Deep-link route: `DeepLink.Parse` → `MainWindow.Route` selects the tab.
4. Game start replaces the window root and returns cleanly (§2.3, §7.2).

**Fails if:** any pane is blank before a click, or content appears only as a side
effect of `SelectionChanged` (§7.14 — this is exactly what shipped).

---

## Pass C — Responsive / layout

Render every primary surface at **820 / 1000 / 1440** logical px.

- 820 is the floor: the `FANavigationView` is in its collapsed/compact state and
  the content column is genuinely tight.
- Any row of >3 controls must be a `WrapPanel` (§6.3b).
- Nothing may clip, overlap, or leave the viewport.

**Fails if:** a control is cut off, or a horizontal group overflows instead of
wrapping.

---

## Pass D — Theme

Render each primary surface in **Light and Dark** (`RequestedThemeVariant`).

- Brand CTAs must keep the brand colour and a legible foreground in BOTH themes.
- Two adjacent CTAs must not disagree (one derived-accent, one hard-coded).
- Text contrast must survive; no black-on-coral or white-on-cream.

**Fails if:** a surface is only designed for one theme. This is the Windows twin
of `macos-light-appearance-pin`.

---

## Pass E — Native Windows idiom (design quality)

This is the pass with no automated check — it is a review against
`docs/WINDOWS-DESIGN.md`:

1. **FluentAvalonia component first** — `NavigationView`, `FAContentDialog`,
   `SettingsExpander`, `InfoBar`, `NumberBox`, `CommandBar` before any custom
   control (§5, §7).
2. **Settings uses `SettingsExpander` rows**, not a hand-rolled stack.
3. **Dialogs are `FAContentDialog`** with real primary/close buttons, not
   improvised panels.
4. **Type ramp**: only the six `App.axaml` levels; no ad-hoc `FontSize`.
5. **`Border.card`** owns elevation; no hand-added shadow padding (§5.2, §7.8).
6. **Buttons size to content**; no full-width button beside another control
   (§5.4, §7.7).
7. **Destructive actions** are confirmed and marked.
8. **Mica** backdrop on the main window; respects transparency settings.

**Fails if:** a surface reimplements something Fluent already provides, or looks
like a ported macOS/iOS layout (§7.1).

---

## Pass F — Window model (real hardware only)

Cannot be verified from the Mac — headless has no real `Screens`, and this repo
has no Windows box with two displays. **Record these as owner-verified or
UNVERIFIED; never imply they were checked.**

1. Projector on a **single-monitor** machine → normal decorated, resizable,
   taskbar-visible window (§6.3a).
2. Projector with a **second monitor** → chromeless fullscreen on the
   non-primary display.
3. **Hot-plug**: unplug mid-night → falls back, never vanishes (§6.3, §7.10).
4. Esc always leaves fullscreen.
5. Taskbar progress reflects the round timer (§6.2).

---

## Pass G — Input & accessibility

1. Every cockpit action has a keyboard route (Space=reveal, ←/→, digits).
2. App-level accelerators exist for the common verbs (Ctrl+N new game,
   Ctrl+, settings) — the Windows twin of macOS's menu commands.
3. **`AutomationProperties.Name` on every icon-only or custom-drawn control** —
   Narrator reads nothing otherwise.
4. Tab order reaches every interactive control; focus is visible.

**Fails if:** a control is mouse-only, or unnamed for assistive tech.

---

## How to run the whole thing

```bash
# A — inventory
python3 tools/audit_windows_parity.py

# B/C/D — runtime, widths, themes (writes artifacts/audit/*.png)
cd windows && dotnet test --filter "FullyQualifiedName~WindowsAuditTest"

# then the REAL gate — render the same set on Windows and read the PNGs
gh workflow run windows-repl.yml
gh run download <id> -D /tmp/winaudit
```

Record every finding in `docs/WINDOWS-PARITY.md` with its rule number, and add a
regression test for anything that shipped broken — a finding without a test is a
finding that comes back.
