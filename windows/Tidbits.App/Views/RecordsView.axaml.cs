using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

public partial class RecordsView : UserControl
{
    private static readonly IBrush Green = new SolidColorBrush(Color.Parse("#2FCB8A"));
    private static readonly IBrush Red = new SolidColorBrush(Color.Parse("#FF5C5C"));

    public RecordsView()
    {
        InitializeComponent();
        RefreshProfile();
        BuildStoryArchiveCard();
        BuildMarathonHistoryCard();
        BuildKnowledgeAtlasCard();
    }

    protected override void OnDataContextChanged(System.EventArgs e)
    {
        base.OnDataContextChanged(e);
        RefreshProfile();
        BuildPie();
        BuildStoryArchiveCard();
        BuildMarathonHistoryCard();
        BuildKnowledgeAtlasCard();
    }

    /// Show who you're playing as (name + deterministic hue avatar) in the banner.
    private void RefreshProfile()
    {
        if (ProfileName is null) return;
        var p = Services.GameData.Shared.Value.Identity.Current;
        ProfileName.Text = $"Playing as {p.Name}";
        ProfileAvatar.Background = new SolidColorBrush(new HslColor(1.0, p.AvatarHue * 360.0, 0.62, 0.55).ToRgb());
    }

    /// The Pie — one wedge per domain, filled in its category color when mastered,
    /// dim otherwise (Trivial-Pursuit breadth metaphor).
    private void BuildPie()
    {
        if (PieCanvas is null) return;
        PieCanvas.Children.Clear();
        if (DataContext is not RecordsViewModel vm || vm.Wedges.Count == 0) return;

        double r = 60, cx = 60, cy = 60;
        int n = vm.Wedges.Count;
        for (int i = 0; i < n; i++)
        {
            double a0 = i * 2 * System.Math.PI / n - System.Math.PI / 2;
            double a1 = (i + 1) * 2 * System.Math.PI / n - System.Math.PI / 2;
            var p0 = new Avalonia.Point(cx + r * System.Math.Cos(a0), cy + r * System.Math.Sin(a0));
            var p1 = new Avalonia.Point(cx + r * System.Math.Cos(a1), cy + r * System.Math.Sin(a1));

            var fig = new PathFigure { StartPoint = new Avalonia.Point(cx, cy), IsClosed = true, IsFilled = true };
            fig.Segments!.Add(new LineSegment { Point = p0 });
            fig.Segments.Add(new ArcSegment
            {
                Point = p1, Size = new Avalonia.Size(r, r), IsLargeArc = false,
                SweepDirection = SweepDirection.Clockwise,
            });
            var geo = new PathGeometry();
            geo.Figures!.Add(fig);

            var w = vm.Wedges[i];
            var path = new Avalonia.Controls.Shapes.Path
            {
                Data = geo,
                Fill = w.Mastered ? new SolidColorBrush(Color.Parse(w.Hex)) : new SolidColorBrush(Color.Parse("#22808080")),
                Stroke = new SolidColorBrush(Color.Parse("#0A0A0A")), StrokeThickness = 1,
            };
            PieCanvas.Children.Add(path);
        }
    }

    /// "See all N games" → a native FAContentDialog listing every game with its
    /// answer-dot strip; tapping a game drills into a per-question recap.
    private async void OnSeeAllGames(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not RecordsViewModel vm) return;
        var dialog = new FAContentDialog { Title = "Your games", CloseButtonText = "Done" };
        void ShowList() => dialog.Content = GameListView(vm.AllGames, g => dialog.Content = RecapView(g, ShowList));
        ShowList();
        await dialog.ShowAsync();
    }

    /// Tap a personal-best row -> the attempts for that mode (newest first), each
    /// drilling into its recap. Reuses the See-all games list. Web openBests parity.
    private async void OnBestDrill(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: BestRow row }) return;
        if (DataContext is not RecordsViewModel vm) return;
        var games = vm.ModeGames(row.ModeId);
        var dialog = new FAContentDialog { Title = $"{row.Title} attempts", CloseButtonText = "Done" };
        void ShowList() => dialog.Content = GameListView(games, g => dialog.Content = RecapView(g, ShowList));
        ShowList();
        await dialog.ShowAsync();
    }

    /// Tap a domain bar -> a native drill-in of its per-question history (missed /
    /// got right), dedup by qid — parity with the web openDomain.
    private async void OnDomainDrill(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: DomainRow row }) return;
        if (DataContext is not RecordsViewModel vm) return;
        var (missed, right) = vm.DomainAnswers(row.CategoryId);

        var panel = new StackPanel { Spacing = 8, MinWidth = 380 };
        if (missed.Count == 0 && right.Count == 0)
            panel.Children.Add(new TextBlock
            {
                Text = "No per-question history yet for this domain. Play a game here and it'll show up.",
                Opacity = 0.7, TextWrapping = TextWrapping.Wrap,
            });
        if (missed.Count > 0)
        {
            panel.Children.Add(DrillHead($"Missed ({missed.Count})"));
            foreach (var a in missed) panel.Children.Add(DomainAnswerLine(a));
        }
        if (right.Count > 0)
        {
            panel.Children.Add(DrillHead($"Got right ({right.Count})"));
            foreach (var a in right) panel.Children.Add(DomainAnswerLine(a));
        }

        var dialog = new FAContentDialog
        {
            Title = row.Name,
            Content = new ScrollViewer { Content = panel, MaxHeight = 460 },
            CloseButtonText = "Done",
        };
        await dialog.ShowAsync();
    }

    private static TextBlock DrillHead(string text) => new()
    {
        Text = text, FontWeight = FontWeight.Bold, FontSize = 15, Margin = new Avalonia.Thickness(0, 8, 0, 2),
    };

    private static Control DomainAnswerLine(AnswerDot a) => new Border
    {
        Background = new SolidColorBrush(Color.Parse("#14808080")),
        CornerRadius = new Avalonia.CornerRadius(8), Padding = new Avalonia.Thickness(12, 8),
        Child = new StackPanel
        {
            Spacing = 2,
            Children =
            {
                new TextBlock { Text = a.Prompt, TextWrapping = TextWrapping.Wrap, FontWeight = FontWeight.SemiBold },
                new TextBlock { Text = $"Answer: {a.Answer}", Foreground = a.Correct ? Green : Red, FontSize = 13 },
            },
        },
    };

    /// The full games list — each a card with header, score, and its dot strip.
    /// `onSelect` drills into the per-question recap.
    public static Control GameListView(IReadOnlyList<GameDetail> games, Action<GameDetail> onSelect)
    {
        var list = new StackPanel { Spacing = 8 };
        foreach (var g in games)
        {
            var game = g;
            var card = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Avalonia.Thickness(14, 12),
            };
            var body = new StackPanel { Spacing = 6 };
            var top = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            top.Children.Add(new TextBlock { Text = game.Header, FontWeight = FontWeight.SemiBold });
            var meta = new TextBlock { Text = game.ScoreLine, Opacity = 0.7, FontSize = 12 };
            Grid.SetColumn(meta, 1);
            top.Children.Add(meta);
            body.Children.Add(top);
            body.Children.Add(DotStrip(game.Answers));
            card.Content = body;
            card.Click += (_, _) => onSelect(game);
            list.Children.Add(card);
        }
        return new ScrollViewer { Content = list, MaxHeight = 460, MinWidth = 380 };
    }

    /// A row of small green/red dots, one per answered question.
    private static Control DotStrip(IReadOnlyList<AnswerDot> answers)
    {
        var strip = new WrapPanel();
        foreach (var a in answers)
            strip.Children.Add(new Border
            {
                Width = 10, Height = 10, CornerRadius = new Avalonia.CornerRadius(5),
                Background = a.Correct ? Green : Red, Margin = new Avalonia.Thickness(0, 0, 4, 4),
            });
        return strip;
    }

    /// Per-question recap for one game — prompt · answer · right/wrong dot.
    public static Control RecapView(GameDetail game, Action onBack)
    {
        var list = new StackPanel { Spacing = 10, MinWidth = 380 };
        var back = new Button { Content = "‹ All games", Background = Brushes.Transparent, Padding = new Avalonia.Thickness(0) };
        back.Click += (_, _) => onBack();
        list.Children.Add(back);
        list.Children.Add(new TextBlock { Text = game.Header, FontWeight = FontWeight.Bold, FontSize = 16 });
        list.Children.Add(new TextBlock { Text = $"{game.ScoreLine} · {game.Date}", Opacity = 0.7, FontSize = 12 });

        foreach (var a in game.Answers)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*"), Margin = new Avalonia.Thickness(0, 4, 0, 0) };
            row.Children.Add(new Border
            {
                Width = 10, Height = 10, CornerRadius = new Avalonia.CornerRadius(5), Background = a.Correct ? Green : Red,
                VerticalAlignment = VerticalAlignment.Top, Margin = new Avalonia.Thickness(0, 5, 10, 0),
            });
            var text = new StackPanel { Spacing = 2 };
            text.Children.Add(new TextBlock { Text = a.Prompt, TextWrapping = TextWrapping.Wrap, FontSize = 13 });
            if (!string.IsNullOrEmpty(a.Answer))
                text.Children.Add(new TextBlock { Text = a.Answer, Opacity = 0.65, FontSize = 12 });
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            list.Children.Add(row);
        }
        return new ScrollViewer { Content = list, MaxHeight = 460 };
    }

    // MARK: - Tidbits Club: Story Archive (docs/CLUB-FEATURES-BUILD.md "Feature 2")

    /// The Records "see all" entry point (R-REC-1) — a Club-marked card mirroring
    /// PlayView's Weak-Spot card. Members open the searchable archive; everyone else
    /// sees a real preview (their most recent story, or an honest static line) and the
    /// existing Club paywall — never a blank wall.
    private void BuildStoryArchiveCard()
    {
        if (StoryArchivePanel is null) return;
        var data = GameData.Shared.Value;
        bool isClub = data.Entitlement.IsClub;
        int count = StoryArchive.Count(data.Records);
        var subtitle = isClub
            ? (count == 0
                ? "Every story you unlock, kept here forever."
                : $"{count} stor{(count == 1 ? "y" : "ies")} collected — searchable, forever.")
            : StoryArchive.PreviewLine(data.Records) ?? "Club keeps every story you unlock, searchable forever.";

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock { Text = "STORY ARCHIVE", Classes = { "body-strong" } });
        if (!isClub)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "CLUB", FontSize = 11, FontWeight = FontWeight.Black, Foreground = Brushes.White },
            });
        }

        var textStack = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        textStack.Children.Add(titleRow);
        textStack.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(textStack);

        var action = new Button
        {
            Content = isClub ? "Open" : "Join Club",
            Classes = { "accent", "compact" },
            VerticalAlignment = VerticalAlignment.Center,
        };
        action.Click += (_, _) => OnStoryArchiveAction();
        Grid.SetColumn(action, 1);
        grid.Children.Add(action);

        StoryArchivePanel.Content = new Border { Classes = { "card" }, Child = grid };
    }

    /// Members open the searchable archive directly; everyone else sees the existing
    /// paywall (same FAContentDialog idiom as PlayView's Weak-Spot card).
    private async void OnStoryArchiveAction()
    {
        var data = GameData.Shared.Value;
        if (!data.Entitlement.IsClub)
        {
            var dialog = new FAContentDialog
            {
                Content = new ScrollViewer { Content = new ClubPaywallView(), MaxWidth = 520, MaxHeight = 640 },
                CloseButtonText = "Close",
            };
            await dialog.ShowAsync();
            BuildStoryArchiveCard(); // reflect a purchase/restore made from inside the dialog
            return;
        }
        await StoryArchiveDialog.ShowAsync(data.Records, question => StartReask(question));
        BuildStoryArchiveCard(); // reflect any favorite toggles / re-ask outcomes
    }

    // MARK: - Tidbits Club: Marathon History (docs/CLUB-FEATURES-BUILD.md "Feature 3")

    /// The permanent record of every completed 200-question run — reachable from
    /// Records (R-REC-1) in addition to the Play card's own in-game "See Marathon
    /// history" link. Mirrors this file's Story Archive card exactly.
    private void BuildMarathonHistoryCard()
    {
        if (MarathonHistoryPanel is null) return;
        var data = GameData.Shared.Value;
        bool isClub = data.Entitlement.IsClub;
        var history = data.Records.MarathonHistory;
        var subtitle = isClub
            ? (history.Count == 0
                ? GameMode.Marathon.Blurb()
                : $"{history.Count} run{(history.Count == 1 ? "" : "s")} played — best {(int)Math.Round(history.Max(s => s.Accuracy) * 100)}%.")
            : "See exactly where you stand across a 200-question run, by domain — Club keeps every run forever.";

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock { Text = "MARATHON HISTORY", Classes = { "body-strong" } });
        if (!isClub)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "CLUB", FontSize = 11, FontWeight = FontWeight.Black, Foreground = Brushes.White },
            });
        }

        var textStack = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        textStack.Children.Add(titleRow);
        textStack.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(textStack);

        var action = new Button
        {
            Content = isClub ? "Open" : "Join Club",
            Classes = { "accent", "compact" },
            VerticalAlignment = VerticalAlignment.Center,
        };
        action.Click += (_, _) => OnMarathonHistoryAction();
        Grid.SetColumn(action, 1);
        grid.Children.Add(action);

        MarathonHistoryPanel.Content = new Border { Classes = { "card" }, Child = grid };
    }

    /// Members open the history list directly; everyone else sees the existing
    /// paywall — never a blank wall.
    private async void OnMarathonHistoryAction()
    {
        var data = GameData.Shared.Value;
        if (!data.Entitlement.IsClub)
        {
            var dialog = new FAContentDialog
            {
                Content = new ScrollViewer { Content = new ClubPaywallView(), MaxWidth = 520, MaxHeight = 640 },
                CloseButtonText = "Close",
            };
            await dialog.ShowAsync();
            BuildMarathonHistoryCard(); // reflect a purchase/restore made from inside the dialog
            return;
        }
        await MarathonHistoryDialog.ShowAsync(data.Records);
        BuildMarathonHistoryCard(); // in case history changed while the dialog was open
    }

    /// Launches the "Re-ask this" 1-question drill (Duel-drill pattern) as an overlay
    /// on top of the Records dashboard — mirrors LeaderboardView's DuelGameHost, so it
    /// never needs a second dialog stacked on the archive's own FAContentDialog.
    private void StartReask(Question question)
    {
        var data = GameData.Shared.Value;
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { ReaskHost.Content = null; BuildStoryArchiveCard(); };
        vm.PlayAgainRequested += () => StartReask(question);
        ReaskHost.Content = new GameView { DataContext = vm };
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named(question.CategoryId), new[] { question });
    }

    // MARK: - Tidbits Club: Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md "Feature 4")

    /// The Records "see all" entry point (R-REC-1) — a Club-marked card mirroring
    /// the Story Archive/Marathon History cards exactly. A transparent, INTERPRETED
    /// layer over the same rows the free Topic Levels/Pie already read (R-MON-1) —
    /// never a gate on those free surfaces. Members open the atlas (every domain
    /// row a tap-to-play door + a Decay radar); everyone else sees a real
    /// strongest/weakest preview and the existing Club paywall — never a blank wall.
    private void BuildKnowledgeAtlasCard()
    {
        if (KnowledgeAtlasPanel is null) return;
        var data = GameData.Shared.Value;
        bool isClub = data.Entitlement.IsClub;
        var mapped = KnowledgeAtlas.Domains(data.Records.Games);
        var subtitle = isClub
            ? (mapped.Count == 0
                ? "Play across a few domains and your Atlas fills in."
                : $"{mapped.Count} domain{(mapped.Count == 1 ? "" : "s")} mapped over 12 months — tap one to play it.")
            : KnowledgeAtlas.PreviewLine(data.Records.Games) ?? "Club maps everything you know and where it's drifting.";

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock { Text = "KNOWLEDGE ATLAS", Classes = { "body-strong" } });
        if (!isClub)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "CLUB", FontSize = 11, FontWeight = FontWeight.Black, Foreground = Brushes.White },
            });
        }

        var textStack = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        textStack.Children.Add(titleRow);
        textStack.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(textStack);

        var action = new Button
        {
            Content = isClub ? "Open" : "Join Club",
            Classes = { "accent", "compact" },
            VerticalAlignment = VerticalAlignment.Center,
        };
        action.Click += (_, _) => OnKnowledgeAtlasAction();
        Grid.SetColumn(action, 1);
        grid.Children.Add(action);

        KnowledgeAtlasPanel.Content = new Border { Classes = { "card" }, Child = grid };
    }

    /// Members open the atlas directly; everyone else sees the existing paywall
    /// (same FAContentDialog idiom as the Story Archive/Marathon cards).
    private async void OnKnowledgeAtlasAction()
    {
        var data = GameData.Shared.Value;
        if (!data.Entitlement.IsClub)
        {
            var dialog = new FAContentDialog
            {
                Content = new ScrollViewer { Content = new ClubPaywallView(), MaxWidth = 520, MaxHeight = 640 },
                CloseButtonText = "Close",
            };
            await dialog.ShowAsync();
            BuildKnowledgeAtlasCard(); // reflect a purchase/restore made from inside the dialog
            return;
        }
        await KnowledgeAtlasDialog.ShowAsync(data.Records, category => StartAtlasPlay(category));
    }

    /// Tapping a domain (or a Decay radar "Shore it up") launches a full round in
    /// that domain as an overlay on the Records dashboard — mirrors the Story
    /// Archive's ReaskHost, so it never needs a second dialog stacked on the
    /// atlas's own FAContentDialog. A full round (not a 1-question drill), same
    /// launch path Quick Play uses (`engine.Start`).
    private async void StartAtlasPlay(TriviaCategory category)
    {
        var data = GameData.Shared.Value;
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { AtlasHost.Content = null; BuildKnowledgeAtlasCard(); };
        vm.PlayAgainRequested += () => StartAtlasPlay(category);
        AtlasHost.Content = new GameView { DataContext = vm };
        await engine.Start(GameMode.Classic, category);
    }
}
