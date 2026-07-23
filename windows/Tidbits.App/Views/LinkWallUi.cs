using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Controls.Shapes;
using Avalonia.Layout;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.Core.Models;

namespace Tidbits.App.Views;

/// The Club Link Wall's pure rendering (docs/CLUB-FEATURES-BUILD.md "Feature 6") —
/// a NYT-Connections-style second daily. Static builders so the board / solved-row /
/// result states render deterministically from injected state in a headless test
/// (mirrors ExpeditionsUi/MarathonUi); `LinkWallDialog` wires these to a live
/// `RecordsStore` + the FAContentDialog shell, rebuilding `dialog.Content` on every
/// tap the same way `ExpeditionsDialog` does.
public static class LinkWallUi
{
    // Yellow -> green -> blue -> purple, the Connections convention (difficulty
    // 1 easiest .. 4 hardest) — same hex family as the Apple/Android/web palette
    // (Core/Design/Design.swift: yellow #FFC93C, mint #2FCB8A, blue #2D5BFF, grape #8B5CF6).
    private static readonly IBrush Yellow = new SolidColorBrush(Color.Parse("#FFC93C"));
    private static readonly IBrush Green = new SolidColorBrush(Color.Parse("#2FCB8A"));
    private static readonly IBrush Blue = new SolidColorBrush(Color.Parse("#2D5BFF"));
    private static readonly IBrush Purple = new SolidColorBrush(Color.Parse("#8B5CF6"));
    private static readonly IBrush Coral = new SolidColorBrush(Color.Parse("#FF5C5C"));
    private static readonly IBrush Ink = new SolidColorBrush(Color.Parse("#1A1714"));

    public static IBrush ColorFor(int difficulty) => difficulty switch
    {
        1 => Yellow,
        2 => Green,
        3 => Blue,
        _ => Purple,
    };

    private static string EmojiFor(int difficulty) => difficulty switch
    {
        1 => "🟨",
        2 => "🟩",
        3 => "🟦",
        _ => "🟪",
    };

    // MARK: - Board

    /// The live 4x4 board: mistakes row, any already-solved groups (collapsed,
    /// colored), the remaining tile grid, an optional "one away" pill, and the
    /// Deselect-All/Shuffle/Submit action row. `onToggleTile`/`onSubmit`/etc. all
    /// trigger a full rebuild in the caller (mirrors ExpeditionsDialog's
    /// re-render-the-whole-subtree idiom).
    public static Control BuildBoard(
        LinkWallPuzzle puzzle,
        LinkWallResult result,
        IReadOnlyList<string> remainingTiles,
        IReadOnlyList<LinkWallGroup> solvedGroups,
        IReadOnlyList<string> selected,
        string? oneAwayMessage,
        Action<string> onToggleTile,
        Action onDeselectAll,
        Action onShuffle,
        Action onSubmit)
    {
        var root = new StackPanel { Spacing = 14, MinWidth = 420, MaxWidth = 460 };

        root.Children.Add(new TextBlock
        {
            Text = "Find the four groups of four.", Classes = { "caption" },
        });
        root.Children.Add(BuildMistakesRow(result.Mistakes));

        foreach (var g in solvedGroups) root.Children.Add(BuildSolvedRow(g));

        root.Children.Add(BuildTileGrid(remainingTiles, selected, onToggleTile));

        if (!string.IsNullOrEmpty(oneAwayMessage))
        {
            root.Children.Add(new Border
            {
                Background = Yellow, CornerRadius = new Avalonia.CornerRadius(999),
                Padding = new Avalonia.Thickness(14, 8), HorizontalAlignment = HorizontalAlignment.Center,
                Child = new TextBlock { Text = oneAwayMessage, Classes = { "body-strong" }, Foreground = Ink },
            });
        }

        root.Children.Add(BuildActionRow(selected.Count, onDeselectAll, onShuffle, onSubmit));
        return new ScrollViewer { Content = root, MaxHeight = 560 };
    }

    private static Control BuildMistakesRow(int mistakes)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        row.Children.Add(new TextBlock { Text = "MISTAKES", Classes = { "caption" }, VerticalAlignment = VerticalAlignment.Center });
        var dots = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        for (int i = 0; i < 4; i++)
        {
            dots.Children.Add(new Ellipse
            {
                Width = 12, Height = 12,
                Fill = i < (4 - mistakes) ? Ink : Brushes.Transparent,
                Stroke = Ink, StrokeThickness = 1.5,
            });
        }
        row.Children.Add(dots);
        return row;
    }

    private static Control BuildSolvedRow(LinkWallGroup g)
    {
        var color = ColorFor(g.Difficulty);
        var stack = new StackPanel { Spacing = 3 };
        stack.Children.Add(new TextBlock { Text = g.Label.ToUpperInvariant(), Classes = { "body-strong" }, Foreground = Ink });
        stack.Children.Add(new TextBlock
        {
            Text = string.Join(" · ", g.Members), Classes = { "caption" }, Foreground = Ink, Opacity = 0.85,
            TextWrapping = Avalonia.Media.TextWrapping.Wrap,
        });
        return new Border
        {
            Background = color, CornerRadius = new Avalonia.CornerRadius(14),
            BorderBrush = Ink, BorderThickness = new Avalonia.Thickness(2),
            Padding = new Avalonia.Thickness(14), Child = stack,
        };
    }

    private static Control BuildTileGrid(IReadOnlyList<string> tiles, IReadOnlyList<string> selected, Action<string> onToggle)
    {
        var grid = new UniformGrid { Columns = 4, Rows = 0 };
        foreach (var tile in tiles)
        {
            var t = tile;
            bool isSelected = selected.Contains(t);
            var btn = new Button
            {
                Content = new TextBlock
                {
                    Text = t, Classes = { "body-strong" }, TextWrapping = Avalonia.Media.TextWrapping.Wrap,
                    TextAlignment = Avalonia.Media.TextAlignment.Center,
                    Foreground = isSelected ? Brushes.White : Ink,
                },
                Background = isSelected ? Ink : new SolidColorBrush(Color.Parse("#F2EEE9")),
                BorderBrush = Ink, BorderThickness = new Avalonia.Thickness(2),
                CornerRadius = new Avalonia.CornerRadius(10),
                Margin = new Avalonia.Thickness(4), Padding = new Avalonia.Thickness(6),
                MinHeight = 74, HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center,
            };
            btn.Click += (_, _) => onToggle(t);
            grid.Children.Add(btn);
        }
        return grid;
    }

    private static Control BuildActionRow(int selectedCount, Action onDeselectAll, Action onShuffle, Action onSubmit)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };

        var deselect = new Button { Content = "Deselect All", Classes = { "compact" }, IsEnabled = selectedCount > 0 };
        deselect.Click += (_, _) => onDeselectAll();
        row.Children.Add(deselect);

        var shuffle = new Button { Content = new FASymbolIcon { Symbol = FASymbol.Shuffle, FontSize = 14 }, Classes = { "compact" } };
        shuffle.Click += (_, _) => onShuffle();
        row.Children.Add(shuffle);

        var submit = new Button
        {
            Content = "Submit", Classes = { "accent", "compact" }, IsEnabled = selectedCount == 4,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        submit.Click += (_, _) => onSubmit();
        row.Children.Add(submit);

        return row;
    }

    /// The "one away" hint: an unsolved group where exactly 3 of the 4 selected
    /// tiles belong to it — the guess was close, not just wrong. Extracted as a
    /// pure helper (used by `LinkWallDialog.Submit`) so it's unit-testable without
    /// driving the live FAContentDialog.
    public static LinkWallGroup? ClosestUnsolvedGroup(
        IReadOnlyList<LinkWallGroup> groups, IReadOnlyList<string> solvedLabels, IReadOnlyList<string> selected) =>
        groups.FirstOrDefault(g =>
            !solvedLabels.Contains(g.Label) &&
            selected.Count(t => g.Members.Contains(t)) == 3);

    // MARK: - Unavailable (the corpus couldn't fill 4 non-colliding groups)

    public static Control BuildUnavailable() => new StackPanel
    {
        Spacing = 8, MinWidth = 380, MaxWidth = 440,
        Children =
        {
            new TextBlock { Text = "Link Wall isn't ready", Classes = { "section-header" } },
            new TextBlock
            {
                Text = "Couldn't build today's board from the corpus. Try again tomorrow.",
                Classes = { "body" }, Opacity = 0.75, TextWrapping = Avalonia.Media.TextWrapping.Wrap,
            },
        },
    };

    // MARK: - Result (win or loss — reveal + shareable colored-square grid)

    /// The just-finished day's outcome — a header, the share grid (if any guesses
    /// were made), every group revealed with its cited "why", and a Share (clipboard)
    /// + Done row.
    public static Control BuildResult(LinkWallPuzzle puzzle, LinkWallResult result, Action onShare, Action onDone)
    {
        var root = new StackPanel { Spacing = 18, MinWidth = 420, MaxWidth = 460 };

        var headerColor = result.Won ? Green : Coral;
        var headerText = result.Won
            ? $"{result.Mistakes} mistake{(result.Mistakes == 1 ? "" : "s")} — nice work."
            : "Here's today's four groups. New wall tomorrow.";
        root.Children.Add(new Border
        {
            Classes = { "card" },
            Child = new StackPanel
            {
                Spacing = 4, HorizontalAlignment = HorizontalAlignment.Center,
                Children =
                {
                    new FASymbolIcon { Symbol = FASymbol.Checkmark, FontSize = 32, Foreground = headerColor, HorizontalAlignment = HorizontalAlignment.Center },
                    new TextBlock { Text = result.Won ? "SOLVED" : "NEXT TIME", Classes = { "section-header" }, HorizontalAlignment = HorizontalAlignment.Center },
                    new TextBlock { Text = headerText, Classes = { "caption" }, TextAlignment = Avalonia.Media.TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, TextWrapping = Avalonia.Media.TextWrapping.Wrap },
                },
            },
        });

        if (result.GuessHistory.Count > 0) root.Children.Add(BuildShareGrid(result));

        var reveal = new StackPanel { Spacing = 10 };
        foreach (var g in puzzle.Groups) reveal.Children.Add(BuildRevealRow(g));
        root.Children.Add(reveal);

        var share = new Button
        {
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center,
                Children = { new FASymbolIcon { Symbol = FASymbol.Share, FontSize = 15 }, new TextBlock { Text = "Share" } },
            },
            Classes = { "accent" }, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center,
            Padding = new Avalonia.Thickness(0, 13),
        };
        share.Click += (_, _) => onShare();
        root.Children.Add(share);

        var done = new Button { Content = "Done", Background = Brushes.Transparent, HorizontalAlignment = HorizontalAlignment.Center };
        done.Click += (_, _) => onDone();
        root.Children.Add(done);

        return new ScrollViewer { Content = root, MaxHeight = 620 };
    }

    private static Control BuildShareGrid(LinkWallResult result)
    {
        var stack = new StackPanel { Spacing = 4, HorizontalAlignment = HorizontalAlignment.Center };
        foreach (var row in result.GuessHistory)
        {
            var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            foreach (var difficulty in row)
                line.Children.Add(new Border { Width = 24, Height = 24, CornerRadius = new Avalonia.CornerRadius(4), Background = ColorFor(difficulty) });
            stack.Children.Add(line);
        }
        return stack;
    }

    private static Control BuildRevealRow(LinkWallGroup g)
    {
        var color = ColorFor(g.Difficulty);
        var stack = new StackPanel { Spacing = 3 };
        stack.Children.Add(new TextBlock { Text = g.Label.ToUpperInvariant(), Classes = { "body-strong" }, Foreground = Ink });
        stack.Children.Add(new TextBlock { Text = g.Why, Classes = { "caption" }, Foreground = Ink, Opacity = 0.9, TextWrapping = Avalonia.Media.TextWrapping.Wrap });
        return new Border
        {
            Background = color, CornerRadius = new Avalonia.CornerRadius(14),
            BorderBrush = Ink, BorderThickness = new Avalonia.Thickness(2),
            Padding = new Avalonia.Thickness(14), Child = stack,
        };
    }

    /// The clipboard share text (Windows has no system share sheet for arbitrary
    /// text — mirrors `GameView.OnShare`). Verbatim of the Apple/web/Android copy
    /// shape: a date-stamped header, one emoji-square row per guess, and the
    /// closing line.
    public static string ShareText(string day, LinkWallResult result)
    {
        var lines = new List<string> { $"Tidbits Link Wall — {DateLabel(day)}" };
        lines.AddRange(result.GuessHistory.Select(row => string.Concat(row.Select(EmojiFor))));
        lines.Add(result.Won
            ? $"Solved in {result.GuessHistory.Count} guess{(result.GuessHistory.Count == 1 ? "" : "es")}."
            : "Didn't solve it today.");
        return string.Join("\n", lines);
    }

    private static string DateLabel(string day) =>
        DateTime.TryParseExact(day, "yyyy-MM-dd", null, System.Globalization.DateTimeStyles.None, out var d)
            ? d.ToString("MMM d") : day;
}
