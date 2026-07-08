using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

/// The async-duels presentation (2.24): a "your turn / waiting / won / lost"
/// list + an inbox of incoming challenges. Static builders so the panel renders
/// from injected data in a headless test (the DuelStore network fetch wires in
/// separately).
public static class DuelsUi
{
    private static readonly IBrush Coral = new SolidColorBrush(Color.Parse("#FF5C35"));
    private static readonly IBrush Green = new SolidColorBrush(Color.Parse("#2FCB8A"));
    private static readonly IBrush Red = new SolidColorBrush(Color.Parse("#FF5C5C"));
    private static readonly IBrush Dim = new SolidColorBrush(Color.Parse("#9098A0"));

    public static (string label, IBrush color) OutcomeChip(DuelSummary d) => d.Outcome switch
    {
        DuelOutcome.YourTurn => ("Your turn", Coral),
        DuelOutcome.WaitingOnThem => ($"Waiting on {d.OppName}", Dim),
        DuelOutcome.YouWon => ($"You won {d.MyScore}–{d.OppScore}", Green),
        DuelOutcome.YouLost => ($"You lost {d.MyScore}–{d.OppScore}", Red),
        _ => ($"Tie {d.MyScore}–{d.OppScore}", Dim),
    };

    /// The full panel: incoming challenges (inbox) + my active/finished duels.
    /// `onAccept(id)` / `onPlay(id)` fire the actions; either may be null in tests.
    public static Control BuildPanel(IReadOnlyList<DuelSummary> mine, IReadOnlyList<DuelInvite> inbox,
        Action<string>? onAccept = null, Action<string>? onPlay = null)
    {
        var root = new StackPanel { Spacing = 14, MinWidth = 380 };

        if (inbox.Count > 0)
        {
            root.Children.Add(Header($"Challenges ({inbox.Count})"));
            foreach (var inv in inbox)
            {
                var id = inv.Id;
                var card = Card();
                var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
                grid.Children.Add(new TextBlock { Text = $"{inv.FromName} challenged you", VerticalAlignment = VerticalAlignment.Center, FontWeight = FontWeight.SemiBold });
                var accept = new Button { Content = "Accept", Padding = new Avalonia.Thickness(14, 6) };
                accept.Click += (_, _) => onAccept?.Invoke(id);
                Grid.SetColumn(accept, 1);
                grid.Children.Add(accept);
                card.Child = grid;
                root.Children.Add(card);
            }
        }

        root.Children.Add(Header("Your duels"));
        if (mine.Count == 0)
        {
            root.Children.Add(new TextBlock { Text = "No duels yet — challenge a friend from the leaderboard.", Opacity = 0.65, TextWrapping = TextWrapping.Wrap });
            return new ScrollViewer { Content = root, MaxHeight = 520 };
        }

        foreach (var d in mine)
        {
            var duel = d;
            var (label, color) = OutcomeChip(d);
            var card = Card();
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            var left = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
            left.Children.Add(new TextBlock { Text = $"vs {d.OppName}", FontWeight = FontWeight.SemiBold });
            left.Children.Add(new TextBlock { Text = label, Foreground = color, FontSize = 12, FontWeight = FontWeight.SemiBold });
            grid.Children.Add(left);
            if (d.Outcome == DuelOutcome.YourTurn)
            {
                var play = new Button { Content = "Play", Padding = new Avalonia.Thickness(16, 6), Foreground = Brushes.White, Background = Coral };
                play.Click += (_, _) => onPlay?.Invoke(duel.Id);
                Grid.SetColumn(play, 1);
                grid.Children.Add(play);
            }
            card.Child = grid;
            root.Children.Add(card);
        }
        return new ScrollViewer { Content = root, MaxHeight = 520 };
    }

    private static TextBlock Header(string t) => new() { Text = t, FontSize = 16, FontWeight = FontWeight.Bold };

    private static Border Card() => new()
    {
        Background = new SolidColorBrush(Color.Parse("#0F808080")),
        CornerRadius = new Avalonia.CornerRadius(12), Padding = new Avalonia.Thickness(14, 12),
    };
}
