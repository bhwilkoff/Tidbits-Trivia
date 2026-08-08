using System.Reflection;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// The Microsoft Store IAP edge is reached by REFLECTION, not by a project reference:
/// `WindowsStoreGateway` needs the `net10.0-windows10.0.x` TFM for `Windows.Services.Store`, a
/// `net10.0` app may not reference a `net10.0-windows` library, and putting that TFM on
/// Tidbits.App broke every Windows publish (docs/WINDOWS-STORE-SUBMISSION.md §7).
///
/// That makes two strings — an assembly file name and a type name — the only thing holding Club
/// purchases together on Windows, with no compiler between them. And the failure is SILENT in the
/// worst possible way: `GameData.ResolveStoreGateway` swallows everything and falls back to
/// `NoStoreGateway`, which answers "unknown", which fails OPEN — so a broken contract looks
/// exactly like a healthy unpackaged build, all the way into the Store.
///
/// A real purchase can only be verified by installing the certified MSIX from the Store
/// (StoreContext returns nothing without a package identity). These tests cover everything
/// UNDERNEATH that gap: the assembly loads, the type is there under the contract name, it really
/// implements the interface, and its constructor takes the owner-HWND callback GameData passes.
public class WindowsStoreGatewayContractTests
{
    private static string GatewayDll => Path.Combine(
        AppContext.BaseDirectory, WindowsStoreGatewayContract.AssemblyFileName);

    [Fact]
    public void The_gateway_assembly_is_built_alongside_the_app()
    {
        Assert.True(File.Exists(GatewayDll),
            $"{WindowsStoreGatewayContract.AssemblyFileName} is missing. windows-store.yml stages " +
            "it into the MSIX; if it stops being built, Club IAP silently disappears on Windows.");
    }

    [Fact]
    public void The_contract_type_name_resolves_in_that_assembly()
    {
        var type = Assembly.LoadFrom(GatewayDll).GetType(WindowsStoreGatewayContract.TypeName);
        Assert.NotNull(type);
    }

    [Fact]
    public void The_gateway_implements_the_interface_the_app_casts_to()
    {
        var type = Assembly.LoadFrom(GatewayDll).GetType(WindowsStoreGatewayContract.TypeName)!;
        // GameData's `is IStoreGateway gateway` pattern is what actually decides whether the
        // real gateway is used; a type that loads but does not implement this is discarded.
        Assert.True(typeof(IStoreGateway).IsAssignableFrom(type));
    }

    [Fact]
    public void The_constructor_takes_the_owner_window_callback()
    {
        var type = Assembly.LoadFrom(GatewayDll).GetType(WindowsStoreGatewayContract.TypeName)!;
        // Activator.CreateInstance(type, (Func<IntPtr>)Win32HostInterop.MainWindowHandle) —
        // StoreContext throws when it shows purchase UI with no owner HWND.
        Assert.NotNull(type.GetConstructor(new[] { typeof(Func<IntPtr>) }));
    }

    [Fact]
    public void The_availability_probe_is_a_public_static_bool()
    {
        var type = Assembly.LoadFrom(GatewayDll).GetType(WindowsStoreGatewayContract.TypeName)!;
        var probe = type.GetProperty(WindowsStoreGatewayContract.AvailabilityProperty,
            BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(probe);
        // GameData reads it as `bool?`; a non-bool would deserialize to null and disable IAP.
        Assert.Equal(typeof(bool), probe!.PropertyType);
    }

    [Fact]
    public void Club_product_ids_are_the_three_the_Store_carries()
    {
        // These are the developer-chosen ids the add-ons were created under in Partner Center,
        // matched against StoreProduct.InAppOfferToken. A mismatch here is an empty paywall with
        // no error anywhere — the Store simply reports no products.
        Assert.Equal(new[] { "club.lifetime", "club.annual", "club.monthly" }, ClubProducts.All);
    }
}
