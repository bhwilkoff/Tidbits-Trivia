using System;
using System.Linq;
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

        RoundModeBox.ItemsSource = NightPlan.AllKinds;
        RoundModeBox.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<GameMode>(
            (m, _) => new TextBlock { Text = m.Title() });
        RoundModeBox.SelectedIndex = 0;
        RoundCountBox.ItemsSource = new[] { 3, 4, 5, 6, 8 };
        RoundCountBox.SelectedIndex = 1; // 4
        BuildSavedEvents();
    }

    // The rounds being composed for a custom event.
    private readonly System.Collections.Generic.List<NightRound> _rounds = new();

    private void OnAddRound(object? sender, RoutedEventArgs e)
    {
        if (RoundModeBox.SelectedItem is not GameMode mode || RoundCountBox.SelectedItem is not int count) return;
        _rounds.Add(new NightRound { Kind = mode, Count = count });
        RebuildBuilderRounds();
    }

    /// Move a round up (−1) or down (+1) in the running order.
    private void MoveRound(int index, int delta)
    {
        int target = index + delta;
        if (index < 0 || index >= _rounds.Count || target < 0 || target >= _rounds.Count) return;
        (_rounds[index], _rounds[target]) = (_rounds[target], _rounds[index]);
        RebuildBuilderRounds();
    }

    private void RebuildBuilderRounds()
    {
        BuilderRounds.Children.Clear();
        for (int i = 0; i < _rounds.Count; i++)
        {
            int idx = i;
            var r = _rounds[i];
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto,Auto"), Margin = new Avalonia.Thickness(0, 0, 0, 2) };
            row.Children.Add(new TextBlock { Text = $"{idx + 1}. {r.Kind.Title()} · {r.Count} questions", VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center });
            var up = new Button { Content = "▲", Padding = new Avalonia.Thickness(7, 2), FontSize = 11, IsEnabled = idx > 0 };
            up.Click += (_, _) => MoveRound(idx, -1);
            Grid.SetColumn(up, 1);
            row.Children.Add(up);
            var down = new Button { Content = "▼", Padding = new Avalonia.Thickness(7, 2), FontSize = 11, IsEnabled = idx < _rounds.Count - 1, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            down.Click += (_, _) => MoveRound(idx, +1);
            Grid.SetColumn(down, 2);
            row.Children.Add(down);
            var del = new Button { Content = "✕", Padding = new Avalonia.Thickness(8, 2), FontSize = 12, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            del.Click += (_, _) => { _rounds.RemoveAt(idx); RebuildBuilderRounds(); };
            Grid.SetColumn(del, 3);
            row.Children.Add(del);
            BuilderRounds.Children.Add(row);
        }
        RebuildBalance();
    }

    /// The balance meter — a bar per question type (width ∝ its share) + a variety
    /// verdict, so the host can see the night's mix as they compose it.
    private void RebuildBalance()
    {
        BalancePanel.Children.Clear();
        BalancePanel.IsVisible = _rounds.Count > 0;
        if (_rounds.Count == 0) return;

        var shares = Tidbits.Core.Networking.LiveEventBalance.ByType(_rounds);
        int max = shares.Count > 0 ? System.Math.Max(1, shares.Max(s => s.Questions)) : 1;
        foreach (var s in shares)
        {
            var stack = new Panel { Height = 22, Margin = new Avalonia.Thickness(0, 1) };
            stack.Children.Add(new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#33FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(5), HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left,
                Width = 120 + 260.0 * s.Questions / max,
            });
            stack.Children.Add(new TextBlock
            {
                Text = $"{s.Kind.Title()} · {s.Questions}", FontSize = 12, Margin = new Avalonia.Thickness(8, 0),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            });
            BalancePanel.Children.Add(stack);
        }
        BalancePanel.Children.Add(new TextBlock
        {
            Text = Tidbits.Core.Networking.LiveEventBalance.Verdict(_rounds),
            FontSize = 12, FontWeight = Avalonia.Media.FontWeight.SemiBold, Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#FF5C35")),
            Margin = new Avalonia.Thickness(0, 4, 0, 0),
        });
    }

    private LiveEvent CurrentEvent() => new()
    {
        Name = string.IsNullOrWhiteSpace(EventNameBox.Text) ? "Custom Night" : EventNameBox.Text!.Trim(),
        Rounds = new System.Collections.Generic.List<NightRound>(_rounds),
    };

    private void OnHostEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        var ev = CurrentEvent();
        StartHosting(ev.ToPlan(), ev.Name);
    }

    private void OnSaveEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        GameData.Shared.Value.LiveEvents.Save(CurrentEvent());
        BuildSavedEvents();
    }

    private void BuildSavedEvents()
    {
        SavedEvents.Children.Clear();
        var events = GameData.Shared.Value.LiveEvents.All;
        SavedEventsHeader.IsVisible = events.Count > 0;
        foreach (var ev in events)
        {
            var e = ev;
            var row = new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#0F808080")),
                CornerRadius = new Avalonia.CornerRadius(10), Padding = new Avalonia.Thickness(14, 10),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto") };
            grid.Children.Add(new StackPanel
            {
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, Spacing = 1,
                Children =
                {
                    new TextBlock { Text = e.Name, FontWeight = Avalonia.Media.FontWeight.SemiBold },
                    new TextBlock { Text = e.Summary, FontSize = 12, Opacity = 0.65 },
                },
            });
            var host = new Button { Content = "Host", Padding = new Avalonia.Thickness(14, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            host.Classes.Add("accent");
            host.Click += (_, _) => StartHosting(e.ToPlan(), e.Name);
            Grid.SetColumn(host, 1);
            grid.Children.Add(host);
            var del = new Button { Content = "✕", Padding = new Avalonia.Thickness(10, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            del.Click += (_, _) => { GameData.Shared.Value.LiveEvents.Remove(e.Id); BuildSavedEvents(); };
            Grid.SetColumn(del, 2);
            grid.Children.Add(del);
            row.Child = grid;
            SavedEvents.Children.Add(row);
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
