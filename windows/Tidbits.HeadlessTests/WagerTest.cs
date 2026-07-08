using System.Collections.Generic;
using System.IO;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

public class WagerTest
{
    [Theory]
    [InlineData(true, 10, 10)]    // correct → +stake
    [InlineData(false, 10, -10)]  // wrong → −stake
    [InlineData(true, 0, 0)]      // no stake → no change
    public void Wager_delta_adds_or_subtracts_the_stake(bool correct, int stake, int expected)
    {
        Assert.Equal(expected, LiveScoring.WagerDelta(correct, stake));
    }

    [Fact]
    public void Wager_flag_persists_on_the_event()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-wager-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new LiveEventStore(path);
            store.Save(new LiveEvent
            {
                Name = "Big Finish",
                Rounds = new List<NightRound> { new() { Kind = GameMode.Classic, Count = 5 } },
                WagerFinalRound = true,
            });
            Assert.True(new LiveEventStore(path).All[0].WagerFinalRound);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public void Host_wager_round_defaults_off()
    {
        var data = Tidbits.App.Services.GameData.Shared.Value;
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), data.Provider, "N");
        Assert.False(host.IsWagerRound);         // no WagerRoundIndex set
        host.WagerRoundIndex = 2;
        Assert.False(host.IsWagerRound);         // still false — no Current question (no live room)
    }
}
