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

/// Plays a REAL Classic game to Finished (mixing right + wrong) and renders the
/// results recap — scorecard, stat row, spoiler-free grid, "Tidbits to remember",
/// and the share/play-again/done actions.
public class ResultsSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    [AvaloniaFact]
    public async Task Finished_game_renders_the_recap()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));

        var vm = new GameViewModel(engine);
        var win = new Window { Width = 900, Height = 900, Content = new GameView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        // Drive the whole game: answer alternating right/wrong so the recap has both
        // a real score and a populated "Tidbits to remember" list.
        int guard = 0;
        bool wrong = false;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 200)
        {
            if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q)
            {
                int pick = wrong ? (q.CorrectIndex + 1) % q.Options.Count : q.CorrectIndex;
                wrong = !wrong;
                engine.Submit(pick);
            }
            else if (engine.CurrentPhase == GameEngine.Phase.Reveal)
            {
                engine.Advance();
            }
            Dispatcher.UIThread.RunJobs();
        }

        Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
        Assert.True(vm.HasMissed, "expected some missed questions to populate the recap");
        Assert.NotEmpty(vm.Grid);

        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-results.png"));
    }
}
