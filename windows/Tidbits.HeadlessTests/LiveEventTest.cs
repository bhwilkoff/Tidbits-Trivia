using System.Collections.Generic;
using System.IO;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

public class LiveEventTest
{
    private static LiveEvent Sample() => new()
    {
        Name = "Friday Pub Quiz",
        Rounds = new List<NightRound>
        {
            new() { Kind = GameMode.Classic, Count = 5 },
            new() { Kind = GameMode.PictureId, Count = 4 },
        },
    };

    [Fact]
    public void Converts_to_a_plan_with_the_same_rounds()
    {
        var ev = Sample();
        Assert.Equal(9, ev.TotalQuestions);
        Assert.Equal("2 rounds · 9 questions", ev.Summary);
        var plan = ev.ToPlan();
        Assert.Equal(2, plan.Rounds.Count);
        Assert.Equal(9, plan.TotalQuestions);
        Assert.Equal(GameMode.Classic, plan.Rounds[0].Kind);
    }

    [Fact]
    public void Store_upserts_persists_and_removes()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-events-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new LiveEventStore(path);
            var ev = Sample();
            store.Save(ev);
            Assert.Single(store.All);

            store.Save(ev with { Name = "Friday v2" });   // same id → upsert, not a 2nd entry
            Assert.Single(store.All);
            Assert.Equal("Friday v2", store.All[0].Name);

            var reloaded = new LiveEventStore(path);       // persisted with rounds intact
            Assert.Equal("Friday v2", reloaded.All[0].Name);
            Assert.Equal(9, reloaded.All[0].TotalQuestions);

            reloaded.Remove(ev.Id);
            Assert.Empty(reloaded.All);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
