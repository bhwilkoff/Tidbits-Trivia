using System;

namespace Tidbits.Core.Networking;

/// Tick 33 — speak in the HOST's clock, not this device's.
///
/// Every countdown the room shares is an absolute epoch-ms deadline (`Pub.Deadline`,
/// `Pub.BreakUntil`), so each client evaluates it against its own clock. Measured
/// 2026-09-10 on the bench: this very box runs 101 SECONDS behind the Mac, and the same
/// 10-minute break read "10 minutes" on the web and "12 minutes" here. On a 30 s question
/// a skew like that is not a wobble — the timer is nonsense.
///
/// The host stamps `Pub.Now` when it publishes; a client keeps the offset that implies and
/// adds it to its own clock before comparing. Mirror of Swift's `LiveClock`.
public static class LiveClock
{
    /// How far this device's clock is BEHIND the host's, in ms (negative when ahead).
    /// A null `pubNow` is an older host that does not stamp — offset 0, the old behaviour.
    public static double OffsetMs(long? pubNow, DateTimeOffset? receivedAt = null) =>
        pubNow is { } n ? n - (receivedAt ?? DateTimeOffset.UtcNow).ToUnixTimeMilliseconds() : 0;

    /// Whole seconds left on a deadline, in the host's frame. Never negative; null when
    /// there is no deadline. Rounded UP, so a timer shows "1" for its final tick rather
    /// than sitting on "0" while the room can still answer.
    public static int? SecondsRemaining(long? deadlineMs, double offsetMs, DateTimeOffset? now = null)
    {
        if (deadlineMs is not { } d) return null;
        var hostNowMs = (now ?? DateTimeOffset.UtcNow).ToUnixTimeMilliseconds() + offsetMs;
        return Math.Max(0, (int)Math.Ceiling((d - hostNowMs) / 1000.0));
    }

    /// This device's clock, expressed in the host's frame.
    public static DateTimeOffset HostNow(double offsetMs, DateTimeOffset? now = null) =>
        (now ?? DateTimeOffset.Now).AddMilliseconds(offsetMs);
}
