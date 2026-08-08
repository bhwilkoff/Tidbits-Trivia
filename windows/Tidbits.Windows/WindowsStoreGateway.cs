using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Tidbits.Core.Networking;
// NOT `using Windows.Services.Store;` — WinRT also defines a `StorePurchaseResult`, and an
// unqualified import makes every mention of ours ambiguous (CS0104). Alias keeps our
// vocabulary primary and marks each WinRT touch explicitly, which is the point of this file.
using WinRTStore = Windows.Services.Store;

namespace Tidbits.Windows;

/// The real Microsoft Store edge behind `IStoreGateway` — Class A for `EntitlementStore`, the
/// Windows twin of Apple's `Transaction.currentEntitlements` and Android's Play Billing.
///
/// Per the Windows playbook this file is the ONLY place that touches WinRT: the behaviour lives
/// in `Tidbits.Core` behind the interface (net10.0, Mac-testable), and everything here is a thin
/// Windows-guarded translation. It lives in its own `net10.0-windows…` class library because that
/// TFM cannot go on `Tidbits.App` without breaking every publish (§7) — `GameData` loads this
/// type reflectively when the assembly is present, and falls back to `NoStoreGateway` when it
/// is not (the Mac head, the headless tests).
///
/// Two things about `StoreContext` that shape every method below:
///
///  1. **It is unusable outside a Store-installed package.** On the direct-download .exe there
///     is no licence context, and calls throw or return nothing. So every entry point degrades
///     to the same "unknown" answer `NoStoreGateway` gives — which the gate treats as no clean
///     signal and FAILS OPEN. A Club member must never be un-Clubbed by a plumbing error.
///  2. **It needs a window handle on desktop.** `StoreContext.GetDefault()` is fine for reads,
///     but `RequestPurchaseAsync` shows Store UI and throws without an owner HWND. The handle
///     comes from `Win32HostInterop`, which is where every other Win32 edge already lives.
public sealed class WindowsStoreGateway : IStoreGateway
{
    // GameData finds this type by NAME, so a rename here would silently un-Club every Store
    // customer with nothing failing anywhere. Asserting the contract inside the namespace it
    // describes makes the two move together: change the namespace or the class name without
    // changing WindowsStoreGatewayContract and this stops compiling.
    // (Division, not `? "ok" : null` — a const string may legally BE null, so that version
    // compiled happily when the names disagreed. Constant division by zero is CS0020.)
    private const int ContractSelfCheck = 1 / (
        WindowsStoreGatewayContract.TypeName ==
            nameof(Tidbits) + "." + nameof(Windows) + "." + nameof(WindowsStoreGateway)
        ? 1 : 0);

    private readonly Func<IntPtr> _ownerWindow;
    private WinRTStore.StoreContext? _context;

    public WindowsStoreGateway(Func<IntPtr>? ownerWindow = null) =>
        _ownerWindow = ownerWindow ?? (() => IntPtr.Zero);

    /// True when this process actually has a Store licence context. Cheap, and the thing
    /// `GameData` checks before preferring this gateway over `NoStoreGateway`.
    ///
    /// `Package.Current` is the discriminator, not `StoreContext.GetDefault()`: the latter can
    /// hand back a context in an unpackaged process and only fail later, one call deeper. A
    /// process with no package identity throws here, which is the clean "not the MSIX" answer.
    public static bool IsAvailable
    {
        get
        {
            try
            {
                if (global::Windows.ApplicationModel.Package.Current is null) return false;
                return WinRTStore.StoreContext.GetDefault() is not null;
            }
            catch { return false; }
        }
    }

    private WinRTStore.StoreContext? Context
    {
        get
        {
            if (_context is not null) return _context;
            try { _context = WinRTStore.StoreContext.GetDefault(); } catch { _context = null; }
            if (_context is not null)
            {
                var hwnd = SafeOwnerWindow();
                if (hwnd != IntPtr.Zero)
                {
                    try { WinRT.Interop.InitializeWithWindow.Initialize(_context, hwnd); } catch { }
                }
            }
            return _context;
        }
    }

    private IntPtr SafeOwnerWindow()
    {
        try { return _ownerWindow(); } catch { return IntPtr.Zero; }
    }

    /// null = unknown (not Store-installed, or the query failed) → the gate fails OPEN.
    /// false is returned ONLY on a clean answer that names no Club add-on.
    public async Task<bool?> IsClubEntitledAsync()
    {
        var ctx = Context;
        if (ctx is null) return null;
        try
        {
            var license = await ctx.GetAppLicenseAsync();
            if (license is null) return null;

            foreach (var kv in license.AddOnLicenses)
            {
                var sku = kv.Value;
                if (sku is null || !sku.IsActive) continue;
                // InAppOfferToken is the developer-chosen product id (ClubProducts.*), which is
                // what we control; the StoreId is Microsoft's and differs per product.
                if (ClubProducts.All.Contains(sku.InAppOfferToken)) return true;
            }
            return false;
        }
        catch
        {
            return null;   // transient / no context — never a negative
        }
    }

    /// The add-on kinds Club can ship as. A Store **subscription is a Durable add-on** carrying
    /// `StoreSku.SubscriptionInfo` — "Subscription" is not a product kind and passing it throws.
    /// So one query covers lifetime AND both plans: the opposite of Play Billing, which THROWS on
    /// a mixed product list and crashed Android for two releases (Decision 055). Do not
    /// "harmonize" this with the Android split.
    private static readonly string[] AddOnKinds = { "Durable", "UnmanagedConsumable", "Consumable" };

    /// Every Club add-on the Store associates with this app, in paywall order.
    ///
    /// `GetAssociatedStoreProductsAsync`, NOT `GetStoreProductsAsync`: the latter's second
    /// argument is Microsoft's **Store IDs** (`9N…`), not the developer-chosen product ids we
    /// control, so querying it with `ClubProducts.All` matches nothing and returns an empty
    /// paywall with no error anywhere. The association query returns the app's own add-ons and
    /// we filter on `InAppOfferToken`, which IS our id.
    private async Task<IReadOnlyList<WinRTStore.StoreProduct>> ClubProductsAsync(WinRTStore.StoreContext ctx)
    {
        var result = await ctx.GetAssociatedStoreProductsAsync(AddOnKinds);
        if (result?.Products is null) return Array.Empty<WinRTStore.StoreProduct>();

        return result.Products.Values
            .Where(p => p is not null && ClubProducts.All.Contains(p.InAppOfferToken))
            // Paywall order is our product list's order (lifetime → annual → monthly), not the
            // arbitrary order the Store hands back.
            .OrderBy(p => ClubProducts.All.ToList().IndexOf(p.InAppOfferToken))
            .ToList();
    }

    public async Task<IReadOnlyList<StoreProductInfo>> GetProductsAsync()
    {
        var ctx = Context;
        if (ctx is null) return Array.Empty<StoreProductInfo>();
        try
        {
            var products = new List<StoreProductInfo>();
            foreach (var p in await ClubProductsAsync(ctx))
            {
                var price = p.Price?.FormattedPrice ?? string.Empty;
                products.Add(new StoreProductInfo(p.InAppOfferToken, p.Title ?? p.InAppOfferToken, price));
            }
            return products;
        }
        catch
        {
            return Array.Empty<StoreProductInfo>();
        }
    }

    public async Task<StorePurchaseResult> PurchaseAsync(string productId)
    {
        var ctx = Context;
        if (ctx is null) return StorePurchaseResult.Unavailable;
        try
        {
            var product = (await ClubProductsAsync(ctx))
                .FirstOrDefault(p => p.InAppOfferToken == productId);
            if (product is null) return StorePurchaseResult.Unavailable;

            var purchase = await product.RequestPurchaseAsync();
            return purchase?.Status switch
            {
                WinRTStore.StorePurchaseStatus.Succeeded => StorePurchaseResult.Success,
                WinRTStore.StorePurchaseStatus.AlreadyPurchased => StorePurchaseResult.AlreadyPurchased,
                WinRTStore.StorePurchaseStatus.NotPurchased => StorePurchaseResult.Cancelled,
                WinRTStore.StorePurchaseStatus.NetworkError => StorePurchaseResult.Failed,
                WinRTStore.StorePurchaseStatus.ServerError => StorePurchaseResult.Failed,
                _ => StorePurchaseResult.Failed,
            };
        }
        catch
        {
            return StorePurchaseResult.Failed;
        }
    }
}
