using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// Renders the host cockpit with a REAL open room + a live-published first question
/// (gated behind TIDBITS_LIVE_SMOKE=1 — needs network + the live backend).
public class LiveCockpitSnapshot
{
    [AvaloniaFact]
    public async Task Cockpit_renders_with_a_real_room()
    {
        if (Environment.GetEnvironmentVariable("TIDBITS_LIVE_SMOKE") != "1") return;

        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var data = GameData.FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), data.Provider, "Quick Night");
        var vm = new LiveHostViewModel(host);
        var win = new Window { Width = 1000, Height = 680, Content = new LiveCockpitView { DataContext = vm } };
        win.Show();

        await host.Start(); // opens a real room + publishes the first question
        Assert.True(host.IsOpen);
        Assert.NotNull(host.Current);
        Dispatcher.UIThread.RunJobs();

        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "live-cockpit.png"));

        // Show-nav (3.17): skip advances without reveal; back returns to it.
        int startIdx = host.Index;
        await host.SkipNext();
        Assert.True(host.Index == startIdx + 1);
        Assert.True(host.CanGoBack);
        await host.GoBack();
        Assert.Equal(startIdx, host.Index);
        Assert.False(host.Revealed);

        // Live countdown (3.23): starting a timer sets a deadline; extending grows it.
        await host.StartTimer(30);
        Assert.NotNull(host.SecondsRemaining);
        Assert.InRange(host.SecondsRemaining!.Value, 25, 30);
        await host.AddTime(30);
        Assert.InRange(host.SecondsRemaining!.Value, 55, 60);
        await host.ClearTimer();
        Assert.Null(host.SecondsRemaining);

        // The projector big-screen view (rendered directly; the 2nd-monitor placement is
        // Windows-runtime and CI-verified separately).
        var proj = new Window { Width = 1280, Height = 720, Content = new ProjectorView { DataContext = vm } };
        proj.Show();
        Dispatcher.UIThread.RunJobs();
        proj.CaptureRenderedFrame()!.Save(Path.Combine(dir, "live-projector.png"));

        // A real joiner receives the question — render the join surface.
        var player = new LivePlayerViewModel();
        await player.Join(host.Code, "Team Bravo");
        var t0 = Environment.TickCount64;
        while (player.Client.Pub is null && Environment.TickCount64 - t0 < 10000) await Task.Delay(150);
        var joinWin = new Window { Width = 560, Height = 680, Content = new JoinPlayerView { DataContext = player } };
        joinWin.Show();
        Dispatcher.UIThread.RunJobs();
        joinWin.CaptureRenderedFrame()!.Save(Path.Combine(dir, "live-join.png"));

        await player.Leave();
        await host.Close();
    }
}
