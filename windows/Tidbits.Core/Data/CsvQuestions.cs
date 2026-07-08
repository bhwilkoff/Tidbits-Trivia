using System;
using System.Collections.Generic;
using System.Text;
using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// Parse hand-authored MCQ questions from a CSV (Wave A hand-fill, 3.12).
/// Columns: prompt, optionA, optionB, optionC, optionD, correct (1–4), explanation.
/// A leading "prompt,…" header row is skipped; malformed rows are dropped.
public static class CsvQuestions
{
    public static List<Question> Parse(string csv)
    {
        var result = new List<Question>();
        if (string.IsNullOrWhiteSpace(csv)) return result;

        foreach (var raw in SplitLines(csv))
        {
            var f = SplitCsvLine(raw);
            if (f.Count < 6) continue;
            if (f[0].Trim().Equals("prompt", StringComparison.OrdinalIgnoreCase)) continue; // header

            var prompt = f[0].Trim();
            var options = new[] { f[1].Trim(), f[2].Trim(), f[3].Trim(), f[4].Trim() };
            if (prompt.Length == 0 || Array.Exists(options, o => o.Length == 0)) continue;
            if (!int.TryParse(f[5].Trim(), out var correct) || correct < 1 || correct > 4) continue;
            var explanation = f.Count >= 7 ? f[6].Trim() : "";

            result.Add(new Question
            {
                Id = "csv-" + Guid.NewGuid().ToString("N")[..8],
                Prompt = prompt, Options = options, CorrectIndex = correct - 1,
                CategoryId = "mixed", Difficulty = 3, Explanation = explanation,
            });
        }
        return result;
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
