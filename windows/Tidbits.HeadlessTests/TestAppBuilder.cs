using Avalonia;
using Avalonia.Headless;
using Tidbits.HeadlessTests;

[assembly: Avalonia.Headless.AvaloniaTestApplication(typeof(TestAppBuilder))]

namespace Tidbits.HeadlessTests;

/// The headless app builder (WINDOWS-PLAYBOOK §3). UseSkia + UseHeadlessDrawing=false
/// render REAL pixels to a bitmap on any OS — so we can capture a PNG of the Windows UI
/// from this Mac and Read it. This is the observability spine of the whole project.
public sealed class TestAppBuilder
{
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<Tidbits.App.App>()
            .UseSkia()
            .WithInterFont()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false });
}
