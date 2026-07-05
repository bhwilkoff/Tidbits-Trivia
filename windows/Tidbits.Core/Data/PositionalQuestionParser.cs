using System.Text.Json;
using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// Parses the compact positional-array question format shared across platforms
/// (assets/corpus.json + the enrichment sets closest/match/order/... json).
/// Direct port of JSONQuestionSource.parse — one parser for every question shape
/// (MCQ, enumeration, matching, ordering, type-answer, numeric/closest, picture).
public static class PositionalQuestionParser
{
    /// Load a `{"questions":[[...],[...]]}` document into questions.
    public static List<Question> Load(Stream json)
    {
        using var doc = JsonDocument.Parse(json);
        var list = new List<Question>();
        if (!doc.RootElement.TryGetProperty("questions", out var rows) || rows.ValueKind != JsonValueKind.Array)
            return list;
        foreach (var row in rows.EnumerateArray())
        {
            var q = Parse(row);
            if (q is not null) list.Add(q);
        }
        return list;
    }

    public static Question? Parse(JsonElement row)
    {
        if (row.ValueKind != JsonValueKind.Array) return null;
        var r = row.EnumerateArray().ToArray();
        if (r.Length < 6 || !IsString(r[0]) || !IsString(r[1])) return null;
        var id = r[0].GetString()!;
        var prompt = r[1].GetString()!;
        var template = id.Split(':').FirstOrDefault() ?? "json";

        // Enumeration: [id, prompt, groups([[String]]), cat, seconds, url]. Branch first
        // (only 6 columns; r[2] is an array-of-arrays).
        if (IsArrayOfArrays(r[2]))
        {
            var groups = r[2].EnumerateArray().Select(StrArr).Where(g => g.Length > 0).ToList();
            if (r.Length < 4 || !IsString(r[3]) || groups.Count == 0) return null;
            return new Question
            {
                Id = id, Prompt = prompt, Options = [], CorrectIndex = 0,
                CategoryId = r[3].GetString()!, Difficulty = 3,
                SourceUrl = r.Length > 5 ? StrOrNull(r[5]) : null,
                TemplateId = template,
                Enumerate = new EnumSpec { Groups = groups.Cast<IReadOnlyList<string>>().ToList() },
            };
        }

        if (r.Length < 8) return null;

        // r[2] is a string array → MCQ / Ordering / Matching.
        if (IsStringArray(r[2]))
        {
            var arr2 = StrArr(r[2]);
            if (IsNumber(r[3])) // MCQ (corpus / picture / thisorthat)
            {
                var correct = IntOf(r[3]) ?? -1;
                if (arr2.Length < 2 || correct < 0 || correct >= arr2.Length || !IsString(r[4])) return null;
                var image = r.Length >= 10 ? StrOrNull(r[9]) : null;
                return new Question
                {
                    Id = id, Prompt = prompt, Options = arr2, CorrectIndex = correct,
                    CategoryId = r[4].GetString()!, Difficulty = IntOf(r[5]) ?? 3,
                    Explanation = StrOr(r[6]), SourceTitle = StrOr(r[7]),
                    SourceUrl = StrOrNull(r[8]), TemplateId = template, ImageUrl = image,
                };
            }
            if (arr2.Length < 2 || !IsString(r[4])) return null;
            if (IsStringArray(r[3])) // Matching: r[3] is the values
            {
                return new Question
                {
                    Id = id, Prompt = prompt, Options = arr2, CorrectIndex = 0,
                    CategoryId = r[4].GetString()!, Difficulty = 3,
                    Explanation = StrOr(r[5]), TemplateId = template,
                    Matching = new MatchSpec { Keys = arr2, Values = StrArr(r[3]) },
                };
            }
            // Ordering: r[3] is an int array (years)
            return new Question
            {
                Id = id, Prompt = prompt, Options = arr2, CorrectIndex = 0,
                CategoryId = r[4].GetString()!, Difficulty = 3,
                Explanation = StrOr(r[5]), SourceTitle = StrOr(r[6]),
                SourceUrl = StrOrNull(r[7]), TemplateId = template, Ordering = arr2,
            };
        }

        // Type-the-answer: [id, prompt, answer(string), accepted(strings), cat, expl, title, url].
        if (IsString(r[2]) && IsStringArray(r[3]))
        {
            if (!IsString(r[4])) return null;
            return new Question
            {
                Id = id, Prompt = prompt, Options = [r[2].GetString()!], CorrectIndex = 0,
                CategoryId = r[4].GetString()!, Difficulty = 3,
                Explanation = StrOr(r[5]), SourceTitle = StrOr(r[6]),
                SourceUrl = StrOrNull(r[7]), TemplateId = template, Accepted = StrArr(r[3]),
            };
        }

        // Numeric (Closest Call): [id, prompt, answer, min, max, step, tol, unit, cat, expl, title, url].
        if (r.Length >= 12 && IsNumber(r[2]) && NumOf(r[3]) is { } mn && NumOf(r[4]) is { } mx
            && NumOf(r[5]) is { } step && NumOf(r[6]) is { } tol && IsString(r[7]) && IsString(r[8]))
        {
            return new Question
            {
                Id = id, Prompt = prompt, Options = [], CorrectIndex = 0,
                CategoryId = r[8].GetString()!, Difficulty = 3,
                Explanation = StrOr(r[9]), SourceTitle = StrOr(r[10]),
                SourceUrl = StrOrNull(r[11]), TemplateId = template,
                Closest = new ClosestSpec
                {
                    Answer = NumOf(r[2])!.Value, Min = mn, Max = mx, Step = step,
                    Tolerance = tol, Unit = r[7].GetString()!,
                },
            };
        }

        return null;
    }

    private static bool IsString(JsonElement e) => e.ValueKind == JsonValueKind.String;
    private static bool IsNumber(JsonElement e) => e.ValueKind == JsonValueKind.Number;
    private static bool IsStringArray(JsonElement e) =>
        e.ValueKind == JsonValueKind.Array && e.EnumerateArray().All(x => x.ValueKind == JsonValueKind.String);
    private static bool IsArrayOfArrays(JsonElement e) =>
        e.ValueKind == JsonValueKind.Array && e.EnumerateArray().FirstOrDefault().ValueKind == JsonValueKind.Array;
    private static string[] StrArr(JsonElement e) => e.EnumerateArray().Select(x => x.GetString() ?? "").ToArray();
    private static string StrOr(JsonElement e) => e.ValueKind == JsonValueKind.String ? e.GetString() ?? "" : "";
    private static string? StrOrNull(JsonElement e) => e.ValueKind == JsonValueKind.String ? e.GetString() : null;
    private static int? IntOf(JsonElement e) => e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out var i) ? i : null;
    private static double? NumOf(JsonElement e) => e.ValueKind == JsonValueKind.Number && e.TryGetDouble(out var d) ? d : null;
}
