using System.Collections.Generic;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// G1 buzz round — the first team to buzz answers out loud.
///
/// The whole feature is the ORDERING, so that is what is pinned. A buzzer decided
/// by whose handset clock runs fast is not a buzzer, and the speed bonus shipped
/// with exactly that bug. Mirrors Swift BuzzRoundTests.
public class BuzzRoundTest
{
    private static LiveRoom.Answer A(long ts, long? sv = null) =>
        new() { Ts = ts, Sv = sv };

    [Fact]
    public void The_server_stamp_decides_not_the_phone()
    {
        // "fast" has a handset three seconds ahead; the server saw "honest" first.
        var answers = new Dictionary<string, LiveRoom.Answer>
        {
            ["fast"] = A(1_000, 5_002),
            ["honest"] = A(4_000, 5_001),
        };
        Assert.Equal("honest", LiveNightHost.FirstBuzz(answers));
    }

    [Fact]
    public void Falls_back_to_the_device_clock_without_a_stamp()
    {
        var answers = new Dictionary<string, LiveRoom.Answer>
        {
            ["a"] = A(9_000),
            ["b"] = A(8_000),
        };
        Assert.Equal("b", LiveNightHost.FirstBuzz(answers));
    }

    [Fact]
    public void Nobody_buzzed()
    {
        Assert.Null(LiveNightHost.FirstBuzz(new Dictionary<string, LiveRoom.Answer>()));
    }

    [Fact]
    public void A_round_is_only_a_buzz_round_when_flagged()
    {
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), null!, "n");
        Assert.False(host.IsBuzzRound);              // no question, no flags
        host.BuzzRounds = new List<bool> { true };
        Assert.False(host.IsBuzzRound);              // still no current question
    }
}
