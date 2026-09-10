using System.Collections.Generic;
using System;
using System.Linq;
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

    /// A3.11 / 3.68: the night read back, as a section of the printed results.
    public static string NightReportSection(LiveNightReport r)
    {
        var sb = new StringBuilder();
        sb.Append("<h2>How the night went</h2><p>")
          .Append(LiveNightReport.Percent(r.OverallAccuracy)).Append(" of answers right · ")
          .Append(LiveNightReport.Percent(r.Participation)).Append(" of tables answering · ")
          .Append(r.Questions.Count).Append(" questions</p>");
        if (r.Hardest is { } h)
            sb.Append("<p><b>Hardest</b> (").Append(LiveNightReport.Percent(h.Accuracy)).Append(" of ").Append(h.Answered).Append("): ")
              .Append(Esc(h.Prompt)).Append(" — ").Append(Esc(h.Answer)).Append("</p>");
        if (r.Easiest is { } e && e.Qid != r.Hardest?.Qid)
            sb.Append("<p><b>Easiest</b> (").Append(LiveNightReport.Percent(e.Accuracy)).Append(" of ").Append(e.Answered).Append("): ")
              .Append(Esc(e.Prompt)).Append(" — ").Append(Esc(e.Answer)).Append("</p>");
        sb.Append("<ul>");
        foreach (var rs in r.Rounds)
            sb.Append("<li>Round ").Append(rs.Round).Append(": ").Append(LiveNightReport.Percent(rs.Accuracy)).Append(" right across ").Append(rs.Questions).Append(rs.Questions == 1 ? " question" : " questions").Append("</li>");
        sb.Append("</ul>");
        return sb.ToString();
    }

    private static string Quote(string s) => $"\"{s.Replace("\"", "\"\"")}\"";

    /// A3.8 / 3.62: the answer sheet — round,question,prompt,answer,team,submitted,points,
    /// one row per team per revealed question, teams alphabetical. Mirrors Swift LiveAnswerLog.csv.
    public static string AnswersCsv(IReadOnlyList<LiveAnswerRecord> records)
    {
        static string Esc(string s) => s.Contains(',') || s.Contains('"') || s.Contains('\n') ? Quote(s) : s;
        var sb = new StringBuilder("round,question,prompt,answer,team,submitted,points\n");
        foreach (var r in records)
            foreach (var l in r.Lines.OrderBy(x => x.Team, StringComparer.OrdinalIgnoreCase))
                sb.Append(r.Round).Append(',').Append(r.Number).Append(',').Append(Esc(r.Prompt)).Append(',').Append(Esc(r.Answer))
                  .Append(',').Append(Esc(l.Team)).Append(',').Append(Esc(l.Submitted)).Append(',').Append(l.Points).Append('\n');
        return sb.ToString();
    }

    /// A print-ready HTML standings sheet (opened in the default browser → print
    /// / save as PDF — the $0 printable fallback). Names are HTML-escaped.
    /// Write a print-ready page and return the path.
    ///
    /// Extracted from the cockpit so the EDGE is testable. The Windows print path
    /// is: build HTML -> write to temp -> hand to the browser, which is where a
    /// Windows host prints or saves as PDF. The HTML was well covered; the WRITE
    /// was not covered anywhere, exactly as on the Mac before the panel seam.
    public static string WritePrintable(string html, string fileName, string? directory = null)
    {
        var dir = directory ?? System.IO.Path.GetTempPath();
        System.IO.Directory.CreateDirectory(dir);
        var path = System.IO.Path.Combine(dir, fileName);
        System.IO.File.WriteAllText(path, html);
        return path;
    }

    public static string StandingsHtml(IReadOnlyList<LiveHostNet.Joined> standings, string title, LiveNightReport? report = null)
    {
        var rows = new StringBuilder();
        for (int i = 0; i < standings.Count; i++)
            rows.Append($"<tr><td>{i + 1}</td><td>{Esc(standings[i].Name)}</td><td>{standings[i].Score}</td></tr>");
        var reportHtml = report is { IsEmpty: false } ? NightReportSection(report) : "";   // A3.11: the night, read back
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>" + Esc(title) + "</title>"
            + "<style>body{font-family:system-ui,sans-serif;margin:40px;color:#0A0A0A}"
            + "h1{color:#FF5C35}table{border-collapse:collapse;width:100%;max-width:560px}"
            + "th,td{padding:8px 14px;border-bottom:1px solid #E0E0E0;text-align:left}"
            + "th{font-size:12px;text-transform:uppercase;opacity:.6}td:last-child{font-weight:800;text-align:right}"
            + "tr:first-child td{font-weight:800}</style></head><body>"
            + "<h1>" + Esc(title) + "</h1><table><tr><th>#</th><th>Team</th><th>Score</th></tr>"
            + rows + "</table>" + reportHtml + "</body></html>";
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

/// One revealed question on the host's answer sheet (A3.8).
public sealed record LiveAnswerRecord(string Qid, int Round, int Number, string Prompt, string Answer, IReadOnlyList<LiveAnswerRecord.Line> Lines)
{
    public sealed record Line(string Uid, string Team, string Submitted, int Points);

    /// What a team submitted, as text, for any format.
    public static string Submitted(Question q, LiveRoom.Answer a)
    {
        if (q.Accepted is not null) return a.Text ?? "";
        if (q.Closest is { } c && a.Number is { } n)
        {
            var s = n == Math.Round(n) ? ((long)n).ToString() : n.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);
            return string.IsNullOrEmpty(c.Unit) ? s : $"{s} {c.Unit}";
        }
        if (a.Choice is { } ch && ch >= 0 && ch < q.Options.Count) return q.Options[ch];
        if (a.List is { Count: > 0 } list) return string.Join(" · ", list);
        if (a.Order is { } order) return string.Join(",", order);
        if (a.Pairs is { } pairs) return string.Join(",", pairs);
        return a.Text ?? "";
    }
}
