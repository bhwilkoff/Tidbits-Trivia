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

/// Plays + records a few games, then renders the Records dashboard reading that store.
public class RecordsSnapshot
{
    [AvaloniaFact]
    public async Task Records_dashboard_renders_with_data()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-rec-{Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);

        try
        {
            // Play + record two games (answer mostly correct) so the dashboard has data.
            for (int n = 0; n < 2; n++)
            {
                var engine = new GameEngine(provider, sources.Difficulty);
                await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
                int g = 0;
                while (engine.CurrentPhase != GameEngine.Phase.Finished && g++ < 30)
                {
                    var q = engine.Current!;
                    engine.Submit(g % 4 == 0 ? (q.CorrectIndex + 1) % q.Options.Count : q.CorrectIndex);
                    engine.Advance();
                }
                store.Record(engine.Summary);
            }

            var win = new Window { Width = 900, Height = 760, Content = new RecordsView { DataContext = new RecordsViewModel(store) } };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "records.png"));
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
