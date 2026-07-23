using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Link Wall generator + persistence (docs/CLUB-FEATURES-BUILD.md
/// "Feature 6") — a faithful C# port of `Core/Store/LinkWall.swift`'s Stage 1.5/1.6
/// content-clean generator (also mirrored in Android's `data/LinkWall.kt` and
/// js/store.js). These tests exercise exactly what a naive port would get wrong:
/// the allowlist/denylist purity filters (capital/currency/author/director/composer),
/// the near-duplicate collision guard, day-to-day determinism, and the day-keyed
/// `RecordsStore` persistence shape. Apple's LinkWall.swift is canonical; Windows is
/// the last of six platforms.
public class LinkWallTests
{
    private static IReadOnlyList<Question> MatchQuestions() =>
        QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"))
            .Enrich(GameMode.Matching).Questions("mixed", new HashSet<string>(), 100_000);

    private static (string path, RecordsStore store) NewStore()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-linkwall-{Guid.NewGuid():N}.json");
        return (path, new RecordsStore(path));
    }

    // The 4 dates the orchestrator asked to verify against the Apple/JS/Kotlin
    // output (all three already agree byte-for-byte).
    private static readonly string[] VerifyDates = { "2026-07-22", "2026-09-15", "2026-12-25", "2026-11-11" };

    // MARK: - The 4 verification dates: content-clean + group structure

    [Fact]
    public void Puzzle_for_the_four_verification_dates_produces_four_clean_groups_of_four_and_writes_a_golden_file()
    {
        var matchQuestions = MatchQuestions();
        Assert.NotEmpty(matchQuestions); // the match.json fixture actually loaded

        var lines = new List<string>();
        foreach (var day in VerifyDates)
        {
            var puzzle = LinkWall.Puzzle(day, matchQuestions);
            Assert.NotNull(puzzle);
            Assert.Equal(day, puzzle!.Day);
            Assert.Equal(4, puzzle.Groups.Count);
            Assert.Equal(16, puzzle.Tiles.Count);

            var allMembers = new List<string>();
            lines.Add($"=== {day} ===");
            foreach (var g in puzzle.Groups)
            {
                Assert.Equal(4, g.Members.Count);
                Assert.Equal(4, g.Members.Select(m => m.ToLowerInvariant()).Distinct().Count()); // no in-group dupes
                Assert.InRange(g.Difficulty, 1, 4);
                allMembers.AddRange(g.Members);
                lines.Add($"[{g.Difficulty}] {g.Label}: {string.Join(" | ", g.Members)}  ({g.Why})");
            }
            // No cross-group collisions — every tile distinct case-insensitively.
            Assert.Equal(16, allMembers.Select(m => m.ToLowerInvariant()).Distinct().Count());
            // Tiles is exactly the 16 members, just reshuffled for display.
            Assert.Equal(allMembers.OrderBy(x => x, StringComparer.Ordinal),
                         puzzle.Tiles.OrderBy(x => x, StringComparer.Ordinal));
            // Ascending difficulty (yellow -> purple, the Connections convention).
            Assert.True(puzzle.Groups.Zip(puzzle.Groups.Skip(1), (a, b) => a.Difficulty <= b.Difficulty).All(x => x));
        }

        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS") ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "linkwall-golden.txt"), string.Join("\n", lines));
    }

    /// A regression guard for every named Stage-1 defect (docs/CLUB-FEATURES-BUILD.md
    /// "Feature 6" Stage 1 RESULT): subnational/historical capitals, a policy
    /// mislabeled as a currency, scripture/legal documents mislabeled as novels, TV
    /// series mislabeled as films, and a near-dup pair. None of these strings should
    /// EVER surface as a tile across a wide sample of days — if the port dropped a
    /// filter, this is what would catch it.
    [Fact]
    public void Puzzle_never_resurfaces_a_named_stage_one_content_defect_across_many_days()
    {
        var matchQuestions = MatchQuestions();
        var knownBad = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            // subnational / historical / disputed capitals (impure `capital` pool)
            "Little Rock", "Truro", "Edo", "Puhar", "Kutaisi", "Gilgit",
            // currency policy-not-currency
            "bimetallism",
            // scripture / founding documents mislabeled as novels
            "Book of Genesis", "Universal Declaration of Human Rights",
            "Constitution of the United States",
            // TV series / game shows mislabeled as films
            "Top of the Pops", "Jeopardy!", "Fawlty Towers", "Family Feud",
        };

        var start = new DateTime(2026, 1, 1);
        for (int i = 0; i < 90; i++)
        {
            var day = start.AddDays(i).ToString("yyyy-MM-dd");
            var puzzle = LinkWall.Puzzle(day, matchQuestions);
            Assert.NotNull(puzzle);
            foreach (var g in puzzle!.Groups)
                foreach (var m in g.Members)
                    Assert.False(knownBad.Contains(m), $"{day}: '{m}' is a named Stage-1 content defect (group '{g.Label}')");
        }
    }

    /// The near-duplicate collision guard (`isNearDuplicate`) exists specifically so
    /// two tiles describing the SAME referent — e.g. "Declaration of Independence"
    /// (a Historic Document) and "Declaration of Independence signed" (a Major
    /// Historical Event) — never both land in one puzzle, even though each is a
    /// perfectly legitimate tile on its own. This is the generic regression guard
    /// (any pair, any day), rather than one hardcoded example.
    [Fact]
    public void Puzzle_never_places_two_near_duplicate_tiles_in_the_same_puzzle()
    {
        var matchQuestions = MatchQuestions();
        var start = new DateTime(2026, 1, 1);
        for (int i = 0; i < 120; i++)
        {
            var day = start.AddDays(i).ToString("yyyy-MM-dd");
            var puzzle = LinkWall.Puzzle(day, matchQuestions);
            Assert.NotNull(puzzle);
            var allMembers = puzzle!.Groups.SelectMany(g => g.Members).ToList();
            for (int a = 0; a < allMembers.Count; a++)
            {
                for (int b = a + 1; b < allMembers.Count; b++)
                {
                    var x = allMembers[a].ToLowerInvariant();
                    var y = allMembers[b].ToLowerInvariant();
                    var isNearDup = Math.Min(x.Length, y.Length) >= 6 && (x.Contains(y) || y.Contains(x));
                    Assert.False(isNearDup, $"{day}: '{allMembers[a]}' / '{allMembers[b]}' are near-duplicates in the same puzzle");
                }
            }
        }
    }

    [Fact]
    public void Puzzle_is_deterministic_for_the_same_day_same_pool()
    {
        var matchQuestions = MatchQuestions();
        var a = LinkWall.Puzzle("2026-07-22", matchQuestions);
        var b = LinkWall.Puzzle("2026-07-22", matchQuestions);

        Assert.NotNull(a);
        Assert.NotNull(b);
        Assert.Equal(a!.Groups.Select(g => g.Label), b!.Groups.Select(g => g.Label));
        Assert.Equal(a.Groups.Select(g => string.Join(",", g.Members)), b.Groups.Select(g => string.Join(",", g.Members)));
        Assert.Equal(a.Tiles, b.Tiles); // even the display shuffle is seeded from the day
    }

    [Fact]
    public void Puzzle_differs_across_different_days()
    {
        var matchQuestions = MatchQuestions();
        var puzzles = VerifyDates.Select(d => LinkWall.Puzzle(d, matchQuestions)!).ToList();
        // Not every day needs a fully disjoint theme set, but the four verification
        // days should not all be byte-identical (that would indicate the day seed
        // isn't threading through the rank at all).
        var signatures = puzzles.Select(p => string.Join("|", p.Groups.Select(g => g.Label))).Distinct().ToList();
        Assert.True(signatures.Count > 1, "all 4 verification days produced the identical theme set — the day seed likely isn't wired");
    }

    [Fact]
    public void Puzzle_returns_null_for_an_empty_pool()
    {
        Assert.Null(LinkWall.Puzzle("2026-07-22", Array.Empty<Question>()));
    }

    // MARK: - Share-grid encoding (LinkWallUi.ShareText)

    [Fact]
    public void ShareText_encodes_one_emoji_row_per_guess_and_the_win_line()
    {
        var result = new LinkWallResult
        {
            Day = "2026-07-22", Won = true, Mistakes = 1,
            GuessHistory = new List<List<int>> { new() { 1, 1, 1, 2 }, new() { 1, 1, 1, 1 }, new() { 2, 2, 2, 2 }, new() { 3, 3, 3, 3 }, new() { 4, 4, 4, 4 } },
        };
        var text = Tidbits.App.Views.LinkWallUi.ShareText("2026-07-22", result);

        Assert.Contains("Tidbits Link Wall — Jul 22", text);
        Assert.Contains("🟨🟨🟨🟩", text); // the wrong first guess (3 yellow + 1 green)
        Assert.Contains("🟨🟨🟨🟨", text);
        Assert.Contains("🟩🟩🟩🟩", text);
        Assert.Contains("🟦🟦🟦🟦", text);
        Assert.Contains("🟪🟪🟪🟪", text);
        Assert.Contains("Solved in 5 guesses.", text);
    }

    [Fact]
    public void ShareText_shows_the_loss_line_when_not_won()
    {
        var result = new LinkWallResult { Day = "2026-07-22", Won = false, GuessHistory = new List<List<int>> { new() { 1, 2, 3, 4 } } };
        var text = Tidbits.App.Views.LinkWallUi.ShareText("2026-07-22", result);
        Assert.Contains("Didn't solve it today.", text);
        Assert.DoesNotContain("Solved in", text);
    }

    // MARK: - One-away detection (LinkWallUi.ClosestUnsolvedGroup — pure, drives the
    // FAContentDialog's "One away…" pill without needing to render it)

    [Fact]
    public void ClosestUnsolvedGroup_finds_a_group_with_exactly_three_of_four_selected()
    {
        var g1 = new LinkWallGroup("World Capitals", "why", new[] { "Nairobi", "Lima", "Suva", "Dili" }, 3);
        var g2 = new LinkWallGroup("Iconic Films", "why", new[] { "Jaws", "Alien", "Se7en", "Amadeus" }, 1);
        var groups = new[] { g1, g2 };

        // 3 of g1 + 1 outsider from g2 -> "one away" from World Capitals.
        var selected = new[] { "Nairobi", "Lima", "Suva", "Jaws" };
        var closest = Tidbits.App.Views.LinkWallUi.ClosestUnsolvedGroup(groups, Array.Empty<string>(), selected);
        Assert.NotNull(closest);
        Assert.Equal("World Capitals", closest!.Label);
    }

    [Fact]
    public void ClosestUnsolvedGroup_ignores_an_already_solved_group()
    {
        var g1 = new LinkWallGroup("World Capitals", "why", new[] { "Nairobi", "Lima", "Suva", "Dili" }, 3);
        var selected = new[] { "Nairobi", "Lima", "Suva", "Jaws" };
        var closest = Tidbits.App.Views.LinkWallUi.ClosestUnsolvedGroup(new[] { g1 }, new[] { "World Capitals" }, selected);
        Assert.Null(closest); // already solved -> not "one away" from it anymore
    }

    [Fact]
    public void ClosestUnsolvedGroup_is_null_for_a_plain_wrong_guess_split_two_and_two()
    {
        var g1 = new LinkWallGroup("World Capitals", "why", new[] { "Nairobi", "Lima", "Suva", "Dili" }, 3);
        var g2 = new LinkWallGroup("Iconic Films", "why", new[] { "Jaws", "Alien", "Se7en", "Amadeus" }, 1);
        var selected = new[] { "Nairobi", "Lima", "Jaws", "Alien" }; // 2 + 2 split, no group at exactly 3
        var closest = Tidbits.App.Views.LinkWallUi.ClosestUnsolvedGroup(new[] { g1, g2 }, Array.Empty<string>(), selected);
        Assert.Null(closest);
    }

    // MARK: - LinkWallResult (guess/solve bookkeeping)

    [Fact]
    public void RecordGuess_appends_rows_in_order_and_RecordSolvedGroup_dedupes()
    {
        var result = new LinkWallResult { Day = "2026-07-22" };
        result.RecordGuess(new[] { 1, 1, 1, 2 });
        result.RecordGuess(new[] { 3, 3, 3, 3 });
        Assert.Equal(2, result.GuessHistory.Count);
        Assert.Equal(new List<int> { 1, 1, 1, 2 }, result.GuessHistory[0]);

        result.RecordSolvedGroup("World Capitals");
        result.RecordSolvedGroup("World Capitals"); // no dupe
        result.RecordSolvedGroup("Iconic Films");
        Assert.Equal(new List<string> { "World Capitals", "Iconic Films" }, result.SolvedLabels);
    }

    // MARK: - Day-lock persistence (RecordsStore)

    [Fact]
    public void LinkWallResultOrCreate_returns_the_same_row_for_a_repeated_day_never_a_fresh_board()
    {
        var (_, records) = NewStore();
        var first = records.LinkWallResultOrCreate("2026-07-22");
        first.Mistakes = 2;
        records.SaveLinkWallResult(first);

        var second = records.LinkWallResultOrCreate("2026-07-22");
        Assert.Equal(2, second.Mistakes); // resumed, not a fresh row
    }

    [Fact]
    public void SaveLinkWallResult_persists_immediately_a_fresh_store_over_the_same_file_sees_it()
    {
        var (path, records) = NewStore();
        var result = records.LinkWallResultOrCreate("2026-07-22");
        result.Mistakes = 3;
        result.Completed = true;
        result.Won = true;
        result.RecordGuess(new[] { 1, 1, 1, 1 });
        result.RecordSolvedGroup("Iconic Films");
        records.SaveLinkWallResult(result);

        var reloaded = new RecordsStore(path);
        var row = reloaded.LinkWall["2026-07-22"];
        Assert.Equal(3, row.Mistakes);
        Assert.True(row.Completed);
        Assert.True(row.Won);
        Assert.Single(row.GuessHistory);
        Assert.Equal(new List<string> { "Iconic Films" }, row.SolvedLabels);
    }

    [Fact]
    public void Different_days_get_independent_rows_several_can_sit_in_the_archive_at_once()
    {
        var (_, records) = NewStore();
        var today = records.LinkWallResultOrCreate("2026-07-22");
        today.Won = true; today.Completed = true;
        records.SaveLinkWallResult(today);

        var yesterday = records.LinkWallResultOrCreate("2026-07-21");
        yesterday.Won = false; yesterday.Completed = true;
        records.SaveLinkWallResult(yesterday);

        Assert.Equal(2, records.LinkWall.Count);
        Assert.True(records.LinkWall["2026-07-22"].Won);
        Assert.False(records.LinkWall["2026-07-21"].Won);
    }

    [Fact]
    public void ResetAll_clears_the_link_wall_archive()
    {
        var (_, records) = NewStore();
        var result = records.LinkWallResultOrCreate("2026-07-22");
        records.SaveLinkWallResult(result);
        Assert.NotEmpty(records.LinkWall);

        records.ResetAll();

        Assert.Empty(records.LinkWall);
    }

    [Fact]
    public void PreviewLine_is_a_real_static_pitch_content_not_player_data()
    {
        var line = LinkWall.PreviewLine();
        Assert.False(string.IsNullOrWhiteSpace(line));
        Assert.Contains("16 tiles", line);
    }
}
