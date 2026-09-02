using System.Text.Json;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Submissions are ranked by when the SERVER saw them, not by the player's phone.
///
/// The speed bonus shipped ranking on `Ts`, which is the handset's own clock, so
/// a table whose phone ran a few seconds fast collected "fastest correct answer"
/// every round without answering faster — and nobody in the room could see why.
/// `Sv` is stamped by Firebase when the write lands; `OrderKey` prefers it and
/// falls back to `Ts` so a client that has not shipped the change still sorts.
public class ServerTimestampOrderingTest
{
    [Fact]
    public void OrderKey_prefers_the_server_stamp()
    {
        // The unfair case, made concrete: a phone three seconds fast claims to have
        // answered first, but the server saw it second.
        var fastClock = new LiveRoom.Answer { Ts = 1_000, Sv = 5_002 };
        var honest    = new LiveRoom.Answer { Ts = 4_000, Sv = 5_001 };
        Assert.True(honest.OrderKey < fastClock.OrderKey, "the server's order must win");
    }

    [Fact]
    public void OrderKey_falls_back_for_a_client_without_the_stamp()
    {
        var old = new LiveRoom.Answer { Ts = 7_777 };
        Assert.Null(old.Sv);
        Assert.Equal(7_777, old.OrderKey);
    }

    [Fact]
    public void The_sender_asks_the_server_for_the_timestamp()
    {
        var json = LivePlayerClient.WithServerTimestamp(new LiveRoom.Answer { Choice = 2, Ts = 123 });
        using var doc = JsonDocument.Parse(json);          // must still be valid JSON
        Assert.Equal("timestamp", doc.RootElement.GetProperty("sv").GetProperty(".sv").GetString());
        Assert.Equal(123, doc.RootElement.GetProperty("ts").GetInt64());
        Assert.Equal(2, doc.RootElement.GetProperty("choice").GetInt32());
    }
}
