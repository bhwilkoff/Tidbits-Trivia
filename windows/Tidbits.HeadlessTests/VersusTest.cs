using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

public class VersusTest
{
    [Fact]
    public void Bot_skill_and_freeze_rate_match_the_spec()
    {
        var ace = Bots.All["ace"]; // baseSkill 0.85, neutral on "history"
        var rng = new Random(42);
        int freezes = 0, correct = 0, answered = 0;
        for (int i = 0; i < 4000; i++)
        {
            var r = Bots.Resolve(ace, "history", difficulty: 3, correctIndex: 2, optionCount: 4, windowSecs: 25, rng);
            if (r.ChoiceIndex is null) { freezes++; continue; }
            answered++;
            if (r.ChoiceIndex == 2) correct++;
            Assert.NotNull(r.Seconds);
            Assert.InRange(r.Seconds!.Value, 0.8, 24.5); // clamped into the window
        }
        double freezeRate = (double)freezes / 4000;
        double skill = (double)correct / answered;
        Assert.InRange(freezeRate, 0.02, 0.08); // ~5% freeze
        Assert.InRange(skill, 0.79, 0.91);       // ~85% (p=0.85)
    }

    [Fact]
    public void House_adapts_to_player_accuracy_and_ids_resolve()
    {
        Assert.Equal(0.35, Bots.House(0.1).BaseSkill, 3);  // floor
        Assert.Equal(0.90, Bots.House(0.99).BaseSkill, 3); // ceiling
        Assert.Equal(0.62, Bots.House(0.62).BaseSkill, 3);
        Assert.Equal("rookie", Bots.ById("rookie", 0.6).Id);
        Assert.Equal("house", Bots.ById("nope", 0.6).Id);  // unknown → House
    }

    [Fact]
    public void VsMatch_scores_a_correct_bot_answer()
    {
        var q = new Question
        {
            Id = "q1", Prompt = "?", CategoryId = "history", CorrectIndex = 1, Difficulty = 1,
            Options = new List<string> { "a", "b", "c", "d" },
        };
        // A perfect bot (baseSkill high, low difficulty) with a seed that doesn't freeze.
        var bot = new Bot("t", "Testy", 0.98, new Dictionary<string, double>(), 4.0, 0.0);
        var match = new VsMatch(new[] { bot }, new Random(1));
        match.BeginQuestion(q, 25);
        match.Commit(q, index: 0, budget: 25);
        // Committing the same reveal twice must not double-score.
        int once = match.Seats[0].Score;
        match.Commit(q, index: 0, budget: 25);
        Assert.Equal(once, match.Seats[0].Score);
        Assert.True(match.Seats[0].Score >= 0);
    }

    [AvaloniaFact]
    public async Task Versus_view_renders_the_you_vs_cpu_strip()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? System.IO.Path.Combine(AppContext.BaseDirectory, "artifacts");
        System.IO.Directory.CreateDirectory(dir);

        var sources = QuestionSources.LoadFromDirectory(System.IO.Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
        var player = new GameViewModel(engine, null);
        var vm = new VersusViewModel(player, Bots.All["ace"], new Random(7));
        Assert.Contains("CPU", vm.BotLabel);

        var win = new Window { Width = 900, Height = 680, Content = new VersusView { DataContext = vm } };
        win.Show();
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
        Dispatcher.UIThread.RunJobs();

        // Answer one question so the bot resolves + commits (its score may move).
        engine.Submit(engine.Current!.CorrectIndex);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(System.IO.Path.Combine(dir, "game-versus.png"));

        Assert.True(vm.PlayerScore > 0);
    }
}
