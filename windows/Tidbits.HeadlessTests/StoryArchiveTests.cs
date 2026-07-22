using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Story Archive (docs/CLUB-FEATURES-BUILD.md "Feature 2") — the permanent,
/// searchable library of every story the player has unlocked, right or wrong.
/// Pure and UI-agnostic; mirrors the Apple/Android test intent (upsert-by-qid,
/// everCorrect ORs rather than overwrites, plain substring search + predicate
/// filters, no ranking model). Windows is the last of six platforms.
public class StoryArchiveTests
{
    private static Question Q(string id, string categoryId = "science", int correctIndex = 0, string explanation = "Because.") => new()
    {
        Id = id, Prompt = $"Prompt {id}", Options = new[] { "A", "B", "C", "D" },
        CorrectIndex = correctIndex, CategoryId = categoryId, Difficulty = 3, Explanation = explanation,
    };

    private static RecordsStore NewStore()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-story-{Guid.NewGuid():N}.json");
        return new RecordsStore(path);
    }

    private static RecordsStore StoreWith(RecordsData data)
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-story-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(data));
        return new RecordsStore(path);
    }

    private static GameSummary Summary(params AnsweredQuestion[] answered) => new()
    {
        Mode = GameMode.Classic, Category = TriviaCategory.Named("mixed"),
        Score = answered.Count(a => a.IsCorrect), Correct = answered.Count(a => a.IsCorrect),
        Total = answered.Length, MaxStreak = 0, Answered = answered,
    };

    [Fact]
    public void Recording_an_answer_upserts_a_seen_story_right_or_wrong()
    {
        var store = NewStore();
        store.Record(Summary(new AnsweredQuestion { Question = Q("a"), ChosenIndex = 1 })); // wrong (correctIndex 0)

        var s = Assert.Single(store.Seen);
        Assert.Equal("a", s.QuestionId);
        Assert.False(s.EverCorrect);
        Assert.Equal("Because.", s.Story);
    }

    [Fact]
    public void EverCorrect_is_ORd_not_overwritten_by_a_later_miss()
    {
        var store = NewStore();
        var q = Q("a");
        store.Record(Summary(new AnsweredQuestion { Question = q, ChosenIndex = 0 })); // right
        store.Record(Summary(new AnsweredQuestion { Question = q, ChosenIndex = 1 })); // wrong, later

        var s = Assert.Single(store.Seen); // same qid -> upserted, not duplicated
        Assert.True(s.EverCorrect);
    }

    [Fact]
    public void Seen_is_most_recent_first()
    {
        var now = DateTime.UtcNow;
        var data = new RecordsData
        {
            Seen =
            {
                SeenStory.From(Q("old"), true, at: now.AddDays(-1)),
                SeenStory.From(Q("new"), true, at: now),
            },
        };
        var store = StoreWith(data);
        Assert.Equal("new", store.Seen[0].QuestionId);
        Assert.Equal("old", store.Seen[1].QuestionId);
    }

    [Fact]
    public void Preview_line_reflects_the_most_recent_story_or_is_null_when_empty()
    {
        Assert.Null(StoryArchive.PreviewLine(NewStore()));

        var store = NewStore();
        store.Record(Summary(new AnsweredQuestion { Question = Q("a", explanation: "A neat fact."), ChosenIndex = 0 }));
        var line = StoryArchive.PreviewLine(store);
        Assert.NotNull(line);
        Assert.Contains("A neat fact.", line);
        Assert.Contains("Club keeps every story", line);
    }

    [Fact]
    public void Search_text_matches_prompt_answer_or_story()
    {
        var store = NewStore();
        store.Record(Summary(
            new AnsweredQuestion { Question = Q("a", explanation: "Zebras are odd-toed."), ChosenIndex = 0 },
            new AnsweredQuestion { Question = Q("b", explanation: "Nothing to do with it."), ChosenIndex = 0 }));

        var results = StoryArchive.Search(store.Seen, "zebra", domain: null, filter: StoryFilter.All);
        var only = Assert.Single(results);
        Assert.Equal("a", only.QuestionId);
    }

    [Fact]
    public void Filter_favorites_missed_and_mastered_are_simple_predicates()
    {
        var store = NewStore();
        store.Record(Summary(
            new AnsweredQuestion { Question = Q("right"), ChosenIndex = 0 },
            new AnsweredQuestion { Question = Q("wrong"), ChosenIndex = 1 }));
        store.ToggleFavorite("wrong");

        Assert.Equal(new[] { "wrong" }, StoryArchive.Search(store.Seen, "", null, StoryFilter.Favorites).Select(s => s.QuestionId));
        Assert.Equal(new[] { "wrong" }, StoryArchive.Search(store.Seen, "", null, StoryFilter.Missed).Select(s => s.QuestionId));
        Assert.Equal(new[] { "right" }, StoryArchive.Search(store.Seen, "", null, StoryFilter.Mastered).Select(s => s.QuestionId));
    }

    [Fact]
    public void Domain_filter_scopes_to_one_category()
    {
        var store = NewStore();
        store.Record(Summary(
            new AnsweredQuestion { Question = Q("h", categoryId: "history"), ChosenIndex = 0 },
            new AnsweredQuestion { Question = Q("s", categoryId: "science"), ChosenIndex = 0 }));

        var results = StoryArchive.Search(store.Seen, "", "history", StoryFilter.All);
        Assert.Equal(new[] { "h" }, results.Select(s => s.QuestionId));
    }

    [Fact]
    public void Reset_all_clears_the_archive()
    {
        var store = NewStore();
        store.Record(Summary(new AnsweredQuestion { Question = Q("a"), ChosenIndex = 0 }));
        Assert.NotEmpty(store.Seen);

        store.ResetAll();
        Assert.Empty(store.Seen);
    }

    [Fact]
    public void Toggle_favorite_persists_across_a_reload()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-story-{Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);
        store.Record(Summary(new AnsweredQuestion { Question = Q("a"), ChosenIndex = 0 }));
        store.ToggleFavorite("a");

        var reloaded = new RecordsStore(path);
        Assert.True(reloaded.Seen.Single().Favorite);
    }

    [Fact]
    public void Reask_question_rebuilds_a_playable_four_option_mcq()
    {
        var store = NewStore();
        var q = Q("a");
        store.Record(Summary(new AnsweredQuestion { Question = q, ChosenIndex = 1 }));

        var rebuilt = store.Seen.Single().Question;
        Assert.NotNull(rebuilt);
        Assert.Equal(q.Id, rebuilt!.Id);
        Assert.Equal(4, rebuilt.Options.Count);
        Assert.Equal(q.CorrectIndex, rebuilt.CorrectIndex);
    }
}
