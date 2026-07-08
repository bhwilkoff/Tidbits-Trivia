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
    // Modes with a built answer surface: MCQ shapes + numeric (Closest Call) +
    // free-text (Name It). Ordering/Matching/Enumerate/Picture ID get their own
    // surfaces in a later parity pass.
    private static readonly GameMode[] Offered =
    {
        GameMode.Classic, GameMode.TimeAttack, GameMode.Survival, GameMode.Sweep,
        GameMode.Ladder, GameMode.OddOneOut, GameMode.ThisOrThat,
        GameMode.ClosestCall, GameMode.TypeAnswer,
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

    private void OnQuickPlay(object? sender, RoutedEventArgs e) => StartGame(GameMode.Classic);
    private void OnDaily(object? sender, RoutedEventArgs e) => StartGame(GameMode.Daily);
}
