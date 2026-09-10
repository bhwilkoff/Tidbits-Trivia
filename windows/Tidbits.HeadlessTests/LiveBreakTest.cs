using System;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A3.14 / 3.77 — the break text is pure and shared, so the big screen, the cockpit and
/// all five joiners say the same thing. Byte-for-byte the Swift `LiveBreakTests`.
public class LiveBreakTest
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    [Fact]
    public void No_promise_is_back_in_a_moment()
    {
        Assert.Equal("Back in a moment", LiveBreak.Headline(null, Now));
        Assert.Equal("", LiveBreak.ClockLine(null, Now));
        Assert.Null(LiveBreak.MinutesLeft(null, Now));
    }

    [Fact]
    public void Minutes_round_to_the_nearest_so_ten_reads_ten_everywhere()
    {
        var up = Now.ToUnixTimeMilliseconds() + (9 * 60 + 30) * 1000L;
        Assert.Equal(10, LiveBreak.MinutesLeft(up, Now));
        Assert.Equal("Back in 10 minutes", LiveBreak.Headline(up, Now));
        // …and 10m05s is TEN, not eleven — rounding up made every slightly-slow clock in
        // the room show a different number (measured: projector 10, Windows joiner 11).
        var skewed = Now.ToUnixTimeMilliseconds() + (10 * 60 + 5) * 1000L;
        Assert.Equal(10, LiveBreak.MinutesLeft(skewed, Now));
    }

    [Fact]
    public void Under_half_a_minute_is_a_moment_rather_than_a_minute()
    {
        var soon = Now.ToUnixTimeMilliseconds() + 10_000L;
        Assert.Null(LiveBreak.MinutesLeft(soon, Now));
        Assert.Equal("Back in a moment", LiveBreak.Headline(soon, Now));
    }

    [Fact]
    public void One_minute_is_singular()
    {
        var until = Now.ToUnixTimeMilliseconds() + 70_000L;
        Assert.Equal("Back in a minute", LiveBreak.Headline(until, Now));
    }

    [Fact]
    public void A_passed_promise_falls_back_rather_than_counting_negative()
    {
        var past = Now.ToUnixTimeMilliseconds() - 120_000L;
        Assert.Null(LiveBreak.MinutesLeft(past, Now));
        Assert.Equal("Back in a moment", LiveBreak.Headline(past, Now));
        Assert.Equal("", LiveBreak.ClockLine(past, Now));
    }

    [Fact]
    public void Until_is_minutes_from_now_and_round_trips()
    {
        var until = LiveBreak.Until(15, Now);
        Assert.Equal(15, LiveBreak.MinutesLeft(until, Now));
        Assert.StartsWith("back at ", LiveBreak.ClockLine(until, Now));
    }
}
