using System.IO;
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

/// Finishing today's Daily bumps the day streak, which the results recap surfaces.
public class DayStreakTest
{
    [AvaloniaFact]
    public async Task Daily_result_shows_the_day_streak()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var sources = QuestionSources.LoadFromDirectory(Path.Combine(System.AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-streak-{System.Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);
        try
        {
            var engine = new GameEngine(provider, sources.Difficulty);
            var vm = new GameViewModel(engine, store);
            var win = new Window { Width = 900, Height = 900, Content = new GameView { DataContext = vm } };
            win.Show();
            await engine.Start(GameMode.Daily, TriviaCategory.Named("mixed"));

            int g = 0;
            while (engine.CurrentPhase != GameEngine.Phase.Finished && g++ < 40)
            {
                if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q) engine.Submit(q.CorrectIndex);
                else if (engine.CurrentPhase == GameEngine.Phase.Reveal) engine.Advance();
                Dispatcher.UIThread.RunJobs();
            }

            Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
            Assert.True(vm.HasDayStreak);       // first daily today → streak 1
            Assert.Equal(1, vm.DayStreak);

            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "results-daystreak.png"));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
