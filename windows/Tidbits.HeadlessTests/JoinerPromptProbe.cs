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

/// The Windows joiner's PROMPT and the Decision 060 clip card, on the glass —
/// with the question arriving AFTER the view is up, the way it does in a room.
/// On the real box the joiner showed the options and the clip card and a blank
/// band where the question should be, and no room name: `Client.Pub.Prompt`
/// bound through an object that never changes, so it never re-read.
public class JoinerPromptProbe
{
    [AvaloniaFact]
    public void The_question_and_the_clip_offer_are_on_the_joiner()
    {
        var vm = new LivePlayerViewModel();
        vm.Client.JoinedForTesting("QATEST");
        var view = new JoinPlayerView { DataContext = vm };
        var win = new Window { Width = 900, Height = 700, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        // The question lands after the join, as on the wire.
        vm.Client.PubForTesting = new LiveRoom.Pub
        {
            Round = 1, RoundTitle = "Warm Up", Qid = "r0q0", QNum = 1, QTotal = 2,
            Phase = LiveRoom.Phase.Question, Prompt = "Which kingdom minted the first coins?", Format = "classic",
            Options = new[] { "Lydia", "Portugal", "Iran", "USSR" },
            Media = new LiveRoom.Media { Kind = "audio", Url = "room:abc", Mime = "audio/mp4", Name = "tune", Bytes = 195_121 },
        };
        vm.Client.JoinedForTesting("QATEST");   // fires Changed → the VM re-notifies
        Dispatcher.UIThread.RunJobs();
        var texts = win.GetVisualDescendants().OfType<TextBlock>()
                       .Where(t => t.IsEffectivelyVisible && !string.IsNullOrWhiteSpace(t.Text)).Select(t => t.Text!).ToList();
        var dump = string.Join(" | ", texts);
        Assert.True(texts.Any(t => t.Contains("Listen to the clip")), "no clip offer: " + dump);
        Assert.True(texts.Any(t => t.Contains("tune")), "no clip name: " + dump);
        Assert.True(texts.Any(t => t.Contains("Which kingdom")), "no prompt: " + dump);

        // On REVEAL the prompt stays, and the Wikipedia source line appears.
        vm.Client.PubForTesting = vm.Client.Pub! with
        {
            Phase = LiveRoom.Phase.Reveal, AnswerIndex = 0, Story = "Electrum coins.",
            Source = new LiveRoom.Source { Title = "Lydia", Url = "https://en.wikipedia.org/wiki/Lydia" },
        };
        vm.Client.JoinedForTesting("QATEST");
        Dispatcher.UIThread.RunJobs();
        var reveal = win.GetVisualDescendants().OfType<TextBlock>()
                        .Where(t => t.IsEffectivelyVisible && !string.IsNullOrWhiteSpace(t.Text)).Select(t => t.Text!).ToList();
        Assert.True(reveal.Any(t => t.Contains("Which kingdom")), "prompt gone on reveal: " + string.Join(" | ", reveal));
        Assert.True(reveal.Any(t => t.Contains("Learn more on Wikipedia") && t.Contains("Lydia")), "no source line: " + string.Join(" | ", reveal));
    }
}
