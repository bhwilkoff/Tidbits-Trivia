using System;

namespace Tidbits.Core.Networking;

/// A8.11 — what the BIG SCREEN says about how far the room has got. The cockpit has
/// always known how many tables are in; the room did not, so only the host could tell
/// whether the stragglers were still typing. Mirror of Swift's `LiveProgress`.
public static class LiveProgress
{
    /// "3 of 8 answered", or null when nobody has joined — "0 of 0 answered" on a
    /// projector is noise, and a lobby is not a question in progress.
    ///
    /// Counts TEAMS, not devices (G7): a table of three phones is one line on the
    /// scoreboard and must be one tick here too.
    public static string? AnswersIn(int answered, int joined) =>
        joined > 0 ? $"{Math.Max(0, Math.Min(answered, joined))} of {joined} answered" : null;
}
