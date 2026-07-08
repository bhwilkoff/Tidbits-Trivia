using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

public class LiveEventBalanceTest
{
    private static List<NightRound> R(params (GameMode k, int c)[] rounds) =>
        rounds.Select(r => new NightRound { Kind = r.k, Count = r.c }).ToList();

    [Fact]
    public void By_type_sums_and_ranks_question_counts()
    {
        var rounds = R((GameMode.Classic, 5), (GameMode.PictureId, 4), (GameMode.Classic, 3));
        var shares = LiveEventBalance.ByType(rounds);
        Assert.Equal(2, shares.Count);
        Assert.Equal(GameMode.Classic, shares[0].Kind);   // 5+3=8, most first
        Assert.Equal(8, shares[0].Questions);
        Assert.Equal(4, shares[1].Questions);
    }

    [Fact]
    public void Verdict_reflects_variety()
    {
        Assert.Equal("", LiveEventBalance.Verdict(R()));
        Assert.StartsWith("One-note", LiveEventBalance.Verdict(R((GameMode.Classic, 5), (GameMode.Classic, 4))));
        Assert.Equal("A little variety", LiveEventBalance.Verdict(R((GameMode.Classic, 5), (GameMode.PictureId, 4))));
        Assert.Equal("Great variety", LiveEventBalance.Verdict(
            R((GameMode.Classic, 4), (GameMode.PictureId, 4), (GameMode.ThisOrThat, 4), (GameMode.ClosestCall, 4))));
    }
}
