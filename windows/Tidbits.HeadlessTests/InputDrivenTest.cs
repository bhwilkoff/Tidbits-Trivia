using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.HeadlessTests;

/// Input-DRIVEN tests (WINDOWS-PLAYBOOK §4). Every other test builds a view and
/// asserts what it renders; these press real keys and click real pixels through
/// Avalonia's headless input stack, so they cover the wiring BETWEEN a widget and
/// the engine — the seam a render-only snapshot cannot see. This is what makes the
/// CI runner a drivable Windows box instead of a screenshot printer.
public class InputDrivenTest
{
    private static GameEngine NewEngine()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        return new GameEngine(new QuestionProvider(sources), sources.Difficulty);
    }

    /// Click the CENTER of a control the way a mouse would: translate to window
    /// coordinates, press, release.
    private static void Click(Window win, Control target)
    {
        var p = target.TranslatePoint(new Point(target.Bounds.Width / 2, target.Bounds.Height / 2), win);
        Assert.True(p.HasValue, "control is not in the window's visual tree");
        win.MouseDown(p!.Value, MouseButton.Left);
        win.MouseUp(p!.Value, MouseButton.Left);
        Dispatcher.UIThread.RunJobs();
    }

    private static List<Button> Buttons(Window win) =>
        win.GetVisualDescendants().OfType<Button>().ToList();

    /// A free-text question. The answer surface is chosen by the QUESTION SHAPE
    /// (GameView: `q.Accepted is not null` -> BuildText), not by GameMode — so a
    /// free-text surface has to be driven by a question carrying Accepted, not by
    /// starting GameMode.TypeAnswer and hoping the draw supplies one.
    private static Question TextQuestion() => new()
    {
        Id = "test-text-1",
        Prompt = "Which planet is known as the Red Planet?",
        Options = new[] { "Mars", "Venus", "Jupiter", "Mercury" },
        CorrectIndex = 0,
        CategoryId = "science",
        Accepted = new[] { "Mars", "mars" },
    };

    [AvaloniaFact]
    public async Task Clicking_the_correct_option_scores_it()
    {
        var engine = NewEngine();
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);

        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var q = engine.Current!;
        // The option buttons carry the option text as Content — find the correct one
        // by text rather than by index, so a layout reshuffle can't silently pass.
        var correctText = q.Options[q.CorrectIndex];
        var target = Buttons(win).Single(b => (b.Content as string) == correctText);

        Click(win, target);

        Assert.Equal(q.CorrectIndex, engine.ChosenIndex);
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Assert.True(engine.Score > 0, $"a correct click should score; score was {engine.Score}");
    }

    [AvaloniaFact]
    public async Task Clicking_a_wrong_option_does_not_score()
    {
        var engine = NewEngine();
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));

        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var q = engine.Current!;
        var wrongIdx = q.CorrectIndex == 0 ? 1 : 0;
        var target = Buttons(win).Single(b => (b.Content as string) == q.Options[wrongIdx]);

        Click(win, target);

        Assert.Equal(wrongIdx, engine.ChosenIndex);
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Assert.Equal(0, engine.Score);
    }

    [AvaloniaFact]
    public async Task Revealed_options_ignore_clicks()
    {
        var engine = NewEngine();
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));

        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var q = engine.Current!;
        var first = Buttons(win).Single(b => (b.Content as string) == q.Options[q.CorrectIndex]);
        Click(win, first);
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        var scoreAfterFirst = engine.Score;
        var chosen = engine.ChosenIndex;

        // On reveal the options go IsHitTestVisible=false (GameView.BuildMcq) — a second
        // click must not re-score or change the choice. Guards the double-scoring class
        // of bug the BotOpponent work already hit once.
        var again = Buttons(win).FirstOrDefault(b => (b.Content as string) == q.Options[q.CorrectIndex]);
        if (again is not null) Click(win, again);

        Assert.Equal(chosen, engine.ChosenIndex);
        Assert.Equal(scoreAfterFirst, engine.Score);
    }

    [AvaloniaFact]
    public void Typing_a_free_text_answer_and_pressing_enter_submits()
    {
        var engine = NewEngine();
        engine.StartCustom(GameMode.TypeAnswer, TriviaCategory.Named("science"), new[] { TextQuestion() });
        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);

        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var box = win.GetVisualDescendants().OfType<TextBox>().First();
        box.Focus();
        Dispatcher.UIThread.RunJobs();

        // Type the CORRECT answer character-by-character through the real input stack.
        var answer = engine.Current!.CorrectAnswer;
        win.KeyTextInput(answer);
        Dispatcher.UIThread.RunJobs();
        Assert.Equal(answer, box.Text);

        win.KeyPress(Key.Enter, RawInputModifiers.None, PhysicalKey.Enter, null);
        Dispatcher.UIThread.RunJobs();

        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Assert.True(engine.Score > 0, "typing the exact answer then Enter should score");
    }

    [AvaloniaFact]
    public void Answer_surface_survives_a_clock_tick_while_typing()
    {
        // Regression guard for the bug 2.8 fixed: the answer surface used to rebuild on
        // every 100ms Remaining tick, which dropped in-progress typing. Drive it for real.
        var engine = NewEngine();
        engine.StartCustom(GameMode.TypeAnswer, TriviaCategory.Named("science"), new[] { TextQuestion() });

        var win = new Window { Width = 900, Height = 680, Content = new GameView { DataContext = new GameViewModel(engine) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var box = win.GetVisualDescendants().OfType<TextBox>().First();
        box.Focus();
        win.KeyTextInput("partial answer");
        Dispatcher.UIThread.RunJobs();

        // Advance the render clock past several timer ticks.
        for (int i = 0; i < 5; i++)
        {
            AvaloniaHeadlessPlatform.ForceRenderTimerTick();
            Dispatcher.UIThread.RunJobs();
        }

        var boxAfter = win.GetVisualDescendants().OfType<TextBox>().First();
        Assert.Equal("partial answer", boxAfter.Text);
        Assert.Same(box, boxAfter);
    }
}
