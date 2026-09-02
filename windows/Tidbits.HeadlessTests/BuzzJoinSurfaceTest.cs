using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// On a buzz round the player's whole answer UI is ONE button.
///
/// The thing that breaks is not whether a BUZZ button exists — it is whether the
/// normal answer UI is still there beside it. A player who can both buzz AND pick
/// an option on a buzz round has two ways to answer and the host adjudicates the
/// wrong one, so the options panel must be GONE, not merely ignored.
public class BuzzJoinSurfaceTest
{
    private static LiveRoom.Pub Question(bool buzz) => new()
    {
        Round = 1, RoundTitle = "R", Qid = "r0q0", QNum = 1, QTotal = 5,
        Phase = LiveRoom.Phase.Question, Prompt = "Who?", Format = "classic",
        Options = new[] { "a", "b", "c", "d" },
        Buzz = buzz ? true : null,
    };

    private static (Window win, LivePlayerViewModel vm) Show(bool buzz)
    {
        var vm = new LivePlayerViewModel();
        vm.Client.PubForTesting = Question(buzz);
        var win = new Window { Width = 420, Height = 760, Content = new JoinPlayerView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        return (win, vm);
    }

    [AvaloniaFact]
    public void A_buzz_question_shows_BUZZ_and_hides_the_options()
    {
        var (win, vm) = Show(buzz: true);
        Assert.True(vm.IsBuzz, "precondition: the VM must see a buzz question, or nothing below can fail");

        var buzzBtn = win.GetVisualDescendants().OfType<Button>()
                         .FirstOrDefault(b => (b.Content as string) == "BUZZ");
        Assert.NotNull(buzzBtn);
        Assert.True(buzzBtn!.IsVisible);

        var options = win.GetVisualDescendants().OfType<StackPanel>()
                         .FirstOrDefault(p => p.Name == "OptionsPanel");
        Assert.NotNull(options);
        Assert.False(options!.IsVisible, "the answer options must be GONE on a buzz round, not merely ignored");
    }

    [AvaloniaFact]
    public void An_ordinary_question_is_unchanged()
    {
        var (win, vm) = Show(buzz: false);
        Assert.False(vm.IsBuzz);
        var options = win.GetVisualDescendants().OfType<StackPanel>()
                         .FirstOrDefault(p => p.Name == "OptionsPanel");
        Assert.True(options!.IsVisible);
    }
}
