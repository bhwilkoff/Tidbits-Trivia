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
