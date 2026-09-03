using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// G6 — the host's phone remote, so the emcee can walk the room instead of
/// standing over the laptop. The C# mirror of Swift `LiveRemote`.
///
/// Every other Live path runs host -> players. This one runs the other way, which
/// inverts the trust: a phone is asking the show to advance. Three rules make
/// that safe, and each is a way the naive version breaks.
public sealed record RemoteCommand
{
    [JsonPropertyName("id")] public int Id { get; init; }          // monotonic within a room
    [JsonPropertyName("verb")] public string Verb { get; init; } = "";
    [JsonPropertyName("pin")] public string Pin { get; init; } = "";
}

public static class LiveRemote
{
    /// What a host can do while walking the room. Deliberately small: this is a
    /// clicker, not a second cockpit. Anything that EDITS the night — scores,
    /// teams, the question list — stays on the laptop where it can be read
    /// properly before it is changed.
    public static readonly IReadOnlySet<string> Verbs =
        new HashSet<string> { "reveal", "next", "skip", "scores", "board" };

    /// A 6-digit pairing PIN, shown on the host's screen and typed into the phone
    /// once. Six digits because it is read across a room by someone holding a
    /// drink — and because the thing it guards, the room code, is already public.
    public static string MakePin() => Random.Shared.Next(0, 1_000_000).ToString("D6");

    /// Should the host run this command?
    ///
    /// False for a wrong PIN, an unknown verb, or an id already run — the three
    /// ways a command arrives that must NOT move the show:
    ///   - **The room code is not authorisation.** It is printed on the projector,
    ///     so every player has it; without a separate PIN any table could reveal
    ///     the answer.
    ///   - **A replay must be a no-op.** A retried write or a reconnect can deliver
    ///     the same command twice, and "next" applied twice skips a question the
    ///     room never saw. Hence a monotonic id rather than a timestamp.
    ///   - **The remote never writes `pub` itself.** Two writers to the show state
    ///     is how a room sees question 4 while the host reads question 5.
    public static bool Accepted(RemoteCommand cmd, string pin, int lastExecutedId)
    {
        if (string.IsNullOrEmpty(pin) || cmd.Pin != pin) return false;
        if (!Verbs.Contains(cmd.Verb)) return false;
        return cmd.Id > lastExecutedId;
    }

    /// The id a remote should send next. A phone that reconnects has lost its own
    /// counter, so it resumes from what the host has already run rather than
    /// restarting at 1 — which would be refused forever.
    public static int NextId(int lastExecutedId) => lastExecutedId + 1;
}
