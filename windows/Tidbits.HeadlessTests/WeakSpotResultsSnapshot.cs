using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.HeadlessTests;

/// Weak-Spot Arena play-through: the per-question "why you're seeing this" reason
/// during play, and the "You closed N gaps" payoff on the results recap
/// (docs/CLUB-FEATURES-BUILD.md "Feature 1"). Deterministic — StartCustom with fixed
/// questions, never engine.Start() (WINDOWS-PLAYBOOK §4.2).
public class WeakSpotResultsSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    private static Question Q(string id, int correctIndex) => new()
    {
        Id = id,
        Prompt = $"Prompt for {id}",
        Options = new[] { "A", "B", "C", "D" },
        CorrectIndex = correctIndex,
        CategoryId = "mixed",
        Difficulty = 2,
        Explanation = "Because.",
    };

    private static GameEngine NewEngine()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        return new GameEngine(new QuestionProvider(sources), sources.Difficulty);
    }

    [AvaloniaFact]
    public void Reason_caption_shows_during_play_for_a_true_miss_question()
    {
        var engine = NewEngine();
        var q = Q("miss-1", 0);
        var reasons = new Dictionary<string, string> { ["miss-1"] = "Missed 2 weeks ago · ×3" };
        engine.StartCustom(GameMode.WeakSpot, TriviaCategory.Named("mixed"), new[] { q }, reasons);

        Assert.Equal("Missed 2 weeks ago · ×3", engine.CurrentReason);

        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "weak-spot-reason-caption.png"));
    }

    [AvaloniaFact]
    public void Results_recap_shows_gaps_closed_for_true_misses_answered_correctly()
    {
        var engine = NewEngine();
        // 2 true misses (answered correctly -> both close) + 1 domain-fill question
        // (answered correctly too, but it must NOT count toward gaps closed).
        var questions = new[] { Q("miss-a", 0), Q("miss-b", 0), Q("fill-c", 0) };
        var reasons = new Dictionary<string, string>
        {
            ["miss-a"] = "Missed 3 days ago · ×2",
            ["miss-b"] = "Missed 1 hr ago · ×1",
            ["fill-c"] = "Shoring up Science",
        };
        engine.StartCustom(GameMode.WeakSpot, TriviaCategory.Named("mixed"), questions, reasons);

        var vm = new GameViewModel(engine);
        var win = new Window { Width = 900, Height = 900, Content = new GameView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        int guard = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 20)
        {
            if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q)
                engine.Submit(q.CorrectIndex); // answer everything correctly
            else if (engine.CurrentPhase == GameEngine.Phase.Reveal)
                engine.Advance();
            Dispatcher.UIThread.RunJobs();
        }

        Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
        Assert.Equal(2, vm.WeakSpotGapsClosed);          // only the 2 true misses, not the fill question
        Assert.Equal("You closed 2 gaps", vm.WeakSpotGapsClosedHeadline);
        Assert.True(vm.HasWeakSpotGapsClosed);

        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "weak-spot-results.png"));
    }
}
