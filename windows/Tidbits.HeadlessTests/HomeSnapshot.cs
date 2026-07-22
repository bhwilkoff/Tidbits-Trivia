using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Services;
using Tidbits.App.Views;
using Tidbits.Core.Models;

namespace Tidbits.HeadlessTests;

/// Renders the Home/Play surface (Quick Play hero + Daily + category + mode grid).
[Collection("EnvSensitive")]
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
        using var _ = new EnvVarScope("TIDBITS_CLUB", "1");
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

    /// Non-member state: the CLUB chip + a real or honest-static preview line — never
    /// a blank wall (CLAUDE.md gating convention).
    [AvaloniaFact]
    public void Play_home_renders_the_weak_spot_arena_card_for_a_non_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "0");
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

    /// Member, no run in progress: the Marathon card renders "Play" with no
    /// RESUME chip (docs/CLUB-FEATURES-BUILD.md "Feature 3").
    [AvaloniaFact]
    public void Play_home_renders_the_marathon_card_for_a_member_with_no_run()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "1");
        GameData.Shared.Value.Records.SaveMarathonRun(null);

        var view = new PlayView();
        var win = new Window { Width = 900, Height = 900, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
        Assert.Contains("MARATHON", texts);
        Assert.DoesNotContain("RESUME", texts);
        var buttons = win.GetVisualDescendants().OfType<Button>()
            .Where(b => (b.Content as string) == "Play").ToList();
        Assert.NotEmpty(buttons);

        ScrollToWeakSpotCard(win);
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home-marathon-member-fresh.png"));
    }

    /// Member WITH an in-progress run: "Question 6 of 10 — tap to resume", a
    /// RESUME chip, and a "Resume" action — the load-bearing resume-across-
    /// sessions mechanic surfaced on Home/Play.
    [AvaloniaFact]
    public void Play_home_renders_the_marathon_card_in_resume_state_for_a_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "1");
        var records = GameData.Shared.Value.Records;
        try
        {
            var run = new MarathonRun("seed", Enumerable.Range(0, 10).Select(i => $"q{i}").ToList()) { CurrentIndex = 5 };
            records.SaveMarathonRun(run);

            var view = new PlayView();
            var win = new Window { Width = 900, Height = 900, Content = view };
            win.Show();
            Dispatcher.UIThread.RunJobs();

            var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
            Assert.Contains("MARATHON", texts);
            Assert.Contains("RESUME", texts);
            Assert.Contains(texts, t => t is not null && t.Contains("Question 6 of 10"));
            var buttons = win.GetVisualDescendants().OfType<Button>()
                .Where(b => (b.Content as string) == "Resume").ToList();
            Assert.NotEmpty(buttons);

            ScrollToWeakSpotCard(win);
            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home-marathon-member-resume.png"));
        }
        finally { records.SaveMarathonRun(null); }
    }

    /// Non-member: the CLUB chip + a real-or-honest preview — never a blank wall.
    [AvaloniaFact]
    public void Play_home_renders_the_marathon_card_for_a_non_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "0");
        var view = new PlayView();
        var win = new Window { Width = 900, Height = 900, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
        Assert.Contains("MARATHON", texts);
        Assert.Contains("CLUB", texts);
        var buttons = win.GetVisualDescendants().OfType<Button>()
            .Where(b => (b.Content as string) == "Join Club").ToList();
        Assert.NotEmpty(buttons);

        ScrollToWeakSpotCard(win);
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home-marathon-non-member.png"));
    }
}
