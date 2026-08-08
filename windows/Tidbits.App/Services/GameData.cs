using System;
using System.IO;
using Tidbits.Core.Data;
using Tidbits.Core.Store;

namespace Tidbits.App.Services;

/// Loads the bundled question data once and hands out a shared QuestionProvider +
/// new GameEngines. Data/ is the shared assets JSONs, copied to output at build.
public sealed class GameData
{
    public QuestionSources Sources { get; }
    public QuestionProvider Provider { get; }
    public RecordsStore Records { get; }
    public GameSettings Settings { get; }
    public DailyLog Daily { get; }
    public SavedSetsStore SavedSets { get; }
    /// Saved quizzes on the shared `quiz.v1` contract (docs/QUIZ-CONTRACT.md).
    /// Supersedes SavedSets, which is web-and-Windows-only and unshareable; the
    /// migration below converts anything a returning player already had.
    public QuizStore Quizzes { get; }
    public PresetsStore Presets { get; }
    public Tidbits.Core.Networking.LiveEventStore LiveEvents { get; }
    public Tidbits.Core.Networking.FriendStore Friends { get; }
    public Tidbits.Core.Networking.PlayerIdentityStore Identity { get; }
    public Tidbits.Core.Networking.DuelStore Duels { get; }
    /// Shared anon-authed RTDB client for non-Live networked features (duels).
    // Tokens ride DPAPI on Windows (1.22) — the refresh token is a long-lived
    // credential and must not sit on disk in cleartext. Falls back to the file store
    // off Windows so the Mac head + headless tests keep working.
    public Tidbits.Core.Networking.FirebaseRtdb Rtdb { get; } = new(tokens: new DpapiTokenStore());
    /// The account layer (portable-identity spine) — anon uid until sign-in, then keyed by
    /// the VERIFIED email so this machine shares one profile with the player's phone/web.
    /// Also the key an entitlement resolves against (Decision 047).
    public Tidbits.Core.Networking.AccountIdentity Account { get; }
    /// Tidbits Club gate (Decision 047) — remote-only on Windows until the Microsoft
    /// Store `StoreContext` local check lands (Phase 3). Mirrors web/Kotlin/Swift.
    public Tidbits.Core.Networking.EntitlementStore Entitlement { get; }
    /// The Microsoft Store IAP seam (paywall + gate share this ONE instance). NoStoreGateway
    /// on the direct-download .exe / Mac head; the WindowsStoreGateway (Microsoft Store
    /// StoreContext) replaces it in the packaged MSIX (Phase 3) — the paywall UI never
    /// changes, it just starts seeing real products/purchases.
    public Tidbits.Core.Networking.IStoreGateway Store { get; }
    public string PlayerName => Identity.Current.Name;
    public Tidbits.Core.Networking.SfxBoard Sfx { get; }
    /// The Wave B media engine (host-only) — lazy so we don't spin LibVLC unless hosting.
    private AvPlayer? _av;
    public AvPlayer Av => _av ??= new AvPlayer();

    private GameData(QuestionSources sources)
    {
        Sources = sources;
        Provider = new QuestionProvider(sources);
        var appDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia");
        Records = new RecordsStore(Path.Combine(appDir, "records.json"));
        Settings = new GameSettings(Path.Combine(appDir, "settings.json"));
        Daily = new DailyLog(Path.Combine(appDir, "daily.json"));
        SavedSets = new SavedSetsStore(Path.Combine(appDir, "saved-sets.json"));
        Quizzes = new QuizStore(Path.Combine(appDir, "quizzes"));
        Presets = new PresetsStore(Path.Combine(appDir, "presets.json"));
        LiveEvents = new Tidbits.Core.Networking.LiveEventStore(Path.Combine(appDir, "live-events.json"));
        Friends = new Tidbits.Core.Networking.FriendStore(Path.Combine(appDir, "friends.json"));
        Identity = new Tidbits.Core.Networking.PlayerIdentityStore(Path.Combine(appDir, "profile.json"));
        Duels = new Tidbits.Core.Networking.DuelStore(Path.Combine(appDir, "duels.json"));
        Sfx = new Tidbits.Core.Networking.SfxBoard(Path.Combine(appDir, "sfx-board.json"));
        Account = new Tidbits.Core.Networking.AccountIdentity(Rtdb, new DpapiTokenStore());
        // ONE instance shared by the entitlement gate and the paywall UI.
        // WindowsStoreGateway only when this process actually has a Store licence context —
        // i.e. the packaged MSIX. The direct-download .exe and the Mac head have none, and
        // StoreContext there throws rather than reporting "no", so NoStoreGateway (which
        // answers "unknown", and therefore fails OPEN) stays the correct choice for them.
        Store = ResolveStoreGateway();
        Entitlement = new Tidbits.Core.Networking.EntitlementStore(Rtdb, Account, Store);
    }

    /// Loads `Tidbits.Windows.WindowsStoreGateway` REFLECTIVELY, because it cannot be
    /// project-referenced: it needs the `net10.0-windows10.0.x` TFM for `Windows.Services.Store`,
    /// a `net10.0` app may not reference a `net10.0-windows` library, and putting that TFM on
    /// Tidbits.App broke every Windows publish (MSB4062 — docs/WINDOWS-STORE-SUBMISSION.md §7).
    /// The MSIX publish drops Tidbits.Windows.dll beside the app; every other build simply has no
    /// such file and falls through, which is the correct answer for the Mac head, the headless
    /// tests, and the direct-download .exe alike.
    ///
    /// `LoadFrom`, not `Load`: the assembly is deliberately not a reference, so it is absent from
    /// deps.json and the default resolver would never find it. Its own dependency on
    /// Tidbits.Core resolves to the copy already loaded, so `IStoreGateway` is the same type.
    private static Tidbits.Core.Networking.IStoreGateway ResolveStoreGateway()
    {
        try
        {
            var dll = Path.Combine(AppContext.BaseDirectory,
                Tidbits.Core.Networking.WindowsStoreGatewayContract.AssemblyFileName);
            if (OperatingSystem.IsWindows() && File.Exists(dll))
            {
                var type = System.Reflection.Assembly.LoadFrom(dll)
                    .GetType(Tidbits.Core.Networking.WindowsStoreGatewayContract.TypeName);
                // IsAvailable is the packaged-MSIX check. The .exe and the Mac head have no Store
                // licence context, and StoreContext there throws rather than reporting "no", so
                // NoStoreGateway (which answers "unknown", and therefore fails OPEN) is right.
                var available = type?
                    .GetProperty(Tidbits.Core.Networking.WindowsStoreGatewayContract.AvailabilityProperty)?
                    .GetValue(null) as bool?;
                if (type is not null && available == true &&
                    Activator.CreateInstance(type, new object?[] { (Func<IntPtr>)Win32HostInterop.MainWindowHandle })
                        is Tidbits.Core.Networking.IStoreGateway gateway)
                {
                    return gateway;
                }
            }
        }
        catch { /* fall through — a store gateway must never stop the app starting */ }

        return new Tidbits.Core.Networking.NoStoreGateway();
    }

    public static GameData FromDirectory(string dir) => new(QuestionSources.LoadFromDirectory(dir));

    /// The app's shared instance (reads the bundled Data/ dir on first use).
    public static readonly Lazy<GameData> Shared =
        new(() => FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data")));

    public GameEngine NewEngine() => new(Provider, Sources.Difficulty);
}
