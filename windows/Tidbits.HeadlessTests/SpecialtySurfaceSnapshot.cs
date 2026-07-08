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

/// The specialty (non-MCQ) answer surfaces render + play: Closest Call (numeric
/// slider) and Name It (free-text). Loads the full shared Data/ set so the
/// specialty question JSONs (closest.json / typeanswer.json) resolve.
public class SpecialtySurfaceSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    private static (GameEngine, GameViewModel, Window) Start(GameMode mode)
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"));
        var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
        var vm = new GameViewModel(engine);
        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = vm } };
        win.Show();
        return (engine, vm, win);
    }

    [AvaloniaFact]
    public async Task Closest_call_renders_a_numeric_slider()
    {
        var (engine, _, win) = Start(GameMode.ClosestCall);
        await engine.Start(GameMode.ClosestCall, TriviaCategory.Named("mixed"));
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);
        Assert.NotNull(engine.Current!.Closest);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-closest.png"));

        // The slider path actually scores: guess the exact answer -> a close hit.
        engine.SetGuess(engine.Current!.Closest!.Answer);
        engine.SubmitGuess();
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Assert.True(engine.LastGuessPoints > 0, "an exact guess should score points");
    }

    [AvaloniaFact]
    public async Task Stake_renders_chips_then_scores_the_stake()
    {
        var (engine, _, win) = Start(GameMode.Stake);
        await engine.Start(GameMode.Stake, TriviaCategory.Named("mixed"));
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);
        Assert.NotEmpty(engine.StakeTiers);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-stake.png"));

        // Answering before a chip is committed is a no-op; committing then answering
        // correct adds exactly the staked value.
        var q = engine.Current!;
        engine.Submit(q.CorrectIndex);
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase); // blocked, no stake yet
        int stake = engine.StakeTiers[0].Value;
        engine.SetStake(stake);
        engine.Submit(q.CorrectIndex);
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Assert.Equal(stake, engine.Score);
    }

    [AvaloniaFact]
    public async Task In_order_renders_reorderable_items_and_submits()
    {
        var (engine, _, win) = Start(GameMode.Ordering);
        await engine.Start(GameMode.Ordering, TriviaCategory.Named("mixed"));
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);
        Assert.NotNull(engine.Current!.Ordering);
        Assert.NotEmpty(engine.CurrentOrder);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-ordering.png"));

        // A move reorders in place; submitting resolves to reveal with a score.
        engine.MoveOrderItem(1, up: true);
        engine.SubmitOrder();
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Assert.True(engine.LastOrderPoints >= 0);
    }

    [AvaloniaFact]
    public async Task Name_it_renders_a_text_field_and_accepts()
    {
        var (engine, _, win) = Start(GameMode.TypeAnswer);
        await engine.Start(GameMode.TypeAnswer, TriviaCategory.Named("mixed"));
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);
        Assert.NotNull(engine.Current!.Accepted);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "game-typeanswer.png"));

        // Typing the accepted answer resolves correct.
        engine.TypedText = engine.Current!.Accepted![0];
        engine.SubmitText();
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Assert.True(engine.LastAnswer!.IsCorrect, "the accepted answer should resolve correct");
    }
}
