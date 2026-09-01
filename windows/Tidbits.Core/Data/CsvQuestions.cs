using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// Parse hand-authored MCQ questions from a CSV (Wave A hand-fill, 3.12).
/// Columns: prompt, optionA, optionB, optionC, optionD, correct (1–4), explanation.
/// A leading "prompt,…" header row is skipped; malformed rows are dropped.
public static class CsvQuestions
{
    /// Parse a host's CSV question bank — docs/LIVE-EVENT-FILE.md §6.
    ///
    /// Both shipped column orders are understood, and a NAMED HEADER beats both.
    /// The two clients had diverged silently: Windows wrote
    /// `prompt, optionA..D, correct(1-4), [explanation]` while macOS wrote
    /// `prompt, correct, wrong1..3, [category], [difficulty], [explanation]`, and
    /// neither knew about the other. A macOS file imported NOTHING here, because
    /// field 5 would not parse as 1-4; a Windows file on the Mac imported with the
    /// FIRST option marked correct, silently marking a correct player wrong.
    public static List<Question> Parse(string csv)
    {
        var result = new List<Question>();
        if (string.IsNullOrWhiteSpace(csv)) return result;

        var rows = SplitLines(csv).Select(SplitCsvLine).ToList();
        if (rows.Count == 0) return result;

        Dictionary<string, int>? header = null;
        if (IsHeaderRow(rows[0]))
        {
            header = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < rows[0].Count; i++) header[rows[0][i].Trim()] = i;
            rows.RemoveAt(0);
        }

        foreach (var f in rows)
        {
            var q = FromRow(f, header);
            if (q is not null) result.Add(q);
        }
        return result;
    }

    private static bool IsHeaderRow(List<string> f) =>
        f.Count > 0 && (f[0].Trim().Equals("prompt", StringComparison.OrdinalIgnoreCase)
                     || f[0].Trim().Equals("question", StringComparison.OrdinalIgnoreCase));

    private static string? Named(List<string> f, Dictionary<string, int>? header, params string[] names)
    {
        if (header is null) return null;
        foreach (var n in names)
            if (header.TryGetValue(n, out var i) && i < f.Count && f[i].Trim().Length > 0)
                return f[i].Trim();
        return null;
    }

    private static Question? FromRow(List<string> f, Dictionary<string, int>? header)
    {
        if (f.Count < 5) return null;
        var prompt = f[0].Trim();
        if (prompt.Length == 0) return null;

        List<string> options;
        string correct;
        var category = "mixed";
        var difficulty = 3;
        var explanation = "";

        if (header is not null)
        {
            options = new[] { "optionA", "optionB", "optionC", "optionD",
                              "option1", "option2", "option3", "option4",
                              "wrong1", "wrong2", "wrong3", "a", "b", "c", "d" }
                .Select(n => Named(f, header, n)).Where(v => v is not null).Select(v => v!).ToList();
            var answer = Named(f, header, "correct", "answer", "correctanswer") ?? "";
            // §6.2 — `correct` may be the answer TEXT or a 1-based INDEX.
            if (int.TryParse(answer, out var idx) && idx >= 1 && idx <= options.Count)
                correct = options[idx - 1];
            else
            {
                correct = answer;
                if (correct.Length > 0 && !options.Contains(correct)) options.Insert(0, correct);
            }
            category = (Named(f, header, "category") ?? "mixed").ToLowerInvariant();
            if (int.TryParse(Named(f, header, "difficulty") ?? "", out var d)) difficulty = d;
            explanation = Named(f, header, "explanation", "reveal", "note") ?? "";
        }
        else
        {
            // §6.3 — field 5 tells the two shipped orders apart. A bare INTEGER
            // there means the Windows order, whatever its value: a macOS category
            // is never a number, so "9" is a malformed Windows row rather than a
            // category called 9. The existing Drops_malformed_rows test caught
            // exactly that regression when this branch keyed on 1-4 alone.
            var fifth = f.Count > 5 ? f[5].Trim() : "";
            if (int.TryParse(fifth, out var idx))
            {
                if (idx < 1 || idx > 4) return null;   // out-of-range answer index
                options = new List<string> { f[1].Trim(), f[2].Trim(), f[3].Trim(), f[4].Trim() };
                correct = options[idx - 1];
                explanation = f.Count > 6 ? f[6].Trim() : "";
            }
            else
            {
                options = new List<string> { f[1].Trim(), f[2].Trim(), f[3].Trim(), f[4].Trim() };
                correct = f[1].Trim();
                if (f.Count > 5 && f[5].Trim().Length > 0) category = f[5].Trim().ToLowerInvariant();
                if (f.Count > 6 && int.TryParse(f[6].Trim(), out var d)) difficulty = d;
                explanation = f.Count > 7 ? f[7].Trim() : "";
            }
        }

        options = options.Where(o => o.Length > 0).Distinct().ToList();
        // §6.4 — an answer no option matches is a question nobody can get right.
        if (correct.Length == 0 || !options.Contains(correct)) return null;
        while (options.Count < 4) options.Add("—");
        options = options.Take(4).ToList();
        var ci = options.IndexOf(correct);
        if (ci < 0) return null;

        return new Question
        {
            Id = "csv-" + Guid.NewGuid().ToString("N")[..8],
            Prompt = prompt, Options = options, CorrectIndex = ci,
            CategoryId = category, Difficulty = Math.Clamp(difficulty, 1, 5),
            Explanation = explanation,
        };
    }

    private static IEnumerable<string> SplitLines(string csv)
    {
        foreach (var line in csv.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
            if (line.Trim().Length > 0) yield return line;
    }

    /// One CSV record → fields, honoring double-quoted fields (with "" escapes).
    private static List<string> SplitCsvLine(string line)
    {
        var fields = new List<string>();
        var sb = new StringBuilder();
        bool quoted = false;
        for (int i = 0; i < line.Length; i++)
        {
            var c = line[i];
            if (quoted)
            {
                if (c == '"')
                {
                    if (i + 1 < line.Length && line[i + 1] == '"') { sb.Append('"'); i++; }
                    else quoted = false;
                }
                else sb.Append(c);
            }
            else if (c == '"') quoted = true;
            else if (c == ',') { fields.Add(sb.ToString()); sb.Clear(); }
            else sb.Append(c);
        }
        fields.Add(sb.ToString());
        return fields;
    }
}
