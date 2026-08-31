using System;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Input;
using CommunityToolkit.Mvvm.Input;
using FluentAvalonia.UI.Controls;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        ClampToScreen();

        Loaded += (_, _) =>
        {
            if (Nav.SelectedItem is null && Nav.MenuItems.Count > 0)
                Nav.SelectedItem = Nav.MenuItems[0];
            // Render the landing surface DIRECTLY rather than waiting for SelectionChanged.
            // FANavigationView can settle on the first item on its own without ever raising
            // the event, which left the detail pane blank until the user clicked the sidebar.
            // TIDBITS_TAB=play|records|leaderboard|create|live — open a section on
            // launch, the Windows mirror of Apple's DebugHooks.initialTab and
            // Android's tidbits_tab. Windows had NO navigation hook at all: it was
            // only ever driven by the headless Avalonia tests, which construct a
            // view in-process and never navigate the real shell. So a harness on a
            // real desktop could launch the app and nothing else, and every
            // "records" or "create" assertion was really grading the Play screen.
            var startTab = Environment.GetEnvironmentVariable("TIDBITS_TAB");
            var tags = Nav.MenuItems.OfType<FANavigationViewItem>().ToList();
            var wanted = tags.FirstOrDefault(i =>
                string.Equals(i.Tag as string, startTab, StringComparison.OrdinalIgnoreCase));
            if (wanted is not null)
                Nav.SelectedItem = wanted;

            if (ContentHost.Content is null)
                Navigate((Nav.SelectedItem as FANavigationViewItem)?.Tag as string ?? "play");
            // Deep-link inbox: route a launch URL once shown (external entry points
            // never touch the nav directly — they land here and the root consumes them).
            var target = Tidbits.Core.Networking.DeepLink.Parse(Program.LaunchUrl);
            Route(target);
            // First-run walkthrough (macOS parity). After routing, so a deep link still lands
            // where it should and the dialog simply sits over it.
            _ = OnboardingDialog.ShowIfFirstRunAsync();
        };

        // App-level accelerators — the Windows twin of the macOS menu commands (Ctrl+N new
        // game, Ctrl+, settings). Windows users reach for these; without them the app is
        // pointer-only for its two most common verbs.
        KeyBindings.Add(new KeyBinding
        {
            Gesture = new KeyGesture(Key.N, KeyModifiers.Control),
            Command = new RelayCommand(() => Select("play")),
        });
        KeyBindings.Add(new KeyBinding
        {
            Gesture = new KeyGesture(Key.OemComma, KeyModifiers.Control),
            Command = new RelayCommand(() => { Nav.IsSettingsVisible = true; Navigate("settings"); }),
        });
    }

    /// Shrink the startup size to fit the display it opens on.
    ///
    /// The window asks for 1180x760, matching the Mac's `.defaultSize`. But AppKit
    /// silently shrinks a window that does not fit the visible frame and Avalonia does
    /// not, so the same numbers behave differently on the two platforms: on the dev box
    /// — a 1080x1920 portrait display — the window opened 1180 wide and ~100px of it,
    /// including the right edge of every screen, was off the display. Measured, not
    /// guessed: the harness reads the window rect off the box and it came back 1.8%
    /// wider than the screen.
    ///
    /// This matters well beyond one rotated monitor. 1366x768 is the most common
    /// Windows 10 laptop resolution there is, and 760 plus a title bar does not fit in
    /// 768 either — so the bottom of every screen was cut off on the cheapest hardware
    /// the app targets, which is exactly the hardware least likely to be tested on.
    ///
    /// WorkingArea, not Bounds: it excludes the taskbar, which is what actually
    /// constrains a window. MinWidth/MinHeight still win — below those the layout
    /// itself breaks, and a window with a scrollbar beats a window with no content.
    private void ClampToScreen()
    {
        var screen = Screens.Primary ?? Screens.All.FirstOrDefault();
        if (screen is null) return;

        var area = screen.WorkingArea;
        var scale = screen.Scaling <= 0 ? 1.0 : screen.Scaling;
        // WorkingArea is in PHYSICAL pixels; Width/Height are logical units.
        var maxW = area.Width / scale;
        var maxH = area.Height / scale;

        Width = Math.Max(MinWidth, Math.Min(Width, maxW));
        Height = Math.Max(MinHeight, Math.Min(Height, maxH));
    }

    /// Select a nav item by tag (keeps the sidebar highlight and the content in step).
    private void Select(string tag)
    {
        foreach (var item in Nav.MenuItems.OfType<FANavigationViewItem>())
            if (item.Tag as string == tag) { Nav.SelectedItem = item; return; }
        Navigate(tag);
    }

    /// Select the nav tab a deep link routes to (no-op for None).
    public void Route(Tidbits.Core.Networking.DeepLinkTarget target)
    {
        if (target.Kind == Tidbits.Core.Networking.DeepLinkKind.None) return;
        foreach (var item in Nav.MenuItems.OfType<FANavigationViewItem>())
            if (item.Tag as string == target.NavTag) { Nav.SelectedItem = item; break; }
    }

    private void OnNavSelectionChanged(object? sender, FANavigationViewSelectionChangedEventArgs e)
    {
        string tag = e.IsSettingsSelected
            ? "settings"
            : (e.SelectedItem as FANavigationViewItem)?.Tag as string ?? "play";
        Navigate(tag);
    }

    /// Swap the detail pane. Only the section-frame fallback needs the view model, so a
    /// missing DataContext must never cost the app its whole right-hand side.
    private void Navigate(string tag)
    {
        // Play + Records are real surfaces now; the other tabs are still frames.
        if (tag == "play")
        {
            ContentHost.Content = new PlayView();
        }
        else if (tag == "records")
        {
            ContentHost.Content = new RecordsView
            {
                DataContext = new RecordsViewModel(Services.GameData.Shared.Value.Records),
            };
        }
        else if (tag == "leaderboard")
        {
            ContentHost.Content = new LeaderboardView();
        }
        else if (tag == "create")
        {
            ContentHost.Content = new CreateView();
        }
        else if (tag == "settings")
        {
            ContentHost.Content = new SettingsView();
        }
        else if (tag == "live")
        {
            ContentHost.Content = new LiveView();
        }
        else if (DataContext is MainWindowViewModel vm && vm.Sections.TryGetValue(tag, out var section))
        {
            ContentHost.Content = new SectionFrameView { DataContext = section };
        }
    }
}
