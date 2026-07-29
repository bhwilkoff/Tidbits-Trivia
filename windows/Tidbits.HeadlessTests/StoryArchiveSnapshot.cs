using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Story Archive (docs/CLUB-FEATURES-BUILD.md "Feature 2") — the Records
/// entry-point card (Club-marked, R-REC-1) and the archive's pure rendering
/// (`StoryArchiveUi`, mirrors ClubPaywallUi's headless-testable static-builder
/// pattern). Windows is the last of six platforms.
[Collection("EnvSensitive")]
public class StoryArchiveSnapshot
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

    private static Question Q(string id, string categoryId = "science", int correctIndex = 0) => new()
    {
        Id = id, Prompt = $"Prompt {id}", Options = new[] { "A", "B", "C", "D" },
        CorrectIndex = correctIndex, CategoryId = categoryId, Difficulty = 3, Explanation = "Because.",
    };

    private static void ScrollToBottom(Window win)
    {
        var scroller = win.GetVisualDescendants().OfType<ScrollViewer>().FirstOrDefault();
        if (scroller is null) return;
        scroller.ScrollToEnd();
        Dispatcher.UIThread.RunJobs();
    }

    // MARK: - Records dashboard card (reads GameData.Shared, like PlayView's Weak-Spot card)

    private static async Task<RecordsStore> StoreWithOneGame()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-rec-{Guid.NewGuid():N}.json");
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

    // MARK: - Archive rendering (StoryArchiveUi — pure, headless-testable)

    [AvaloniaFact]
    public void Empty_archive_shows_the_play_a_few_rounds_message()
    {
        var content = StoryArchiveUi.BuildResultsList(
            all: Array.Empty<SeenStory>(), filtered: Array.Empty<SeenStory>(),
            onSelect: _ => { }, onFavorite: _ => { });

        var win = new Window { Width = 480, Height = 260, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Contains(TextsOf(win), t => t is not null && t.Contains("kept here forever", StringComparison.Ordinal));
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "story-archive-empty.png"));
    }

    [AvaloniaFact]
    public void No_results_shows_a_no_stories_match_message_distinct_from_the_empty_state()
    {
        var stories = new[] { SeenStory.From(Q("a"), true) };
        var content = StoryArchiveUi.BuildResultsList(stories, filtered: Array.Empty<SeenStory>(),
            onSelect: _ => { }, onFavorite: _ => { });

        var win = new Window { Width = 480, Height = 260, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Contains("No stories match.", TextsOf(win));
    }

    [AvaloniaFact]
    public void Story_cards_show_prompt_answer_domain_and_favorite_state()
    {
        var mastered = SeenStory.From(Q("a", "history"), true);
        var missed = SeenStory.From(Q("b", "science"), false);
        missed.Favorite = true;
        var stories = new[] { mastered, missed };

        var selected = new List<string>();
        var content = StoryArchiveUi.BuildResultsList(stories, stories,
            onSelect: s => selected.Add(s.QuestionId), onFavorite: _ => { });

        var win = new Window { Width = 480, Height = 420, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("Prompt a", texts);
        Assert.Contains("Prompt b", texts);
        Assert.Contains("Answer: A", texts);
        Assert.Contains("★", texts); // missed is favorited
        Assert.Contains("☆", texts); // mastered is not

        // Tapping a card's select button fires onSelect with that story's qid.
        var selectButtons = win.GetVisualDescendants().OfType<Button>()
            .Where(b => b.Content is Control).ToList();
        Assert.NotEmpty(selectButtons);
        selectButtons[0].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Single(selected);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "story-archive-list.png"));
    }

    [AvaloniaFact]
    public void Chips_row_marks_the_active_filter_and_domain_and_fires_callbacks()
    {
        var domains = new[] { TriviaCategory.Named("history"), TriviaCategory.Named("science") };
        StoryFilter? pickedFilter = null;
        string? pickedDomain = "unset";

        var content = StoryArchiveUi.BuildChips(domains, StoryFilter.Favorites, "history",
            onFilter: f => pickedFilter = f, onDomain: d => pickedDomain = d);

        var win = new Window { Width = 480, Height = 200, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("Favorites", texts);
        Assert.Contains("All domains", texts);
        Assert.Contains("History", texts);
        Assert.Contains("Science", texts);

        var missedChip = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "Missed");
        missedChip.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Equal(StoryFilter.Missed, pickedFilter);

        var allDomains = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "All domains");
        allDomains.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Null(pickedDomain);
    }

    [AvaloniaFact]
    public void Detail_panel_shows_the_full_story_and_a_reask_button_when_the_question_rebuilds()
    {
        var story = SeenStory.From(Q("a"), true);
        var content = StoryArchiveUi.BuildDetailPanel(story, onBack: () => { }, onFavorite: () => { }, onReask: () => { });

        var win = new Window { Width = 480, Height = 420, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("Prompt a", texts);
        Assert.Contains("Answer: A", texts);
        Assert.Contains("Because.", texts);
        Assert.Contains("Re-ask this", texts);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "story-archive-detail.png"));
    }

    [AvaloniaFact]
    public void Detail_panel_omits_the_reask_button_when_no_onReask_is_supplied()
    {
        var story = SeenStory.From(Q("a"), true);
        var content = StoryArchiveUi.BuildDetailPanel(story, onBack: () => { }, onFavorite: () => { }, onReask: null);

        var win = new Window { Width = 480, Height = 420, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.DoesNotContain("Re-ask this", TextsOf(win));
    }
}
