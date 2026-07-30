using System;
using System.IO;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Styling;
using Avalonia.Threading;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;

namespace Tidbits.HeadlessTests;

/// Passes C and D of docs/WINDOWS-PARITY-AUDIT.md.
///
/// The per-view snapshots render ONE view, at ONE comfortable width, in ONE theme — which is
/// how a blank shell, an unwrapped button row and a dark-mode brand inversion all shipped.
/// These render the WHOLE shell at the narrow floor and in both themes instead.
[Collection("EnvSensitive")]
public class WindowsAuditTest
{
    private static string Art()
    {
        var d = Path.Combine(AppContext.BaseDirectory, "artifacts", "audit");
        Directory.CreateDirectory(d);
        return d;
    }

    private static MainWindow Shell(int w, int h) =>
        new() { DataContext = new MainWindowViewModel(), Width = w, Height = h };

    /// Pass D — both themes. A surface designed for one theme is a finding (§5.5).
    [AvaloniaTheory]
    [InlineData("light")]
    [InlineData("dark")]
    public void Shell_renders_in_both_themes(string theme)
    {
        Application.Current!.RequestedThemeVariant =
            theme == "dark" ? ThemeVariant.Dark : ThemeVariant.Light;
        try
        {
            var win = Shell(1200, 780);
            win.Show();
            Dispatcher.UIThread.RunJobs();
            Assert.NotNull(win.FindControl<ContentControl>("ContentHost")!.Content);
            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), $"shell-{theme}.png"));
        }
        finally { Application.Current.RequestedThemeVariant = ThemeVariant.Default; }
    }

    /// Pass D — Settings carries the account + destructive surfaces, so it gets its own
    /// both-themes render rather than riding on the shell's landing page.
    [AvaloniaTheory]
    [InlineData("light")]
    [InlineData("dark")]
    public void Settings_renders_in_both_themes(string theme)
    {
        Application.Current!.RequestedThemeVariant =
            theme == "dark" ? ThemeVariant.Dark : ThemeVariant.Light;
        try
        {
            var win = new Window { Width = 900, Height = 800, Content = new SettingsView() };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), $"settings-{theme}.png"));
        }
        finally { Application.Current.RequestedThemeVariant = ThemeVariant.Default; }
    }

    /// Pass C — 820 is the floor (the nav is compact and the content column is genuinely
    /// tight). Anything that clips or overflows shows up here first.
    [AvaloniaTheory]
    [InlineData(820)]
    [InlineData(1000)]
    [InlineData(1440)]
    public void Shell_renders_at_width(int w)
    {
        var win = Shell(w, 720);
        win.Show();
        Dispatcher.UIThread.RunJobs();
        Assert.NotNull(win.FindControl<ContentControl>("ContentHost")!.Content);
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), $"shell-w{w}.png"));
    }
}
