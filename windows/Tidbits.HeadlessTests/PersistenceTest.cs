using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.HeadlessTests;

/// Plays a full game, records it, and verifies the JSON-backed RecordsStore persists
/// the record, best score, and (across a reload) survives to disk.
public class PersistenceTest
{
    [Fact]
    public async Task Finished_game_is_recorded_and_persists()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        var engine = new GameEngine(new QuestionProvider(sources), sources.Difficulty);
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
        int guard = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 30)
        {
            engine.Submit(engine.Current!.CorrectIndex);
            engine.Advance();
        }

        var path = Path.Combine(Path.GetTempPath(), $"tidbits-records-{Guid.NewGuid():N}.json");
        try
        {
            var store = new RecordsStore(path);
            var isNewBest = store.Record(engine.Summary);

            Assert.True(isNewBest);
            Assert.Single(store.Games);
            Assert.Equal(10, store.Games[0].Total);
            Assert.Equal(10, store.Games[0].Correct);
            Assert.True(store.BestScore(GameMode.Classic, "mixed") > 0);

            // Reload from disk — persistence survives.
            var reloaded = new RecordsStore(path);
            Assert.Single(reloaded.Games);
            Assert.Equal(store.Games[0].Score, reloaded.Games[0].Score);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
