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

        // §6.1: a named header decides — and it need not be the FIRST row. Kahoot's
        // spreadsheet template carries instruction rows above its header, so the
        // header is looked for in the first dozen rows and everything above it is
        // ignored. Any spreadsheet in QUIZ-FORMATS-RESEARCH §1 is read by its names.
        var header = CsvHeader.Find(rows, out var at);
        if (header is not null) rows.RemoveRange(0, at + 1);

        foreach (var f in rows)
        {
            if (header is not null && f.Count < 2) continue;
            var q = FromRow(f, header);
            if (q is not null) result.Add(q);
        }
        return result;
    }

    /// A named header, read by NORMALIZED names so the spreadsheets of other tools
    /// map onto ours: "Question Text" (Crowdpurr, Blooket), "Question - max 95
    /// characters" and "Answer 1 - max 60 characters" (Kahoot), "Incorrect Answer 1"
    /// (Gimkit), "Answer Option 1", "Correct Answer(s)", "Question Media URL"…
    public sealed class CsvHeader
    {
        public required Dictionary<string, int> Columns { get; init; }
        public required int PromptColumn { get; init; }
        public required List<int> OptionColumns { get; init; }

        public static readonly string[] PromptNames = { "prompt", "questiontext", "question" };
        public static readonly string[] CorrectNames = { "correct", "correctanswer", "correctanswers", "answer", "correctoption", "correctanswerindex" };
        private static readonly System.Text.RegularExpressions.Regex OptionName =
            new("^((answer|option|answeroption|choice|incorrectanswer|wrong|distractor)([1-9]|[a-d])|[a-d])$");
        private static readonly System.Text.RegularExpressions.Regex KahootSuffix = new("max[0-9]+characters$");

        /// lowercase, alphanumerics only, minus Kahoot's "- max N characters" suffix.
        public static string Normalize(string raw)
        {
            var s = new string(raw.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());
            return KahootSuffix.Replace(s, "");
        }

        public static CsvHeader? Find(List<List<string>> rows, out int at)
        {
            at = -1;
            for (int i = 0; i < Math.Min(12, rows.Count); i++)
            {
                var cols = new Dictionary<string, int>(StringComparer.Ordinal);
                for (int c = 0; c < rows[i].Count; c++)
                {
                    var n = Normalize(rows[i][c]);
                    if (n.Length > 0 && !cols.ContainsKey(n)) cols[n] = c;
                }
                int prompt = -1;
                foreach (var pn in PromptNames) if (cols.TryGetValue(pn, out var pc)) { prompt = pc; break; }
                if (prompt < 0) continue;
                var options = cols.Where(kv => OptionName.IsMatch(kv.Key)).Select(kv => kv.Value).OrderBy(v => v).ToList();
                // "Correct answer(s) - choose at least one" (Kahoot) normalizes to a longer
                // name; a column that STARTS with "correctanswer" is the answer column.
                if (!CorrectNames.Any(cols.ContainsKey))
                {
                    var longName = cols.Keys.FirstOrDefault(k => k.StartsWith("correctanswer", StringComparison.Ordinal));
                    if (longName is not null) cols["correctanswers"] = cols[longName];
                }
                var hasCorrect = CorrectNames.Any(cols.ContainsKey);
                // A header names the prompt AND either the answer or at least two choices;
                // a data row whose first cell happens to say "question" does neither.
                if (!hasCorrect && options.Count < 2) continue;
                at = i;
                return new CsvHeader { Columns = cols, PromptColumn = prompt, OptionColumns = options };
            }
            return null;
        }

        public string? Value(List<string> f, params string[] names)
        {
            foreach (var n in names)
                if (Columns.TryGetValue(n, out var i) && i < f.Count && f[i].Trim().Length > 0)
                    return f[i].Trim();
            return null;
        }

        public List<string> Options(List<string> f) =>
            OptionColumns.Where(c => c < f.Count).Select(c => f[c].Trim()).Where(v => v.Length > 0).ToList();
    }

    /// The answer cell of another tool's sheet: text, a 1-based index, a letter,
    /// Kahoot's "1,3" (multiple correct → the first), Crowdpurr's "a@@@b".
    private static List<string> CorrectAnswers(string raw, List<string> options)
    {
        var commaPieces = raw.Split(',').Select(p => p.Trim()).ToList();
        if (commaPieces.Count > 1 && commaPieces.All(p => int.TryParse(p, out _)))
            return commaPieces.Select(int.Parse).Where(i => i >= 1 && i <= options.Count).Select(i => options[i - 1]).ToList();
        var parts = raw.Split("@@@").SelectMany(p => p.Split(';')).Select(p => p.Trim()).Where(p => p.Length > 0).ToList();
        var outList = new List<string>();
        foreach (var p in parts)
        {
            if (int.TryParse(p, out var idx) && idx >= 1 && idx <= options.Count) { outList.Add(options[idx - 1]); continue; }
            if (p.Length == 1 && "abcd".Contains(char.ToLowerInvariant(p[0])))
            {
                var li = "abcd".IndexOf(char.ToLowerInvariant(p[0]));
                if (li < options.Count) { outList.Add(options[li]); continue; }
            }
            outList.Add(p);
        }
        return outList;
    }

    private static Question? FromRow(List<string> f, CsvHeader? header)
    {
        List<string> options;
        string correct;
        var category = "mixed";
        var difficulty = 3;
        var explanation = "";
        string? imageUrl = null;
        List<string>? accepted = null;
        List<string>? ordering = null;
        string prompt;

        if (header is not null)
        {
            prompt = header.PromptColumn < f.Count ? f[header.PromptColumn].Trim() : "";
            if (prompt.Length == 0) return null;
            var opts = header.Options(f);
            var rawAnswer = header.Value(f, CsvHeader.CorrectNames) ?? "";
            var answers = CorrectAnswers(rawAnswer, opts);
            category = (header.Value(f, "category") ?? "mixed").ToLowerInvariant();
            if (int.TryParse(header.Value(f, "difficulty") ?? "", out var d)) difficulty = d;
            explanation = header.Value(f, "explanation", "reveal", "note", "questionnote", "feedback") ?? "";
            var m = header.Value(f, "questionmediaurl", "mediaurl", "media", "imageurl", "image", "picture", "pictureurl");
            if (m is not null && m.StartsWith("http", StringComparison.OrdinalIgnoreCase)) imageUrl = m;

            // The question TYPE, where a sheet names one: Crowdpurr's type code, Quizizz's
            // "Fill-in-the-blank", Blooket's typing column. Polls have no right answer
            // and are dropped, never imported as a question nobody can get right.
            var type = (header.Value(f, "questiontypecode", "questiontype", "type") ?? "").ToLowerInvariant();
            var typing = header.Value(f, "typing", "typinganswer", "typeanswer") is not null;
            if (type.Contains("poll") || type.Contains("survey") || type.Contains("yesno") || type.Contains("likedislike")
                || type.Contains("wordcloud") || type.Contains("openended") || type.Contains("open-ended")) return null;
            if (type.Contains("reorder") || type.Contains("order"))
            {
                if (opts.Count < 3) return null;
                ordering = opts; options = opts; correct = opts[0];
            }
            else if (typing || type.Contains("text") || type.Contains("fill") || type.Contains("short") || type.Contains("numerical") || type.Contains("number"))
            {
                var acc = answers.Count == 0 ? opts : answers;
                if (acc.Count == 0) return null;
                accepted = acc; options = new List<string> { acc[0] }; correct = acc[0];
            }
            else
            {
                if (answers.Count == 0) return null;
                correct = answers[0];
                options = opts.Contains(correct) ? opts : new[] { correct }.Concat(opts).Where(o => o.Length > 0).ToList();
            }
        }
        else
        {
            if (f.Count < 5) return null;
            prompt = f[0].Trim();
            if (prompt.Length == 0) return null;
            // No header. Field 5 tells the two shipped shapes apart: an integer 1-4
            // there means the Windows order, whatever its value: a macOS category
            // would be a word. (The earlier "any integer" reading also took a macOS
            // difficulty column for an index, producing an option "9" and a
            // category called 9. The existing Drops_malformed_rows test caught
            // the option; nothing caught the category.)
            var fifth = f.Count > 5 ? f[5].Trim() : "";
            if (int.TryParse(fifth, out var idx))
            {
                // An integer there is the Windows order; one outside 1-4 names no option.
                if (idx < 1 || idx > 4) return null;
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
        if (accepted is null && ordering is null)
        {
            while (options.Count < 4) options.Add("—");
            options = options.Take(4).ToList();
        }
        var ci = options.IndexOf(correct);
        if (ci < 0) return null;

        return new Question
        {
            Id = "csv-" + Guid.NewGuid().ToString("N")[..8],
            Prompt = prompt, Options = options, CorrectIndex = ci,
            CategoryId = category, Difficulty = Math.Clamp(difficulty, 1, 5),
            Explanation = explanation,
            ImageUrl = imageUrl, Accepted = accepted, Ordering = ordering,
        };
    }

    /// Write a question bank back out as CSV — LIVE-EVENT-FILE §6.1.
    ///
    /// A host revises their bank in a spreadsheet between weeks; the event file is
    /// Tidbits-to-Tidbits and no use for that. Import used to be a one-way door on
    /// both platforms.
    ///
    /// Always emits the NAMED HEADER, with the same column names the Swift
    /// exporter writes, so a bank exported on either machine re-imports on the
    /// other. The Swift suite asserts these names too; if they drift, a Mac export
    /// stops importing here and nothing else would notice.
    public static string Export(IReadOnlyList<Question> questions)
    {
        var sb = new StringBuilder();
        sb.Append("prompt,correct,optionA,optionB,optionC,optionD,category,difficulty,explanation,imageURL\n");
        foreach (var q in questions)
        {
            var opts = q.Options.ToList();
            while (opts.Count < 4) opts.Add("");
            var fields = new[]
            {
                q.Prompt, q.CorrectAnswer, opts[0], opts[1], opts[2], opts[3],
                q.CategoryId, q.Difficulty.ToString(), q.Explanation, q.ImageUrl ?? "",
            };
            sb.Append(string.Join(",", fields.Select(EscapeField))).Append('\n');
        }
        return sb.ToString();
    }

    /// Quote a field that would otherwise break the row, doubling any inner quote
    /// — the convention SplitCsvLine reads back and every spreadsheet emits.
    private static string EscapeField(string s)
    {
        if (s is null) return "";
        if (!s.Contains(',') && !s.Contains('"') && !s.Contains('\n') && !s.Contains('\r')) return s;
        return "\"" + s.Replace("\"", "\"\"") + "\"";
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
