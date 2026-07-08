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

/// The Records "See all games" drill-in: the VM exposes full game detail, and the
/// list + per-question recap render.
public class DrillInSnapshot
{
    private static string Art()
    {
        var d = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    [AvaloniaFact]
    public async Task Drill_in_list_and_recap_render_from_recorded_games()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-drill-{System.Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);

        try
        {
            // Record a game with per-answer detail (some right, some wrong).
            var engine = new GameEngine(provider, sources.Difficulty);
            await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
            int g = 0;
            while (engine.CurrentPhase != GameEngine.Phase.Finished && g++ < 30)
            {
                var q = engine.Current!;
                engine.Submit(g % 3 == 0 ? (q.CorrectIndex + 1) % q.Options.Count : q.CorrectIndex);
                engine.Advance();
            }
            for (int i = 0; i < 5; i++) store.Record(engine.Summary); // >3 so "See all" applies

            var vm = new RecordsViewModel(store);
            Assert.True(vm.HasMoreGames);
            Assert.Equal(5, vm.AllGames.Count);
            var first = vm.AllGames[0];
            Assert.NotEmpty(first.Answers);                          // per-question detail present
            Assert.Contains(first.Answers, a => a.Correct);          // some right
            Assert.Contains(first.Answers, a => !a.Correct);         // some wrong

            // The list renders...
            GameDetail? picked = null;
            var listView = RecordsView.GameListView(vm.AllGames, gd => picked = gd);
            var win = new Window { Width = 460, Height = 520, Content = listView };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "records-drillin-list.png"));

            // ...and the per-question recap renders.
            var recap = RecordsView.RecapView(first, () => { });
            win.Content = recap;
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "records-drillin-recap.png"));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
