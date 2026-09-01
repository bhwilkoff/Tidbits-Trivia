using System.Collections.Generic;
using System.Text;
using Tidbits.Core.Models;

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

    /// The teams' blank answer sheet — numbered lines per round, from the PLAN alone, so a
    /// host can print it before the night starts (macOS-DESIGN §A5.2, the Wi-Fi-dies
    /// contingency). Only round titles and counts are needed, which is why this one works at
    /// build time while [QuestionPackHtml] cannot.
    public static string AnswerSheetHtml(string eventName, IReadOnlyList<NightRound> rounds)
    {
        var body = new StringBuilder();
        for (int r = 0; r < rounds.Count; r++)
        {
            body.Append($"<h2>Round {r + 1}: {Esc(rounds[r].Title)}</h2><ol>");
            for (int q = 0; q < rounds[r].Count; q++) body.Append("<li><span class=\"rule\"></span></li>");
            body.Append("</ol>");
        }
        return Page(eventName + " — Answer sheet",
            "<h1>" + Esc(eventName) + "</h1>"
            + "<p class=\"team\">Team name: <span class=\"rule\"></span></p>" + body,
            ".rule{display:inline-block;border-bottom:1px solid #999;height:1em;min-width:220px;width:60%}"
            + "ol{margin:0 0 18px 0;padding-left:26px}li{margin:12px 0}"
            + "h2{font-size:15px;margin:18px 0 6px}.team{margin:0 0 22px}");
    }

    /// The host's copy — every question with its answer. Takes the questions the night is
    /// ACTUALLY serving rather than a fresh draw, so the paper and the room always agree.
    ///
    /// This used to be printable only from the cockpit, because a saved Windows event
    /// stored {kind, count} and nothing else — a pack printed from the builder would have
    /// handed the host a different set than the room got. An event that carries its own
    /// questions (LiveEvent.RoundQuestions) has no such gap, so the builder can print it
    /// BEFORE the night, which is the whole point of a Wi-Fi-dies fallback.
    public static string QuestionPackHtml(string eventName, IReadOnlyList<Question> questions)
    {
        var body = new StringBuilder();
        int round = -1;
        for (int i = 0; i < questions.Count; i++)
        {
            var q = questions[i];
            if (q.RoundIndex != round)
            {
                if (round >= 0) body.Append("</ol>");
                round = q.RoundIndex ?? 0;
                body.Append($"<h2>Round {round + 1}</h2><ol>");
            }
            body.Append("<li><div class=\"q\">" + Esc(q.Prompt) + "</div>"
                      + "<div class=\"a\">Answer: " + Esc(q.CorrectAnswer) + "</div></li>");
        }
        if (round >= 0) body.Append("</ol>");
        return Page(eventName + " — Question pack",
            "<h1>" + Esc(eventName) + "</h1>"
            + $"<p class=\"meta\">Host copy · {questions.Count} questions</p>" + body,
            "ol{margin:0 0 18px 0;padding-left:26px}li{margin:12px 0}.q{font-size:14px}"
            + ".a{font-size:13px;font-weight:700;opacity:.75;margin-top:2px}"
            + "h2{font-size:15px;margin:18px 0 6px}.meta{opacity:.6;font-size:12px;margin:0 0 18px}");
    }

    /// Shared print-page chrome — black on white, no app chrome, sized for paper.
    private static string Page(string title, string body, string extraCss) =>
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>" + Esc(title) + "</title>"
        + "<style>body{font-family:system-ui,sans-serif;margin:40px;color:#0A0A0A}"
        + "h1{color:#FF5C35;font-size:24px;margin:0 0 4px}" + extraCss
        + "@media print{body{margin:0}}</style></head><body>" + body + "</body></html>";

    private static string Esc(string s) => s
        .Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
}
