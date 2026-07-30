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

        Loaded += (_, _) =>
        {
            if (Nav.SelectedItem is null && Nav.MenuItems.Count > 0)
                Nav.SelectedItem = Nav.MenuItems[0];
            // Render the landing surface DIRECTLY rather than waiting for SelectionChanged.
            // FANavigationView can settle on the first item on its own without ever raising
            // the event, which left the detail pane blank until the user clicked the sidebar.
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
