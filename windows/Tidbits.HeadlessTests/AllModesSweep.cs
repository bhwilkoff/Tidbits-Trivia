using System;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Windows half of the QA sweep (docs/QA-SWEEP-LOG.md) — render EVERY game mode, not
/// just Classic, so a shape that renders wrong is visible as a PNG.
///
/// The equivalent sweep on the other four platforms found a real bug in every one, and the
/// Android bug in particular (MCQ buttons drawn on top of every non-MCQ shape) is exactly
/// the class this catches: it is invisible in a Classic-only snapshot.
[Collection("EnvSensitive")]
public class AllModesSweep
{
    public static TheoryData<GameMode> Modes => new()
    {
        GameMode.Classic, GameMode.TimeAttack, GameMode.Survival, GameMode.Stake,
        GameMode.Sweep, GameMode.PictureId, GameMode.ThisOrThat, GameMode.ClosestCall,
        GameMode.Ordering, GameMode.Matching, GameMode.TypeAnswer, GameMode.OddOneOut,
        GameMode.Ladder, GameMode.Enumerate, GameMode.Daily,
    };

    [AvaloniaTheory]
    [MemberData(nameof(Modes))]
    public async Task Every_mode_renders_a_playable_question(GameMode mode)
    {
        var data = GameData.FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"));
        var engine = data.NewEngine();
        await engine.Start(mode, TriviaCategory.Named("mixed"));

        // A mode with no questions is itself a finding — the player would see an empty board.
        Assert.True(engine.CurrentPhase == GameEngine.Phase.Playing,
            $"{mode} did not reach Playing (phase={engine.CurrentPhase})");
        Assert.NotNull(engine.Current);

        var win = new Window { Width = 900, Height = 760, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var dir = Path.Combine(AppContext.BaseDirectory, "artifacts", "sweep");
        Directory.CreateDirectory(dir);
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, $"mode-{mode}.png"));
    }
}
