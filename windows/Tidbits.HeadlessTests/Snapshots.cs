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
}
