using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// G3 negative marking (COMPETITOR-SCAN — QuizXpress offers it; pub hosts use it
/// to stop blind guessing on a four-option question).
///
/// The rule that matters is not "wrong answers lose points" — it is WHO can lose
/// them. A team that submitted nothing is declining to guess, not answering
/// wrongly, and penalising silence would punish the table whose phone died. The
/// implementation gets this for free on both desktops because the scoring loop
/// iterates the ANSWERS, but that is an accident of structure, so it is pinned
/// here rather than left to be refactored away.
public class NegativeMarkingTest
{
    [Fact]
    public void Off_by_default()
    {
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), null!, "n");
        Assert.Equal(0, host.WrongAnswerPenalty);
    }

    [Fact]
    public void The_cockpit_control_cycles_and_labels_itself()
    {
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), null!, "n");
        var vm = new LiveHostViewModel(host);
        Assert.Equal("No penalty", vm.PenaltyLabel);
        vm.CyclePenalty();
        Assert.Equal(1, host.WrongAnswerPenalty);
        Assert.Equal("-1/wrong", vm.PenaltyLabel);
        vm.CyclePenalty();
        Assert.Equal(2, host.WrongAnswerPenalty);
        vm.CyclePenalty();                       // wraps back to off
        Assert.Equal(0, host.WrongAnswerPenalty);
        Assert.Equal("No penalty", vm.PenaltyLabel);
    }
}
