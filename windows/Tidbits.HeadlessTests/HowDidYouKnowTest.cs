using System;
using System.Collections.Generic;
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

public class HowDidYouKnowTest
{
    [Fact]
    public void Share_text_is_a_conversation_starter()
    {
        var q = new Question
        {
            Id = "q", Prompt = "Who composed 4′33″?", CategoryId = "music",
            CorrectIndex = 3, Options = new List<string> { "a", "b", "c", "John Cage" }, Difficulty = 5,
        };
        var a = new AnsweredQuestion { Question = q, ChosenIndex = 3, SecondsTaken = 5 };
        var text = GameViewModel.HowDidYouKnowText(a);
        Assert.Contains("I knew", text);
        Assert.Contains("John Cage", text);
        Assert.Contains("How did YOU know that?", text);
    }

    [AvaloniaFact]
    public async Task Nailed_section_renders_on_an_all_correct_game()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
        var vm = new GameViewModel(engine);
        var win = new Window { Width = 900, Height = 1000, Content = new GameView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        int guard = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 200)
        {
            if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q)
                engine.Submit(q.CorrectIndex);                 // all correct
            else if (engine.CurrentPhase == GameEngine.Phase.Reveal)
                engine.Advance();
            Dispatcher.UIThread.RunJobs();
        }

        // The Nailed filter = correct AND difficulty >= 4 (a subset of the correct set).
        Assert.All(vm.Nailed, a => Assert.True(a.IsCorrect && a.Question.Difficulty >= 4));
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "game-nailed.png"));
    }
}
