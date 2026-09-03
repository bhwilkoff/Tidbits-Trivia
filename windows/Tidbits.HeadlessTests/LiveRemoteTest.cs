using System.Linq;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// G6 — the host's phone remote. The SAME cases as Swift
/// TidbitsTriviaTests/LiveRemoteTests.swift.
public class LiveRemoteTest
{
    private static RemoteCommand Cmd(int id, string verb, string pin = "123456") =>
        new() { Id = id, Verb = verb, Pin = pin };

    [Fact]
    public void A_valid_command_is_accepted() =>
        Assert.True(LiveRemote.Accepted(Cmd(1, "next"), "123456", 0));

    [Fact]
    public void The_wrong_pin_is_refused() =>
        // The room code is on the projector; every player has it.
        Assert.False(LiveRemote.Accepted(Cmd(1, "next", "000000"), "123456", 0));

    [Fact]
    public void A_host_with_no_pin_accepts_nothing() =>
        // Not-yet-paired must fail closed, not open.
        Assert.False(LiveRemote.Accepted(Cmd(1, "next", ""), "", 0));

    [Fact]
    public void A_replayed_command_is_refused()
    {
        Assert.True(LiveRemote.Accepted(Cmd(5, "next"), "123456", 4));
        Assert.False(LiveRemote.Accepted(Cmd(5, "next"), "123456", 5));
    }

    [Fact]
    public void An_out_of_order_command_is_refused() =>
        Assert.False(LiveRemote.Accepted(Cmd(3, "next"), "123456", 7));

    [Fact]
    public void An_unknown_verb_is_refused()
    {
        Assert.False(LiveRemote.Accepted(Cmd(1, "endnight"), "123456", 0));
        Assert.False(LiveRemote.Accepted(Cmd(1, ""), "123456", 0));
    }

    [Fact]
    public void The_remote_is_a_clicker_not_a_second_cockpit()
    {
        Assert.Equal(new[] { "board", "next", "reveal", "scores", "skip" }, LiveRemote.Verbs.OrderBy(v => v));
        foreach (var v in new[] { "setscore", "removeteam", "editquestion", "endnight" })
            Assert.DoesNotContain(v, LiveRemote.Verbs);
    }

    [Fact]
    public void A_reconnecting_remote_resumes_from_the_hosts_counter()
    {
        Assert.Equal(10, LiveRemote.NextId(9));
        Assert.True(LiveRemote.Accepted(Cmd(LiveRemote.NextId(9), "reveal"), "123456", 9));
    }

    [Fact]
    public void A_pin_is_six_digits()
    {
        for (int i = 0; i < 50; i++)
        {
            var p = LiveRemote.MakePin();
            Assert.Equal(6, p.Length);
            Assert.All(p, c => Assert.True(char.IsDigit(c)));
        }
    }
}
