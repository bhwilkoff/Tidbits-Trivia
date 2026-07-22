using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Models;

namespace Tidbits.App.Views;

/// Rendering for the Club Marathon scorecard + history list
/// (docs/CLUB-FEATURES-BUILD.md "Feature 3") — a static, headless-testable
/// builder (mirrors `StoryArchiveUi`). Used both for the just-finished in-game
/// recap (`GameView.MarathonResultHost`) and a past run's read-only detail
/// (`MarathonHistoryDialog`), so there is exactly one scorecard implementation.
public static class MarathonUi
{
    private static readonly IBrush Teal = new SolidColorBrush(Color.Parse("#13B6C9"));
    private static readonly IBrush Blue = new SolidColorBrush(Color.Parse("#2D5BFF"));
    private static readonly IBrush Coral = new SolidColorBrush(Color.Parse("#FF5C35"));

    /// The just-finished recap: score + "vs your last run" + per-domain bars +
    /// See History / Start a new Marathon / Done. `historyCount` is the
    /// "Marathons" stat tile (includes the run just written).
    public static Control BuildScorecard(MarathonScore score, MarathonScore? previous, int historyCount,
        Action onPlayAgain, Action onDone, Action onSeeHistory)
    {
        var stack = new StackPanel { Spacing = 16, MaxWidth = 520 };
        stack.Children.Add(ScoreCard(score));
        stack.Children.Add(ComparisonCard(score, previous));
        stack.Children.Add(StatsRow(score, historyCount));
        stack.Children.Add(DomainCard(score));

        var history = new Button
        {
            Content = "See Marathon history",
            Background = Brushes.Transparent, BorderThickness = new Avalonia.Thickness(0),
            Padding = new Avalonia.Thickness(0), HorizontalAlignment = HorizontalAlignment.Left,
            Foreground = Teal, FontWeight = FontWeight.SemiBold,
        };
        history.Click += (_, _) => onSeeHistory();
        stack.Children.Add(history);

        var playAgain = new Button
        {
            Content = "Start a new Marathon", Classes = { "accent" }, FontWeight = FontWeight.Bold,
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center,
            Padding = new Avalonia.Thickness(0, 13),
        };
        playAgain.Click += (_, _) => onPlayAgain();
        stack.Children.Add(playAgain);

        var done = new Button
        {
            Content = "Done", HorizontalAlignment = HorizontalAlignment.Center,
            Background = Brushes.Transparent, Padding = new Avalonia.Thickness(26, 10),
        };
        done.Click += (_, _) => onDone();
        stack.Children.Add(done);

        return stack;
    }

    /// A past run's read-only detail (Marathon History drill-in) — the same
    /// scorecard content, with a Back link instead of Play Again / Done.
    public static Control BuildHistoryDetail(MarathonScore score, MarathonScore? previous, Action onBack)
    {
        var stack = new StackPanel { Spacing = 16, MinWidth = 380, MaxWidth = 460 };
        var back = new Button
        {
            Content = "‹ All runs", Background = Brushes.Transparent, Padding = new Avalonia.Thickness(0),
        };
        back.Click += (_, _) => onBack();
        stack.Children.Add(back);
        stack.Children.Add(ScoreCard(score));
        stack.Children.Add(ComparisonCard(score, previous));
        stack.Children.Add(DomainCard(score));
        return new ScrollViewer { Content = stack, MaxHeight = 520 };
    }

    /// The history list — most recent first, each a row with score + date. Empty
    /// state matches Apple's honest first-run pitch (never a blank wall).
    public static Control BuildHistoryList(IReadOnlyList<MarathonScore> scores, Action<MarathonScore> onSelect)
    {
        if (scores.Count == 0)
        {
            return new TextBlock
            {
                Text = "A 200-question test of everything. Play it across as many sittings as you like — we'll keep your place.",
                Opacity = 0.7, TextWrapping = Avalonia.Media.TextWrapping.Wrap, MaxWidth = 360,
                Margin = new Avalonia.Thickness(4, 40),
            };
        }

        var list = new StackPanel { Spacing = 8, MinWidth = 380 };
        foreach (var s in scores)
        {
            var score = s;
            var row = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Avalonia.Thickness(14, 12),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            var left = new StackPanel { Spacing = 3 };
            left.Children.Add(new TextBlock
            {
                Text = $"{score.Correct}/{score.Total} correct · {(int)Math.Round(score.Accuracy * 100)}%",
                FontWeight = FontWeight.SemiBold,
            });
            left.Children.Add(new TextBlock
            {
                Text = score.Date.ToLocalTime().ToString("ddd, MMM d"), FontSize = 12, Opacity = 0.6,
            });
            grid.Children.Add(left);
            var scoreText = new TextBlock
            {
                Text = score.Score.ToString(), FontSize = 20, FontWeight = FontWeight.Black,
                Foreground = Teal, VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(scoreText, 1);
            grid.Children.Add(scoreText);
            row.Content = grid;
            row.Click += (_, _) => onSelect(score);
            list.Children.Add(row);
        }
        return new ScrollViewer { Content = list, MaxHeight = 460 };
    }

    private static Control ScoreCard(MarathonScore score) => new Border
    {
        Classes = { "card" }, Padding = new Avalonia.Thickness(24, 20),
        Child = new StackPanel
        {
            Spacing = 2, HorizontalAlignment = HorizontalAlignment.Center,
            Children =
            {
                new TextBlock { Text = "MARATHON COMPLETE", Classes = { "section-header" }, HorizontalAlignment = HorizontalAlignment.Center },
                new TextBlock { Text = score.Score.ToString(), FontSize = 56, FontWeight = FontWeight.Black, HorizontalAlignment = HorizontalAlignment.Center },
                new TextBlock
                {
                    Text = $"{score.Correct}/{score.Total} correct · {DurationLabel(score.DurationSeconds)}",
                    Classes = { "caption" }, HorizontalAlignment = HorizontalAlignment.Center,
                },
            },
        },
    };

    /// "+6% vs your last run" — the measured-mastery payoff (the whole reason
    /// Marathon isn't just a long Classic).
    private static Control ComparisonCard(MarathonScore score, MarathonScore? previous)
    {
        string headline, subtitle;
        if (previous is null)
        {
            headline = "Your first Marathon";
            subtitle = "Play another to see how you're improving";
        }
        else
        {
            var delta = (int)Math.Round((score.Accuracy - previous.Accuracy) * 100);
            headline = delta == 0 ? "Same as your last run" : $"{(delta > 0 ? "+" : "")}{delta}% vs your last run";
            subtitle = $"Last run: {(int)Math.Round(previous.Accuracy * 100)}% · this run: {(int)Math.Round(score.Accuracy * 100)}%";
        }
        return new Border
        {
            Classes = { "card" },
            Child = new StackPanel
            {
                Spacing = 2, HorizontalAlignment = HorizontalAlignment.Center,
                Children =
                {
                    new TextBlock { Text = headline, Classes = { "body-strong" }, HorizontalAlignment = HorizontalAlignment.Center },
                    new TextBlock { Text = subtitle, Classes = { "caption" }, HorizontalAlignment = HorizontalAlignment.Center },
                },
            },
        };
    }

    private static Control StatsRow(MarathonScore score, int historyCount)
    {
        var grid = new UniformGrid { Columns = 3 };
        grid.Children.Add(StatBox($"{(int)Math.Round(score.Accuracy * 100)}%", "Accuracy", Blue));
        grid.Children.Add(StatBox(score.Score.ToString(), "Score", Teal));
        grid.Children.Add(StatBox(historyCount.ToString(), "Marathons", Coral));
        return grid;
    }

    private static Control StatBox(string value, string label, IBrush color) => new StackPanel
    {
        Spacing = 2, HorizontalAlignment = HorizontalAlignment.Center,
        Children =
        {
            new TextBlock { Text = value, FontSize = 22, FontWeight = FontWeight.Bold, Foreground = color, HorizontalAlignment = HorizontalAlignment.Center },
            new TextBlock { Text = label, FontSize = 12, Opacity = 0.7, HorizontalAlignment = HorizontalAlignment.Center },
        },
    };

    /// Per-domain accuracy bars — the measured-mastery map (not just a score).
    private static Control DomainCard(MarathonScore score)
    {
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(new TextBlock { Text = "Where you stood this run", Classes = { "section-header" } });
        foreach (var d in score.DomainBreakdown.Where(d => d.Total > 0))
        {
            var cat = TriviaCategory.Named(d.CategoryId);
            var row = new StackPanel { Spacing = 4, Margin = new Avalonia.Thickness(0, 0, 0, 8) };
            var head = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            head.Children.Add(new TextBlock { Text = cat.Name, Classes = { "body" } });
            var line = new TextBlock
            {
                Text = $"{d.Correct}/{d.Total} · {(int)Math.Round(d.Accuracy * 100)}%", Classes = { "caption" },
            };
            Grid.SetColumn(line, 1);
            head.Children.Add(line);
            row.Children.Add(head);
            row.Children.Add(new ProgressBar { Minimum = 0, Maximum = 1, Value = d.Accuracy });
            stack.Children.Add(row);
        }
        return new Border { Classes = { "card" }, Child = stack };
    }

    private static string DurationLabel(double seconds)
    {
        var minutes = (int)(seconds / 60);
        if (minutes < 60) return $"{Math.Max(1, minutes)} min";
        var hours = minutes / 60;
        var rem = minutes % 60;
        return rem == 0 ? $"{hours}h" : $"{hours}h {rem}m";
    }
}
