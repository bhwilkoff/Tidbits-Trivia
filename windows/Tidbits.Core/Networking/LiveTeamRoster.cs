using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// G7 — several phones, one team. The C# mirror of Swift `LiveTeamRoster`.
///
/// A device used to BE a team, which is right for a table sharing one phone and
/// wrong for the table that is not: three friends each open the app, each becomes
/// a separate team, and the table's night is split three ways.
public sealed record LiveMember
{
    [JsonPropertyName("uid")] public required string Uid { get; init; }
    [JsonPropertyName("teamName")] public required string TeamName { get; init; }
    [JsonPropertyName("joinedAt")] public long JoinedAt { get; init; }   // epoch ms, SERVER stamped
}

public sealed record RosterTeam(string Key, string Name, IReadOnlyList<LiveMember> Members)
{
    public LiveMember? Leader => Members.Count > 0 ? Members[0] : null;
    public int Size => Members.Count;
}

public static class LiveTeamRoster
{
    /// Two people typing the same team name must land on the SAME team, so the key
    /// folds what a person varies without meaning to: surrounding space, case, and
    /// runs of whitespace.
    ///
    /// It deliberately does NOT fold punctuation or accents. "St. Elmo" and
    /// "St Elmo" are plausibly different tables, and merging is destructive in a
    /// way splitting is not — a host can merge two rows but cannot un-merge a
    /// night's scoring.
    public static string Key(string teamName) =>
        string.Join(" ", (teamName ?? "")
            .ToLowerInvariant()
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    /// Group members into teams, earliest joiner first.
    ///
    /// Ordered by JoinedAt then Uid. The Uid tiebreak is not decoration: two
    /// phones can be stamped the same millisecond, and without it the leader —
    /// and so whose answer counts — would differ by stack and by run.
    public static IReadOnlyList<RosterTeam> Teams(IEnumerable<LiveMember> members)
    {
        var byKey = new Dictionary<string, List<LiveMember>>();
        foreach (var m in members)
        {
            var k = Key(m.TeamName);
            if (k.Length == 0) continue;
            if (!byKey.TryGetValue(k, out var list)) byKey[k] = list = new List<LiveMember>();
            list.Add(m);
        }
        return byKey.Select(kv =>
                {
                    var ordered = kv.Value
                        .OrderBy(m => m.JoinedAt)
                        .ThenBy(m => m.Uid, StringComparer.Ordinal)
                        .ToList();
                    // The display name is the LEADER's spelling — a later joiner
                    // does not get to restyle the row the table already has.
                    return new RosterTeam(kv.Key, ordered[0].TeamName, ordered);
                })
            .OrderBy(t => t.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public static RosterTeam? TeamOf(string uid, IEnumerable<LiveMember> members) =>
        Teams(members).FirstOrDefault(t => t.Members.Any(m => m.Uid == uid));

    /// Whose answer counts for a team. The FIRST by server stamp stands and a
    /// teammate cannot replace it — any other rule lets the loudest phone at the
    /// table overwrite a teammate, or lets a team change its mind after watching
    /// the tally move. Same ordering the buzzer uses.
    public static string? AnsweringMember(RosterTeam team, IReadOnlyDictionary<string, long> answeredAt)
    {
        string? bestUid = null;
        long bestAt = long.MaxValue;
        foreach (var m in team.Members)
        {
            if (!answeredAt.TryGetValue(m.Uid, out var at)) continue;
            if (at < bestAt || (at == bestAt && string.CompareOrdinal(m.Uid, bestUid ?? "") < 0))
            {
                bestAt = at;
                bestUid = m.Uid;
            }
        }
        return bestUid;
    }

    /// Who leads after `gone` have left. A team whose leader closes their phone is
    /// not disbanded — a table does not stop playing because one person went to
    /// the bar.
    public static LiveMember? LeaderAfterDepartures(RosterTeam team, ISet<string> gone) =>
        team.Members.FirstOrDefault(m => !gone.Contains(m.Uid));
}
