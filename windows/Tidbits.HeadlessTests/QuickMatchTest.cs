using System.Text.Json;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

public class QuickMatchTest
{
    [Fact]
    public void Wire_keys_match_the_web_schema()
    {
        var queue = JsonSerializer.Serialize(
            new QuickQueueEntry { RoomId = "AB12", Host = "u1", Ts = 100 }, Wire.Json);
        Assert.Contains("\"roomId\":\"AB12\"", queue);
        Assert.Contains("\"host\":\"u1\"", queue);
        Assert.Contains("\"ts\":100", queue);

        var meta = JsonSerializer.Serialize(
            new QuickRoomMeta { Host = "u1", CreatedAt = 5, State = "playing", StartedAt = 9, Questions = "[]" }, Wire.Json);
        Assert.Contains("\"host\":\"u1\"", meta);
        Assert.Contains("\"createdAt\":5", meta);
        Assert.Contains("\"state\":\"playing\"", meta);
        Assert.Contains("\"startedAt\":9", meta);
        Assert.Contains("\"questions\":\"[]\"", meta);

        var player = JsonSerializer.Serialize(
            new QuickPlayer { Name = "Ben", Score = 700, JoinedAt = 3, Done = true }, Wire.Json);
        Assert.Contains("\"name\":\"Ben\"", player);
        Assert.Contains("\"score\":700", player);
        Assert.Contains("\"joinedAt\":3", player);
        Assert.Contains("\"done\":true", player);
    }

    [Fact]
    public void ShouldClaim_matches_the_web_transaction()
    {
        Assert.False(QuickMatch.ShouldClaim(null, "me"));                                              // empty queue -> create
        Assert.False(QuickMatch.ShouldClaim(new QuickQueueEntry { RoomId = "", Host = "x" }, "me"));   // no room advertised
        Assert.False(QuickMatch.ShouldClaim(new QuickQueueEntry { RoomId = "R1", Host = "me" }, "me"));// my own room -> don't self-claim
        Assert.True(QuickMatch.ShouldClaim(new QuickQueueEntry { RoomId = "R1", Host = "them" }, "me"));// someone waiting -> claim
    }

    [Fact]
    public void Result_is_best_score_wins()
    {
        Assert.Equal(QuickOutcome.Win, QuickMatch.Result(700, 500));
        Assert.Equal(QuickOutcome.Lose, QuickMatch.Result(300, 500));
        Assert.Equal(QuickOutcome.Tie, QuickMatch.Result(500, 500));
    }
}
