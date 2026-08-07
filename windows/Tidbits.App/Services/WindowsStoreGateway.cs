#if WINDOWS
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Tidbits.Core.Networking;
// NOT `using Windows.Services.Store;` — WinRT also defines a `StorePurchaseResult`, and an
// unqualified import makes every mention of ours ambiguous (CS0104). Alias keeps our
// vocabulary primary and marks each WinRT touch explicitly, which is the point of this file.
using WinRTStore = Windows.Services.Store;

namespace Tidbits.App.Services;

/// The real Microsoft Store edge behind `IStoreGateway` — Class A for `EntitlementStore`, the
/// Windows twin of Apple's `Transaction.currentEntitlements` and Android's Play Billing.
///
/// Per the Windows playbook this file is the ONLY place that touches WinRT: the behaviour lives
/// in `Tidbits.Core` behind the interface (net10.0, Mac-testable), and everything here is a thin
/// Windows-guarded translation. Compiled only for the `net10.0-windows…` TFM, which the csproj
/// selects on a Windows host; the Mac head never sees it and keeps using `NoStoreGateway`.
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
    private readonly Func<IntPtr> _ownerWindow;
    private WinRTStore.StoreContext? _context;

    public WindowsStoreGateway(Func<IntPtr>? ownerWindow = null) =>
        _ownerWindow = ownerWindow ?? (() => IntPtr.Zero);

    /// True when this process actually has a Store licence context. Cheap, and the thing
    /// `GameData` checks before preferring this gateway over `NoStoreGateway`.
    public static bool IsAvailable
    {
        get
        {
            try { return WinRTStore.StoreContext.GetDefault() is not null; }
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

    public async Task<IReadOnlyList<StoreProductInfo>> GetProductsAsync()
    {
        var ctx = Context;
        if (ctx is null) return Array.Empty<StoreProductInfo>();
        try
        {
            // Durable (one-time) and Subscription are separate Store product kinds. Unlike Play
            // Billing — which THROWS on a mixed product list and crashed Android for two
            // releases (Decision 055) — WinRT takes the kinds together, so one query is correct
            // here. Do not "harmonize" this with the Android split.
            var kinds = new[] { "Durable", "UnmanagedConsumable", "Consumable" };
            var result = await ctx.GetStoreProductsAsync(kinds, ClubProducts.All);
            if (result?.Products is null) return Array.Empty<StoreProductInfo>();

            var products = new List<StoreProductInfo>();
            foreach (var kv in result.Products)
            {
                var p = kv.Value;
                if (p is null) continue;
                var price = p.Price?.FormattedPrice ?? string.Empty;
                products.Add(new StoreProductInfo(p.InAppOfferToken, p.Title ?? p.InAppOfferToken, price));
            }
            // Paywall order is the product list's order (lifetime → annual → monthly), not the
            // arbitrary order the Store hands back.
            return products
                .OrderBy(p => ClubProducts.All.ToList().IndexOf(p.Id) is var i && i >= 0 ? i : int.MaxValue)
                .ToList();
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
            // Purchase by StoreId, which means resolving the developer-chosen id first.
            var kinds = new[] { "Durable", "UnmanagedConsumable", "Consumable" };
            var found = await ctx.GetStoreProductsAsync(kinds, new[] { productId });
            var product = found?.Products?.Values?.FirstOrDefault();
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
#endif
