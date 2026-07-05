using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// A bundled JSON question set for the enrichment-built modes (Picture ID,
/// This-or-That, Closest Call, Ordering, Matching, Type-the-answer, Odd-One-Out,
/// Enumeration) — same compact array shape as corpus.json. Port of
/// Core/Data/JSONQuestionSource.swift. One loader per resource (closest.json,
/// match.json, …).
public sealed class JsonQuestionSource
{
    private readonly List<Question> _all;

    public JsonQuestionSource(IEnumerable<Question> questions) => _all = questions.ToList();

    public static JsonQuestionSource Load(Stream json) => new(PositionalQuestionParser.Load(json));

    public bool IsAvailable => _all.Count > 0;
    public int Count => _all.Count;

    public List<Question> Questions(string categoryId, ISet<string> seen, int limit)
    {
        var pool = _all.Where(q => (categoryId == "mixed" || q.CategoryId == categoryId) && !seen.Contains(q.Id)).ToList();
        return QueryHelpers.Shuffle(pool).Take(limit).ToList();
    }

    /// Topic-matched pull (Create shape variety): questions whose prompt/title
    /// mention a token but whose answer doesn't give it away.
    public List<Question> SearchMatch(string topic, int limit)
    {
        var tokens = QueryHelpers.Tokenize(topic);
        if (tokens.Count == 0) return [];
        var hits = _all.Where(q =>
        {
            var ans = q.CorrectAnswer.ToLowerInvariant();
            if (tokens.Any(t => ans.Contains(t))) return false;
            var hay = (q.Prompt + " " + q.SourceTitle).ToLowerInvariant();
            return tokens.Any(t => hay.Contains(t));
        }).ToList();
        return QueryHelpers.Shuffle(hits).Take(limit).ToList();
    }
}
