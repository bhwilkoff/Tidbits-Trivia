using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club-only Weak-Spot Arena generator (docs/CLUB-FEATURES-BUILD.md "Feature 1").
/// Pure and UI-agnostic — mirrors the Apple/Android test intent: true misses first
/// (most-missed, oldest-first), a transparent reason per question, and an honest
/// category-fill top-up below the floor. Windows is the last of six platforms.
public class WeakSpotArenaTests
{
    private static MissedFact Miss(string id, string categoryId, int missCount, DateTime lastSeen, bool resolved = false)
    {
        var q = new Question
        {
            Id = id, Prompt = $"Prompt {id}", Options = new[] { "A", "B", "C", "D" },
            CorrectIndex = 0, CategoryId = categoryId, Difficulty = 3, Explanation = "Because.",
        };
        var fact = MissedFact.From(q);
        fact.MissCount = missCount;
        fact.LastSeen = lastSeen;
        fact.Resolved = resolved;
        return fact;
    }

    private static RecordsStore StoreWith(RecordsData data)
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-weakspot-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(data));
        return new RecordsStore(path);
    }

    private static CorpusDatabase Corpus() =>
        QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures")).Corpus;

    [Fact]
    public void True_misses_sort_most_missed_then_oldest_first_and_carry_a_missed_reason()
    {
        var now = DateTime.UtcNow;
        var data = new RecordsData
        {
            Missed =
            {
                Miss("a", "science", missCount: 1, lastSeen: now.AddDays(-1)),
                Miss("b", "science", missCount: 3, lastSeen: now.AddDays(-10)),
                Miss("c", "science", missCount: 3, lastSeen: now.AddDays(-20)), // same count, older -> before b
                Miss("d", "science", missCount: 2, lastSeen: now),
            },
        };
        var round = WeakSpotArena.Build(StoreWith(data), Corpus());

        Assert.Equal(4, round.MissCount);
        Assert.Equal(new[] { "c", "b", "d", "a" }, round.Questions.Select(q => q.Id));
        foreach (var q in round.Questions)
        {
            Assert.True(round.Reasons.TryGetValue(q.Id, out var reason));
            Assert.StartsWith("Missed ", reason);
            Assert.Contains("·", reason);
        }
        Assert.Contains("×3", round.Reasons["b"]);
    }

    [Fact]
    public void Resolved_misses_are_excluded()
    {
        var data = new RecordsData
        {
            Missed =
            {
                Miss("resolved", "science", 5, DateTime.UtcNow, resolved: true),
                Miss("open", "science", 1, DateTime.UtcNow),
            },
        };
        var round = WeakSpotArena.Build(StoreWith(data), Corpus());

        Assert.Equal(1, round.MissCount);
        Assert.DoesNotContain(round.Questions, q => q.Id == "resolved");
    }

    [Fact]
    public void Caps_true_misses_at_round_size_even_with_more_history()
    {
        var data = new RecordsData();
        for (int i = 0; i < 15; i++)
            data.Missed.Add(Miss($"q{i}", "science", missCount: 15 - i, lastSeen: DateTime.UtcNow));

        var round = WeakSpotArena.Build(StoreWith(data), Corpus());

        Assert.Equal(WeakSpotArena.RoundSize, round.Questions.Count);
        Assert.Equal(WeakSpotArena.RoundSize, round.MissCount);
        // Highest miss count (lowest index) wins every slot.
        Assert.Equal("q0", round.Questions[0].Id);
    }

    [Fact]
    public void Below_the_floor_tops_up_from_the_weakest_category_and_labels_it_shoring_up()
    {
        var data = new RecordsData
        {
            // Only 1 true miss -> below TrueMissFloor (4) -> fill kicks in.
            Missed = { Miss("only-miss", "science", 1, DateTime.UtcNow) },
            Games =
            {
                new GameRecord { CategoryId = "history", Correct = 1, Total = 10 },  // 10% — weakest
                new GameRecord { CategoryId = "science", Correct = 9, Total = 10 },   // 90%
            },
        };
        var round = WeakSpotArena.Build(StoreWith(data), Corpus());

        Assert.Equal(1, round.MissCount); // true-miss count stays honest even after fill
        Assert.True(round.Questions.Count > 1, "expected the fill to top the round up");
        Assert.True(round.Questions.Count <= WeakSpotArena.FillTarget);

        var fillReasons = round.Reasons.Where(kv => kv.Key != "only-miss").Select(kv => kv.Value).ToList();
        Assert.NotEmpty(fillReasons);
        Assert.All(fillReasons, r => Assert.StartsWith("Shoring up ", r));
        Assert.Contains(fillReasons, r => r.Contains(TriviaCategory.Named("history").Name));
    }

    [Fact]
    public void A_category_with_fewer_than_3_games_is_not_eligible_for_fill()
    {
        var data = new RecordsData
        {
            Missed = { Miss("only-miss", "science", 1, DateTime.UtcNow) },
            Games = { new GameRecord { CategoryId = "history", Correct = 0, Total = 2 } }, // Total < 3
        };
        var round = WeakSpotArena.Build(StoreWith(data), Corpus());

        // No domain qualifies (Total >= 3 required) -> no fill, round stays at the true miss.
        Assert.Single(round.Questions);
    }

    [Fact]
    public void Four_or_more_true_misses_never_triggers_fill()
    {
        var now = DateTime.UtcNow;
        var data = new RecordsData
        {
            Missed = Enumerable.Range(0, WeakSpotArena.TrueMissFloor)
                .Select(i => Miss($"m{i}", "science", 1, now)).ToList(),
            Games = { new GameRecord { CategoryId = "history", Correct = 0, Total = 10 } },
        };
        var round = WeakSpotArena.Build(StoreWith(data), Corpus());

        Assert.Equal(WeakSpotArena.TrueMissFloor, round.Questions.Count);
        Assert.All(round.Reasons.Values, r => Assert.StartsWith("Missed ", r));
    }

    [Fact]
    public void Preview_line_reflects_the_top_miss_or_is_null_when_there_are_none()
    {
        var withMiss = StoreWith(new RecordsData { Missed = { Miss("p", "science", 2, DateTime.UtcNow) } });
        var line = WeakSpotArena.PreviewLine(withMiss);
        Assert.NotNull(line);
        Assert.Contains("Prompt p", line);
        Assert.Contains("Club turns misses", line);

        var empty = StoreWith(new RecordsData());
        Assert.Null(WeakSpotArena.PreviewLine(empty));
    }
}
