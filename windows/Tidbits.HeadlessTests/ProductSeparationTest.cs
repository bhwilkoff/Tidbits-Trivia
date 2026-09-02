using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Trivia Night and Tidbits Live are two products (WINDOWS-DESIGN 6.0,
/// macOS-DESIGN A0.4).
///
/// Trivia Night is for everyone and hosts from ANY device. Tidbits Live is the
/// desktop-only pub-trivia rig. Windows had them on one page, so joining a
/// friend's night appeared to require the emcee rig — the owner reported exactly
/// this confusion. Nothing could catch it: the snapshot tests render the page and
/// save a PNG, so they passed identically before and after the split.
public class ProductSeparationTest
{
    private static string[] ButtonText(Control root)
    {
        var win = new Window { Width = 900, Height = 900, Content = root };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        return win.GetVisualDescendants().OfType<Button>()
                  .Select(b => b.Content as string ?? "")
                  .Where(t => t.Length > 0).ToArray();
    }

    [AvaloniaFact]
    public void Joining_is_offered_on_Play()
    {
        // A0.4.1 — joining is ALWAYS a Trivia Night action.
        Assert.Contains(ButtonText(new PlayView()), t => t.Contains("Join a night"));
    }

    [AvaloniaFact]
    public void Joining_is_NOT_offered_on_Tidbits_Live()
    {
        // The regression this exists to prevent: putting a join affordance back on
        // the emcee page, which is what implied you need a desktop rig to play.
        Assert.DoesNotContain(ButtonText(new LiveView()), t => t.Contains("Join"));
    }
}
