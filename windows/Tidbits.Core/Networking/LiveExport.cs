using System.Collections.Generic;
using System.Text;

namespace Tidbits.Core.Networking;

/// Export helpers for a live night (Wave C). Pure so the CSV can be unit-tested.
public static class LiveExport
{
    /// Unified standings as CSV: Rank,Team,Score — ranked as given (host passes the
    /// already-sorted standings). Fields are quoted + double-quote-escaped so a team
    /// name with a comma or quote can't break the columns.
    public static string StandingsCsv(IReadOnlyList<LiveHostNet.Joined> standings)
    {
        var sb = new StringBuilder();
        sb.Append("Rank,Team,Score\n");
        for (int i = 0; i < standings.Count; i++)
            sb.Append(i + 1).Append(',').Append(Quote(standings[i].Name)).Append(',').Append(standings[i].Score).Append('\n');
        return sb.ToString();
    }

    private static string Quote(string s) => $"\"{s.Replace("\"", "\"\"")}\"";
}
