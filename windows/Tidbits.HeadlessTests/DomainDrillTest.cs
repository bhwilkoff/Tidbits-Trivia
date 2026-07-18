using System;
using System.IO;
using System.Linq;
using Avalonia.Headless.XUnit;
using Tidbits.App.ViewModels;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

public class DomainDrillTest
{
    [AvaloniaFact]
    public async Task Domain_drill_in_splits_missed_and_right_by_domain()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-domain-{Guid.NewGuid():N}.json");
        try
        {
            var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
            var store = new RecordsStore(path);
            var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
            await engine.Start(GameMode.Classic, TriviaCategory.Named("science"));

            int guard = 0;
            while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 200)
            {
                if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q)
                    engine.Submit(q.CorrectIndex);                     // all correct
                else if (engine.CurrentPhase == GameEngine.Phase.Reveal)
                    engine.Advance();
            }
            store.Record(engine.Summary);

            var vm = new RecordsViewModel(store);
            var (missed, right) = vm.DomainAnswers("science");
            Assert.Empty(missed);                                       // answered all correct
            Assert.All(right, a => Assert.True(a.Correct));
            Assert.Equal(right.Count, right.Select(a => a.Prompt).Distinct().Count()); // dedup by qid

            // A domain never played has no per-question history.
            var (m2, r2) = vm.DomainAnswers("history");
            Assert.Empty(m2);
            Assert.Empty(r2);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
