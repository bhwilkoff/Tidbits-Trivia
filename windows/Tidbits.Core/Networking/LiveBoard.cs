using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// G5 — one cell of the pick-your-category board.
public sealed record LiveBoardCell
{
    [JsonPropertyName("categoryID")] public required string CategoryId { get; init; }
    [JsonPropertyName("tier")] public int Tier { get; init; }          // 1…5, the difficulty row
    [JsonPropertyName("questionID")] public required string QuestionId { get; init; }
    [JsonPropertyName("taken")] public bool Taken { get; set; }

    [JsonIgnore] public string Id => $"{CategoryId}:{Tier}";
    /// Points come from the TIER, not the question, so the room can see what it is
    /// risking before it picks. A question's own difficulty may be adjusted later;
    /// the board's promise to the room must not move with it.
    [JsonIgnore] public int Points => Tier * 100;
}

/// G5 — the pick-your-category board, QuizXpress's Jeopardy-style round: categories
/// across, point tiers down, and the ROOM chooses which cell to play next. The C#
/// mirror of Swift `LiveBoard`; both stacks are pinned by the same cases.
public sealed class LiveBoard
{
    public static readonly int[] DefaultTiers = { 1, 2, 3, 4, 5 };

    [JsonPropertyName("categories")] public IReadOnlyList<string> Categories { get; init; } = new List<string>();
    [JsonPropertyName("tiers")] public IReadOnlyList<int> Tiers { get; init; } = DefaultTiers;
    [JsonPropertyName("cells")] public List<LiveBoardCell> Cells { get; init; } = new();

    public LiveBoardCell? Cell(string categoryId, int tier) =>
        Cells.FirstOrDefault(c => c.CategoryId == categoryId && c.Tier == tier);

    public IReadOnlyList<LiveBoardCell> Remaining => Cells.Where(c => !c.Taken).ToList();
    public bool IsComplete => !Cells.Any(c => !c.Taken);
    /// The points still on the board — what the host tells the room is left to play for.
    public int PointsRemaining => Cells.Where(c => !c.Taken).Sum(c => c.Points);

    /// Mark a cell played. Returns false when the cell does not exist or was ALREADY
    /// taken — the caller must not advance on a double-pick, which is what happens
    /// when two host clicks land on one cell.
    public bool Take(string categoryId, int tier)
    {
        var cell = Cells.FirstOrDefault(c => c.CategoryId == categoryId && c.Tier == tier && !c.Taken);
        if (cell is null) return false;
        cell.Taken = true;
        return true;
    }
}

public static class LiveBoardBuilder
{
    /// Build a board from a question pool.
    ///
    /// A cell is only created when the pool actually holds a question for that
    /// (category, tier). A board with a cell nothing can fill is worse than a
    /// smaller board: the room picks it, the host has nothing to read, and the night
    /// stalls in front of everyone. So an unfillable cell is ABSENT and the surfaces
    /// render a hole rather than a dead button.
    ///
    /// No question is used twice, even across categories — a repeat mid-board reads
    /// as a mistake to the room whichever cell it came from.
    public static LiveBoard Build(IReadOnlyList<Question> pool, IReadOnlyList<string> categories,
                                  IReadOnlyList<int>? tiers = null)
    {
        tiers ??= DefaultTiers;
        var used = new HashSet<string>();
        var cells = new List<LiveBoardCell>();
        foreach (var c in categories)
        {
            foreach (var t in tiers)
            {
                var q = pool.FirstOrDefault(x => x.CategoryId == c && x.Difficulty == t && !used.Contains(x.Id));
                if (q is null) continue;
                used.Add(q.Id);
                cells.Add(new LiveBoardCell { CategoryId = c, Tier = t, QuestionId = q.Id });
            }
        }
        return new LiveBoard { Categories = categories.ToList(), Tiers = tiers.ToList(), Cells = cells };
    }

    private static readonly int[] DefaultTiers = LiveBoard.DefaultTiers;

    /// Which category columns the pool can fill COMPLETELY — what a host should be
    /// offered, so they do not build a board that is mostly holes.
    public static IReadOnlyList<string> FillableCategories(IReadOnlyList<Question> pool,
                                                           IReadOnlyList<int>? tiers = null)
    {
        tiers ??= DefaultTiers;
        var byCategory = new Dictionary<string, HashSet<int>>();
        foreach (var q in pool)
        {
            if (!tiers.Contains(q.Difficulty)) continue;
            if (!byCategory.TryGetValue(q.CategoryId, out var set))
                byCategory[q.CategoryId] = set = new HashSet<int>();
            set.Add(q.Difficulty);
        }
        return byCategory.Where(kv => kv.Value.Count == tiers.Count)
                         .Select(kv => kv.Key).OrderBy(k => k, StringComparer.Ordinal).ToList();
    }

    /// Who picks the next cell. The team that just answered correctly picks — the
    /// Jeopardy rule a room already understands. When NOBODY got it right the pick
    /// would otherwise stay put and one table would drive the whole board, so it
    /// rotates instead.
    public static string? NextChooser(string? current, string? correct, IReadOnlyList<string> teams)
    {
        if (teams.Count == 0) return null;
        if (correct != null && teams.Contains(correct)) return correct;
        if (current == null) return teams[0];
        var i = teams.ToList().IndexOf(current);
        if (i < 0) return teams[0];
        return teams[(i + 1) % teams.Count];
    }
}
