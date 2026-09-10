using System;
using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Networking;

namespace Tidbits.Core.Models;

/// A2.14 — the joker. Before a round starts each table names ONE round of the night
/// as its joker, and every point it scores in that round counts double. Pure, and a
/// mirror of Swift's `LiveJoker`, because six stacks have to agree.
public static class LiveJoker
{
    /// The rounds a joker can still be played on: every round AFTER the one in
    /// progress (`current` 0-based; -1 before the night starts), minus the wager round.
    public static IReadOnlyList<LiveRoom.JokerRound> Playable(int current, IReadOnlyList<string> titles, int? wager = null)
    {
        var list = new List<LiveRoom.JokerRound>();
        for (int i = 0; i < titles.Count; i++)
        {
            if (i <= current || i == wager) continue;
            list.Add(new LiveRoom.JokerRound { Index = i, Title = string.IsNullOrEmpty(titles[i]) ? $"Round {i + 1}" : titles[i] });
        }
        return list;
    }

    /// Lock the picks for the round that is starting: the TEAMS (by name — G7) whose
    /// joker is on `round`. A pick for any other round names nothing here.
    public static HashSet<string> Played(int round, IReadOnlyDictionary<string, int> picks, Func<string, string?> teamOf)
    {
        var set = new HashSet<string>(StringComparer.Ordinal);
        foreach (var kv in picks)
            if (kv.Value == round && teamOf(kv.Key) is { Length: > 0 } name) set.Add(name);
        return set;
    }

    public static int Multiplier(string team, IReadOnlySet<string> played) => played.Contains(team) ? 2 : 1;

    /// The big-screen line on the first question of a round — null when nobody played one.
    public static string? Line(IEnumerable<string> played)
    {
        var names = played.OrderBy(n => n, StringComparer.Ordinal).ToList();
        if (names.Count == 0) return null;
        return (names.Count == 1 ? "Joker played: " : "Jokers played: ") + string.Join(", ", names);
    }
}
