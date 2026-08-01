using Tidbits.Core.Data;
using Tidbits.Core.Networking;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// <summary>
/// Local persistence for saved quizzes (docs/QUIZ-CONTRACT.md §4).
///
/// Local is the source of truth for a player's own quizzes: they must work offline
/// and before sign-in, so nothing here needs an account. What's stored is the
/// CONTRACT JSON, one file per quiz — not a Windows-specific shape, which would be
/// a fifth representation to keep in step with the four stacks.
///
/// Not DPAPI-protected, unlike the credential stores: a quiz is content the player
/// may well publish, not a secret. Encrypting it would only make it unreadable to
/// the tooling that has to debug it.
/// </summary>
public sealed class QuizStore
{
    private readonly string _dir;

    public QuizStore(string directory)
    {
        _dir = directory;
        try { Directory.CreateDirectory(_dir); } catch { /* read-only dir: All() degrades to empty */ }
    }

    private string PathFor(string id) => Path.Combine(_dir, id + ".json");

    /// <summary>Newest first — a quiz you just made belongs at the top of your list.</summary>
    public IReadOnlyList<SavedQuiz> All()
    {
        try
        {
            return Directory.EnumerateFiles(_dir, "*.json")
                .Select(f => { try { return SavedQuiz.FromJson(File.ReadAllText(f)); } catch { return null; } })
                .Where(q => q is not null)
                .Select(q => q!)
                .OrderByDescending(q => q.CreatedAtMs)
                .ToList();
        }
        catch { return Array.Empty<SavedQuiz>(); }
    }

    public SavedQuiz? Get(string id)
    {
        try
        {
            var p = PathFor(id);
            return File.Exists(p) ? SavedQuiz.FromJson(File.ReadAllText(p)) : null;
        }
        catch { return null; }
    }

    /// <summary>Idempotent: saving the same quiz twice overwrites rather than duplicating.</summary>
    public bool Save(SavedQuiz quiz)
    {
        try { File.WriteAllText(PathFor(quiz.Id), quiz.ToJson()); return true; }
        catch { return false; }
    }

    public void Delete(string id)
    {
        try { File.Delete(PathFor(id)); } catch { /* already gone */ }
    }

    public void Rename(string id, string title)
    {
        var q = Get(id);
        if (q is null) return;
        q.Title = SavedQuiz.CleanTitle(title);
        Save(q);
    }

    /// <summary>Build and store in one step — every created quiz is kept automatically.</summary>
    public SavedQuiz SaveCreated(IEnumerable<Question> questions, string topic, string creatorId, string creatorName)
    {
        var quiz = SavedQuiz.From(questions, topic, creatorId, creatorName);
        Save(quiz);
        return quiz;
    }

    /// <summary>
    /// Resolve a quiz's refs against everything this build actually ships. Ordering is
    /// preserved and an unresolvable ref is COUNTED, not replaced — a shared quiz that
    /// quietly swaps in a different question is worse than one that admits it's short.
    /// </summary>
    public static QuizResolution ResolveForPlay(SavedQuiz quiz, CorpusDatabase corpus, QuestionSources sources)
        => quiz.Resolve(
            corpus.Question,
            // Deliberately no corpus fallback for a set ref: the corpus holds a
            // DIFFERENT question under a bundled set's ID (166 of 200 sampled Picture
            // ID rows collide), which is the whole reason set-refs carry their set.
            (set, id) => sources.Question(set, id));
}

/// <summary>
/// One-time migration off the pre-contract SavedSetsStore, which stored FULL question
/// text keyed by a label, was Windows-and-web-only, and could not be shared
/// (docs/QUIZ-CONTRACT.md §7). Mirrors the web's migrateLegacySavedSets.
/// </summary>
public static class QuizMigration
{
    /// <summary>
    /// Convert each legacy set to a <c>quiz.v1</c> object. Questions are
    /// re-REFERENCED where their ID still resolves and only inlined when it doesn't:
    /// a naive conversion inlines everything and turns a 400-byte quiz into a 40KB
    /// one. That means this MUST run after the sources are loaded — with nothing
    /// resolvable every lookup misses and every question inlines, which is exactly
    /// how the web version failed until it was made to wait for its corpus.
    /// </summary>
    public static int Run(SavedSetsStore legacy, QuizStore quizzes, QuestionSources sources)
    {
        var sets = legacy.All;
        if (sets.Count == 0) return 0;

        var existingTitles = quizzes.All().Select(q => q.Title.ToLowerInvariant()).ToHashSet();
        int converted = 0;
        foreach (var set in sets)
        {
            var title = SavedQuiz.CleanTitle(set.Label);
            if (!existingTitles.Add(title.ToLowerInvariant())) continue;   // already migrated
            if (set.Questions.Count == 0) continue;

            var entries = set.Questions.Select(q => LegacyEntry(q, sources)).ToList();
            quizzes.Save(new SavedQuiz
            {
                Id = SavedQuiz.MakeId(),
                Title = title,
                Topic = set.Label ?? "",
                CreatorId = "local",
                CreatorName = "",
                // The legacy record carries no timestamp, so migrated quizzes all
                // land at "now". Ordering among them is arbitrary rather than wrong.
                CreatedAtMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                Mode = "mix",
                Entries = entries,
            });
            converted++;
        }
        return converted;
    }

    /// <summary>
    /// One legacy question → one contract entry. Pure, so the decision is testable
    /// separately from the ordering concern above.
    /// </summary>
    public static QuizEntry LegacyEntry(Question q, QuestionSources sources)
    {
        if (sources.Corpus.Question(q.Id) is not null) return QuizEntry.OfRef(q.Id);
        foreach (var set in QuestionSources.ContractSetNames)
            if (sources.Question(set, q.Id) is not null) return QuizEntry.OfSetRef(set, q.Id);
        // Genuinely unresolvable: inline it, keeping the ORIGINAL id. Rewriting it
        // would destroy the only thing a later pass could use to re-reference it.
        return QuizEntry.OfInline(new InlineQuestion(
            q.Id, q.Prompt, q.Options, q.CorrectIndex, q.CategoryId,
            q.Difficulty, q.Explanation, q.SourceTitle, q.SourceUrl ?? ""));
    }
}

/// <summary>
/// Publishing and fetching a shared quiz (docs/QUIZ-CONTRACT.md §5). Writes the SAME
/// quiz.v1 bytes as every other stack — a quiz shared from Windows has to open on a
/// phone and on the web, which is the whole point.
/// </summary>
public static class QuizSharing
{
    /// The canonical link target on every platform: the web app is the one surface
    /// someone without the app can open.
    public static string ShareUrl(string id) => $"https://tidbitstrivia.com/#/quiz/{id}";

    /// What a fetch came back with. "Gone" and "couldn't load" are DIFFERENT: telling
    /// someone with a working link that the quiz was deleted stops them retrying
    /// something transient.
    public abstract record FetchResult
    {
        public sealed record Found(SavedQuiz Quiz) : FetchResult;
        public sealed record NotFound : FetchResult;
        public sealed record Failed(string Message) : FetchResult;
    }

    /// Publish so anyone with the link can play it. EXPLICIT — a quiz you never share
    /// never leaves your account. The creator is stamped at publish time so the rules
    /// (`by === auth.uid`) let only its author overwrite it later, and the stamped
    /// copy is saved back LOCALLY or a re-share fails that same rule.
    public static async Task<string?> Publish(SavedQuiz quiz, FirebaseRtdb rtdb, QuizStore store)
    {
        var uid = await rtdb.EnsureAuth();
        quiz.CreatorId = uid;
        await rtdb.PutJson($"quizzes/{quiz.Id}", quiz.ToJson());
        store.Save(quiz);
        return ShareUrl(quiz.Id);
    }

    public static async Task<FetchResult> Fetch(string id, FirebaseRtdb rtdb)
    {
        try
        {
            var json = await rtdb.GetJson($"quizzes/{id}");
            if (json is null) return new FetchResult.NotFound();
            var quiz = SavedQuiz.FromJson(json);
            return quiz is null
                ? new FetchResult.Failed("This quiz is in a format this version can't read.")
                : new FetchResult.Found(quiz);
        }
        catch
        {
            return new FetchResult.Failed("Couldn't reach the quiz. Check your connection and try again.");
        }
    }
}
