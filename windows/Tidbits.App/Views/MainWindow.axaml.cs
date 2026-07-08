using System.Linq;
using Avalonia.Controls;
using FluentAvalonia.UI.Controls;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        // Select the first item once loaded (DataContext is set by then, so the
        // SelectionChanged handler can resolve the section).
        Loaded += (_, _) =>
        {
            if (Nav.SelectedItem is null && Nav.MenuItems.Count > 0)
                Nav.SelectedItem = Nav.MenuItems[0];
            // Deep-link inbox: route a launch URL once shown (external entry points
            // never touch the nav directly — they land here and the root consumes them).
            var target = Tidbits.Core.Networking.DeepLink.Parse(Program.LaunchUrl);
            Route(target);
        };
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
        if (DataContext is not MainWindowViewModel vm)
            return;

        string tag = e.IsSettingsSelected
            ? "settings"
            : (e.SelectedItem as FANavigationViewItem)?.Tag as string ?? "play";

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
        else if (vm.Sections.TryGetValue(tag, out var section))
        {
            ContentHost.Content = new SectionFrameView { DataContext = section };
        }
    }
}
