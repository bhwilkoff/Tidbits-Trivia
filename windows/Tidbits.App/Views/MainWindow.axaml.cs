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
        };
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
