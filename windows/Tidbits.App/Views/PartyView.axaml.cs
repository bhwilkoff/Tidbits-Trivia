using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// Pass & Play — 2–4 players share one device, each playing the SAME question set
/// with a hand-off between turns and a ranked scoreboard. Matches don't write
/// records (same as the other platforms).
public partial class PartyView : UserControl
{
    private List<string> _names = new();
    private readonly List<int> _scores = new();
    private List<Question> _set = new();
    private int _current;

    /// Raised when the party finishes / the player exits back to Play.
    public event System.Action? Closed;

    public PartyView() => InitializeComponent();

    private async void OnStart(object? sender, RoutedEventArgs e)
    {
        _names = new[] { P1.Text, P2.Text, P3.Text, P4.Text }
            .Select(t => (t ?? "").Trim()).Where(t => t.Length > 0).ToList();
        if (_names.Count < 2) { SetupError.Text = "Enter at least 2 players."; SetupError.IsVisible = true; return; }

        // One shared set for everyone (drawn once, replayed per player).
        _set = await GameData.Shared.Value.Provider.Questions(GameMode.Classic, TriviaCategory.Named("mixed"));
        if (_set.Count == 0) { SetupError.Text = "Couldn't load questions. Try again."; SetupError.IsVisible = true; return; }

        _scores.Clear();
        _current = 0;
        Setup.IsVisible = false;
        ShowHandoff();
    }

    private void ShowHandoff()
    {
        HandoffName.Text = _names[_current];
        StartTurnBtn.Content = _current == 0 ? "Start turn" : "Start turn";
        Handoff.IsVisible = true;
    }

    private void OnStartTurn(object? sender, RoutedEventArgs e)
    {
        Handoff.IsVisible = false;
        var engine = GameData.Shared.Value.NewEngine();
        var vm = new GameViewModel(engine, records: null); // party games don't write records
        vm.Finished += () =>
        {
            _scores.Add(engine.Score);
            GameHost.Content = null;
            _current++;
            if (_current < _names.Count) ShowHandoff();
            else ShowScoreboard();
        };
        vm.Closed += () => { GameHost.Content = null; Closed?.Invoke(); }; // quit mid-party
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("mixed"), new List<Question>(_set));
    }

    private void ShowScoreboard()
    {
        ScoreList.Children.Clear();
        var ranked = _names.Zip(_scores, (name, score) => (name, score))
            .OrderByDescending(p => p.score).ToList();
        // A tie is a real outcome of a shared question set: identical play earns
        // identical scores, so highlighting only the first-sorted row reported an
        // arbitrary sort order as a victory.
        var entries = ranked.Select(p => (Name: p.name, Score: p.score)).ToList();
        int topScore = ranked.Count == 0 ? 0 : ranked.Max(p => p.score);
        WinnerLine.Text = Tidbits.Core.Store.StandingsOutcome.Headline(entries, "Final scores");
        for (int i = 0; i < ranked.Count; i++)
        {
            var row = new Border
            {
                Background = new SolidColorBrush(Color.Parse(ranked[i].score == topScore ? "#FF5C35" : "#0F808080")),
                CornerRadius = new Avalonia.CornerRadius(10), Padding = new Avalonia.Thickness(16, 12),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
            bool win = ranked[i].score == topScore;
            grid.Children.Add(new TextBlock { Text = $"{i + 1}", FontWeight = FontWeight.Black, Foreground = win ? Brushes.White : null, Margin = new Avalonia.Thickness(0, 0, 12, 0) });
            var name = new TextBlock { Text = ranked[i].name, FontWeight = FontWeight.SemiBold, Foreground = win ? Brushes.White : null };
            Grid.SetColumn(name, 1);
            grid.Children.Add(name);
            var score = new TextBlock { Text = $"{ranked[i].score}", FontWeight = FontWeight.Black, Foreground = win ? Brushes.White : null };
            Grid.SetColumn(score, 2);
            grid.Children.Add(score);
            row.Child = grid;
            ScoreList.Children.Add(row);
        }
        Scoreboard.IsVisible = true;
    }

    private void OnDone(object? sender, RoutedEventArgs e) => Closed?.Invoke();
}
