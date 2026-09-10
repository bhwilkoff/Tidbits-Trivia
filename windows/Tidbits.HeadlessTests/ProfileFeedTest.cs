using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// The Windows leg of the portable identity spine: a finished game — solo or a live
/// night — folds into the profile the way Swift `recordGame`/`recordLiveGame` and the
/// JS/Kotlin twins do. Until 2026-09-10 nothing on Windows ever wrote a game into it.
public class ProfileFeedTest
{
    private static PlayerIdentity.Profile Fresh() => PlayerIdentity.Profile.New("Player 1", createdAt: 1);

    [Fact]
    public void A_solo_game_moves_the_rating_and_sums_the_counters()
    {
        var p = PlayerIdentity.AfterGame(Fresh(), correct: 8, total: 10, today: "2026-09-10");
        Assert.True(p.Rating.Value > PlayerIdentity.Rating.Start);   // 80% against a 1200 field from 1000: up
        Assert.Equal(1, p.Rating.Games);
        Assert.Equal(1, p.Stats.GamesPlayed);
        Assert.Equal(10, p.Stats.QuestionsAnswered);
        Assert.Equal(8, p.Stats.Correct);
        Assert.Equal(0, p.Stats.LiveNights);
        Assert.Equal(1, p.Streak.Current);
        Assert.Equal("2026-09-10", p.Streak.LastPlayedDay);
        Assert.Equal(0, p.Streak.Freezes);
    }

    [Fact]
    public void A_live_night_counts_keeps_the_streak_and_grants_a_freeze_even_unanswered()
    {
        var p = PlayerIdentity.AfterLiveNight(Fresh(), correct: 0, answered: 0, today: "2026-09-10");
        Assert.Equal(PlayerIdentity.Rating.Start, p.Rating.Value);   // no MCQ accuracy: the rating holds
        Assert.Equal(0, p.Rating.Games);
        Assert.Equal(1, p.Stats.LiveNights);
        Assert.Equal(1, p.Stats.GamesPlayed);
        Assert.Equal(1, p.Streak.Current);
        Assert.Equal(1, p.Streak.Freezes);
    }

    [Fact]
    public void A_live_night_with_answers_weights_the_rating_more_than_a_solo_game()
    {
        var solo = PlayerIdentity.AfterGame(Fresh(), 8, 10, "2026-09-10");
        var live = PlayerIdentity.AfterLiveNight(Fresh(), 8, 10, "2026-09-10");
        Assert.True(live.Rating.Value > solo.Rating.Value);
    }

    [Fact]
    public void Consecutive_days_extend_the_streak_and_a_freeze_bridges_a_gap()
    {
        var p = PlayerIdentity.AfterLiveNight(Fresh(), 0, 0, "2026-09-10");   // streak 1, freeze 1
        p = PlayerIdentity.AfterGame(p, 5, 10, "2026-09-11");               // 2
        p = PlayerIdentity.AfterGame(p, 5, 10, "2026-09-13");               // skipped the 12th: the freeze bridges it
        Assert.Equal(3, p.Streak.Current);
        Assert.Equal(0, p.Streak.Freezes);
        Assert.Equal(3, p.Streak.Longest);
    }

    [Fact]
    public void The_summary_line_reads_like_the_mac_settings_row()
    {
        var p = PlayerIdentity.AfterLiveNight(Fresh(), 8, 10, "2026-09-10");
        var line = PlayerIdentity.SummaryLine(p);
        Assert.StartsWith("Tidbits Rating ", line);
        Assert.Contains("provisional", line);
        Assert.Contains("1-day streak", line);
        Assert.Contains("1 live night", line);
    }
}
