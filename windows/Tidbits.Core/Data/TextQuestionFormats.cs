using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// Text question formats: Moodle GIFT and Aiken (QUIZ-FORMATS-RESEARCH §1, §4).
/// The Windows twin of the Mac `LiveTextFormats`; the two suites assert the
/// same fixtures. Both are read through the one Import button — the text says
/// which it is — and GIFT is the archive form Tidbits writes back.
public static class TextQuestionFormats
{
    public enum Kind { Gift, Aiken, Csv }

    private static readonly Regex OptionLine = new(@"^[A-Z][.)]\s", RegexOptions.Compiled);
    private static readonly Regex GiftBlock = new(@"\{[^{}]*[=~#][^{}]*\}|\{\s*(T|F|TRUE|FALSE)\s*\}", RegexOptions.Compiled);

    public static Kind Detect(string text)
    {
        var lines = text.Split('\n').Select(l => l.Trim()).ToList();
        var answerLines = lines.Count(l => l.StartsWith("ANSWER:", StringComparison.OrdinalIgnoreCase));
        var optionLines = lines.Count(l => OptionLine.IsMatch(l));
        if (answerLines > 0 && optionLines >= 2 * answerLines) return Kind.Aiken;
        if (GiftBlock.IsMatch(text)) return Kind.Gift;
        return Kind.Csv;
    }

    // ---------------------------------------------------------------- Aiken

    public static List<Question> ParseAiken(string text)
    {
        var outList = new List<Question>();
        foreach (var block in Blocks(text))
        {
            var prompt = new List<string>(); var options = new List<string>(); string? answer = null;
            foreach (var raw in block)
            {
                var line = raw.Trim();
                if (line.StartsWith("ANSWER:", StringComparison.OrdinalIgnoreCase)) answer = line["ANSWER:".Length..].Trim().ToUpperInvariant();
                else if (OptionLine.IsMatch(line)) options.Add(line[2..].Trim());
                else if (options.Count == 0 && line.Length > 0) prompt.Add(line);
            }
            var p = string.Join(" ", prompt);
            if (p.Length == 0 || options.Count < 2 || string.IsNullOrEmpty(answer)) continue;
            var ci = "ABCDEFGHIJ".IndexOf(answer[0]);
            if (ci < 0 || ci >= options.Count) continue;
            outList.Add(Make(p, options, ci, "", "aiken"));
        }
        return outList;
    }

    // ---------------------------------------------------------------- GIFT

    public static List<Question> ParseGift(string text)
    {
        var outList = new List<Question>();
        foreach (var block in Blocks(text))
        {
            var joined = string.Join("\n", block.Where(l => !l.TrimStart().StartsWith("//")));
            var q = GiftQuestion(joined);
            if (q is not null) outList.Add(q);
        }
        return outList;
    }

    private static Question? GiftQuestion(string raw)
    {
        var s = raw.Trim();
        if (s.Length == 0) return null;
        string? title = null;
        if (s.StartsWith("::"))
        {
            var end = s.IndexOf("::", 2, StringComparison.Ordinal);
            if (end > 0) { title = s[2..end]; s = s[(end + 2)..]; }
        }
        s = Regex.Replace(s, @"^\s*\[(html|markdown|plain|moodle)\]", "");
        var open = UnescapedIndex(s, '{', 0);
        if (open < 0) return null;
        var close = UnescapedIndex(s, '}', open + 1);
        if (close < 0) return null;
        var before = Unescape(s[..open]).Trim();
        var after = Unescape(s[(close + 1)..]).Trim();
        var inner = s[(open + 1)..close];
        var explanation = "";
        var g = inner.IndexOf("####", StringComparison.Ordinal);
        if (g >= 0) { explanation = Unescape(inner[(g + 4)..]).Trim(); inner = inner[..g]; }
        inner = inner.Trim();
        var prompt = after.Length > 0 ? before + " ___ " + after : before;
        if (prompt.Length == 0) prompt = title ?? "";
        if (prompt.Length == 0) return null;
        var id = "gift-" + Guid.NewGuid().ToString("N")[..8];

        var tf = inner.ToUpperInvariant();
        if (tf is "T" or "TRUE" or "F" or "FALSE")
            return Make(prompt, new[] { "True", "False" }, tf.StartsWith('T') ? 0 : 1, explanation, "gift", id);

        if (inner.StartsWith('#'))
        {
            var body = inner[1..].Trim();
            var first = body.Split('=').Select(x => x.Trim()).FirstOrDefault(x => x.Length > 0) ?? body;
            var spec = first.Split('#')[0];
            double answer, tol;
            var range = spec.IndexOf("..", StringComparison.Ordinal);
            if (range >= 0)
            {
                var lo = double.TryParse(spec[..range].Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var l) ? l : 0;
                var hi = double.TryParse(spec[(range + 2)..].Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var h) ? h : lo;
                answer = (lo + hi) / 2; tol = (hi - lo) / 2;
            }
            else
            {
                var parts = spec.Split(':').Select(x => x.Trim()).ToArray();
                answer = double.TryParse(parts[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var a) ? a : 0;
                tol = parts.Length > 1 && double.TryParse(parts[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var t) ? t : 0;
            }
            var tolerance = Math.Max(tol, Math.Max(Math.Abs(answer) * 0.05, 1));
            var span = Math.Max(tolerance * 10, Math.Max(Math.Abs(answer) * 0.5, 10));
            var closest = new ClosestSpec
            {
                Answer = answer, Min = Math.Floor(answer - span), Max = Math.Ceiling(answer + span),
                Step = Math.Max(1, Math.Round(span / 50)), Tolerance = tolerance, Unit = "",
            };
            return new Question
            {
                Id = id, Prompt = prompt, Options = new[] { closest.FormattedAnswer }, CorrectIndex = 0, CategoryId = "mixed",
                Difficulty = 3, Explanation = explanation, TemplateId = "gift", Closest = closest,
            };
        }

        var answers = new List<(bool Correct, string Text, int Weight)>();
        var cur = new StringBuilder(); bool isCorrect = false, started = false;
        for (int i = 0; i < inner.Length; i++)
        {
            var ch = inner[i];
            if (ch == '\\' && i + 1 < inner.Length) { cur.Append(ch).Append(inner[i + 1]); i++; continue; }
            if (ch == '=' || ch == '~')
            {
                if (started) answers.Add((isCorrect, cur.ToString(), 100));
                cur.Clear(); isCorrect = ch == '='; started = true;
            }
            else if (started) cur.Append(ch);
        }
        if (started) answers.Add((isCorrect, cur.ToString(), 100));
        var cleaned = new List<(bool Correct, string Text, int Weight)>();
        foreach (var a in answers)
        {
            var t = a.Text.Trim(); var w = 100;
            var m = Regex.Match(t, @"^%(-?\d+)%");
            if (m.Success) { w = int.Parse(m.Groups[1].Value); t = t[m.Length..].Trim(); }
            var f = UnescapedIndex(t, '#', 0);
            if (f >= 0) t = t[..f].Trim();
            t = Unescape(t);
            if (t.Length > 0) cleaned.Add((a.Correct, t, w));
        }
        if (cleaned.Count == 0) return null;
        if (cleaned.Count >= 2 && cleaned.All(c => c.Text.Contains("->")))
        {
            var pairs = cleaned.Select(c => c.Text.Split("->").Select(x => x.Trim()).ToArray()).ToList();
            var keys = pairs.Select(p => p[0]).ToList();
            var values = pairs.Select(p => p.Length > 1 ? p[1] : "").ToList();
            return new Question
            {
                Id = id, Prompt = prompt, Options = keys, CorrectIndex = 0, CategoryId = "mixed", Difficulty = 3,
                Explanation = explanation, TemplateId = "gift", Matching = new MatchSpec { Keys = keys, Values = values },
            };
        }
        var corrects = cleaned.Where(c => c.Correct).ToList();
        if (cleaned.All(c => c.Correct) && corrects.Count > 0)
            return new Question
            {
                Id = id, Prompt = prompt, Options = new[] { corrects[0].Text }, CorrectIndex = 0, CategoryId = "mixed", Difficulty = 3,
                Explanation = explanation, TemplateId = "gift", Accepted = corrects.Select(c => c.Text).ToList(),
            };
        if (corrects.Count == 0) return null;
        var best = corrects.OrderByDescending(c => c.Weight).First();
        var options = cleaned.Select(c => c.Text).ToList();
        return Make(prompt, options, Math.Max(0, options.IndexOf(best.Text)), explanation, "gift", id);
    }

    // ---------------------------------------------------------------- GIFT export

    public static string ExportGift(IReadOnlyList<Question> questions)
    {
        var sb = new StringBuilder("// Tidbits Trivia — GIFT export\n\n");
        foreach (var q in questions)
        {
            var feedback = string.IsNullOrEmpty(q.Explanation) ? "" : "\n####" + Esc(q.Explanation);
            string body;
            if (q.Closest is { } c)
                body = "#" + c.Answer.ToString(System.Globalization.CultureInfo.InvariantCulture) + ":" + c.Tolerance.ToString(System.Globalization.CultureInfo.InvariantCulture);
            else if (q.Matching is { } m)
                body = string.Join(" ", m.Keys.Zip(m.Values, (k, v) => "=" + Esc(k) + " -> " + Esc(v)));
            else if (q.Accepted is { } acc)
                body = string.Join(" ", acc.Select(a => "=" + Esc(a)));
            else if (q.Ordering is { } order)
                body = "=" + Esc(string.Join(", ", order));
            else if (q.Options.Select(o => o.ToLowerInvariant()).SequenceEqual(new[] { "true", "false" }))
                body = q.CorrectIndex == 0 ? "T" : "F";
            else
                body = string.Join(" ", q.Options.Select((o, i) => (i == q.CorrectIndex ? "=" : "~") + Esc(o)));
            sb.Append("::").Append(Esc(q.Id)).Append(":: ").Append(Esc(q.Prompt)).Append(" {").Append(body).Append(feedback).Append("}\n\n");
        }
        return sb.ToString();
    }

    // ---------------------------------------------------------------- bits

    private static IEnumerable<List<string>> Blocks(string text)
    {
        var cur = new List<string>();
        foreach (var line in text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            if (line.Trim().Length == 0) { if (cur.Count > 0) { yield return cur; cur = new(); } }
            else cur.Add(line);
        }
        if (cur.Count > 0) yield return cur;
    }

    private static int UnescapedIndex(string s, char ch, int from)
    {
        for (int i = from; i < s.Length; i++)
        {
            if (s[i] == '\\') { i++; continue; }
            if (s[i] == ch) return i;
        }
        return -1;
    }

    private static string Unescape(string s)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i] == '\\' && i + 1 < s.Length) { sb.Append(s[i + 1]); i++; }
            else sb.Append(s[i]);
        }
        return sb.ToString().Replace("\\n", " ");
    }

    private static string Esc(string s)
    {
        var t = s;
        foreach (var c in new[] { "\\", "{", "}", "=", "~", "#", ":" }) t = t.Replace(c, "\\" + c);
        return t.Replace("\n", " ");
    }

    private static Question Make(string prompt, IReadOnlyList<string> options, int correctIndex, string explanation, string templateId, string? id = null) =>
        new()
        {
            Id = id ?? ("text-" + Guid.NewGuid().ToString("N")[..8]), Prompt = prompt, Options = options, CorrectIndex = correctIndex,
            CategoryId = "mixed", Difficulty = 3, Explanation = explanation, TemplateId = templateId,
        };
}
