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
                return Filled(_src.Enrich(mode), category, need, _seen);
            case GameMode.OddOneOut: // now covers every category — honor it (with fallback)
                return Filled(_src.Enrich(mode), category, need, _seen);
            case GameMode.Enumerate: // replayable recall drill — ignore the seen-set
                return Filled(_src.Enrich(mode), category, need, new HashSet<string>());
            case GameMode.Ladder:
            {
                // The pool must come from the PICKED category: this asked for
                // "mixed" regardless, so a Ladder run in Geography delivered
                // whatever share of the mixed corpus happens to be geography —
                // measured on the shipped Apple build, 13%.
                var pool = _src.Corpus.Questions(category.Id, _seen, 80);
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
        // A night must not ask the same thing twice. Tracking IDs alone is not
        // enough: 4,261 (prompt, answer) pairs appear on MORE THAN ONE corpus row,
        // because the comparison templates generate several questions that differ
        // only in their distractors. "Which of these is the largest by area? ->
        // Sonora" twice in one night is the same question to the room, and the
        // second one is free.
        var asked = new HashSet<string>();

        for (int ri = 0; ri < plan.Rounds.Count; ri++)
        {
            var round = plan.Rounds[ri];
            int taken = 0;
            // Ask for more than we need so dropped repeats can be replaced rather
            // than leaving the round short — a short round is worse than a repeat.
            for (int attempt = 0; attempt < 3 && taken < round.Count; attempt++)
            {
                var exclude = new HashSet<string>(_seen);
                exclude.UnionWith(picked);
                var want = (round.Count - taken) * (attempt == 0 ? 1 : 3);
                var qs = await Sourced(round.Kind, category, want, exclude);
                if (qs.Count == 0) break;
                foreach (var q in qs)
                {
                    picked.Add(q.Id);
                    if (taken >= round.Count) continue;
                    if (!asked.Add(AskedKey(q))) continue;   // same prompt AND answer
                    all.Add(q with { RoundIndex = ri });
                    taken++;
                }
            }
        }
        MarkSeen(all.Select(q => q.Id));
        return all;
    }

    /// What makes two questions "the same" to the room: the prompt and the answer.
    /// Distractors do not count — a player who saw the first gets the second free.
    private static string AskedKey(Question q) =>
        (q.Prompt ?? "").Trim().ToLowerInvariant() + "\u0000" + (q.CorrectAnswer ?? "").Trim().ToLowerInvariant();

    /// Never-empty per-type pull for the category-filtered special types: try the
    /// picked category, relax to the whole type pool ("mixed") to top up short/empty
    /// combos (e.g. sports×matching = 0 rows), then — only if the type file failed to
    /// load entirely — a Classic corpus backstop. Keeps the MODE pure.
    private List<Question> Filled(Data.JsonQuestionSource source, TriviaCategory category, int need, ISet<string> excluding)
    {
        var qs = source.Questions(category.Id, excluding, need);
        if (qs.Count < need && category.Id != "mixed")
        {
            var have = new HashSet<string>(excluding);
            have.UnionWith(qs.Select(q => q.Id));
            qs.AddRange(source.Questions("mixed", have, need - qs.Count));
        }
        return qs.Count > 0 ? qs : _src.Corpus.Questions(category.Id, excluding, need);
    }

    private async Task<List<Question>> Sourced(GameMode type, TriviaCategory category, int count, ISet<string> excluding)
    {
        switch (type)
        {
            case GameMode.PictureId or GameMode.ThisOrThat or GameMode.ClosestCall
                or GameMode.Ordering or GameMode.Matching or GameMode.TypeAnswer:
                return Filled(_src.Enrich(type), category, count, excluding);
            case GameMode.OddOneOut:
                return Filled(_src.Enrich(type), category, count, excluding);
            case GameMode.Enumerate:
                return Filled(_src.Enrich(type), category, count, new HashSet<string>());
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
            var all = await _wiki.Summaries(titles);
            // Wikipedia's search returns what is RELATED to the topic, not what is
            // about it: "Zendaya" brings back Tom Holland, Law Roach and Dune. An
            // article earns its place only if it names the topic — the whole PHRASE,
            // since requiring only the words let "Albert Einstein" through Bob
            // Einstein, whose summary happens to name his brother Albert. And the
            // same different-person guard the corpus ranker uses is needed here, or
            // "Denver" fetches John Denver straight from Wikipedia after the corpus
            // correctly refused him.
            var tokens = Data.QueryHelpers.Tokenize(topic);
            var phrase = Data.QueryHelpers.TopicPhrase(topic);
            var guardNames = tokens.Count == 1
                && all.Any(x => Data.QueryHelpers.Flatten(x.Title) == phrase);
            var onTopic = all.Where(x =>
            {
                var subject = Data.QueryHelpers.Flatten(x.Title);
                if (guardNames && subject != phrase && subject.Split(' ').Length == 2
                    && Data.QueryHelpers.ContainsWord(subject, phrase)) return false;
                var hay = Data.QueryHelpers.Fold($"{x.Title} {x.Extract} {x.Description}");
                return Data.QueryHelpers.ContainsWord(hay, phrase);
            }).ToList();
            var seed = Engine.StableSeed.Of($"{topic}:{count}");
            return Engine.TemplateEngine.MakeQuestions(onTopic, category.Id, count, seed,
                relaxed: true, distractors: all);
        }
        catch { return new(); }
    }

    public static string DayKey() => DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
    public static string DayKey(DateTime date) => date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
}
