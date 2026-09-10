using System;
using System.Collections.Generic;

namespace Tidbits.Core.Networking;

/// A3.14 — what a room on a break is told. Pure and shared so the big screen, the
/// cockpit and all five joiners say the SAME thing: a break announced two different
/// ways on the projector and the phone is a room asking the host which is right.
/// Mirror of Swift's `LiveBreak`.
public static class LiveBreak
{
    /// The headline. A promised return time counts down in whole minutes and never
    /// goes negative — "Back in 0 min" is worse than saying nothing.
    public static string Headline(long? until, DateTimeOffset? now = null)
    {
        var mins = MinutesLeft(until, now);
        if (mins is not { } m || m <= 0) return "Back in a moment";
        return m == 1 ? "Back in a minute" : $"Back in {m} minutes";
    }

    /// Whole minutes left, to the NEAREST minute (half up). A host who says ten is not
    /// immediately shown nine — and a device whose clock runs a few seconds slow is not
    /// shown ELEVEN, which rounding up did (measured on the bench, tick 32: the projector
    /// said 10 and this joiner said 11). Under 30 seconds it falls through to "Back in a
    /// moment". null when no return time was promised or it has passed.
    public static int? MinutesLeft(long? until, DateTimeOffset? now = null)
    {
        if (until is not { } u) return null;
        var secs = u / 1000.0 - (now ?? DateTimeOffset.Now).ToUnixTimeMilliseconds() / 1000.0;
        if (secs <= 0) return null;
        var mins = (int)Math.Round(secs / 60, MidpointRounding.AwayFromZero);
        return mins > 0 ? mins : null;
    }

    /// "back at 9:15" — the clock time, which is what a room actually acts on when
    /// people wander to the bar. Empty when no return time was promised.
    public static string ClockLine(long? until, DateTimeOffset? now = null)
    {
        if (until is not { } u || MinutesLeft(until, now) is null) return "";
        return "back at " + DateTimeOffset.FromUnixTimeMilliseconds(u).LocalDateTime.ToString("t");
    }

    /// The epoch-ms a break of `minutes` from now ends.
    public static long Until(int minutes, DateTimeOffset? now = null) =>
        (now ?? DateTimeOffset.Now).ToUnixTimeMilliseconds() + minutes * 60_000L;

    /// The minute choices a host is offered — a pub break is five, ten or fifteen.
    public static IReadOnlyList<int> Choices { get; } = new[] { 5, 10, 15 };
}
