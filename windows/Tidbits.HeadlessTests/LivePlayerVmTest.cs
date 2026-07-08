using Tidbits.App.ViewModels;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The join-client view model's Wave A display fields degrade safely before any
/// question is published (the live values come from the SSE-fed pub, gated).
public class LivePlayerVmTest
{
    [Fact]
    public void Display_fields_are_null_safe_before_a_question()
    {
        var vm = new LivePlayerViewModel();
        Assert.True(vm.NotJoined);
        Assert.False(vm.ShowQuestion);
        Assert.False(vm.ShowReveal);
        Assert.Null(vm.SecondsRemaining);   // no deadline yet
        Assert.Null(vm.RevealAnswerLine);
        Assert.False(vm.HasRevealAnswer);
        Assert.False(vm.HasStory);
    }
}
