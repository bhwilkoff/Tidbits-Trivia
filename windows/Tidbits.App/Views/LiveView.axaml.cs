using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

public partial class LiveView : UserControl
{
    public LiveView()
    {
        InitializeComponent();

        CategoryPicker.ItemsSource = TriviaCategory.All;
        CategoryPicker.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<TriviaCategory>(
            (c, _) => new TextBlock { Text = c?.Name ?? "" });
        CategoryPicker.SelectedIndex = 0; // Mixed Bag

        foreach (var (name, blurb, plan) in NightPlan.Presets)
        {
            var p = plan;
            var btn = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Avalonia.Thickness(18, 14),
                Content = new StackPanel
                {
                    Spacing = 2,
                    Children =
                    {
                        new TextBlock { Text = name, FontWeight = Avalonia.Media.FontWeight.Bold, FontSize = 16 },
                        new TextBlock { Text = blurb, FontSize = 12, Opacity = 0.65 },
                    },
                },
            };
            btn.Click += (_, _) => StartHosting(p, name);
            PresetsPanel.Children.Add(btn);
        }
    }

    private async void StartHosting(NightPlan plan, string title)
    {
        var data = GameData.Shared.Value;
        var category = CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");
        var host = new LiveNightHost(plan, category, data.Provider, title)
        {
            SpeedBonus = SpeedBonusCheck.IsChecked == true,
            HostPlays = HostPlaysCheck.IsChecked == true,
            HostName = string.IsNullOrWhiteSpace(HostNameBox.Text) ? "Host" : HostNameBox.Text!.Trim(),
        };
        var vm = new LiveHostViewModel(host);
        Setup.IsVisible = false;
        CockpitHost.Content = new LiveCockpitView { DataContext = vm };
        StatusText.IsVisible = false;
        try
        {
            await vm.StartHosting();
            if (!host.IsOpen)
            {
                // Couldn't open a room — return to setup with the reason.
                CockpitHost.Content = null;
                Setup.IsVisible = true;
                StatusText.Text = host.ErrorText ?? "Couldn't start hosting.";
                StatusText.IsVisible = true;
            }
        }
        catch (Exception ex)
        {
            CockpitHost.Content = null;
            Setup.IsVisible = true;
            StatusText.Text = $"Couldn't start hosting: {ex.Message}";
            StatusText.IsVisible = true;
        }
    }

    private void OnJoinGame(object? sender, RoutedEventArgs e)
    {
        Setup.IsVisible = false;
        CockpitHost.Content = new JoinPlayerView { DataContext = new LivePlayerViewModel() };
    }

    /// Called by the cockpit's Close to return to setup.
    public void BackToSetup()
    {
        CockpitHost.Content = null;
        Setup.IsVisible = true;
    }
}
