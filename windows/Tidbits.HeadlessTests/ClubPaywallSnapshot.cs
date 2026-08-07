using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Renders the paywall exactly as a Microsoft Store customer sees it TODAY — `NoStoreGateway`
/// ships inside the MSIX (there is no `WindowsStoreGateway` yet), so `products` is empty and
/// the empty-state note is the whole purchase story. Observed, not assumed: the previous copy
/// told Store customers Club "is available in the Microsoft Store edition" while they were
/// running it.
[Collection("EnvSensitive")]
public class ClubPaywallSnapshot
{
    [AvaloniaFact]
    public void Store_edition_paywall_png()
    {
        var panel = ClubPaywallUi.BuildPanel(
            isClub: false,
            products: Array.Empty<StoreProductInfo>(),
            busyProductId: null,
            message: null,
            onPurchase: _ => { },
            onRestore: () => { });

        var win = new Window { Width = 520, Height = 900, Content = panel };
        win.Show();
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "club-paywall-store-edition.png"));
    }
}
