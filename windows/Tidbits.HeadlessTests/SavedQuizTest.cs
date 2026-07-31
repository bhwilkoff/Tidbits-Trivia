using Tidbits.Core.Models;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A saved quiz is the first user-authored object in Tidbits and it is shareable, so
/// it outlives the app version that wrote it and must decode identically on six
/// platforms. These pin docs/QUIZ-CONTRACT.md and assert against the SAME shared
/// fixture the Apple and web suites read — a drift here is a share link that opens a
/// different quiz on Windows.
public class SavedQuizTest
{
    private static string FixturePath()
    {
        // Walk up from the test binary to the repo root.
        var dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8 && dir is not null; i++)
        {
            var candidate = Path.Combine(dir, "tools", "quiz-wire", "golden", "quiz-v1.json");
            if (File.Exists(candidate)) return candidate;
            dir = Path.GetDirectoryName(dir.TrimEnd(Path.DirectorySeparatorChar));
        }
        throw new FileNotFoundException("shared quiz wire fixture not found");
    }

    private static string FixtureText() => File.ReadAllText(FixturePath()).Trim();

    private static Question Q(string id, string template = "src") => new()
    {
        Id = id, Prompt = $"prompt {id}", Options = ["a", "b", "c", "d"], CorrectIndex = 1,
        CategoryId = "arts", Difficulty = 3, Explanation = $"why {id}",
        SourceTitle = $"title {id}", SourceUrl = $"https://example.org/{id}", TemplateId = template,
    };

    // MARK: the shared golden

    [Fact]
    public void The_shared_fixture_decodes_to_the_expected_quiz()
    {
        var quiz = SavedQuiz.FromJson(FixtureText());
        Assert.NotNull(quiz);
        Assert.Equal("k7m3qp9x2r", quiz!.Id);
        Assert.Equal("Jazz Legends", quiz.Title);
        Assert.Equal("Jazz", quiz.Topic);
        Assert.Equal("uid-1", quiz.CreatorId);
        Assert.Equal("Ben", quiz.CreatorName);
        Assert.Equal("mix", quiz.Mode);
        Assert.Equal(1753900000000L, quiz.CreatedAtMs);
        Assert.Equal(3, quiz.Entries.Count);
        Assert.Equal("src:desc:Q1", quiz.Entries[0].Ref);
        Assert.False(quiz.Entries[1].IsRef);
        Assert.True(quiz.Entries[2].IsSetRef);
        Assert.Equal("picture", quiz.Entries[2].Set);
        Assert.Equal("src:describe:Ornette_Coleman", quiz.Entries[2].Ref);
        Assert.Equal("Which Texan city did the group form in?", quiz.Entries[1].Inline!.Prompt);
        Assert.Equal(new[] { "Houston", "Dallas", "Austin", "El Paso" }, quiz.Entries[1].Inline!.Options);
        Assert.Equal(0, quiz.Entries[1].Inline!.CorrectIndex);
    }

    /// Re-encoding must reproduce the fixture byte for byte. Two devices saving the
    /// same quiz produce identical bytes, which is what makes the "created or deleted,
    /// never edited in place" merge guard checkable rather than aspirational.
    [Fact]
    public void Re_encoding_reproduces_the_fixture_exactly()
    {
        var text = FixtureText();
        var quiz = SavedQuiz.FromJson(text);
        Assert.Equal(text, quiz!.ToJson());
    }

    /// The inline entry carries an apostrophe and a URL precisely so escaping is
    /// covered: System.Text.Json escapes ' to ' by default, which would have made
    /// every Windows-written quiz differ from every other stack.
    [Fact]
    public void Escaping_survives_the_round_trip()
    {
        var quiz = SavedQuiz.FromJson(FixtureText());
        var inline = quiz!.Entries[1].Inline!;
        Assert.Equal("Destiny's Child", inline.SourceTitle);
        Assert.Contains("Destiny's_Child", inline.SourceUrl);
        Assert.Contains("Destiny's Child", quiz.ToJson());
    }

    // MARK: refs vs inline

    [Fact]
    public void Corpus_questions_become_refs_and_live_ones_inline()
    {
        var quiz = SavedQuiz.From([Q("src:desc:Q1"), Q("live:abc", "live")], "Jazz", "uid-1", "Ben");
        Assert.True(quiz.Entries[0].IsRef);
        Assert.False(quiz.Entries[1].IsRef);
        Assert.False(quiz.Entries[1].IsSetRef);
    }

    /// A question's SHAPE identifies its set, so provenance survives without being
    /// threaded through every call site.
    [Fact]
    public void A_bundled_question_is_saved_as_a_set_ref_not_a_bare_ref()
    {
        var picture = Q("src:describe:Tito") with { ImageUrl = "https://example.org/p.jpg" };
        var quiz = SavedQuiz.From([picture, Q("src:desc:Q1")], "Jazz", "uid-1", "Ben");
        Assert.True(quiz.Entries[0].IsSetRef);
        Assert.Equal("picture", quiz.Entries[0].Set);
        Assert.True(quiz.Entries[1].IsRef);
    }

    /// The regression: the corpus holds a DIFFERENT question under the same ID, and
    /// it must never be served in the bundled question's place.
    [Fact]
    public void A_set_ref_never_falls_back_to_the_colliding_corpus_row()
    {
        var quiz = SavedQuiz.FromJson(FixtureText())!;
        var r = quiz.Resolve(id => Q(id), setLookup: null);
        Assert.Equal(1, r.Missing);                       // the set ref stays missing
        Assert.Equal(2, r.Questions.Count);               // corpus ref + inline only
    }

    [Fact]
    public void A_set_ref_resolves_from_its_own_set()
    {
        var quiz = SavedQuiz.FromJson(FixtureText())!;
        var r = quiz.Resolve(_ => null,
            (set, id) => set == "picture" ? Q(id) with { Prompt = "Who is this?" } : null);
        Assert.Equal(1, r.Missing);   // only the corpus ref, which has no lookup here
        Assert.Contains(r.Questions, q => q.Prompt == "Who is this?");
    }

    /// A quiz must stay small enough to sync and share for free — refs are what make
    /// that true.
    [Fact]
    public void A_ref_only_quiz_is_under_a_kilobyte()
    {
        var quiz = SavedQuiz.From(Enumerable.Range(0, 20).Select(i => Q($"src:desc:Q{i}")),
                                  "Space", "uid-1", "Ben");
        Assert.True(quiz.ToJson().Length < 1024);
    }

    // MARK: leniency

    [Fact]
    public void Unknown_keys_are_ignored_rather_than_failing()
    {
        var text = FixtureText().TrimEnd('}') + ",\"fromV2\":{\"a\":1}}";
        var quiz = SavedQuiz.FromJson(text);
        Assert.NotNull(quiz);
        Assert.Equal(3, quiz!.Entries.Count);
    }

    [Fact]
    public void A_malformed_entry_is_skipped_not_fatal()
    {
        var quiz = SavedQuiz.FromJson(
            "{\"id\":\"abc\",\"by\":\"u\",\"qs\":[\"src:a\",42,[\"short\"],{\"s\":\"picture\"},\"pic:b\"]}");
        Assert.Equal(2, quiz!.Entries.Count);   // the set-ref missing its `i` is skipped
    }

    [Fact]
    public void A_quiz_with_no_id_or_questions_is_rejected()
    {
        Assert.Null(SavedQuiz.FromJson("{\"by\":\"u\",\"qs\":[\"a\"]}"));
        Assert.Null(SavedQuiz.FromJson("{\"id\":\"abc\",\"by\":\"u\"}"));
        Assert.Null(SavedQuiz.FromJson("not json at all"));
    }

    // MARK: resolving — the degrade path

    [Fact]
    public void Missing_refs_are_reported_not_substituted()
    {
        var quiz = SavedQuiz.From(Enumerable.Range(0, 8).Select(i => Q($"src:desc:Q{i}")),
                                  "Space", "uid-1", "Ben");
        var known = new HashSet<string> { "src:desc:Q0", "src:desc:Q1", "src:desc:Q2", "src:desc:Q3", "src:desc:Q4" };
        var r = quiz.Resolve(id => known.Contains(id) ? Q(id) : null);
        Assert.Equal(5, r.Questions.Count);
        Assert.Equal(3, r.Missing);
        Assert.True(r.IsPlayable);
        Assert.False(r.IsComplete);
    }

    [Fact]
    public void Too_few_resolved_refs_is_not_playable()
    {
        var quiz = SavedQuiz.From(Enumerable.Range(0, 8).Select(i => Q($"src:desc:Q{i}")),
                                  "Space", "uid-1", "Ben");
        var r = quiz.Resolve(id => id == "src:desc:Q0" ? Q(id) : null);
        Assert.False(r.IsPlayable);
    }

    /// An inline question needs no lookup at all — that is the point of carrying it.
    [Fact]
    public void Inline_questions_survive_without_the_corpus()
    {
        var quiz = SavedQuiz.FromJson(FixtureText());
        var r = quiz!.Resolve(_ => null);
        Assert.Single(r.Questions);
        Assert.Equal("Which Texan city did the group form in?", r.Questions[0].Prompt);
        Assert.Equal(2, r.Missing);   // the corpus ref and the set ref
    }

    // MARK: ids and titles

    /// The alphabet drops 0/o, 1/l/i and u so an ID read aloud in a pub or typed off a
    /// projector is unambiguous, and a random ID can't spell something unfortunate.
    [Fact]
    public void Ids_avoid_ambiguous_characters_and_are_unique()
    {
        var rng = new Random(7);
        var ids = Enumerable.Range(0, 500).Select(_ => SavedQuiz.MakeId(rng)).ToList();
        Assert.All(ids, id =>
        {
            Assert.Equal(10, id.Length);
            Assert.All(id, c => Assert.Contains(c, SavedQuiz.IdAlphabet));
            Assert.DoesNotContain(id, c => "01loiu".Contains(c));
        });
        Assert.Equal(ids.Count, ids.Distinct().Count());
    }

    [Fact]
    public void Titles_are_trimmed_capped_and_never_empty()
    {
        Assert.Equal("Jazz", SavedQuiz.CleanTitle("  Jazz  "));
        Assert.Equal("Untitled quiz", SavedQuiz.CleanTitle("   "));
        Assert.Equal("Untitled quiz", SavedQuiz.CleanTitle(null));
        Assert.Equal(60, SavedQuiz.CleanTitle(new string('x', 200)).Length);
    }

    [Fact]
    public void A_quiz_with_no_title_falls_back_to_its_topic()
        => Assert.Equal("Volcanoes", SavedQuiz.From([Q("src:desc:Q1")], "Volcanoes", "uid-1", "Ben").Title);
}
