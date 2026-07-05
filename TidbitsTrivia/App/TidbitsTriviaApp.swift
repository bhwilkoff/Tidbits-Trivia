import SwiftUI
import SwiftData

@main
struct TidbitsTriviaApp: App {
    @State private var store = AppStore()
    @State private var gameCenter = GameCenterManager.shared
    #if os(macOS)
    /// Shares the active Tidbits Live host session between the cockpit and the
    /// projector (big-screen) windows (§A1.1).
    @State private var liveCoordinator = LiveHostCoordinator()
    #endif
    /// One container shared across scenes (the Mac Settings scene resets records
    /// through the SAME store as the main window).
    private let modelContainer = TidbitsTriviaApp.makeModelContainer()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(gameCenter)
                #if os(macOS)
                .environment(liveCoordinator)
                #endif
                .tint(Tidbits.Palette.blue)
                .environment(PlayerIdentityStore.shared)
                .task {
                    gameCenter.authenticate()
                    await PlayerIdentityStore.shared.bootstrap()   // stable uid → portable profile
                }
                #if os(macOS)
                .task {   // design-observability: render the cockpit to a PNG + exit (never in normal use)
                    if let path = ProcessInfo.processInfo.environment["TIDBITS_SNAPSHOT"] {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        LiveCockpitSnapshot.writePNG(to: path)
                        exit(0)
                    }
                }
                #endif
                // .onOpenURL fires for BOTH custom schemes and Universal
                // Links on iOS 17+. Route into the inbox, never directly.
                .onOpenURL { url in
                    switch url.host {
                    case "daily": store.post(.daily)
                    case "topic": store.post(.topic(url.lastPathComponent))
                    case "category": store.post(.category(url.lastPathComponent))
                    default: break
                    }
                }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .commands { TidbitsCommands() }   // ⌘N → New Quick Play (§B1a)
        // Resize freely down to the content's min — WITHOUT this the default
        // (.automatic) lets fixed content sizes fight the window drag (the
        // cockpit + projector felt "stuck" when resizing).
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        #endif

        #if os(macOS)
        Settings {
            SettingsView_macOS()
                .environment(gameCenter)
                .tint(Tidbits.Palette.blue)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)

        // The Tidbits Live projector output — its own window; drag to the
        // second display. Reads the shared host session (§A1.1/A1.2).
        WindowGroup(id: "tidbits-bigscreen") {
            LiveBigScreen_macOS()
                .environment(liveCoordinator)
                .tint(Tidbits.Palette.blue)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
        .windowResizability(.contentMinSize)   // projector must resize to any display
        .defaultSize(width: 1280, height: 720)
        #endif
    }

    /// Plain on-disk store with an in-memory fallback so the app ALWAYS
    /// launches. NOTE: a real Apple TV needs an App Group `ModelConfiguration`
    /// here (Application Support isn't writable on tvOS hardware — Decision
    /// 017). That path is deferred to the tvOS milestone because
    /// `groupContainer:` *traps* (not throws) when the App Group entitlement
    /// isn't present, so it can't ship before the entitlement is configured.
    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([GameRecord.self, MissedFact.self, DailyStreak.self, CalibrationTally.self])
        #if os(tvOS)
        // Application Support is NOT writable on real Apple TV (Decision 017;
        // the simulator is lenient and won't catch it). Persist in Caches,
        // which IS writable on device. (An App Group store would survive
        // cache purges — add it with the entitlement later.)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let url = caches.appendingPathComponent("tidbits.store")
            if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(url: url)) {
                return c
            }
        }
        #else
        if let plain = try? ModelContainer(for: schema) { return plain }
        #endif
        return try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

/// One entry point, two native view trees. Core/ is shared; the
/// experience is not.
struct RootView: View {
    var body: some View {
        #if os(tvOS)
        ContentView_tvOS()
        #elseif os(macOS)
        // The Tidbits sticker design is a light "cream paper" theme — pin light
        // appearance so the Mac chrome (title bar, sidebar, List, fields) matches
        // instead of following system dark mode (the iOS §7.2 analog).
        ContentView_macOS().preferredColorScheme(.light)
        #else
        ContentView_iOS()
        #endif
    }
}
