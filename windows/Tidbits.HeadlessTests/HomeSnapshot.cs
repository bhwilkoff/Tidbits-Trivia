using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;

namespace Tidbits.HeadlessTests;

/// Renders the Home/Play surface (Quick Play hero + Daily + category + mode grid).
public class HomeSnapshot
{
    private static string Art()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    [AvaloniaFact]
    public void Play_home_renders()
    {
        var win = new Window { Width = 900, Height = 680, Content = new PlayView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home.png"));
    }

    /// The Weak-Spot Arena card in MEMBER state (docs/CLUB-FEATURES-BUILD.md "Feature
    /// 1") — TIDBITS_CLUB=1 forces the debug override so the card renders "Play"
    /// with no CLUB chip, without depending on a real purchase or the network.
    [AvaloniaFact]
    public void Play_home_renders_the_weak_spot_arena_card_for_a_member()
    {
        var previous = Environment.GetEnvironmentVariable("TIDBITS_CLUB");
        try
        {
            Environment.SetEnvironmentVariable("TIDBITS_CLUB", "1");
            var view = new PlayView();
            var win = new Window { Width = 900, Height = 900, Content = view };
            win.Show();
            Dispatcher.UIThread.RunJobs();

            var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
            Assert.Contains("WEAK-SPOT ARENA", texts);
            Assert.DoesNotContain("CLUB", texts); // member -> no chip
            var buttons = win.GetVisualDescendants().OfType<Button>()
                .Where(b => (b.Content as string) == "Play").ToList();
            Assert.NotEmpty(buttons);

            ScrollToWeakSpotCard(win);
            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home-weak-spot-member.png"));
        }
        finally { Environment.SetEnvironmentVariable("TIDBITS_CLUB", previous); }
    }

    /// Non-member state: the CLUB chip + a real or honest-static preview line — never
    /// a blank wall (CLAUDE.md gating convention).
    [AvaloniaFact]
    public void Play_home_renders_the_weak_spot_arena_card_for_a_non_member()
    {
        var previous = Environment.GetEnvironmentVariable("TIDBITS_CLUB");
        try
        {
            Environment.SetEnvironmentVariable("TIDBITS_CLUB", "0");
            var view = new PlayView();
            var win = new Window { Width = 900, Height = 900, Content = view };
            win.Show();
            Dispatcher.UIThread.RunJobs();

            var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
            Assert.Contains("WEAK-SPOT ARENA", texts);
            Assert.Contains("CLUB", texts);
            var buttons = win.GetVisualDescendants().OfType<Button>()
                .Where(b => (b.Content as string) == "Join Club").ToList();
            Assert.NotEmpty(buttons);

            ScrollToWeakSpotCard(win);
            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home-weak-spot-non-member.png"));
        }
        finally { Environment.SetEnvironmentVariable("TIDBITS_CLUB", previous); }
    }

    /// The card sits below the Daily archive (14 rows) — scroll the Home
    /// ScrollViewer to the bottom so the render actually shows it (it renders fine;
    /// it's just off the first screenful, same as the tvOS hero the doc notes).
    private static void ScrollToWeakSpotCard(Window win)
    {
        var scroller = win.GetVisualDescendants().OfType<ScrollViewer>().FirstOrDefault();
        if (scroller is null) return;
        scroller.ScrollToEnd();
        Dispatcher.UIThread.RunJobs();
    }
}
