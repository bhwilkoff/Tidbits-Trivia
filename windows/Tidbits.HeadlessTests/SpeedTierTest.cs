using System.Collections.Generic;
using Tidbits.Core.Networking;
using Xunit;

public class SpeedTierTest
{
    [Fact]
    public void Fastest_three_correct_score_3_2_1()
    {
        var b = LiveScoring.SpeedBonuses(new[] { "a", "b", "c", "d", "e" });
        Assert.Equal(3, b["a"]);
        Assert.Equal(2, b["b"]);
        Assert.Equal(1, b["c"]);
        Assert.False(b.ContainsKey("d")); // 4th+ get no bonus
        Assert.False(b.ContainsKey("e"));
    }

    [Fact]
    public void Fewer_than_three_correct_is_fine()
    {
        var b = LiveScoring.SpeedBonuses(new[] { "solo" });
        Assert.Equal(3, b["solo"]);
        Assert.Single(b);
        Assert.Empty(LiveScoring.SpeedBonuses(new List<string>())); // nobody correct
    }
}
