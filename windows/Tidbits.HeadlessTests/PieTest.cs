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

/// Mastering a domain (≥15 correct, ≥60% acc) fills its Pie wedge.
public class PieTest
{
    [AvaloniaFact]
    public async Task Mastered_domain_fills_a_pie_wedge()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var sources = QuestionSources.LoadFromDirectory(Path.Combine(System.AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-pie-{System.Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);
        try
        {
            // Two all-correct Science games → 20 correct at 100% → Science mastered.
            for (int n = 0; n < 2; n++)
            {
                var e = new GameEngine(provider, sources.Difficulty);
                await e.Start(GameMode.Classic, TriviaCategory.Named("science"));
                int g = 0;
                while (e.CurrentPhase != GameEngine.Phase.Finished && g++ < 40)
                {
                    if (e.CurrentPhase == GameEngine.Phase.Playing && e.Current is { } q) e.Submit(q.CorrectIndex);
                    else if (e.CurrentPhase == GameEngine.Phase.Reveal) e.Advance();
                }
                store.Record(e.Summary);
            }

            var vm = new RecordsViewModel(store);
            Assert.Equal(7, vm.Wedges.Count);
            Assert.True(vm.WedgesEarned >= 1);
            Assert.Contains(vm.Wedges, w => w.Name == "Science" && w.Mastered);

            var win = new Window { Width = 900, Height = 900, Content = new RecordsView { DataContext = vm } };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "records-pie.png"));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
