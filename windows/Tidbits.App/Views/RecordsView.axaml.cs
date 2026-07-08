using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class RecordsView : UserControl
{
    private static readonly IBrush Green = new SolidColorBrush(Color.Parse("#2FCB8A"));
    private static readonly IBrush Red = new SolidColorBrush(Color.Parse("#FF5C5C"));

    public RecordsView()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(System.EventArgs e)
    {
        base.OnDataContextChanged(e);
        BuildPie();
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
}
