using System;
using System.IO;
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

/// The projector reflects the Wave D venue branding — a white-label accent color
/// and a sponsor footer — even before a room opens (lobby stage).
public class ProjectorBrandSnapshot
{
    [AvaloniaFact]
    public void Branded_projector_lobby_renders()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var data = GameData.FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), data.Provider, "Friday Night")
        {
            Sponsor = "The Anchor Pub",
            BrandHex = "#0047FF",
        };
        var vm = new LiveHostViewModel(host);
        var win = new Window { Width = 1280, Height = 720, Content = new ProjectorView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "projector-brand.png"));
    }
}
