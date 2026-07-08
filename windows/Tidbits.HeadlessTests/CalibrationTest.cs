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

namespace Tidbits.HeadlessTests;

/// A Stake round records per-tier calibration; the Records dashboard shows it.
public class CalibrationTest
{
    [AvaloniaFact]
    public async Task Stake_round_populates_the_calibration_readout()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var sources = QuestionSources.LoadFromDirectory(Path.Combine(System.AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-cal-{System.Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);
        try
        {
            var engine = new GameEngine(provider, sources.Difficulty);
            await engine.Start(GameMode.Stake, TriviaCategory.Named("mixed"));

            int g = 0;
            while (engine.CurrentPhase != GameEngine.Phase.Finished && g++ < 40)
            {
                if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q)
                {
                    // Commit a chip (required before answering in Stake), then answer —
                    // alternate right/wrong so the tier has both hits and misses.
                    engine.SetStake(engine.StakeTiers[g % engine.StakeTiers.Count].Value);
                    engine.Submit(g % 2 == 0 ? q.CorrectIndex : (q.CorrectIndex + 1) % q.Options.Count);
                }
                else if (engine.CurrentPhase == GameEngine.Phase.Reveal) engine.Advance();
            }
            store.Record(engine.Summary);

            var vm = new RecordsViewModel(store);
            Assert.True(vm.HasCalibration);
            Assert.All(vm.Calibration, r => Assert.True(r.Total > 0));
            Assert.All(vm.Calibration, r => Assert.InRange(r.Rate, 0.0, 1.0));

            var win = new Window { Width = 900, Height = 1000, Content = new RecordsView { DataContext = vm } };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "records-calibration.png"));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
