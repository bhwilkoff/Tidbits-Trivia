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

/// 3.75 — the Windows joiner answers EVERY format. Until 2026-09-10 it drew answer
/// buttons from Pub.Options and nothing else, so a Name-It, Closest, Ordering,
/// Matching or Name-as-many question showed a prompt with no way to answer it.
public class JoinAnswerFormatsTest
{
    private static LiveRoom.Pub Base(string fmt) => new()
    {
        Round = 1, RoundTitle = "R", Qid = "r0q0", QNum = 1, QTotal = 5,
        Phase = LiveRoom.Phase.Question, Prompt = "Who?", Format = fmt,
    };

    private static Window Show(LiveRoom.Pub pub)
    {
        var vm = new LivePlayerViewModel();
        vm.Client.PubForTesting = pub;
        var win = new Window { Width = 420, Height = 760, Content = new JoinPlayerView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        return win;
    }

    private static T? Find<T>(Window w, string name) where T : Control =>
        w.GetVisualDescendants().OfType<T>().FirstOrDefault(c => c.Name == name);
    private static Button? ButtonNamed(Window w, string content) =>
        w.GetVisualDescendants().OfType<Button>().FirstOrDefault(b => (b.Content as string) == content);

    [AvaloniaFact]
    public void A_typed_question_gets_a_text_box_and_a_submit()
    {
        var win = Show(Base("typeAnswer"));
        Assert.NotNull(Find<TextBox>(win, "AnswerText"));
        Assert.NotNull(ButtonNamed(win, "Submit"));
    }

    [AvaloniaFact]
    public void A_closest_question_gets_a_slider_and_the_midpoint()
    {
        var win = Show(Base("closest") with { Numeric = new LiveRoom.Numeric { Min = 1900, Max = 2000, Step = 1, Unit = "" } });
        Assert.NotNull(win.GetVisualDescendants().OfType<Slider>().FirstOrDefault());
        Assert.Equal("1950", Find<TextBlock>(win, "AnswerNumber")!.Text);
        Assert.NotNull(ButtonNamed(win, "Submit"));
    }

    [AvaloniaFact]
    public void An_ordering_question_lists_every_item_with_move_buttons()
    {
        var win = Show(Base("ordering") with { OrderItems = new[] { "b", "a", "c" } });
        var list = Find<StackPanel>(win, "AnswerOrder");
        Assert.NotNull(list);
        Assert.Equal(3, list!.Children.Count);
        Assert.NotNull(ButtonNamed(win, "Submit order"));
        Assert.Equal(6, win.GetVisualDescendants().OfType<Button>().Count(b => (b.Content as string) is "▲" or "▼"));
    }

    [AvaloniaFact]
    public void A_matching_question_offers_a_pick_per_key_and_submits_only_when_complete()
    {
        var win = Show(Base("matching") with { MatchKeys = new[] { "France", "Peru" }, MatchValues = new[] { "Lima", "Paris" } });
        Assert.Equal(2, win.GetVisualDescendants().OfType<ComboBox>().Count());
        var submit = ButtonNamed(win, "Submit matches");
        Assert.NotNull(submit);
        Assert.False(submit!.IsEnabled, "nothing chosen yet");
    }

    [AvaloniaFact]
    public void A_name_as_many_question_has_an_add_row_and_done()
    {
        var win = Show(Base("enumerate") with { EnumTarget = 5 });
        Assert.Contains("0/5", Find<TextBlock>(win, "AnswerEnumHead")!.Text);
        Assert.NotNull(Find<TextBox>(win, "AnswerEnumBox"));
        Assert.NotNull(ButtonNamed(win, "Done"));
    }

    [AvaloniaFact]
    public void A_choice_question_still_gets_its_buttons_and_no_text_box()
    {
        var win = Show(Base("classic") with { Options = new[] { "a", "b", "c", "d" } });
        Assert.Null(Find<TextBox>(win, "AnswerText"));
        Assert.Equal(4, win.GetVisualDescendants().OfType<Button>().Count(b => (b.Content as string) is "a" or "b" or "c" or "d"));
    }
}
