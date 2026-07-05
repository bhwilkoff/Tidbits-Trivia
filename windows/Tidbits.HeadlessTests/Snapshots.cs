using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Styling;
using Avalonia.Threading;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;

namespace Tidbits.HeadlessTests;

/// Renders each surface to a PNG the developer can Read. Doubles as a visual-regression
/// harness once baselines are committed. Run: `dotnet test` (Mac or windows-latest CI).
public class Snapshots
{
    private static string ArtifactsDir()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    [AvaloniaTheory]
    [InlineData("Light")]
    [InlineData("Dark")]
    public void MainWindow_shell(string theme)
    {
        var win = new MainWindow
        {
            DataContext = new MainWindowViewModel(),
            RequestedThemeVariant = theme == "Dark" ? ThemeVariant.Dark : ThemeVariant.Light,
        };
        win.Show();

        // Pump the dispatcher so Loaded fires (initial nav selection → content) and layout settles.
        Dispatcher.UIThread.RunJobs();

        var frame = win.CaptureRenderedFrame();
        frame!.Save(Path.Combine(ArtifactsDir(), $"mainwindow-{theme}.png"));
    }

    // Proves the frame of EVERY Mac tab renders (the bootstrap-loop goal).
    [AvaloniaTheory]
    [InlineData("play")]
    [InlineData("records")]
    [InlineData("create")]
    [InlineData("live")]
    [InlineData("settings")]
    public void Section_frame(string key)
    {
        var sections = new MainWindowViewModel().Sections;
        var win = new Window
        {
            Width = 900,
            Height = 680,
            Content = new SectionFrameView { DataContext = sections[key] },
        };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(ArtifactsDir(), $"section-{key}.png"));
    }
}
