using System;
using System.Collections.Generic;
using System.Linq;

namespace Tidbits.Core.Models;

/// A2.15 — how far a table MOVED since the last round's scoreboard. Mirror of Swift's
/// `LiveStandingsMove`.
///
/// The between-rounds scoreboard is the ritual moment of a pub quiz, and a bare list of
/// scores throws away the half people actually react to: not "we have 14" but "we were
/// fifth and now we're second".
public static class LiveStandingsMove
{
    public enum Kind { New, Same, Up, Down }

    public readonly record struct Move(Kind Kind, int Places)
    {
        public static readonly Move New = new(Kind.New, 0);
        public static readonly Move Same = new(Kind.Same, 0);
        public static Move Up(int n) => new(Kind.Up, n);
        public static Move Down(int n) => new(Kind.Down, n);
    }

    /// Movement per team NAME, from two rank-ordered name lists (index 0 = first).
    /// Names, not uids: a table may be several phones (G7) and a paper team has no uid.
    public static Dictionary<string, Move> Moves(IReadOnlyList<string> previous, IReadOnlyList<string> current)
    {
        var was = new Dictionary<string, int>(StringComparer.Ordinal);
        for (int i = 0; i < previous.Count; i++)
            if (!was.ContainsKey(previous[i])) was[previous[i]] = i;   // a duplicate name keeps its BEST rank

        var outp = new Dictionary<string, Move>(StringComparer.Ordinal);
        for (int now = 0; now < current.Count; now++)
        {
            var n = current[now];
            if (!was.TryGetValue(n, out var before)) { outp[n] = Move.New; continue; }
            // A SMALLER index is a better rank, so 4 -> 1 is up 3.
            var delta = before - now;
            outp[n] = delta == 0 ? Move.Same : delta > 0 ? Move.Up(delta) : Move.Down(-delta);
        }
        return outp;
    }

    /// The chip the big screen draws. Null on the FIRST scoreboard of the night —
    /// everyone would read "NEW", which is noise, not news.
    public static string? Label(Move? m) => m switch
    {
        null => null,
        { Kind: Kind.New } => "NEW",
        { Kind: Kind.Same } => "—",
        { Kind: Kind.Up } u => $"▲{u.Places}",
        { Kind: Kind.Down } d => $"▼{d.Places}",
        _ => null,
    };

    /// One line the host can read out: the biggest climb of the round, when there was
    /// one worth naming. A round where nobody moved says nothing.
    public static string? BiggestClimb(IReadOnlyDictionary<string, Move> moves)
    {
        var best = moves.Where(kv => kv.Value.Kind == Kind.Up && kv.Value.Places > 0)
                        .OrderByDescending(kv => kv.Value.Places)
                        .ThenBy(kv => kv.Key, StringComparer.Ordinal)
                        .Select(kv => (Name: kv.Key, N: kv.Value.Places))
                        .FirstOrDefault();
        return best.Name is null ? null : $"Biggest climb: {best.Name} up {best.N}";
    }
}
