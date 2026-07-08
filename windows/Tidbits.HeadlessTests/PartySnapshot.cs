using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;

namespace Tidbits.HeadlessTests;

/// Pass & Play setup renders (name entry for 2–4 players). The turn/handoff/
/// scoreboard flow is event-driven over the shared question set.
public class PartySnapshot
{
    [AvaloniaFact]
    public void Setup_renders()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        var win = new Window { Width = 620, Height = 560, Content = new PartyView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "party-setup.png"));
    }
}
