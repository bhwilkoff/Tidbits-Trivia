using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.HeadlessTests;

/// End-to-end engine test: load the real corpus, play a full Classic game to the
/// finish answering correctly, and verify the phases/score/streak/summary. Proves
/// the ported GameEngine loop works before any UI is wired.
public class EnginePlaythrough
{
    private static GameEngine NewEngine()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        return new GameEngine(new QuestionProvider(sources), sources.Difficulty);
    }

    [Fact]
    public async Task Classic_game_plays_start_to_finish()
    {
        var engine = NewEngine();
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));

        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);
        Assert.Equal(10, engine.Questions.Count); // classic = 10 questions

        int played = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && played < 20)
        {
            Assert.NotNull(engine.Current);
            engine.Submit(engine.Current!.CorrectIndex); // answer correctly
            Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
            engine.Advance();
            played++;
        }

        var s = engine.Summary;
        Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
        Assert.Equal(10, s.Total);
        Assert.Equal(10, s.Correct);
        Assert.Equal(10, s.MaxStreak);
        Assert.True(s.Score > 0, "a perfect game should score points");
    }

    [Fact]
    public async Task Wrong_answer_breaks_the_streak()
    {
        var engine = NewEngine();
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
        var q = engine.Current!;
        var wrong = (q.CorrectIndex + 1) % q.Options.Count;
        engine.Submit(wrong);
        Assert.Equal(0, engine.Streak);
        Assert.False(engine.LastAnswer!.IsCorrect);
    }
}
