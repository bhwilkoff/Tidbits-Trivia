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
    /// Built once at construction: a saved quiz resolves its refs through here, and
    /// scanning 128k rows per ref would be the wrong shape entirely.
    private readonly Dictionary<string, Question> _byId;

    public CorpusDatabase(IEnumerable<Question> questions)
    {
        _all = questions.ToList();
        _byId = new Dictionary<string, Question>(_all.Count);
        foreach (var q in _all) _byId[q.Id] = q;
    }

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
    /// <summary>Look up one question by ID — a saved quiz's refs resolve here.</summary>
    public Question? Question(string id) => _byId.TryGetValue(id, out var q) ? q : null;

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
        // A topic made of nothing but stopwords cannot be searched for. "From (TV
        // series)" reduces to the word `from`, which matched every row containing
        // it — Notes from Underground, Spider-Man: Far From Home, From Dusk till
        // Dawn. The corpus says so and live generation takes the topic instead.
        if (!QueryHelpers.HasSignificantWord(tokens)) return [];
        var phrase = QueryHelpers.TopicPhrase(topic);
        // Is the typed word itself a subject here? That single fact is what licenses
        // the different-person guard: "Denver" is a place in this corpus, so "Bob
        // Denver" is someone else. "Potter" is not a subject, so "Harry Potter" is
        // the best reading of it.
        var guardNames = tokens.Count == 1 && _all.Any(q =>
            QueryHelpers.Flatten(q.SourceTitle) == phrase
            || QueryHelpers.Flatten(QueryHelpers.StripParens(q.SourceTitle)) == phrase);
        var requirePhrase = QueryHelpers.PhraseIsRequired(topic);

        // WHERE (prompt LIKE %t% OR title LIKE %t%) for any token, LIMIT 400 (pre-filter).
        var matched = new List<Question>();
        foreach (var q in _all)
        {
            // Folded, not merely lowercased, so "beyonce" finds "Beyoncé". Windows
            // holds the corpus in RAM, so it folds here rather than reading the sparse
            // search_text column the SQL-backed platforms need for the same result.
            var prompt = QueryHelpers.Fold(q.Prompt);
            var title = QueryHelpers.Fold(q.SourceTitle);
            var explanationPre = QueryHelpers.Fold(q.Explanation);
            var tagsPre = q.Tags.Select(QueryHelpers.Fold).ToList();
            if (tokens.Any(t => prompt.Contains(t) || title.Contains(t) || explanationPre.Contains(t) || tagsPre.Any(tg => tg.Contains(t))))
            {
                matched.Add(q);
                // The cap applies BEFORE ranking, so it must contain the genuine
                // matches. At 400, "van gogh" lost all 20 real rows to substring
                // noise. Mirrors the Swift fix.
                // 4,000 was not enough once relevance became strict: a common word
                // like "art" matches ~19,500 rows and the genuine ones sit past the
                // cap. The cap is now only a runaway guard.
                if (matched.Count >= 25000) break;
            }
        }

        var scored = new List<(Question q, int score, int matchedTokens)>();
        var giveaways = new List<(Question q, int score, int matchedTokens)>();
        foreach (var q in matched)
        {
            if (q.Id.StartsWith("src:continent:")) continue;        // repetitive template
            if (q.Difficulty <= 1) continue;                        // trivially easy
            var title = QueryHelpers.Fold(q.SourceTitle);
            var prompt = QueryHelpers.Fold(q.Prompt);
            var explanation = QueryHelpers.Fold(q.Explanation);
            var tags = q.Tags.Select(QueryHelpers.Fold).ToList();
            // The relevance FLOOR, applied before any ranking.
            var tier = QueryHelpers.Tier(q.SourceTitle, q.Prompt, q.Tags, tokens, phrase, guardNames, requirePhrase);
            if (tier is null) continue;
            var score = tokens.Sum(t => (tags.Any(tg => QueryHelpers.ContainsWord(tg, t)) ? 3 : 0)
                                      + (QueryHelpers.ContainsWord(title, t) ? 2 : 0)
                                      + (QueryHelpers.ContainsWord(prompt, t) ? 1 : 0)
                                      + (QueryHelpers.ContainsWord(explanation, t) ? 1 : 0));
            var matchedTokens = tier.Value;
            // A question whose ANSWER is/contains the topic is a giveaway ("Chicago"
            // -> answer "Chicago"), held in RESERVE rather than dropped: for a person
            // most good questions answer with their name (17 of the 20 real van Gogh
            // questions do), so a hard drop starved the pool below a full quiz.
            var answer = QueryHelpers.Fold(q.CorrectAnswer);
            if (tokens.Any(t => QueryHelpers.ContainsWord(answer, t))) giveaways.Add((q, score, matchedTokens));
            else scored.Add((q, score, matchedTokens));
        }

        var outp = FillByTier(scored, limit);
        if (outp.Count < limit)
        {
            var taken = outp.Select(q => q.Id).ToHashSet();
            outp.AddRange(FillByTier(giveaways, limit).Where(q => !taken.Contains(q.Id)).Take(limit - outp.Count));
        }
        return outp;
    }

    /// <summary>
    /// Take from the highest occupied relevance tier first, diversifying INSIDE it.
    /// Diversifying across tiers is what promoted a one-word coincidence into a
    /// category lane — "Ansel Adams" returned exactly one row per category (Samuel
    /// Adams, Hansel and Gretel, Phil Anselmo, Davante Adams...). Mirrors Swift.
    /// </summary>
    private static List<Question> FillByTier(List<(Question q, int score, int tier)> scored, int limit)
    {
        var outp = new List<Question>();
        foreach (var t in new[] { 3, 2, 1, 0, -1 })
        {
            if (outp.Count >= limit) break;
            var lane = scored.Where(s => s.tier == t)
                             .OrderByDescending(s => s.score).Select(s => s.q).ToList();
            outp.AddRange(Diversify(lane, limit - outp.Count));
        }
        return outp.Take(limit).ToList();
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
