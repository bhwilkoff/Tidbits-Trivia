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

/// Renders a REAL in-progress game (a Classic question with options) to a PNG —
/// the visual proof the Windows app is playable, not just frames.
public class GameSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    [AvaloniaFact]
    public async Task Playing_a_real_question_renders()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);

        var vm = new GameViewModel(engine);
        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-question.png"));
    }

    [AvaloniaFact]
    public async Task Reveal_highlights_the_answer()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));

        var vm = new GameViewModel(engine);
        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        // Answer wrong so the PNG shows green (correct) + red (chosen-wrong).
        var q = engine.Current!;
        engine.Submit((q.CorrectIndex + 1) % q.Options.Count);
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-reveal.png"));
    }
}
