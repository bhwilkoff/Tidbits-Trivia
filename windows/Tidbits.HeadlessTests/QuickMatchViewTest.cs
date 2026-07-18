using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

public class QuickMatchViewTest
{
    [Fact]
    public void Result_headline_reads_the_outcome()
    {
        Assert.Equal("You win!", QuickMatchViewModel.ResultHeadline(QuickOutcome.Win));
        Assert.Equal("You lost", QuickMatchViewModel.ResultHeadline(QuickOutcome.Lose));
        Assert.Equal("Dead tie", QuickMatchViewModel.ResultHeadline(QuickOutcome.Tie));
    }

    [AvaloniaFact]
    public void Searching_screen_renders()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        // Default stage is Searching; no FindMatch call, so no network.
        var vm = new QuickMatchViewModel(new QuickMatchClient(GameData.Shared.Value.Rtdb), GameData.Shared.Value);
        Assert.True(vm.IsSearching);
        Assert.Equal("Finding an opponent…", vm.StatusLine);

        var win = new Window { Width = 900, Height = 620, Content = new QuickMatchView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "quickmatch-searching.png"));
    }
}
