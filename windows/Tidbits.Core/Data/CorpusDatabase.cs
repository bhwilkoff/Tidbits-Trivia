using Tidbits.Core.Engine;
using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// Read-only reader over the shared corpus (assets/corpus.json — the same 20k+
/// quality-gated questions as the Apple SQLite / Android Room / web IndexedDB:
/// one corpus, four readers). Loaded in-memory; query semantics port
/// Core/Data/CorpusDatabase.swift.
public sealed class CorpusDatabase
{
    private readonly List<Question> _all;

    public CorpusDatabase(IEnumerable<Question> questions) => _all = questions.ToList();

    public static CorpusDatabase Load(Stream corpusJson) => new(PositionalQuestionParser.Load(corpusJson));

    public bool IsAvailable => _all.Count > 0;
    public int Count => _all.Count;

    /// Up to `limit` random questions in a category, excluding seen ids. "mixed" = all.
    public List<Question> Questions(string categoryId, ISet<string> seen, int limit)
    {
        var pool = _all.Where(q => (categoryId == "mixed" || q.CategoryId == categoryId) && !seen.Contains(q.Id)).ToList();
        return QueryHelpers.Shuffle(pool).Take(limit).ToList();
    }

    /// All ids for a category in a stable order. The daily uses this + DailyPick,
    /// which is order-independent, so only the id SET matters (identical across
    /// platforms because the corpus is identical). "mixed"/"" = the whole corpus.
    public List<string> OrderedIds(string categoryId)
    {
        var whole = categoryId is "mixed" or "";
        return _all.Where(q => whole || q.CategoryId == categoryId)
                   .Select(q => q.Id)
                   .OrderBy(x => x, Utf8Ordinal.Instance)
                   .ToList();
    }

    /// Fetch specific questions by id, returned in the SAME order as `ids`.
    public List<Question> Questions(IReadOnlyList<string> ids)
    {
        if (ids.Count == 0) return [];
        var want = new HashSet<string>(ids);
        var byId = new Dictionary<string, Question>();
        foreach (var q in _all)
            if (want.Contains(q.Id)) byId[q.Id] = q;
        return ids.Select(id => byId.GetValueOrDefault(id)).Where(q => q is not null).Select(q => q!).ToList();
    }

    /// Topic search for Create: vetted corpus questions whose prompt/title match the
    /// topic's words, ranked by hits (title weighted), with the answer-giveaway,
    /// continent-template, and trivially-easy filters — then diversified.
    public List<Question> Search(string topic, int limit)
    {
        var tokens = QueryHelpers.Tokenize(topic);
        if (tokens.Count == 0) return [];

        // WHERE (prompt LIKE %t% OR title LIKE %t%) for any token, LIMIT 400 (pre-filter).
        var matched = new List<Question>();
        foreach (var q in _all)
        {
            var prompt = q.Prompt.ToLowerInvariant();
            var title = q.SourceTitle.ToLowerInvariant();
            var explanationPre = q.Explanation.ToLowerInvariant();
            var tagsPre = q.Tags.Select(tg => tg.ToLowerInvariant()).ToList();
            if (tokens.Any(t => prompt.Contains(t) || title.Contains(t) || explanationPre.Contains(t) || tagsPre.Any(tg => tg.Contains(t))))
            {
                matched.Add(q);
                // The cap applies BEFORE ranking, so it must contain the genuine
                // matches. At 400, "van gogh" lost all 20 real rows to substring
                // noise. Mirrors the Swift fix.
                if (matched.Count >= 4000) break;
            }
        }

        var scored = new List<(Question q, int score, int matchedTokens)>();
        foreach (var q in matched)
        {
            var answer = q.CorrectAnswer.ToLowerInvariant();
            if (tokens.Any(t => answer.Contains(t))) continue;      // answer would give it away
            if (q.Id.StartsWith("src:continent:")) continue;        // repetitive template
            if (q.Difficulty <= 1) continue;                        // trivially easy
            var title = q.SourceTitle.ToLowerInvariant();
            var prompt = q.Prompt.ToLowerInvariant();
            var explanation = q.Explanation.ToLowerInvariant();
            var tags = q.Tags.Select(tg => tg.ToLowerInvariant()).ToList();
            var score = tokens.Sum(t => (tags.Any(tg => tg.Contains(t)) ? 3 : 0) + (title.Contains(t) ? 2 : 0) + (prompt.Contains(t) ? 1 : 0) + (explanation.Contains(t) ? 1 : 0));
            // How many of the typed words this row matched AT ALL. Scoring alone
            // is not enough: Diversify round-robins by CATEGORY afterwards, so a
            // one-word coincidence gets PROMOTED to fill a lane. Measured on the
            // shipping corpus, "Marie Curie" has 15 real two-word matches (all
            // science) against 211 one-word hits across 7 categories, 189 of
            // which never mention Curie.
            var matchedTokens = tokens.Count(t => tags.Any(tg => tg.Contains(t)) || title.Contains(t) || prompt.Contains(t) || explanation.Contains(t));
            scored.Add((q, score, matchedTokens));
        }

        // Keep only rows matching the MOST typed words, then rank within that
        // tier. Single-word topics are unaffected (every row ties at 1).
        var bestMatched = scored.Count == 0 ? 0 : scored.Max(s => s.matchedTokens);
        var ranked = scored.Where(s => s.matchedTokens == bestMatched)
                           .OrderByDescending(s => s.score).Select(s => s.q).ToList();
        return Diversify(ranked, limit);
    }

    /// Round-robin a ranked list across categories, capping any one domain (the
    /// anti-monopoly rule for Create).
    public static List<Question> Diversify(List<Question> ranked, int limit)
    {
        var perCat = Math.Max(2, (int)Math.Ceiling(limit / 3.0));
        var lanes = new Dictionary<string, Queue<Question>>();
        var order = new List<string>();
        foreach (var q in ranked)
        {
            if (!lanes.TryGetValue(q.CategoryId, out var lane))
            {
                lane = new Queue<Question>();
                lanes[q.CategoryId] = lane;
                order.Add(q.CategoryId);
            }
            if (lane.Count < perCat) lane.Enqueue(q);
        }

        var outp = new List<Question>();
        var progressed = true;
        while (outp.Count < limit && progressed)
        {
            progressed = false;
            foreach (var c in order)
            {
                if (lanes[c].Count > 0)
                {
                    outp.Add(lanes[c].Dequeue());
                    progressed = true;
                    if (outp.Count >= limit) break;
                }
            }
        }
        // The per-category cap is an ANTI-MONOPOLY rule, not a quota: a genuinely
        // single-domain relevant pool must not starve the set ("Marie Curie" is
        // all science — capping at 3 turned a requested 8-question quiz into 4).
        if (outp.Count < limit)
        {
            var taken = outp.Select(q => q.Id).ToHashSet();
            outp.AddRange(ranked.Where(q => !taken.Contains(q.Id)).Take(limit - outp.Count));
        }
        return QueryHelpers.Shuffle(outp);
    }
}
