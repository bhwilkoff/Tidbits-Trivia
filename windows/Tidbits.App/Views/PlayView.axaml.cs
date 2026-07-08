using System;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;

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
    private void OnDaily(object? sender, RoutedEventArgs e) => StartGame(GameMode.Daily);
}
