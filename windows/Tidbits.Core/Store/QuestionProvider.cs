using System.Globalization;
using Tidbits.Core.Data;
using Tidbits.Core.Engine;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// The single source of questions for any game (port of Core/Data/QuestionProvider.swift).
/// Corpus + enrichment first (offline, never-repeat), tracks seen ids, seeds the Daily
/// deterministically. Live Wikipedia top-up is stubbed here — Create's live-gen is a
/// later parity item (WikipediaClient + TemplateEngine, 1.11/1.12); with a 20k corpus
/// the top-up rarely triggers for normal play.
public sealed class QuestionProvider
{
    private readonly QuestionSources _src;
    private readonly HashSet<string> _seen = new();
    private Networking.WikipediaClient? _wiki;

    public QuestionProvider(QuestionSources sources) => _src = sources;

    public IReadOnlySet<string> Seen => _seen;
    public int CorpusCount => _src.Corpus.Count;

    public void MarkSeen(IEnumerable<string> ids)
    {
        foreach (var id in ids) _seen.Add(id);
        if (_seen.Count > 9000) _seen.Clear(); // cap; recycling is fine once most is seen
    }

    public void ResetSeen() => _seen.Clear();

    /// Questions for a standard game. Corpus first; live top-up if thin (stubbed).
    public async Task<List<Question>> Questions(GameMode mode, TriviaCategory category, string? dailyDay = null)
    {
        var need = mode == GameMode.TimeAttack ? Math.Min(mode.QuestionCount(), 25) : mode.QuestionCount();

        if (mode == GameMode.Daily) return await DailyQuestions(category, dailyDay ?? DayKey());

        switch (mode)
        {
            case GameMode.PictureId or GameMode.ThisOrThat or GameMode.ClosestCall
                or GameMode.Ordering or GameMode.Matching or GameMode.TypeAnswer:
                return _src.Enrich(mode).Questions(category.Id, _seen, need);
            case GameMode.OddOneOut: // geography-only data; ignore the picked category
                return _src.Enrich(mode).Questions("mixed", _seen, need);
            case GameMode.Enumerate: // small replayable pool; ignore the seen-set (like Daily)
                return _src.Enrich(mode).Questions("mixed", new HashSet<string>(), need);
            case GameMode.Ladder:
            {
                var pool = _src.Corpus.Questions("mixed", _seen, 80);
                pool.Sort((a, b) => _src.Difficulty.DifficultyFor(a).CompareTo(_src.Difficulty.DifficultyFor(b)));
                if (pool.Count < need) return pool;
                return Enumerable.Range(0, need)
                    .Select(i => pool[i * (pool.Count - 1) / Math.Max(1, need - 1)]).ToList();
            }
        }

        var pulled = _src.Corpus.Questions(category.Id, _seen, need);
        if (pulled.Count < need)
        {
            var topic = category.Id == "mixed" ? "popular" : category.Name;
            pulled.AddRange(await LiveQuestions(topic, category, need - pulled.Count));
        }
        return pulled.Take(need).ToList();
    }

    /// Build a Trivia Night question stream from a plan — per round, source `Count`
    /// of that round's TYPE, tag with the round index, concatenate.
    public async Task<List<Question>> NightQuestions(NightPlan plan, TriviaCategory category)
    {
        var all = new List<Question>();
        var picked = new HashSet<string>();
        for (int ri = 0; ri < plan.Rounds.Count; ri++)
        {
            var round = plan.Rounds[ri];
            var exclude = new HashSet<string>(_seen);
            exclude.UnionWith(picked);
            var qs = await Sourced(round.Kind, category, round.Count, exclude);
            foreach (var q in qs)
            {
                all.Add(q with { RoundIndex = ri });
                picked.Add(q.Id);
            }
        }
        MarkSeen(all.Select(q => q.Id));
        return all;
    }

    private async Task<List<Question>> Sourced(GameMode type, TriviaCategory category, int count, ISet<string> excluding)
    {
        switch (type)
        {
            case GameMode.PictureId or GameMode.ThisOrThat or GameMode.ClosestCall
                or GameMode.Ordering or GameMode.Matching or GameMode.TypeAnswer:
                return _src.Enrich(type).Questions(category.Id, excluding, count);
            case GameMode.OddOneOut:
                return _src.Enrich(type).Questions("mixed", excluding, count);
            case GameMode.Enumerate:
                return _src.Enrich(type).Questions("mixed", new HashSet<string>(), count);
            default:
                var pulled = _src.Corpus.Questions(category.Id, excluding, count);
                if (pulled.Count < count)
                {
                    var topic = category.Id == "mixed" ? "popular" : category.Name;
                    pulled.AddRange(await LiveQuestions(topic, category, count - pulled.Count));
                }
                return pulled.Take(count).ToList();
        }
    }

    /// A fixed-size set for a party game — the SAME questions for every player.
    public async Task<List<Question>> Questions(TriviaCategory category, int count)
    {
        var pulled = _src.Corpus.Questions(category.Id, _seen, count);
        if (pulled.Count < count)
        {
            var topic = category.Id == "mixed" ? "popular" : category.Name;
            pulled.AddRange(await LiveQuestions(topic, category, count - pulled.Count));
        }
        var set = pulled.Take(count).ToList();
        MarkSeen(set.Select(q => q.Id));
        return set;
    }

    /// Custom Mix: pull from every selected mode and shuffle together (no rounds).
    public async Task<List<Question>> MixQuestions(IReadOnlyList<GameMode> modes, TriviaCategory category, int count)
    {
        if (modes.Count == 0) return [];
        var perMode = Math.Max(2, (int)Math.Ceiling((double)count / modes.Count) + 1);
        var pool = new List<Question>();
        foreach (var mode in modes)
        {
            var qs = await Questions(mode, category);
            pool.AddRange(qs.Take(perMode).Select(q => q with { RoundIndex = null }));
        }
        MarkSeen(pool.Select(q => q.Id));
        return QueryHelpers.Shuffle(pool).Take(count).ToList();
    }

    /// Create a quiz on a topic — vetted corpus questions matching the topic
    /// (retrieval + diversify), live-gen top-up if thin (stubbed for now). Marks seen.
    public async Task<List<Question>> CreateQuestions(string topic, int count = 10)
    {
        var found = _src.Corpus.Search(topic, count);
        if (found.Count < count)
        {
            var live = await LiveQuestions(topic, TriviaCategory.Named("mixed"), count - found.Count);
            found = found.Concat(live).ToList();
        }
        var set = found.Take(count).ToList();
        MarkSeen(set.Select(q => q.Id));
        return set;
    }

    /// The Daily puzzle: deterministic for the calendar day (DailyPick, order-independent).
    public async Task<List<Question>> DailyQuestions(TriviaCategory category, string? day = null)
    {
        day ??= DayKey();
        var ids = _src.Corpus.OrderedIds(category.Id);
        var count = GameMode.Daily.QuestionCount();
        if (ids.Count < count) return await LiveQuestions("On this day", category, count);
        var picked = DailyPick.Pick(ids, day, category.Id, count);
        return _src.Corpus.Questions(picked);
    }

    /// Live Wikipedia generation (1.11/1.12): search the topic, fetch candidate
    /// summaries, and run the TemplateEngine filter → good MCQs. Deterministic for
    /// a (topic, count) pair. Degrades to empty on any network/parse failure — the
    /// corpus is the primary source; this is the any-topic top-up.
    public async Task<List<Question>> LiveQuestions(string topic, TriviaCategory category, int count)
    {
        try
        {
            _wiki ??= new Networking.WikipediaClient();
            var titles = await _wiki.Search(topic, 30);
            if (titles.Count == 0) return new();
            var summaries = await _wiki.Summaries(titles);
            var seed = Engine.StableSeed.Of($"{topic}:{count}");
            return Engine.TemplateEngine.MakeQuestions(summaries, category.Id, count, seed);
        }
        catch { return new(); }
    }

    public static string DayKey() => DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
    public static string DayKey(DateTime date) => date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
}
