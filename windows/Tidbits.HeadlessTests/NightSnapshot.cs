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

/// Solo Trivia Night: a preset plan builds a multi-round question stream, each
/// round opens with an interstitial card, and every shape plays through to the
/// results recap.
public class NightSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    /// Submit *something* for whatever shape is on screen, so a night can be
    /// driven end-to-end regardless of round type.
    private static void AnswerCurrent(GameEngine e)
    {
        var q = e.Current!;
        if (q.Closest is not null) { e.SubmitGuess(); return; }
        if (q.Accepted is not null) { e.SubmitText(); return; }
        if (q.Ordering is not null) { e.SubmitOrder(); return; }
        if (q.Matching is not null) { e.SubmitMatch(); return; }
        if (q.Enumerate is not null) { e.FinishEnum(); return; }
        if (e.Mode == GameMode.Stake && e.CurrentStake == 0) e.SetStake(e.StakeTiers[0].Value);
        e.Submit(q.CorrectIndex);
    }

    [AvaloniaFact]
    public async Task A_solo_night_shows_round_intros_and_finishes()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"));
        var provider = new QuestionProvider(sources);
        var engine = new GameEngine(provider, sources.Difficulty);
        var vm = new GameViewModel(engine, null);
        var win = new Window { Width = 900, Height = 720, Content = new GameView { DataContext = vm } };
        win.Show();

        var plan = NightPlan.Quick;
        var questions = await provider.NightQuestions(plan, TriviaCategory.Named("mixed"));
        Assert.NotEmpty(questions);
        engine.StartNight(plan, TriviaCategory.Named("mixed"), questions);

        // First thing a night shows is the round-1 interstitial.
        Assert.Equal(GameEngine.Phase.RoundIntro, engine.CurrentPhase);
        Assert.Equal("ROUND 1 OF 3", engine.RoundBanner);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-night-intro.png"));

        // Drive the whole night: start each round, answer each question, advance
        // each reveal — until the results recap.
        int guard = 0, rounds = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 500)
        {
            switch (engine.CurrentPhase)
            {
                case GameEngine.Phase.RoundIntro: rounds++; engine.StartRound(); break;
                case GameEngine.Phase.Playing: AnswerCurrent(engine); break;
                case GameEngine.Phase.Reveal: engine.Advance(); break;
            }
            Dispatcher.UIThread.RunJobs();
        }

        Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
        Assert.Equal(3, rounds);                       // all three Quick-Night rounds ran
        Assert.Equal(questions.Count, engine.Summary.Answered.Count);
    }
}
