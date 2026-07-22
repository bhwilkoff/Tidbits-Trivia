using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Avalonia.Controls;
using Tidbits.App.Services;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

/// The Tidbits Club join surface (docs/CLUB-MARKETING.md, Decision 047). Reachable from
/// Settings via a FAContentDialog — never an interstitial. Wires `ClubPaywallUi`'s static
/// content to `GameData.Shared` (the shared `IStoreGateway` seam, the same instance the
/// entitlement gate reads) and rebuilds on purchase/restore.
///
/// R-MON-2: purchase is via the Store gateway only; "already bought elsewhere?" is
/// **sign in** (Settings), never a code/key/coupon field.
public partial class ClubPaywallView : UserControl
{
    private IReadOnlyList<StoreProductInfo> _products = Array.Empty<StoreProductInfo>();
    private string? _busyProductId;
    private string? _message;

    public ClubPaywallView()
    {
        InitializeComponent();
        Rebuild();
        _ = LoadProducts();
    }

    private async Task LoadProducts()
    {
        var g = GameData.Shared.Value;
        try { _products = await g.Store.GetProductsAsync(); }
        catch { _products = Array.Empty<StoreProductInfo>(); }
        Rebuild();
    }

    private void Rebuild()
    {
        var g = GameData.Shared.Value;
        Root.Children.Clear();
        Root.Children.Add(ClubPaywallUi.BuildPanel(
            isClub: g.Entitlement.IsClub,
            products: _products,
            busyProductId: _busyProductId,
            message: _message,
            onPurchase: async id => await Purchase(id),
            onRestore: async () => await Restore()));
    }

    private async Task Purchase(string productId)
    {
        var g = GameData.Shared.Value;
        _busyProductId = productId;
        _message = null;
        Rebuild();

        StorePurchaseResult result;
        try { result = await g.Store.PurchaseAsync(productId); }
        catch { result = StorePurchaseResult.Failed; }

        _message = result switch
        {
            StorePurchaseResult.Success or StorePurchaseResult.AlreadyPurchased => null,
            StorePurchaseResult.Pending => "Your purchase is pending approval. Club unlocks once it's approved.",
            StorePurchaseResult.Cancelled => null,
            _ => "That didn't go through. No charge was made — try again.",
        };

        if (result is StorePurchaseResult.Success or StorePurchaseResult.AlreadyPurchased)
            await g.Entitlement.RefreshAsync();

        _busyProductId = null;
        Rebuild();
    }

    private async Task Restore()
    {
        var g = GameData.Shared.Value;
        await g.Entitlement.RefreshAsync();
        _message = g.Entitlement.IsClub ? null : "No purchase found to restore.";
        Rebuild();
    }
}
