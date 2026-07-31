using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Local persistence is the source of truth for a player's own quizzes (they must
/// work offline and before sign-in), and the migration off the pre-contract
/// SavedSetsStore touches quizzes players ALREADY HAVE — so it gets tests rather
/// than a careful read. Mirrors tools/quiz-wire/check_migration.mjs.
public class QuizStoreTest : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "tidbits-quiz-" + Guid.NewGuid().ToString("N"));

    public void Dispose() { try { Directory.Delete(_dir, true); } catch { } }

    private static Question Q(string id) => new()
    {
        Id = id, Prompt = $"prompt {id}", Options = ["a", "b", "c", "d"], CorrectIndex = 1,
        CategoryId = "arts", Difficulty = 3, Explanation = "e",
        SourceTitle = "t", SourceUrl = "", TemplateId = "src",
    };

    private static SavedQuiz Quiz(string id, string title = "Jazz", int n = 5) =>
        SavedQuiz.From(Enumerable.Range(0, n).Select(i => Q($"src:desc:Q{i}")),
                       "Jazz", "uid-1", "Ben", title: title, id: id);

    [Fact]
    public void Saving_then_loading_returns_an_identical_quiz()
    {
        var store = new QuizStore(_dir);
        var original = Quiz("aaaaaaaaaa");
        Assert.True(store.Save(original));
        var loaded = store.Get("aaaaaaaaaa");
        Assert.NotNull(loaded);
        Assert.Equal(original.Title, loaded!.Title);
        Assert.Equal(original.Entries, loaded.Entries);
    }

    /// Saving the same quiz twice is normal (replay, then save again). It must
    /// overwrite rather than grow a second copy in the player's list.
    [Fact]
    public void Saving_the_same_quiz_twice_updates_rather_than_duplicating()
    {
        var store = new QuizStore(_dir);
        store.Save(Quiz("aaaaaaaaaa", "First"));
        store.Save(Quiz("aaaaaaaaaa", "Second"));
        Assert.Single(store.All());
        Assert.Equal("Second", store.Get("aaaaaaaaaa")!.Title);
    }

    [Fact]
    public void Deleting_removes_only_that_quiz()
    {
        var store = new QuizStore(_dir);
        store.Save(Quiz("aaaaaaaaaa"));
        store.Save(Quiz("bbbbbbbbbb"));
        store.Delete("aaaaaaaaaa");
        Assert.Single(store.All());
        Assert.Null(store.Get("aaaaaaaaaa"));
    }

    [Fact]
    public void Deleting_something_that_is_not_there_is_harmless()
    {
        var store = new QuizStore(_dir);
        store.Save(Quiz("aaaaaaaaaa"));
        store.Delete("zzzzzzzzzz");
        Assert.Single(store.All());
    }

    /// An empty shelf is a real state, not an error.
    [Fact]
    public void An_empty_store_lists_nothing_rather_than_failing()
    {
        var store = new QuizStore(Path.Combine(_dir, "does-not-exist-yet"));
        Assert.Empty(store.All());
        Assert.Null(store.Get("nope"));
    }

    /// A corrupt file must not take the whole shelf down with it.
    [Fact]
    public void A_corrupt_quiz_file_is_skipped_not_fatal()
    {
        var store = new QuizStore(_dir);
        store.Save(Quiz("aaaaaaaaaa"));
        File.WriteAllText(Path.Combine(_dir, "broken.json"), "{ not json");
        Assert.Single(store.All());
    }

    // MARK: the migration decision (QUIZ-CONTRACT §7)

    private static QuestionSources SourcesWith(IEnumerable<Question> corpus, IEnumerable<Question> pictures) =>
        new()
        {
            Corpus = new CorpusDatabase(corpus),
            Difficulty = new DifficultyOverlay(),
            Enrichment = new Dictionary<GameMode, JsonQuestionSource>
            {
                [GameMode.PictureId] = new JsonQuestionSource(pictures),
            },
        };

    /// The whole point of §7: a naive conversion inlines everything and turns a
    /// 400-byte quiz into a 40KB one.
    [Fact]
    public void A_legacy_question_still_in_the_corpus_becomes_a_bare_ref()
    {
        var sources = SourcesWith([Q("src:cloze:Himyar")], []);
        Assert.Equal("src:cloze:Himyar", QuizMigration.LegacyEntry(Q("src:cloze:Himyar"), sources).Ref);
        Assert.True(QuizMigration.LegacyEntry(Q("src:cloze:Himyar"), sources).IsRef);
    }

    [Fact]
    public void A_legacy_question_from_a_bundled_set_becomes_a_set_ref()
    {
        var sources = SourcesWith([], [Q("src:describe:Sayfo")]);
        var entry = QuizMigration.LegacyEntry(Q("src:describe:Sayfo"), sources);
        Assert.True(entry.IsSetRef);
        Assert.Equal("picture", entry.Set);
    }

    /// An unresolvable question keeps its ORIGINAL id. Rewriting it would destroy
    /// the only information a later pass could use to re-reference it.
    [Fact]
    public void An_unresolvable_legacy_question_is_inlined_with_its_id_intact()
    {
        var sources = SourcesWith([], []);
        var entry = QuizMigration.LegacyEntry(Q("genuinely:retired"), sources);
        Assert.False(entry.IsRef);
        Assert.False(entry.IsSetRef);
        Assert.Equal("genuinely:retired", entry.Inline!.Id);
    }

    /// The shape of the bug the web hit: with nothing resolvable EVERY question
    /// inlines. The decision is right in isolation, which is why the ordering has to
    /// be guaranteed by the caller.
    [Fact]
    public void A_blind_lookup_inlines_but_stays_recoverable()
    {
        var sources = SourcesWith([], []);
        var entry = QuizMigration.LegacyEntry(Q("src:cloze:Himyar"), sources);
        Assert.Equal("src:cloze:Himyar", entry.Inline!.Id);
    }
}
