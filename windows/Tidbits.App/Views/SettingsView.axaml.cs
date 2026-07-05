using System.Reflection;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Tidbits.App.Services;

namespace Tidbits.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        ReviewToggle.IsChecked = GameData.Shared.Value.Settings.ReviewEnabled;
        var v = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"Tidbits Trivia for Windows — version {v?.ToString(3) ?? "1.0.0"}";
    }

    private void OnReviewToggled(object? sender, RoutedEventArgs e)
    {
        var s = GameData.Shared.Value.Settings;
        s.ReviewEnabled = ReviewToggle.IsChecked ?? true;
        s.Save();
    }

    private void OnResetSeen(object? sender, RoutedEventArgs e)
    {
        GameData.Shared.Value.Provider.ResetSeen();
        ShowStatus("Seen-questions history cleared.");
    }

    private void OnResetRecords(object? sender, RoutedEventArgs e)
    {
        GameData.Shared.Value.Records.ResetAll();
        ShowStatus("All records reset.");
    }

    private void ShowStatus(string text)
    {
        DataStatus.Text = text;
        DataStatus.IsVisible = true;
    }
}
