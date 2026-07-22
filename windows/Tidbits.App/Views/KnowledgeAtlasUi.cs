using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Knowledge Atlas's pure rendering (docs/CLUB-FEATURES-BUILD.md "Feature 4").
/// Static builders so the domain rows / decay section / empty state render
/// deterministically from injected state in a headless test (mirrors
/// StoryArchiveUi/ClubPaywallUi) — `KnowledgeAtlasDialog` wires these to a live
/// `RecordsStore` + the FAContentDialog shell. The anti-Sporcle guard: EVERY
/// domain row is a full-row Button that launches a domain-scoped round — this
/// interprets AND acts, never a passive stats wall.
public static class KnowledgeAtlasUi
{
    private static readonly IBrush Green = new SolidColorBrush(Color.Parse("#2FCB8A"));
    private static readonly IBrush Red = new SolidColorBrush(Color.Parse("#FF5C5C"));

    private static string Hex(int i) => i switch
    {
        0 => "#FF5C35", 1 => "#2D5BFF", 2 => "#8B5CF6", 3 => "#2FCB8A", 4 => "#13B6C9", 5 => "#FF7A00", _ => "#888888"
    };

    /// The full atlas: an intro line, every mapped domain (a tap-to-play door),
    /// then the Decay radar when any domain qualifies. `domains` empty renders
    /// the honest "not enough history yet" empty state instead.
    public static Control BuildAtlas(
        IReadOnlyList<KnowledgeAtlas.DomainAtlasEntry> domains,
        IReadOnlyList<KnowledgeAtlas.DecayEntry> decaying,
        Action<TriviaCategory> onPlay)
    {
        if (domains.Count == 0) return BuildEmptyState();

        var root = new StackPanel { Spacing = 14, MinWidth = 420, MaxWidth = 460 };
        root.Children.Add(new TextBlock
        {
            Text = "Your accuracy by domain over the trailing 12 months. Tap any domain to play a round in it.",
            Classes = { "caption" }, TextWrapping = TextWrapping.Wrap,
        });

        foreach (var d in domains)
        {
            var entry = d;
            root.Children.Add(BuildDomainRow(entry, () => onPlay(TriviaCategory.Named(entry.CategoryId))));
        }

        if (decaying.Count > 0)
        {
            root.Children.Add(new TextBlock { Text = "Decay radar", Classes = { "section-header" }, Margin = new Avalonia.Thickness(0, 6, 0, 0) });
            root.Children.Add(new TextBlock
            {
                Text = "Domains you were strong in 6+ months ago that have since slipped.",
                Classes = { "caption" }, TextWrapping = TextWrapping.Wrap,
            });
            foreach (var d in decaying)
            {
                var entry = d;
                root.Children.Add(BuildDecayRow(entry, () => onPlay(TriviaCategory.Named(entry.CategoryId))));
            }
        }

        return new ScrollViewer { Content = root, MaxHeight = 480 };
    }

    public static Control BuildEmptyState() => new TextBlock
    {
        Text = "Play across a few domains and your Atlas fills in — it needs a few weeks of history to show a trajectory.",
        Classes = { "body" }, Opacity = 0.75, TextWrapping = TextWrapping.Wrap,
        Margin = new Avalonia.Thickness(4, 24, 4, 4), MaxWidth = 420,
    };

    /// One domain: accuracy, sample size, a trajectory arrow (▲▼ + delta), and a
    /// progress bar — the whole card is the tap-to-play button (every number is
    /// a door, never a passive readout).
    public static Control BuildDomainRow(KnowledgeAtlas.DomainAtlasEntry entry, Action onPlay)
    {
        var cat = TriviaCategory.Named(entry.CategoryId);
        var body = new StackPanel { Spacing = 6 };

        var top = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto,Auto") };
        top.Children.Add(new TextBlock { Text = cat.Name, Classes = { "body-strong" }, VerticalAlignment = VerticalAlignment.Center });

        var trajectory = TrajectoryBadge(entry.TrajectoryDelta);
        if (trajectory is not null)
        {
            Grid.SetColumn(trajectory, 1);
            top.Children.Add(trajectory);
        }

        var pct = new TextBlock
        {
            Text = $"{(int)Math.Round(entry.Accuracy * 100)}%", FontWeight = FontWeight.Black, FontSize = 17,
            VerticalAlignment = VerticalAlignment.Center, Margin = new Avalonia.Thickness(8, 0, 6, 0),
        };
        Grid.SetColumn(pct, 2);
        top.Children.Add(pct);

        var chevron = new TextBlock { Text = "›", FontWeight = FontWeight.Bold, Opacity = 0.6, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(chevron, 3);
        top.Children.Add(chevron);
        body.Children.Add(top);

        body.Children.Add(new ProgressBar
        {
            Minimum = 0, Maximum = 1, Value = entry.Accuracy, Height = 10,
            Foreground = new SolidColorBrush(Color.Parse(Hex(cat.ColorIndex))),
        });

        body.Children.Add(new TextBlock
        {
            Text = $"{entry.Correct}/{entry.SampleSize} answered · last 12 months",
            Classes = { "caption" },
        });

        var btn = new Button
        {
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Avalonia.Thickness(14, 12), Content = body,
        };
        btn.Click += (_, _) => onPlay();
        return new Border { Classes = { "card" }, Padding = new Avalonia.Thickness(0), Child = btn };
    }

    /// A decaying domain: past vs. recent accuracy, and a dedicated "Shore it up"
    /// play button (the Decay radar's action, distinct from the plain domain tap).
    public static Control BuildDecayRow(KnowledgeAtlas.DecayEntry entry, Action onPlay)
    {
        var cat = TriviaCategory.Named(entry.CategoryId);
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };

        var text = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = cat.Name, Classes = { "body-strong" } });
        text.Children.Add(new TextBlock
        {
            Text = $"{(int)Math.Round(entry.PastAccuracy * 100)}% then → {(int)Math.Round(entry.RecentAccuracy * 100)}% now",
            Classes = { "caption" },
        });
        grid.Children.Add(text);

        var shoreUp = new Button { Content = "Shore it up", Classes = { "accent", "compact" }, VerticalAlignment = VerticalAlignment.Center };
        shoreUp.Click += (_, _) => onPlay();
        Grid.SetColumn(shoreUp, 1);
        grid.Children.Add(shoreUp);

        return new Border { Classes = { "card" }, Padding = new Avalonia.Thickness(14, 12), Child = grid };
    }

    private static Control? TrajectoryBadge(double? delta)
    {
        if (delta is not { } d) return null;
        var up = d >= 0;
        var pts = (int)Math.Round(Math.Abs(d) * 100);
        return new Border
        {
            Background = up ? Green : Red, CornerRadius = new Avalonia.CornerRadius(6),
            Padding = new Avalonia.Thickness(6, 2), VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = $"{(up ? "▲" : "▼")}{pts}", FontSize = 12, FontWeight = FontWeight.Black,
                Foreground = Brushes.White,
            },
        };
    }
}
