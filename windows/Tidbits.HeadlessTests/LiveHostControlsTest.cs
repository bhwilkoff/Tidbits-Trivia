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
    public void Projector_chrome_is_safe_before_any_players()
    {
        var vm = new LiveHostViewModel(NewHost());
        Assert.False(vm.HasWinner);              // no standings yet
        Assert.Equal("", vm.WinnerLine);
        Assert.Contains("player", vm.QuestionChrome); // renders a chrome string, no throw
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
