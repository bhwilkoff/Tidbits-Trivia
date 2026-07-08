using System.IO;
using System.Threading.Tasks;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The new host show-nav (skip / back) + manual score override wiring. The live
/// pacing path itself needs the RTDB backend (gated in LiveCockpitSnapshot); here
/// we verify the guards + defaults are safe with no open room.
public class LiveHostControlsTest
{
    private static LiveNightHost NewHost()
    {
        var data = GameData.FromDirectory(Path.Combine(System.AppContext.BaseDirectory, "Data"));
        return new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), data.Provider, "Quick Night");
    }

    [Fact]
    public async Task Controls_are_safe_before_a_room_is_open()
    {
        var host = NewHost();
        Assert.Equal(LiveNightHost.Stage.Lobby, host.CurrentStage);
        Assert.False(host.CanGoBack);            // index 0, not playing

        // In the lobby these are no-ops, not crashes.
        await host.SkipNext();
        await host.GoBack();
        await host.AdjustScore("someuid", +5);
        await host.AdjustScore("", -1);          // empty uid ignored
        await host.StartTimer(30);               // no room / not playing → ignored
        await host.AddTime(15);
        await host.ClearTimer();
        Assert.Null(host.SecondsRemaining);      // no timer running
        Assert.Equal(LiveNightHost.Stage.Lobby, host.CurrentStage);
        Assert.False(host.CanGoBack);
    }

    [Fact]
    public void Answer_distribution_tallies_choices_per_option()
    {
        // 4 options; choices from 6 teams (one unanswered, one out-of-range).
        var choices = new int?[] { 0, 2, 2, 1, null, 9 };
        var tally = LiveNightHost.Tally(4, choices);
        Assert.Equal(new[] { 1, 1, 2, 0 }, tally); // idx0:1, idx1:1, idx2:2, idx3:0
    }

    [Fact]
    public void ViewModel_exposes_the_new_commands()
    {
        var vm = new LiveHostViewModel(NewHost());
        Assert.True(vm.IsLobby);
        Assert.False(vm.CanGoBack);
        // The command surface exists and returns tasks (no throw to construct).
        Assert.NotNull(vm.Skip());
        Assert.NotNull(vm.Back());
        Assert.NotNull(vm.Adjust("uid", 1));
        Assert.NotNull(vm.StartTimer(30));
    }

    [Fact]
    public void Projector_flags_default_off_before_a_live_round()
    {
        var vm = new LiveHostViewModel(NewHost());
        Assert.False(vm.ShowRoundIntro);         // no live question → no round-intro band
        Assert.False(vm.IsWagerRound);
        Assert.False(vm.HasRoundNote);
        Assert.Null(vm.RevealCorrectIndex);      // nothing revealed → no green highlight
    }

    [Fact]
    public void Big_screen_standings_hold_toggles()
    {
        var vm = new LiveHostViewModel(NewHost());
        Assert.False(vm.HoldStandings);
        Assert.Empty(vm.RankedStandings);        // no players yet
        vm.ToggleHold();
        Assert.True(vm.HoldStandings);
        Assert.False(vm.ShowBigScreenStandings); // gated on IsPlaying (still lobby)
        vm.ToggleHold();
        Assert.False(vm.HoldStandings);
    }

    [Fact]
    public void Projector_chrome_is_safe_before_any_players()
    {
        var vm = new LiveHostViewModel(NewHost());
        Assert.False(vm.HasWinner);              // no standings yet
        Assert.Equal("", vm.WinnerLine);
        Assert.Contains("player", vm.QuestionChrome); // renders a chrome string, no throw
    }

    [Fact]
    public void Venue_branding_flows_to_the_view_model()
    {
        var host = NewHost();
        var vm = new LiveHostViewModel(host);
        Assert.False(vm.HasSponsor);
        Assert.Equal(Avalonia.Media.Color.Parse("#FF5C35"), ((Avalonia.Media.SolidColorBrush)vm.BrandBrush).Color); // default

        host.Sponsor = "The Anchor Pub";
        host.BrandHex = "#0047FF";
        Assert.True(vm.HasSponsor);
        Assert.Equal("Brought to you by The Anchor Pub", vm.SponsorLine);
        Assert.Equal(Avalonia.Media.Color.Parse("#0047FF"), ((Avalonia.Media.SolidColorBrush)vm.BrandBrush).Color);

        host.BrandHex = "not-a-color";   // invalid → falls back to the brand coral
        Assert.Equal(Avalonia.Media.Color.Parse("#FF5C35"), ((Avalonia.Media.SolidColorBrush)vm.BrandBrush).Color);

        Assert.False(vm.HasLeadCapture);
        host.LeadCaptureUrl = "https://anchor.pub/list";
        Assert.True(vm.HasLeadCapture);
        Assert.Equal("https://anchor.pub/list", vm.LeadCaptureUrl);
    }

    [Fact]
    public void Answer_lock_defaults_are_safe()
    {
        var host = NewHost();
        var vm = new LiveHostViewModel(host);
        Assert.False(vm.IsLocked);        // not locked before play
        Assert.False(vm.AutoLockDue);     // no deadline → no auto-lock cue
    }

    [Fact]
    public async Task Paper_team_joins_the_standings_and_is_scored()
    {
        var host = NewHost();
        host.AddPaperTeam("");                       // empty ignored
        host.AddPaperTeam("Corner Booth");
        var paper = Assert.Single(host.Standings);
        Assert.Equal("Corner Booth", paper.Name);
        Assert.StartsWith("paper:", paper.Id);
        Assert.Equal(0, paper.Score);

        await host.AdjustScore(paper.Id, 5);         // host scores the paper team
        Assert.Equal(5, host.Standings.Single(j => j.Id == paper.Id).Score);
        await host.AdjustScore(paper.Id, -10);       // clamps at 0
        Assert.Equal(0, host.Standings.Single(j => j.Id == paper.Id).Score);
    }

    [Fact]
    public void Moderation_gate_toggles_a_hidden_name()
    {
        var host = NewHost();
        Assert.False(host.IsHidden("u1"));
        host.ToggleHidden("u1");
        Assert.True(host.IsHidden("u1"));
        host.ToggleHidden("u1");
        Assert.False(host.IsHidden("u1"));   // toggles back
        host.ToggleHidden("");               // empty uid ignored
        Assert.Empty(host.ModeratedStandings); // no teams yet, no throw
    }

    [Fact]
    public async Task Team_merge_folds_and_hides_the_merged_team()
    {
        var host = NewHost();
        await host.MergeTeams("a", "a");        // same team → no-op
        Assert.False(host.IsHidden("a"));
        await host.MergeTeams("", "b");          // empty target → no-op
        Assert.False(host.IsHidden("b"));
        await host.MergeTeams("a", "b");         // fold b into a → b leaves the screen
        Assert.True(host.IsHidden("b"));
    }

    [Fact]
    public void Free_text_review_is_empty_before_reveal_and_leniency_holds()
    {
        var host = NewHost();
        Assert.Empty(host.TextReview);   // not revealed → nothing to review

        // Spelling leniency (the matcher the review uses): case / diacritic / "the"-insensitive.
        var accepted = new[] { "The Beatles", "Café" };
        Assert.True(Tidbits.Core.Store.GameEngine.MatchesAccepted("beatles", accepted));
        Assert.True(Tidbits.Core.Store.GameEngine.MatchesAccepted("cafe", accepted));
        Assert.False(Tidbits.Core.Store.GameEngine.MatchesAccepted("rolling stones", accepted));
    }

    [Fact]
    public void Tie_detection_finds_shared_top_score()
    {
        var J = (string id, int s) => new LiveHostNet.Joined(id, id, s);
        // A clear leader → no tie.
        Assert.Empty(LiveNightHost.Ties(new[] { J("a", 30), J("b", 20) }));
        // Two teams tied at the (non-zero) top → both returned.
        var tie = LiveNightHost.Ties(new[] { J("a", 30), J("b", 30), J("c", 10) });
        Assert.Equal(2, tie.Count);
        // A tie at zero (nobody scored) is not a tie-break situation.
        Assert.Empty(LiveNightHost.Ties(new[] { J("a", 0), J("b", 0) }));
    }

    [Fact]
    public void Cheat_flag_is_clear_before_any_answers()
    {
        var host = NewHost();
        Assert.Equal(0, host.FlaggedCount);
        Assert.False(host.HasFlags);
        var vm = new LiveHostViewModel(host);
        Assert.False(vm.HasFlags);
        Assert.Contains("left the app", vm.FlagLine); // the line renders (0 teams)
    }
}
