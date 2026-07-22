using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Story Archive's pure rendering (docs/CLUB-FEATURES-BUILD.md "Feature 2").
/// Static builders so the chips/results/detail states render deterministically from
/// injected state in a headless test (mirrors ClubPaywallUi/DuelsUi) — `StoryArchiveDialog`
/// wires these to a live `RecordsStore` + the FAContentDialog shell.
public static class StoryArchiveUi
{
    private static readonly IBrush Green = new SolidColorBrush(Color.Parse("#2FCB8A"));
    private static readonly IBrush Red = new SolidColorBrush(Color.Parse("#FF5C5C"));
    private static readonly IBrush Gold = new SolidColorBrush(Color.Parse("#FFC531"));

    public static Control BuildChips(
        IReadOnlyList<TriviaCategory> domains, StoryFilter filter, string? domain,
        Action<StoryFilter> onFilter, Action<string?> onDomain)
    {
        var root = new StackPanel { Spacing = 6, Margin = new Avalonia.Thickness(0, 0, 0, 10) };

        var filterRow = new WrapPanel();
        foreach (var f in Enum.GetValues<StoryFilter>())
        {
            var ff = f;
            var chip = new Button { Content = ff.Label(), Classes = { "compact" }, Margin = new Avalonia.Thickness(0, 0, 8, 8) };
            if (ff == filter) chip.Classes.Add("accent");
            chip.Click += (_, _) => onFilter(ff);
            filterRow.Children.Add(chip);
        }
        root.Children.Add(filterRow);

        if (domains.Count > 0)
        {
            var domainRow = new WrapPanel();
            var all = new Button { Content = "All domains", Classes = { "compact" }, Margin = new Avalonia.Thickness(0, 0, 8, 8) };
            if (domain is null) all.Classes.Add("accent");
            all.Click += (_, _) => onDomain(null);
            domainRow.Children.Add(all);
            foreach (var cat in domains)
            {
                var id = cat.Id;
                var chip = new Button { Content = cat.Name, Classes = { "compact" }, Margin = new Avalonia.Thickness(0, 0, 8, 8) };
                if (domain == id) chip.Classes.Add("accent");
                chip.Click += (_, _) => onDomain(id);
                domainRow.Children.Add(chip);
            }
            root.Children.Add(domainRow);
        }
        return root;
    }

    /// `all` is the unfiltered set (drives the "nothing seen yet" empty state vs. the
    /// "no stories match" no-results state); `filtered` is what actually renders.
    public static Control BuildResultsList(
        IReadOnlyList<SeenStory> all, IReadOnlyList<SeenStory> filtered,
        Action<SeenStory> onSelect, Action<SeenStory> onFavorite)
    {
        if (all.Count == 0)
        {
            return new TextBlock
            {
                Text = "Play a few rounds — the stories you unlock are kept here forever.",
                Classes = { "body" }, Opacity = 0.75, TextWrapping = TextWrapping.Wrap,
                Margin = new Avalonia.Thickness(4, 24, 4, 4),
            };
        }
        if (filtered.Count == 0)
        {
            return new TextBlock { Text = "No stories match.", Classes = { "caption" }, Margin = new Avalonia.Thickness(4, 24, 4, 4) };
        }

        var list = new StackPanel { Spacing = 8 };
        foreach (var story in filtered)
        {
            var s = story;
            list.Children.Add(StoryCard(s, () => onSelect(s), () => onFavorite(s)));
        }
        return list;
    }

    /// One story card: a full-card select button (opens detail) with a small
    /// favorite star layered on top in the corner — the star intercepts clicks in
    /// its own bounds, the rest of the card falls through to the select button
    /// underneath (the same "corner action over a card" pattern as elsewhere).
    public static Control StoryCard(SeenStory s, Action onSelect, Action onFavorite)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };

        var selectBtn = new Button
        {
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Avalonia.Thickness(14, 12),
            Content = StoryCardBody(s),
        };
        selectBtn.Click += (_, _) => onSelect();
        Grid.SetColumnSpan(selectBtn, 2);
        grid.Children.Add(selectBtn);

        var favBtn = new Button
        {
            Content = s.Favorite ? "★" : "☆",
            FontSize = 16,
            Foreground = s.Favorite ? Gold : Brushes.Gray,
            Background = Brushes.Transparent,
            BorderThickness = new Avalonia.Thickness(0),
            VerticalAlignment = VerticalAlignment.Top,
            HorizontalAlignment = HorizontalAlignment.Right,
            Padding = new Avalonia.Thickness(10),
        };
        favBtn.Click += (_, _) => onFavorite();
        Grid.SetColumn(favBtn, 1);
        grid.Children.Add(favBtn);

        return new Border { Classes = { "card" }, Padding = new Avalonia.Thickness(0), Child = grid };
    }

    private static Control StoryCardBody(SeenStory s)
    {
        var body = new StackPanel { Spacing = 4 };

        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        top.Children.Add(new TextBlock { Text = TriviaCategory.Named(s.CategoryId).Name.ToUpperInvariant(), Classes = { "caption" }, FontWeight = FontWeight.SemiBold });
        top.Children.Add(new Border
        {
            Width = 10, Height = 10, CornerRadius = new Avalonia.CornerRadius(5),
            Background = s.EverCorrect ? Green : Red, VerticalAlignment = VerticalAlignment.Center,
        });
        body.Children.Add(top);

        body.Children.Add(new TextBlock { Text = s.Prompt, TextWrapping = TextWrapping.Wrap, Classes = { "body-strong" } });
        body.Children.Add(new TextBlock { Text = $"Answer: {s.CorrectAnswer}", Classes = { "caption" } });
        body.Children.Add(new TextBlock { Text = s.LastSeen.ToLocalTime().ToString("MMM d, h:mm tt"), Classes = { "caption" } });
        return body;
    }

    /// The full story + favorite toggle + "Re-ask this" (a 1-question drill on the
    /// shared engine — mirrors the app's Duel-drill launch pattern). `onReask` is
    /// omitted (no button) when the story can't rebuild a plain 4-option MCQ.
    public static Control BuildDetailPanel(SeenStory story, Action onBack, Action onFavorite, Action? onReask)
    {
        var root = new StackPanel { Spacing = 14, MinWidth = 380, MaxWidth = 460 };

        var back = new Button { Content = "‹ All stories", Background = Brushes.Transparent, BorderThickness = new Avalonia.Thickness(0), Padding = new Avalonia.Thickness(0) };
        back.Click += (_, _) => onBack();
        root.Children.Add(back);

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(new TextBlock { Text = TriviaCategory.Named(story.CategoryId).Name, Classes = { "caption" }, VerticalAlignment = VerticalAlignment.Center });
        var favBtn = new Button { Content = story.Favorite ? "★ Favorited" : "☆ Favorite", Classes = { "compact" } };
        favBtn.Click += (_, _) => onFavorite();
        Grid.SetColumn(favBtn, 1);
        header.Children.Add(favBtn);
        root.Children.Add(header);

        root.Children.Add(new TextBlock { Text = story.Prompt, Classes = { "section-header" }, TextWrapping = TextWrapping.Wrap });
        root.Children.Add(new TextBlock { Text = $"Answer: {story.CorrectAnswer}", Classes = { "body-strong" }, TextWrapping = TextWrapping.Wrap });
        root.Children.Add(new TextBlock { Text = story.Story, Classes = { "body" }, TextWrapping = TextWrapping.Wrap });

        if (onReask is not null)
        {
            var reask = new Button
            {
                Content = "Re-ask this", Classes = { "accent" },
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center,
                Padding = new Avalonia.Thickness(0, 12),
            };
            reask.Click += (_, _) => onReask();
            root.Children.Add(reask);
        }

        return new ScrollViewer { Content = root, MaxHeight = 460 };
    }
}
