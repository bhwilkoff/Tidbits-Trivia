using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;

namespace Tidbits.HeadlessTests;

/// The Tidbits Live host setup — presets plus the night options (category, speed
/// bonus, "I'll play too"). No network: the setup surface builds offline.
public class LiveSetupSnapshot
{
    [AvaloniaFact]
    public void Setup_renders_night_options_and_presets()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var win = new Window { Width = 700, Height = 640, Content = new LiveView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "live-setup.png"));
    }
}
