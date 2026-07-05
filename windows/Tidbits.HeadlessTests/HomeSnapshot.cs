using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;

namespace Tidbits.HeadlessTests;

/// Renders the Home/Play surface (Quick Play hero + Daily + category + mode grid).
public class HomeSnapshot
{
    [AvaloniaFact]
    public void Play_home_renders()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var win = new Window { Width = 900, Height = 680, Content = new PlayView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "home.png"));
    }
}
