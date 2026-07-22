using System;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Marathon play-through + scorecard (docs/CLUB-FEATURES-BUILD.md
/// "Feature 3") — the load-bearing new mechanic (resume across sessions) end to
/// end: the HUD's true position when resumed, persisting every answer, and the
/// permanent scorecard once the run reaches its true end (with NO GameRecord /
/// miss / seen-story written). Deterministic — StartCustom with fixed questions,
/// never engine.Start() (WINDOWS-PLAYBOOK §4.2).
public class MarathonResultsSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    private static Question Q(string id, string categoryId, int difficulty = 3) => new()
    {
        Id = id, Prompt = $"Prompt for {id}", Options = new[] { "A", "B", "C", "D" },
        CorrectIndex = 0, CategoryId = categoryId, Difficulty = difficulty, Explanation = "Because.",
    };

    private static GameEngine NewEngine()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        return new GameEngine(new QuestionProvider(sources), sources.Difficulty);
    }

    private static RecordsStore NewRecords()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-marathon-vm-{Guid.NewGuid():N}.json");
        return new RecordsStore(path);
    }

    [AvaloniaFact]
    public void HUD_shows_the_true_position_across_the_whole_run_when_resumed()
    {
        var engine = NewEngine();
        // Resuming with 2 remaining out of a 10-question run (8 already answered
        // in earlier sessions) — the HUD must read "9 / 10", never "1 / 2".
        var questions = new[] { Q("r1", "history"), Q("r2", "science") };
        engine.StartCustom(GameMode.Marathon, TriviaCategory.Named("mixed"), questions, marathonOffset: 8);

        Assert.Equal("9 / 10", engine.MarathonProgressLabel);

        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "marathon-hud-resume.png"));
    }

    [AvaloniaFact]
    public void Finishing_a_run_writes_no_game_record_and_shows_the_permanent_scorecard()
    {
        var engine = NewEngine();
        var questions = new[]
        {
            Q("m1", "history"), Q("m2", "science"), Q("m3", "history"), Q("m4", "science"),
        };
        var records = NewRecords();
        var run = new MarathonRun("seed", questions.Select(q => q.Id).ToList());
        records.SaveMarathonRun(run);
        engine.StartCustom(GameMode.Marathon, TriviaCategory.Named("mixed"), questions);

        var vm = new GameViewModel(engine, records, run);
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
        Assert.NotNull(vm.MarathonResult);
        Assert.Equal(4, vm.MarathonResult!.Correct);
        Assert.Equal(4, vm.MarathonResult.Total);
        Assert.Equal(120, vm.MarathonResult.Score); // 4 correct, each difficulty 3 -> 4 * 3 * 10
        Assert.Null(records.MarathonRun); // the in-progress slot is cleared
        Assert.Single(records.MarathonHistory);

        // Marathon writes NO GameRecord / miss / seen-story — a partial session
        // slice would misreport lifetime stats (docs/CLUB-FEATURES-BUILD.md
        // "Feature 3"). This is the assertion that catches a regression back to
        // the generic `_records.Record(Engine.Summary)` path.
        Assert.Empty(records.Games);
        Assert.Empty(records.Missed);
        Assert.Empty(records.Seen);

        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "marathon-scorecard.png"));
    }
}
