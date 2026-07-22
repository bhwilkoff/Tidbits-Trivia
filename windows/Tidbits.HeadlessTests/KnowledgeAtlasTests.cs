using System;
using System.Collections.Generic;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Feature 4 — Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md). Pure derivation over
/// `GameRecord` rows — no store, no schema change (confirmed by using the existing
/// `GameRecord.Date` directly, same as the Android port). Mirrors the Apple/Android
/// test intent: sample-floor withholding, trailing-12-month cutoff, quarter
/// trajectory math, decay-radar strong-then-dropped detection, and the honest
/// non-member preview. Windows is the last of six platforms.
public class KnowledgeAtlasTests
{
    private static GameRecord G(string categoryId, int correct, int total, int monthsAgo) => new()
    {
        CategoryId = categoryId, Correct = correct, Total = total, Score = correct,
        Date = DateTime.UtcNow.AddMonths(-monthsAgo),
    };

    [Fact]
    public void Domains_aggregates_correct_and_total_across_games_in_the_same_domain()
    {
        var games = new List<GameRecord> { G("history", 8, 10, 1), G("history", 4, 5, 4) };
        var d = Assert.Single(KnowledgeAtlas.Domains(games));
        Assert.Equal("history", d.CategoryId);
        Assert.Equal(12, d.Correct);
        Assert.Equal(15, d.Total);
    }

    [Fact]
    public void Domains_omits_a_domain_never_played()
    {
        var games = new List<GameRecord> { G("history", 8, 10, 1) };
        var domains = KnowledgeAtlas.Domains(games);
        Assert.DoesNotContain(domains, d => d.CategoryId == "science");
    }

    [Fact]
    public void Records_older_than_12_months_drop_out_of_the_atlas()
    {
        var games = new List<GameRecord> { G("history", 8, 10, 13) };
        Assert.Empty(KnowledgeAtlas.Domains(games));
    }

    [Fact]
    public void Quarter_accuracy_is_withheld_below_the_sample_floor()
    {
        // Only 7 answers in the recent quarter (months 0-2) — below sampleFloor (8).
        var games = new List<GameRecord> { G("history", 5, 7, 1) };
        var d = Assert.Single(KnowledgeAtlas.Domains(games));
        Assert.Null(d.RecentAccuracy);
        Assert.Null(d.TrajectoryDelta);
        Assert.False(d.IsDecaying);
    }

    [Fact]
    public void Quarter_accuracy_reads_once_the_sample_floor_is_met()
    {
        var games = new List<GameRecord> { G("history", 8, 10, 1) }; // exactly at the floor
        var d = Assert.Single(KnowledgeAtlas.Domains(games));
        Assert.Equal(0.8, d.RecentAccuracy);
    }

    [Fact]
    public void Trajectory_delta_is_recent_minus_prior_and_flags_decay_at_the_threshold()
    {
        var games = new List<GameRecord>
        {
            G("history", 4, 10, 1),  // recent quarter (0-2): 40%
            G("history", 8, 10, 4),  // prior quarter (3-5): 80%
        };
        var d = Assert.Single(KnowledgeAtlas.Domains(games));
        Assert.NotNull(d.TrajectoryDelta);
        Assert.Equal(-0.4, d.TrajectoryDelta!.Value, 3);
        Assert.True(d.IsDecaying); // -0.4 <= -decayDelta (0.12)
    }

    [Fact]
    public void Trajectory_does_not_flag_decay_for_a_small_dip_under_the_threshold()
    {
        var games = new List<GameRecord>
        {
            G("history", 8, 10, 1),  // recent: 80%
            G("history", 9, 10, 4),  // prior: 90% -> delta -0.10, under decayDelta 0.12
        };
        var d = Assert.Single(KnowledgeAtlas.Domains(games));
        Assert.False(d.IsDecaying);
    }

    [Fact]
    public void Domains_are_sorted_by_total_sample_size_descending()
    {
        var games = new List<GameRecord> { G("science", 2, 3, 1), G("history", 8, 10, 1) };
        var domains = KnowledgeAtlas.Domains(games);
        Assert.Equal(new[] { "history", "science" }, new[] { domains[0].CategoryId, domains[1].CategoryId });
    }

    [Fact]
    public void Decay_radar_flags_a_domain_strong_6_to_11_months_ago_that_has_since_dropped()
    {
        var games = new List<GameRecord>
        {
            G("history", 8, 10, 8),  // past window (6-11): 80% -> strong (>=70%)
            G("history", 5, 10, 2),  // recent window (0-5): 50% -> dropped >=12pts
        };
        var entry = Assert.Single(KnowledgeAtlas.DecayRadar(games));
        Assert.Equal("history", entry.CategoryId);
        Assert.Equal(0.8, entry.PastAccuracy);
        Assert.Equal(0.5, entry.RecentAccuracy);
        Assert.Equal(-0.3, entry.Delta, 3);
    }

    [Fact]
    public void Decay_radar_excludes_a_domain_that_was_never_strong_in_the_past_window()
    {
        var games = new List<GameRecord>
        {
            G("history", 5, 10, 8),  // past: 50% -> below strongThreshold (0.70)
            G("history", 2, 10, 2),  // recent: 20%
        };
        Assert.Empty(KnowledgeAtlas.DecayRadar(games));
    }

    [Fact]
    public void Decay_radar_excludes_a_domain_that_stayed_strong()
    {
        var games = new List<GameRecord>
        {
            G("history", 8, 10, 8),  // past: 80%
            G("history", 8, 10, 2),  // recent: 80% -> no drop
        };
        Assert.Empty(KnowledgeAtlas.DecayRadar(games));
    }

    [Fact]
    public void Decay_radar_respects_the_sample_floor_on_both_windows()
    {
        var games = new List<GameRecord>
        {
            G("history", 5, 6, 8),  // past window: only 6 answers -> below floor (8)
            G("history", 1, 10, 2), // recent: 10%
        };
        Assert.Empty(KnowledgeAtlas.DecayRadar(games));
    }

    [Fact]
    public void Decay_radar_is_sorted_by_the_steepest_drop_first()
    {
        var games = new List<GameRecord>
        {
            G("history", 8, 10, 8), G("history", 4, 10, 2),   // history: 80% -> 40%, delta -0.4
            G("science", 8, 10, 9), G("science", 6, 10, 3),   // science: 80% -> 60%, delta -0.2
        };
        var radar = KnowledgeAtlas.DecayRadar(games);
        Assert.Equal(2, radar.Count);
        Assert.Equal("history", radar[0].CategoryId); // steepest delta first
    }

    [Fact]
    public void Preview_line_is_null_below_a_minimum_of_3_answers_in_any_domain()
    {
        var games = new List<GameRecord> { G("history", 1, 2, 1) };
        Assert.Null(KnowledgeAtlas.PreviewLine(games));
    }

    [Fact]
    public void Preview_line_reports_a_genuine_strongest_and_weakest_domain()
    {
        var games = new List<GameRecord> { G("history", 9, 10, 1), G("science", 2, 10, 1) };
        var line = KnowledgeAtlas.PreviewLine(games);
        Assert.NotNull(line);
        Assert.Contains("90%", line);
        Assert.Contains("History", line);
        Assert.Contains("20%", line);
        Assert.Contains("Science", line);
    }

    [Fact]
    public void Preview_line_uses_single_domain_phrasing_when_only_one_domain_qualifies()
    {
        var games = new List<GameRecord> { G("history", 7, 10, 1) };
        var line = KnowledgeAtlas.PreviewLine(games);
        Assert.NotNull(line);
        Assert.Contains("70%", line);
        Assert.Contains("History", line);
        Assert.Contains("so far", line);
    }
}
