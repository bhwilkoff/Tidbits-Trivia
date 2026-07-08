using System.Collections.Generic;
using System.IO;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

public class DuelStoreTest
{
    private static Question Q(string prompt, int ci) => new()
    {
        Id = "x", Prompt = prompt, Options = new[] { "a", "b", "c", "d" }, CorrectIndex = ci,
        CategoryId = "mixed", Explanation = "because",
    };

    [Fact]
    public void Compact_round_trips_to_playable_questions()
    {
        var original = new[] { Q("Capital of France?", 2), Q("2+2?", 0) };
        var compact = DuelStore.Compact(original);
        var duel = new Duel { Questions = compact };
        var back = DuelStore.QuestionsOf(duel);

        Assert.Equal(2, back.Count);
        Assert.Equal("Capital of France?", back[0].Prompt);
        Assert.Equal(2, back[0].CorrectIndex);
        Assert.Equal(new[] { "a", "b", "c", "d" }, back[0].Options);
        Assert.Equal("because", back[0].Explanation);
    }

    [Theory]
    [InlineData(false, false, 0, 0, DuelOutcome.YourTurn)]      // I haven't played
    [InlineData(true, false, 5, 0, DuelOutcome.WaitingOnThem)]  // done, they haven't
    [InlineData(true, true, 7, 4, DuelOutcome.YouWon)]
    [InlineData(true, true, 3, 8, DuelOutcome.YouLost)]
    [InlineData(true, true, 5, 5, DuelOutcome.Tie)]
    public void Classify_is_the_whole_state_machine(bool myDone, bool oppDone, int mine, int opp, DuelOutcome expected)
    {
        Assert.Equal(expected, DuelStore.Classify(myDone, oppDone, mine, opp));
    }

    [Fact]
    public void Tracks_ids_newest_first_deduped_capped()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-duels-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new DuelStore(path);
            store.Track("a");
            store.Track("b");
            store.Track("a");                       // dupe ignored
            Assert.Equal(new[] { "b", "a" }, store.Ids); // newest-first
            Assert.Equal(2, store.Ids.Count);

            Assert.Equal(new[] { "b", "a" }, new DuelStore(path).Ids); // persisted
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public void New_id_is_nonempty_and_unique()
    {
        Assert.NotEqual(DuelStore.NewId(), DuelStore.NewId());
        Assert.NotEmpty(DuelStore.NewId());
    }
}
