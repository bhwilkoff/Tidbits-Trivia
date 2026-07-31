namespace Tidbits.Core.Store;

/// <summary>
/// How a finished board is announced.
///
/// Every scoreboard used to sort by score and treat element 0 as "the winner".
/// On a tie that reports an arbitrary sort order as a victory — and ties are not
/// an edge case: Pass &amp; Play deals ONE shared question set, so two players who
/// answer identically genuinely finish level.
///
/// Mirrors Swift <c>Core/Models/StandingsOutcome.swift</c> and the JS/Kotlin
/// copies; kept in Core (not the view) so the rule is a pure, testable function.
/// </summary>
public static class StandingsOutcome
{
    /// <summary>Every name sharing the top score; empty when there are no entries.</summary>
    public static IReadOnlyList<string> Winners(IReadOnlyList<(string Name, int Score)> entries)
    {
        if (entries.Count == 0) return Array.Empty<string>();
        int top = entries.Max(e => e.Score);
        return entries.Where(e => e.Score == top).Select(e => e.Name).ToList();
    }

    /// <summary>True when <paramref name="score"/> ties the leader — highlight EVERY leading row.</summary>
    public static bool IsTop(int score, IReadOnlyList<(string Name, int Score)> entries)
        => entries.Count != 0 && score == entries.Max(e => e.Score);

    /// <summary>The announcement. <paramref name="empty"/> is the no-players copy.</summary>
    public static string Headline(IReadOnlyList<(string Name, int Score)> entries, string empty)
    {
        var won = Winners(entries);
        if (won.Count == 0) return empty;
        if (won.Count == 1) return $"{won[0]} wins!";
        if (won.Count == entries.Count) return "It's a tie!";
        return $"Tie — {string.Join(" & ", won)}";
    }
}
