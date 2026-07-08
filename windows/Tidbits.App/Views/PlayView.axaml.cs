using System;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

public partial class PlayView : UserControl
{
    // Every consumer mode now has a built answer surface: MCQ shapes + Stake +
    // numeric (Closest Call) + free-text (Name It) + reorder (In Order) +
    // Match Up + Name as Many + Picture ID (image pipeline).
    private static readonly GameMode[] Offered =
    {
        GameMode.Classic, GameMode.TimeAttack, GameMode.Survival, GameMode.Stake,
        GameMode.Sweep, GameMode.Ladder, GameMode.OddOneOut, GameMode.ThisOrThat,
        GameMode.ClosestCall, GameMode.TypeAnswer, GameMode.Ordering,
        GameMode.Matching, GameMode.Enumerate, GameMode.PictureId,
    };

    public PlayView()
    {
        InitializeComponent();
        CategoryPicker.ItemsSource = TriviaCategory.All;
        CategoryPicker.ItemTemplate = new FuncDataTemplate<TriviaCategory>((c, _) =>
            new TextBlock { Text = c?.Name ?? "" });
        CategoryPicker.SelectedIndex = 0; // Mixed Bag

        foreach (var m in Offered)
        {
            var mode = m;
            var btn = new Button
            {
                Content = mode.Title(),
                Margin = new Avalonia.Thickness(0, 0, 10, 10),
                Padding = new Avalonia.Thickness(16, 11),
            };
            btn.Click += (_, _) => StartGame(mode);
            ModesPanel.Children.Add(btn);
        }

        // Trivia Night presets (Quick / Pub / The Works) — each launches a solo,
        // self-paced night of themed rounds with a round interstitial.
        foreach (var preset in NightPlan.Presets)
        {
            var plan = preset.Plan;
            var card = new Button
            {
                Margin = new Avalonia.Thickness(0, 0, 10, 10), Padding = new Avalonia.Thickness(16, 12),
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Content = new StackPanel
                {
                    Spacing = 2,
                    Children =
                    {
                        new TextBlock { Text = preset.Name, FontWeight = Avalonia.Media.FontWeight.Bold },
                        new TextBlock { Text = preset.Blurb, FontSize = 12, Opacity = 0.65 },
                    },
                },
            };
            card.Click += (_, _) => StartNight(plan);
            NightPanel.Children.Add(card);
        }

        BuildDaily();
    }

    /// Today's Daily (play-once — a done card once completed) plus a "Previous
    /// Tidbits" archive of the last 14 days: past days are playable (deterministic
    /// day-key seed) and never bump the streak (enforced in RecordsStore).
    private void BuildDaily()
    {
        DailyPanel.Children.Clear();
        var log = GameData.Shared.Value.Daily;
        var today = QuestionProvider.DayKey();

        for (int i = 0; i < 14; i++)
        {
            var date = DateTime.Now.Date.AddDays(-i);
            var day = QuestionProvider.DayKey(date);
            bool isToday = day == today;
            var result = log.Result(day);
            var label = isToday ? "Today" : date.ToString("ddd, MMM d");

            var row = new Border
            {
                Background = isToday && result is null ? new SolidColorBrush(Color.Parse("#FF5C35")) : null,
                CornerRadius = new Avalonia.CornerRadius(10),
                BorderBrush = result is not null || !isToday ? new SolidColorBrush(Color.Parse("#22808080")) : null,
                BorderThickness = new Avalonia.Thickness(isToday && result is null ? 0 : 1),
                Padding = new Avalonia.Thickness(16, 12), Margin = new Avalonia.Thickness(0, 0, 0, 6),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            bool heroToday = isToday && result is null;
            var labelBlock = new TextBlock
            {
                Text = label, FontWeight = Avalonia.Media.FontWeight.SemiBold, VerticalAlignment = VerticalAlignment.Center,
            };
            if (heroToday) labelBlock.Foreground = Brushes.White; // else inherit the themed default
            grid.Children.Add(labelBlock);

            if (result is not null)
            {
                var done = new TextBlock
                {
                    Text = $"{result.Correct}/{result.Total} · {result.Score} pts", VerticalAlignment = VerticalAlignment.Center,
                    Opacity = 0.75, FontSize = 13,
                };
                Grid.SetColumn(done, 1);
                grid.Children.Add(done);
            }
            else
            {
                var d = day;
                var play = new Button
                {
                    Content = isToday ? "Play today's Tidbit" : "Play",
                    Padding = new Avalonia.Thickness(16, 8),
                    Classes = { "accent" },
                };
                play.Click += (_, _) => StartDaily(d);
                Grid.SetColumn(play, 1);
                grid.Children.Add(play);
            }
            row.Child = grid;
            DailyPanel.Children.Add(row);
        }
    }

    private async void StartDaily(string day)
    {
        var data = GameData.Shared.Value;
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; BuildDaily(); };
        vm.Finished += () =>
        {
            var s = engine.Summary;
            data.Daily.Record(s.DailyDay ?? day, s.Score, s.Correct, s.Total);
        };
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        await engine.Start(GameMode.Daily, TriviaCategory.Named("mixed"), dailyDay: day);
    }

    private TriviaCategory SelectedCategory() =>
        CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");

    private async void StartGame(GameMode mode, TriviaCategory? category = null)
    {
        var cat = category ?? SelectedCategory();
        var engine = GameData.Shared.Value.NewEngine();
        var vm = new GameViewModel(engine, GameData.Shared.Value.Records);
        vm.Closed += () =>
        {
            GameHost.Content = null;
            Landing.IsVisible = true;
        };
        // Play Again restarts the exact mode + category that was just played.
        vm.PlayAgainRequested += () => StartGame(vm.Summary.Mode, vm.Summary.Category);
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        await engine.Start(mode, cat);
    }

    private async void StartNight(NightPlan plan)
    {
        var cat = SelectedCategory();
        var data = GameData.Shared.Value;
        var questions = await data.Provider.NightQuestions(plan, cat);
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; };
        vm.PlayAgainRequested += () => StartNight(plan);
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartNight(plan, cat, questions);
    }

    private void OnQuickPlay(object? sender, RoutedEventArgs e) => StartGame(GameMode.Classic);
}
