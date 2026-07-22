using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.Core.Data;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Marathon History surface off Records (R-REC-1,
/// docs/CLUB-FEATURES-BUILD.md "Feature 3") — the Records entry-point card
/// (Club-marked) and the history list/detail rendering (`MarathonUi`, mirrors
/// `StoryArchiveUi`'s headless-testable static-builder pattern).
public class MarathonHistorySnapshot
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

    private static void ScrollToBottom(Window win)
    {
        var scroller = win.GetVisualDescendants().OfType<ScrollViewer>().FirstOrDefault();
        if (scroller is null) return;
        scroller.ScrollToEnd();
        Dispatcher.UIThread.RunJobs();
    }

    private static MarathonScore Score(int correct, int total, int scoreValue, DateTime date) => new()
    {
        Date = date, Score = scoreValue, Correct = correct, Total = total, DurationSeconds = 600,
        DomainBreakdown = { new MarathonDomainStat("history", correct, total) },
    };

    /// The Records dashboard's own top-level gate (`HasGames` / Apple's
    /// `records.isEmpty`) hides EVERY section — including this card — until at
    /// least one ordinary game exists. Same precondition StoryArchiveSnapshot's
    /// Records-card tests need; not something Marathon changes.
    private static async Task<RecordsStore> StoreWithOneGame()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-rec-marathon-{Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);
        var engine = new GameEngine(provider, sources.Difficulty);
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
        int guard = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 30)
        {
            engine.Submit(engine.Current!.CorrectIndex);
            engine.Advance();
        }
        store.Record(engine.Summary);
        return store;
    }

    [AvaloniaFact]
    public async Task Records_shows_the_marathon_history_card_for_a_member()
    {
        var previous = Environment.GetEnvironmentVariable("TIDBITS_CLUB");
        try
        {
            Environment.SetEnvironmentVariable("TIDBITS_CLUB", "1");
            var store = await StoreWithOneGame();

            var win = new Window { Width = 900, Height = 900, Content = new RecordsView { DataContext = new RecordsViewModel(store) } };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            ScrollToBottom(win);

            var texts = TextsOf(win);
            Assert.Contains("MARATHON HISTORY", texts);
            Assert.DoesNotContain("CLUB", texts); // member -> no chip
            var buttons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Open").ToList();
            Assert.NotEmpty(buttons);

            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "records-marathon-history-member.png"));
        }
        finally { Environment.SetEnvironmentVariable("TIDBITS_CLUB", previous); }
    }

    [AvaloniaFact]
    public async Task Records_shows_the_club_chip_and_an_honest_pitch_for_a_non_member()
    {
        var previous = Environment.GetEnvironmentVariable("TIDBITS_CLUB");
        try
        {
            Environment.SetEnvironmentVariable("TIDBITS_CLUB", "0");
            var store = await StoreWithOneGame();

            var win = new Window { Width = 900, Height = 900, Content = new RecordsView { DataContext = new RecordsViewModel(store) } };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            ScrollToBottom(win);

            var texts = TextsOf(win);
            Assert.Contains("MARATHON HISTORY", texts);
            Assert.Contains("CLUB", texts);
            var buttons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Join Club").ToList();
            Assert.NotEmpty(buttons);
            Assert.Contains(texts, t => t is not null && t.Contains("Club", StringComparison.Ordinal));

            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "records-marathon-history-non-member.png"));
        }
        finally { Environment.SetEnvironmentVariable("TIDBITS_CLUB", previous); }
    }

    [AvaloniaFact]
    public void History_list_shows_the_empty_pitch_with_no_runs()
    {
        var content = MarathonUi.BuildHistoryList(Array.Empty<MarathonScore>(), _ => { });
        var win = new Window { Width = 480, Height = 200, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Contains(TextsOf(win), t => t is not null && t.Contains("we'll keep your place", StringComparison.Ordinal));
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "marathon-history-empty.png"));
    }

    [AvaloniaFact]
    public void History_list_and_detail_render_and_wire_selection()
    {
        var older = Score(3, 4, 90, DateTime.UtcNow.AddDays(-2));
        var newer = Score(4, 4, 120, DateTime.UtcNow);
        var scores = new[] { newer, older };

        var selected = new List<MarathonScore>();
        var list = MarathonUi.BuildHistoryList(scores, s => selected.Add(s));
        var win = new Window { Width = 480, Height = 420, Content = list };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("120", texts);
        Assert.Contains("90", texts);
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "marathon-history-list.png"));

        var rows = win.GetVisualDescendants().OfType<Button>().ToList();
        Assert.Equal(2, rows.Count);
        rows[0].RaiseEvent(new Avalonia.Interactivity.RoutedEventArgs(Button.ClickEvent));
        Assert.Single(selected);
        Assert.Same(newer, selected[0]); // most recent first

        var backCalled = false;
        var detail = MarathonUi.BuildHistoryDetail(newer, older, onBack: () => backCalled = true);
        var detailWin = new Window { Width = 480, Height = 700, Content = detail };
        detailWin.Show();
        Dispatcher.UIThread.RunJobs();

        var detailTexts = TextsOf(detailWin);
        Assert.Contains("MARATHON COMPLETE", detailTexts);
        Assert.Contains(detailTexts, t => t is not null && t.Contains("vs your last run"));
        detailWin.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "marathon-history-detail.png"));

        var back = detailWin.GetVisualDescendants().OfType<Button>().First();
        back.RaiseEvent(new Avalonia.Interactivity.RoutedEventArgs(Button.ClickEvent));
        Assert.True(backCalled);
    }
}
