using System;
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

public class BestsTest
{
    [AvaloniaFact]
    public async Task Personal_bests_group_by_mode_and_render()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-bests-{Guid.NewGuid():N}.json");
        try
        {
            var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
            var store = new RecordsStore(path);

            // Two Classic/science games so a best + play-count exist.
            for (int n = 0; n < 2; n++)
            {
                var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
                await engine.Start(GameMode.Classic, TriviaCategory.Named("science"));
                int guard = 0;
                while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 200)
                {
                    if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q)
                        engine.Submit(q.CorrectIndex);
                    else if (engine.CurrentPhase == GameEngine.Phase.Reveal)
                        engine.Advance();
                }
                store.Record(engine.Summary);
            }

            var vm = new RecordsViewModel(store);
            Assert.True(vm.HasBests);
            var classic = vm.Bests.Single(b => b.ModeId == "classic");
            Assert.Equal(2, classic.Plays);
            Assert.True(classic.Best > 0);
            Assert.Equal(2, vm.ModeGames("classic").Count);
            Assert.Empty(vm.ModeGames("timeAttack"));

            var win = new Window { Width = 900, Height = 1600, Content = new RecordsView { DataContext = vm } };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "records-bests.png"));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
