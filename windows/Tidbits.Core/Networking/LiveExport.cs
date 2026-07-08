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

    /// A print-ready HTML standings sheet (opened in the default browser → print
    /// / save as PDF — the $0 printable fallback). Names are HTML-escaped.
    public static string StandingsHtml(IReadOnlyList<LiveHostNet.Joined> standings, string title)
    {
        var rows = new StringBuilder();
        for (int i = 0; i < standings.Count; i++)
            rows.Append($"<tr><td>{i + 1}</td><td>{Esc(standings[i].Name)}</td><td>{standings[i].Score}</td></tr>");
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>" + Esc(title) + "</title>"
            + "<style>body{font-family:system-ui,sans-serif;margin:40px;color:#0A0A0A}"
            + "h1{color:#FF5C35}table{border-collapse:collapse;width:100%;max-width:560px}"
            + "th,td{padding:8px 14px;border-bottom:1px solid #E0E0E0;text-align:left}"
            + "th{font-size:12px;text-transform:uppercase;opacity:.6}td:last-child{font-weight:800;text-align:right}"
            + "tr:first-child td{font-weight:800}</style></head><body>"
            + "<h1>" + Esc(title) + "</h1><table><tr><th>#</th><th>Team</th><th>Score</th></tr>"
            + rows + "</table></body></html>";
    }

    private static string Esc(string s) => s
        .Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
}
