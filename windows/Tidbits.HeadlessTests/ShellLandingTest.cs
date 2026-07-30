using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// WINDOWS-DESIGN §7.14: the detail pane must render on load, never as a side effect of
/// `SelectionChanged`. FANavigationView can settle on the first item without raising the
/// event, which shipped a Windows build whose whole right-hand side stayed blank until the
/// user clicked the sidebar. Assert the landing content exists with NO interaction at all.
[Collection("EnvSensitive")]
public class ShellLandingTest
{
    [AvaloniaFact]
    public void Detail_pane_has_content_without_touching_the_nav()
    {
        var win = new MainWindow { DataContext = new MainWindowViewModel(), Width = 1100, Height = 720 };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var host = win.FindControl<ContentControl>("ContentHost");
        Assert.NotNull(host);
        Assert.NotNull(host!.Content);
        Assert.IsType<PlayView>(host.Content);

        var dir = Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "shell-landing.png"));
    }
}
