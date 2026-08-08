namespace Tidbits.Core.Networking;

/// The Microsoft Store IAP seam (docs/CLUB-MONETIZATION-BUILD.md Phase 3, MONETIZATION §6).
/// Per the Windows playbook: BEHAVIOUR is a pure interface here in `Tidbits.Core` (net10.0,
/// Mac-testable), and the actual `Windows.Services.Store.StoreContext` call is a thin
/// Windows-guarded edge (`WindowsStoreGateway`, in a Windows-TFM project — CI-only) that
/// implements this. Everything the app and the EntitlementStore touch is this interface, so
/// the purchase state machine unit-tests off Windows with a fake.
///
/// This is the Class A (local, cryptographically-attested by the Store, offline) source for
/// `EntitlementStore` — the Windows twin of Apple's `Transaction.currentEntitlements`.
public interface IStoreGateway
{
    /// The local Club check. Mirrors Apple's grace semantics EXACTLY:
    ///  - `true`  — the Store attests a non-revoked Club license/add-on.
    ///  - `false` — the Store definitively reports no Club license.
    ///  - `null`  — unknown (no license context yet / not a Store-installed package) → the
    ///              gate treats it as "no clean signal" and FAILS OPEN (never revokes).
    Task<bool?> IsClubEntitledAsync();

    /// The purchasable Club products for the paywall.
    Task<IReadOnlyList<StoreProductInfo>> GetProductsAsync();

    /// Buy a Club product by its Store product id.
    Task<StorePurchaseResult> PurchaseAsync(string productId);
}

/// `BillingPeriod` is the short unit a subscription renews on ("mo", "yr", or "3 mo" when the
/// count is not 1), and null for a one-time product like Founding Member.
public sealed record StoreProductInfo(
    string Id, string Title, string FormattedPrice, string? BillingPeriod = null)
{
    /// Price WITH the billing period for subscriptions ("$29.99/yr"); the bare price for a
    /// one-time product. Store policy — like App Store 3.1.2 and Play's subscriptions policy —
    /// requires the period be shown before purchase, and every store hands back a raw amount
    /// only. The Apple (`priceLabel`) and Android (`periodSuffix`) twins render the same shapes.
    public string PriceLabel => BillingPeriod is null ? FormattedPrice : $"{FormattedPrice}/{BillingPeriod}";
}

public enum StorePurchaseResult { Success, AlreadyPurchased, Cancelled, Pending, Failed, Unavailable }

/// The Club add-on product ids (the Partner Center contract — an owner must create matching
/// add-ons on Store ID 9NRKS9LDRCWC). Developer-chosen in-app product ids; the same three
/// products as every other platform, all granting the one "club" entitlement.
public static class ClubProducts
{
    public const string Lifetime = "club.lifetime";   // durable (non-consumable)
    public const string Annual   = "club.annual";     // subscription
    public const string Monthly  = "club.monthly";    // subscription
    public static readonly IReadOnlyList<string> All = new[] { Lifetime, Annual, Monthly };
}

/// The reflection contract between `GameData` and the `Tidbits.Windows` class library. It has to
/// be reflection rather than a project reference because that library is on the
/// `net10.0-windows10.0.x` TFM and `Tidbits.App` cannot be (docs/WINDOWS-STORE-SUBMISSION.md §7),
/// so nothing but these two strings ties the halves together. They live here, once, and both
/// sides + the packaging test read them — a silent rename is the failure mode this prevents.
public static class WindowsStoreGatewayContract
{
    public const string AssemblyFileName = "Tidbits.Windows.dll";
    public const string TypeName = "Tidbits.Windows.WindowsStoreGateway";
    public const string AvailabilityProperty = "IsAvailable";
}

/// The default gateway on every non-Windows build (the Mac head, headless tests) and any
/// unpackaged .exe with no Store license context. Reports "unknown / unavailable" — so the
/// gate fails OPEN and the paywall shows its graceful empty state. The real
/// `WindowsStoreGateway` replaces it in the packaged MSIX (Phase 3, CI-verified).
public sealed class NoStoreGateway : IStoreGateway
{
    public Task<bool?> IsClubEntitledAsync() => Task.FromResult<bool?>(null);
    public Task<IReadOnlyList<StoreProductInfo>> GetProductsAsync() =>
        Task.FromResult<IReadOnlyList<StoreProductInfo>>(Array.Empty<StoreProductInfo>());
    public Task<StorePurchaseResult> PurchaseAsync(string productId) =>
        Task.FromResult(StorePurchaseResult.Unavailable);
}
