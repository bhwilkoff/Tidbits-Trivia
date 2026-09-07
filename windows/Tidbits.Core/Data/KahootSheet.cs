using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.Core.Data;

/// Write a night as Kahoot's own `.xlsx` import template, so a host can hand a
/// Tidbits night to someone who runs Kahoot (QUIZ-FORMATS-RESEARCH §4). Their
/// importer accepts ONLY xlsx, so a CSV would be useless here; this builds a
/// minimal but valid OOXML workbook laid out exactly like the template they
/// publish. The Windows twin of the Mac `LiveKahootSheet`; both suites assert
/// the same cells.
public static class KahootSheet
{
    public const int QuestionCap = 95;
    public const int AnswerCap = 60;
    /// The only values their importer accepts; anything else silently becomes 20.
    public static readonly int[] AllowedTimes = { 5, 10, 20, 30, 60, 90, 120, 240 };

    public static readonly string[] Header =
    {
        "Question - max 95 characters",
        "Answer 1 - max 60 characters", "Answer 2 - max 60 characters",
        "Answer 3 - max 60 characters", "Answer 4 - max 60 characters",
        "Time limit (sec) - 5,10,20,30,60,90 or 120 secs",
        "Correct answer(s) - choose at least one",
    };

    public static readonly string[] Instructions =
    {
        "Quiz template",
        "Exported from Tidbits Trivia. Add or edit questions below, then upload this file to Kahoot.",
        "Questions have a limit of 95 characters and answers 60 characters. If several answers are correct, separate them with a comma.",
        "The header row below must stay exactly as it is — Kahoot's importer reads it.",
    };

    public sealed record Row(string Prompt, IReadOnlyList<string> Answers, int Seconds, IReadOnlyList<int> Correct);

    /// Which questions can travel, and what could not. Pure, so it is tested
    /// without writing a file.
    public static (List<Row> Rows, List<string> Notes) Rows(IReadOnlyList<Question> questions, int? seconds)
    {
        var rows = new List<Row>();
        var notes = new List<string>();
        for (int i = 0; i < questions.Count; i++)
        {
            var q = questions[i]; var n = i + 1;
            if (!LiveScoring.IsMcq(q)) { notes.Add($"Q{n}: a {KindName(q)} has no form in Kahoot's sheet — left out"); continue; }
            var answers = q.Options.Where(o => !string.IsNullOrWhiteSpace(o)).ToList();
            if (answers.Count < 2) { notes.Add($"Q{n}: fewer than two answer choices — left out"); continue; }
            if (answers.Count > 4) notes.Add($"Q{n}: Kahoot allows four answers; the last {answers.Count - 4} were left out");
            var kept = answers.Take(4).ToList();
            var correctText = q.CorrectIndex >= 0 && q.CorrectIndex < q.Options.Count ? q.Options[q.CorrectIndex] : null;
            var correctIdx = correctText is null ? -1 : kept.IndexOf(correctText);
            if (correctIdx < 0) { notes.Add($"Q{n}: the correct answer is not among the first four choices — left out"); continue; }
            if (q.Prompt.Length > QuestionCap)
                notes.Add($"Q{n}: the question was {q.Prompt.Length} characters and Kahoot allows {QuestionCap} — shortened");
            for (int j = 0; j < kept.Count; j++)
                if (kept[j].Length > AnswerCap)
                    notes.Add($"Q{n}: answer {j + 1} was {kept[j].Length} characters and Kahoot allows {AnswerCap} — shortened");
            if (q.ImageUrl is not null)
                notes.Add($"Q{n}: Kahoot's sheet carries no pictures — add it in their editor after uploading");
            rows.Add(new Row(Clip(q.Prompt, QuestionCap), kept.Select(a => Clip(a, AnswerCap)).ToList(),
                             NearestTime(seconds), new[] { correctIdx + 1 }));
        }
        return (rows, notes);
    }

    private static string KindName(Question q) =>
        q.Closest is not null ? "numeric question"
        : q.Ordering is not null ? "put-in-order question"
        : q.Matching is not null ? "match-up question"
        : q.Enumerate is not null ? "name-as-many question"
        : q.Accepted is not null ? "type-the-answer question"
        : "question";

    public static int NearestTime(int? seconds)
    {
        if (seconds is not > 0) return 20;
        return AllowedTimes.OrderBy(t => Math.Abs(t - seconds.Value)).First();
    }

    private static string Clip(string s, int cap)
    {
        var flat = s.Replace("\n", " ");
        return flat.Length <= cap ? flat : flat[..(cap - 1)] + "…";
    }

    // ---------------------------------------------------------------- workbook

    public static byte[] Xlsx(IReadOnlyList<Row> rows)
    {
        var sheet = new StringBuilder(@"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>");
        sheet.Append(@"<worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main""><sheetData>");
        for (int i = 0; i < Instructions.Length; i++)
            sheet.Append($"<row r=\"{i + 1}\">").Append(Cell("B", i + 1, Instructions[i])).Append("</row>");
        sheet.Append("<row r=\"8\">");
        for (int i = 0; i < Header.Length; i++) sheet.Append(Cell(Column(2 + i), 8, Header[i]));
        sheet.Append("</row>");
        for (int i = 0; i < rows.Count; i++)
        {
            var n = 9 + i; var r = rows[i];
            sheet.Append($"<row r=\"{n}\">").Append(Cell("A", n, i + 1)).Append(Cell("B", n, r.Prompt));
            for (int j = 0; j < 4; j++) sheet.Append(Cell(Column(3 + j), n, j < r.Answers.Count ? r.Answers[j] : ""));
            sheet.Append(Cell("G", n, r.Seconds));
            sheet.Append(Cell("H", n, string.Join(",", r.Correct)));
            sheet.Append("</row>");
        }
        sheet.Append("</sheetData></worksheet>");

        const string contentTypes = @"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><Types xmlns=""http://schemas.openxmlformats.org/package/2006/content-types""><Default Extension=""rels"" ContentType=""application/vnd.openxmlformats-package.relationships+xml""/><Default Extension=""xml"" ContentType=""application/xml""/><Override PartName=""/xl/workbook.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml""/><Override PartName=""/xl/worksheets/sheet1.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml""/></Types>";
        const string rels = @"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships""><Relationship Id=""rId1"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"" Target=""xl/workbook.xml""/></Relationships>";
        const string workbook = @"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><workbook xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"" xmlns:r=""http://schemas.openxmlformats.org/officeDocument/2006/relationships""><sheets><sheet name=""Sheet1"" sheetId=""1"" r:id=""rId1""/></sheets></workbook>";
        const string workbookRels = @"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships""><Relationship Id=""rId1"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"" Target=""worksheets/sheet1.xml""/></Relationships>";

        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
        {
            void Add(string name, string xml)
            {
                var e = zip.CreateEntry(name, CompressionLevel.Optimal);
                e.LastWriteTime = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
                using var s = e.Open();
                var bytes = Encoding.UTF8.GetBytes(xml);
                s.Write(bytes, 0, bytes.Length);
            }
            Add("[Content_Types].xml", contentTypes);
            Add("_rels/.rels", rels);
            Add("xl/workbook.xml", workbook);
            Add("xl/_rels/workbook.xml.rels", workbookRels);
            Add("xl/worksheets/sheet1.xml", sheet.ToString());
        }
        return ms.ToArray();
    }

    /// A..Z is all this sheet needs (it is eight columns wide).
    public static string Column(int index) => ((char)('A' + Math.Clamp(index, 1, 26) - 1)).ToString();

    private static string Cell(string col, int row, string text) =>
        text.Length == 0 ? "" : $"<c r=\"{col}{row}\" t=\"inlineStr\"><is><t xml:space=\"preserve\">{EscapeXml(text)}</t></is></c>";
    private static string Cell(string col, int row, int number) => $"<c r=\"{col}{row}\"><v>{number}</v></c>";

    public static string EscapeXml(string s)
    {
        var escaped = s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
        // A control character is not legal in XML at all and would make the
        // workbook unopenable rather than merely wrong.
        return new string(escaped.Where(c => c == '\t' || c == '\n' || c >= ' ').ToArray());
    }
}
