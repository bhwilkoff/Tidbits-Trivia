using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Data.Core;
using Avalonia.Data.Core.Plugins;
using System.Linq;
using Avalonia.Markup.Xaml;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;

namespace Tidbits.App;

public partial class App : Application
{
    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        // Core cannot encode images; the App lends it Skia so a package picture can
        // reach the phones as a small data URL (LIVE-PACKAGE-FORMAT §5.3).
        Tidbits.Core.Networking.LiveMediaStore.DataUrlProvider = Services.MediaPublisher.DataUrl;
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow
            {
                DataContext = new MainWindowViewModel(),
            };
        }

        base.OnFrameworkInitializationCompleted();
    }
}