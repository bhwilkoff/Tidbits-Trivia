using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;

namespace Tidbits.HeadlessTests;

/// Renders the Create + Settings tab landings.
public class TabsSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    [AvaloniaFact]
    public void Create_renders()
    {
        var win = new Window { Width = 900, Height = 680, Content = new CreateView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "create.png"));
    }

    [AvaloniaFact]
    public void Settings_renders()
    {
        var win = new Window { Width = 900, Height = 680, Content = new SettingsView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "settings.png"));
    }

    [AvaloniaFact]
    public void Live_setup_renders()
    {
        var win = new Window { Width = 900, Height = 680, Content = new LiveView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "live-setup.png"));
    }
}
