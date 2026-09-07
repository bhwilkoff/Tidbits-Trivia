using Avalonia;
using System;

namespace Tidbits.App;

sealed class Program
{
    // Initialization code. Don't use any Avalonia, third-party APIs or any
    // SynchronizationContext-reliant code before AppMain is called: things aren't initialized
    // yet and stuff might break.
    /// A deep-link URL the app was launched with (tidbitstrivia://… or the https
    /// twin), consumed by MainWindow once shown. Set once at startup.
    public static string? LaunchUrl { get; private set; }

    /// A `.tidbits` package the app was launched to open (double-click / Open With
    /// through the MSIX file-type association), consumed by the Live view once
    /// shown (LIVE-PACKAGE-FORMAT §8.2). Set once at startup.
    public static string? LaunchPackage { get; private set; }

    [STAThread]
    public static void Main(string[] args)
    {
        LaunchUrl = System.Array.Find(args, a =>
            a.StartsWith("tidbitstrivia:", StringComparison.OrdinalIgnoreCase)
            || a.StartsWith("https://tidbitstrivia.com", StringComparison.OrdinalIgnoreCase));
        LaunchPackage = System.Array.Find(args, a =>
            a.EndsWith(".tidbits", StringComparison.OrdinalIgnoreCase) && System.IO.File.Exists(a));
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
#if DEBUG
            .WithDeveloperTools()
#endif
            .WithInterFont()
            .LogToTrace();
}
