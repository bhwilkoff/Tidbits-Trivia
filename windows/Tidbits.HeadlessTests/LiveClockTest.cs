using System;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Tick 33 / 3.78 — every countdown the room shares is an ABSOLUTE deadline, so a device
/// whose clock is off counts down to the wrong moment. Measured on the bench: THIS box
/// runs 101 s behind the Mac. Byte-for-byte the Swift `LiveClockTests`.
public class LiveClockTest
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
    private static long NowMs => Now.ToUnixTimeMilliseconds();

    [Fact]
    public void An_older_host_that_does_not_stamp_leaves_the_clock_alone()
    {
        Assert.Equal(0, LiveClock.OffsetMs(null, Now));
        Assert.Equal(30, LiveClock.SecondsRemaining(NowMs + 30_000, 0, Now));
    }

    [Fact]
    public void A_device_running_behind_still_counts_the_hosts_seconds()
    {
        var deviceNow = Now.AddSeconds(-101);
        var offset = LiveClock.OffsetMs(NowMs, deviceNow);
        Assert.Equal(101, (int)(offset / 1000));
        var deadline = NowMs + 30_000;
        Assert.Equal(30, LiveClock.SecondsRemaining(deadline, offset, deviceNow));
        Assert.Equal(131, LiveClock.SecondsRemaining(deadline, 0, deviceNow));   // what it showed before
    }

    [Fact]
    public void A_device_running_ahead_is_corrected_too()
    {
        var deviceNow = Now.AddSeconds(45);
        var offset = LiveClock.OffsetMs(NowMs, deviceNow);
        Assert.Equal(-45, (int)(offset / 1000));
        Assert.Equal(30, LiveClock.SecondsRemaining(NowMs + 30_000, offset, deviceNow));
    }

    [Fact]
    public void An_expired_deadline_is_zero_not_negative()
    {
        Assert.Equal(0, LiveClock.SecondsRemaining(NowMs - 5_000, 0, Now));
        Assert.Null(LiveClock.SecondsRemaining(null, 0, Now));
    }

    [Fact]
    public void The_break_countdown_agrees_across_skewed_devices()
    {
        var until = LiveBreak.Until(10, Now);
        var deviceNow = Now.AddSeconds(-101);
        var offset = LiveClock.OffsetMs(NowMs, deviceNow);
        var corrected = LiveClock.HostNow(offset, deviceNow);
        Assert.Equal("Back in 10 minutes", LiveBreak.Headline(until, corrected));
        Assert.Equal("Back in 12 minutes", LiveBreak.Headline(until, deviceNow));   // the bench symptom
    }
}
