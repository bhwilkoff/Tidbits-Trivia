using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Tidbits.Core.Models;
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
    private static string[] AllText(Control root)
    {
        var win = new Window { Width = 900, Height = 1400, Content = root };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        return win.GetVisualDescendants().OfType<TextBlock>()
                  .Select(t => t.Text ?? "").Where(t => t.Length > 0).ToArray();
    }

    private static string[] ButtonText(Control root)
    {
        var win = new Window { Width = 900, Height = 900, Content = root };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        // A button's label is its string Content OR the TextBlocks inside a richer
        // Content (the Quick Play hero and the JOIN A GAME card are two-line
        // StackPanels). Reading only string Content made a card-shaped button
        // invisible to this test, so a join affordance could be present and the
        // assertion still fail — or absent and, on the Live page, still pass.
        return win.GetVisualDescendants().OfType<Button>()
                  .Select(b => b.Content as string
                               ?? string.Join(" ", b.GetVisualDescendants().OfType<TextBlock>()
                                                     .Select(t => t.Text ?? "")))
                  .Where(t => t.Length > 0).ToArray();
    }

    [AvaloniaFact]
    public void Joining_is_offered_on_Play()
    {
        // A0.4.1 — joining is ALWAYS a Trivia Night action; R-JOIN-1 — and it is a
        // card that says JOIN, second on Play, not a row under the night presets.
        var labels = ButtonText(new PlayView());
        Assert.Contains(labels, t => t.Contains("JOIN A GAME"));
        // Second thing after the hero: the hero, its two secondaries, then join.
        var idx = Array.FindIndex(labels, t => t.Contains("JOIN A GAME"));
        Assert.InRange(idx, 0, 3);
    }

    [AvaloniaFact]
    public void Joining_is_NOT_offered_on_Tidbits_Live()
    {
        // The regression this exists to prevent: putting a join affordance back on
        // the emcee page, which is what implied you need a desktop rig to play.
        Assert.DoesNotContain(ButtonText(new LiveView()), t => t.Contains("Join"));
    }

    [AvaloniaFact]
    public void Hosting_a_night_is_offered_on_Play()
    {
        // Hosting a night needs no desktop rig either — "host from any device" is
        // the whole point of Trivia Night.
        // NOT the bare preset name: Play already listed "Quick Night" as a SOLO
        // night, so asserting on that passed with the hosted presets absent — the
        // A/B caught it. Assert the hosted label specifically.
        var first = NightPlan.Presets[0].Item1;
        Assert.Contains(AllText(new PlayView()), t => t.Contains($"Host {first}"));
    }

    [AvaloniaFact]
    public void Night_presets_are_NOT_on_Tidbits_Live()
    {
        var first = NightPlan.Presets[0].Item1;
        Assert.DoesNotContain(AllText(new LiveView()), t => t.Contains(first));
    }
}
