using Tidbits.App.Services;
using Xunit;
using static Tidbits.App.Services.Win32HostInterop;

namespace Tidbits.HeadlessTests;

/// The taskbar indicator's BEHAVIOUR (§6.2: a host with the cockpit minimized still
/// reads round state off the taskbar). The mapping is a pure function so it is
/// verifiable off Windows; only the final P/Invoke is Windows-gated, and that is
/// exercised by the windows-latest CI run.
public class Win32InteropTest
{
    [Fact]
    public void A_running_clock_shows_remaining_time()
    {
        var (state, value, max) = RoundIndicator(secondsRemaining: 18, secondsTotal: 30,
                                                 teamsAnswered: 0, teamsTotal: 4);
        Assert.Equal(TaskbarProgress.Normal, state);
        Assert.Equal(18ul, value);
        Assert.Equal(30ul, max);
    }

    [Fact]
    public void An_expired_clock_is_an_error_not_a_full_bar()
    {
        // Pencils down should read as an alert. A "full" green bar would say the
        // opposite of what happened.
        var (state, value, max) = RoundIndicator(0, 30, 2, 4);
        Assert.Equal(TaskbarProgress.Error, state);
        Assert.Equal(max, value);
    }

    [Fact]
    public void The_clock_outranks_the_team_count()
    {
        var (state, value, max) = RoundIndicator(secondsRemaining: 5, secondsTotal: 20,
                                                 teamsAnswered: 4, teamsTotal: 4);
        Assert.Equal(TaskbarProgress.Normal, state);
        Assert.Equal(5ul, value);
        Assert.Equal(20ul, max);
    }

    [Fact]
    public void Without_a_clock_it_shows_teams_answered()
    {
        var (state, value, max) = RoundIndicator(null, null, teamsAnswered: 2, teamsTotal: 5);
        Assert.Equal(TaskbarProgress.Normal, state);
        Assert.Equal(2ul, value);
        Assert.Equal(5ul, max);
    }

    [Fact]
    public void All_teams_answered_is_the_reveal_cue()
    {
        var (state, value, max) = RoundIndicator(null, null, teamsAnswered: 5, teamsTotal: 5);
        Assert.Equal(TaskbarProgress.Paused, state);
        Assert.Equal(5ul, value);
        Assert.Equal(5ul, max);
    }

    [Fact]
    public void Nothing_running_shows_nothing()
    {
        var (state, _, _) = RoundIndicator(null, null, 0, 0);
        Assert.Equal(TaskbarProgress.None, state);
    }

    [Theory]
    [InlineData(-5, 30)]   // a clock that overran
    [InlineData(45, 30)]   // more remaining than total
    public void Out_of_range_clocks_are_clamped_not_thrown(int remaining, int total)
    {
        var (_, value, max) = RoundIndicator(remaining, total, 0, 0);
        Assert.InRange(value, 0ul, max);
    }

    [Fact]
    public void Team_counts_beyond_the_total_are_clamped()
    {
        var (state, value, max) = RoundIndicator(null, null, teamsAnswered: 9, teamsTotal: 4);
        Assert.Equal(TaskbarProgress.Paused, state);
        Assert.Equal(4ul, value);
        Assert.Equal(4ul, max);
    }
}
