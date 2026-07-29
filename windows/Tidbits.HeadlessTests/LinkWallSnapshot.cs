using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Link Wall surfaces (docs/CLUB-FEATURES-BUILD.md "Feature 6") — the
/// Home/Play entry-point card and the board/result rendering (`LinkWallUi`, mirrors
/// ExpeditionsUi/MarathonUi's headless-testable static-builder pattern). `PlayView`
/// reads `TIDBITS_CLUB` (via `DebugHooks.ForceClub`) at construction time, so every
/// test here is env-sensitive — same discipline as `ExpeditionsSnapshot`.
[Collection("EnvSensitive")]
public class LinkWallSnapshot
{
    private static string Art()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static List<string?> TextsOf(Control root) =>
        root.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();

    private static void ScrollToEnd(Window win)
    {
        var scroller = win.GetVisualDescendants().OfType<ScrollViewer>().FirstOrDefault();
        if (scroller is null) return;
        scroller.ScrollToEnd();
        Dispatcher.UIThread.RunJobs();
    }

    private static LinkWallPuzzle Puzzle() => new(
        "2026-07-22",
        new[]
        {
            new LinkWallGroup("Iconic Films", "Jaws → Spielberg · Alien → Scott · Se7en → Fincher · Amadeus → Forman", new[] { "Jaws", "Alien", "Se7en", "Amadeus" }, 1),
            new LinkWallGroup("Olympic Host Cities", "1896 → Athens · 1900 → Paris · 1904 → St. Louis · 1908 → London", new[] { "Athens", "Paris", "St. Louis", "London" }, 2),
            new LinkWallGroup("World Capitals", "Kenya → Nairobi · Peru → Lima · Fiji → Suva · Timor-Leste → Dili", new[] { "Nairobi", "Lima", "Suva", "Dili" }, 3),
            new LinkWallGroup("Chemical Element Symbols", "Gold → Au · Silver → Ag · Iron → Fe · Lead → Pb", new[] { "Au", "Ag", "Fe", "Pb" }, 4),
        },
        new[] { "Jaws", "Alien", "Se7en", "Amadeus", "Athens", "Paris", "St. Louis", "London", "Nairobi", "Lima", "Suva", "Dili", "Au", "Ag", "Fe", "Pb" });

    // MARK: - Home/Play entry-point card

    // MARK: - The board (LinkWallUi.BuildBoard — pure, headless-testable)

    [AvaloniaFact]
    public void Board_renders_all_sixteen_tiles_mistakes_row_and_wires_toggle_and_submit()
    {
        var puzzle = Puzzle();
        var result = new LinkWallResult { Day = puzzle.Day };
        var selected = new List<string>();
        string? toggled = null;
        bool submitted = false;

        var content = LinkWallUi.BuildBoard(
            puzzle, result, puzzle.Tiles, Array.Empty<LinkWallGroup>(), selected, oneAwayMessage: null,
            onToggleTile: t => toggled = t, onDeselectAll: () => { }, onShuffle: () => { }, onSubmit: () => submitted = true);

        var win = new Window { Width = 520, Height = 800, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Contains("MISTAKES", TextsOf(win));
        var tileButtons = win.GetVisualDescendants().OfType<Button>()
            .Where(b => b.Content is TextBlock).ToList();
        Assert.Equal(16, tileButtons.Count);

        tileButtons[0].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.NotNull(toggled);

        // Submit is disabled until exactly 4 are selected.
        var submitButton = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "Submit");
        Assert.False(submitButton.IsEnabled);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "linkwall-board-fresh.png"));
        Assert.False(submitted); // no click fired
    }

    [AvaloniaFact]
    public void Board_shows_a_solved_collapsed_row_and_one_away_pill_and_fewer_remaining_tiles()
    {
        var puzzle = Puzzle();
        var solved = new[] { puzzle.Groups[0] }; // Iconic Films solved
        var remaining = puzzle.Tiles.Where(t => !puzzle.Groups[0].Members.Contains(t)).ToList();
        var result = new LinkWallResult { Day = puzzle.Day, Mistakes = 2 };

        var content = LinkWallUi.BuildBoard(
            puzzle, result, remaining, solved, selected: Array.Empty<string>(), oneAwayMessage: "One away…",
            onToggleTile: _ => { }, onDeselectAll: () => { }, onShuffle: () => { }, onSubmit: () => { });

        var win = new Window { Width = 520, Height = 800, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("ICONIC FILMS", texts); // collapsed solved row, uppercased label
        Assert.Contains(texts, t => t is not null && t.Contains("Jaws · Alien · Se7en · Amadeus"));
        Assert.Contains("One away…", texts);

        var tileButtons = win.GetVisualDescendants().OfType<Button>().Where(b => b.Content is TextBlock).ToList();
        Assert.Equal(12, tileButtons.Count); // 16 - the 4 solved

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "linkwall-board-solved-and-one-away.png"));
    }

    // MARK: - Result (LinkWallUi.BuildResult — win / loss, share grid)

    [AvaloniaFact]
    public void Result_shows_solved_the_share_grid_and_wires_share_and_done()
    {
        var puzzle = Puzzle();
        var result = new LinkWallResult
        {
            Day = puzzle.Day, Completed = true, Won = true, Mistakes = 1,
            GuessHistory = new List<List<int>> { new() { 1, 1, 1, 2 }, new() { 1, 1, 1, 1 }, new() { 2, 2, 2, 2 }, new() { 3, 3, 3, 3 }, new() { 4, 4, 4, 4 } },
        };
        bool shared = false, done = false;
        var content = LinkWallUi.BuildResult(puzzle, result, onShare: () => shared = true, onDone: () => done = true);

        var win = new Window { Width = 520, Height = 900, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("SOLVED", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("1 mistake"));
        // Every group is revealed with its cited "why".
        Assert.Contains(texts, t => t is not null && t.Contains("Jaws → Spielberg"));

        var shareButton = win.GetVisualDescendants().OfType<Button>().First(b => b.Content is StackPanel sp && sp.GetVisualDescendants().OfType<TextBlock>().Any(t => t.Text == "Share"));
        shareButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.True(shared);

        var doneButton = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "Done");
        doneButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.True(done);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "linkwall-result-won.png"));
    }

    [AvaloniaFact]
    public void Result_shows_next_time_and_every_group_revealed_on_a_loss()
    {
        var puzzle = Puzzle();
        var result = new LinkWallResult
        {
            Day = puzzle.Day, Completed = true, Won = false, Mistakes = 4,
            GuessHistory = new List<List<int>> { new() { 1, 2, 3, 4 }, new() { 1, 2, 3, 4 }, new() { 1, 2, 3, 4 }, new() { 1, 2, 3, 4 } },
        };
        var content = LinkWallUi.BuildResult(puzzle, result, onShare: () => { }, onDone: () => { });

        var win = new Window { Width = 520, Height = 900, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("NEXT TIME", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("New wall tomorrow"));
        Assert.Contains("CHEMICAL ELEMENT SYMBOLS", texts); // even the unsolved purple group is revealed

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "linkwall-result-lost.png"));
    }

    [AvaloniaFact]
    public void Unavailable_state_renders_a_calm_message_never_a_blank_screen()
    {
        var content = LinkWallUi.BuildUnavailable();
        var win = new Window { Width = 480, Height = 300, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Contains("Link Wall isn't ready", TextsOf(win));
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "linkwall-unavailable.png"));
    }
}
