using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.HeadlessTests;

/// The baseline-gated renders (WINDOWS-PLAYBOOK §4). These are the surfaces whose
/// pixels are contractual — a drift fails CI.
///
/// Every render here MUST be deterministic. The existing GameSnapshot tests call
/// engine.Start(), which draws a random question out of the 131k corpus, so their
/// pixels differ on every run — fine for "prove it renders", useless as a baseline.
/// These use StartCustom with fixed questions so the only thing that can change the
/// pixels is a change to the app.
public class BaselineSnapshots
{
    private static GameEngine NewEngine()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        return new GameEngine(new QuestionProvider(sources), sources.Difficulty);
    }

    private static Question Fixed() => new()
    {
        Id = "baseline-mcq-1",
        Prompt = "Which planet is known as the Red Planet?",
        Options = new[] { "Mars", "Venus", "Jupiter", "Mercury" },
        CorrectIndex = 0,
        CategoryId = "science",
        Difficulty = 2,
        Explanation = "Iron oxide on the surface gives Mars its colour.",
    };

    private static Window GameWindow(GameEngine engine) =>
        new() { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };

    [AvaloniaFact]
    public void Mcq_playing_surface_matches_baseline()
    {
        var engine = NewEngine();
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("science"), new[] { Fixed() });
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);

        var win = GameWindow(engine);
        win.Show();
        VisualBaseline.Matches(win, "baseline-mcq-playing");
    }

    [AvaloniaFact]
    public void Mcq_reveal_surface_matches_baseline()
    {
        var engine = NewEngine();
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("science"), new[] { Fixed() });

        var win = GameWindow(engine);
        win.Show();
        Dispatcher.UIThread.RunJobs();

        // Answer wrong so the baseline pins BOTH the green-correct and red-chosen states.
        engine.Submit(1);
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);

        VisualBaseline.Matches(win, "baseline-mcq-reveal");
    }
}
