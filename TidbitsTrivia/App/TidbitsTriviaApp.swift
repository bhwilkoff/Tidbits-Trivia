import SwiftUI
import SwiftData

@main
struct TidbitsTriviaApp: App {
    @State private var store = AppStore()
    @State private var gameCenter = GameCenterManager.shared
    #if os(iOS)
    /// Captures the APNs device token (docs/PUSH-CONTRACT.md). Inert until the owner
    /// enables the Push capability on the App ID.
    @UIApplicationDelegateAdaptor(PushManager.self) private var pushDelegate
    #endif
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
        // Before the first render: a fresh simulator install otherwise opens on the
        // first-run walkthrough, which is what the Home + Create store shots came back as.
        if DebugHooks.skipOnboarding { UserDefaults.standard.set(true, forKey: "tidbits.hasOnboarded") }
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
                .environment(EntitlementStore.shared)
                .task {
                    gameCenter.authenticate()
                    StoreKitStore.shared.start()                   // install the local (StoreKit) Club check + listen for renewals
                    // Seed BEFORE bootstrap: on macOS the awaited network bootstrap can take
                    // longer than a screenshot capture waits, so a seed placed after it had
                    // simply not run yet and Records rendered "0 days". Seeding first also
                    // short-circuits bootstrap entirely for screenshot runs (it returns early
                    // once seeded), which makes the capture deterministic and offline.
                    if let n = DebugHooks.seedRecords, n > 0 { DebugHooks.applyIdentitySeed(n) }
                    await PlayerIdentityStore.shared.bootstrap()   // stable uid → portable profile
                    await EntitlementStore.shared.refresh()        // Club status (local store || web entitlement)
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
                    case "quiz": store.post(.quiz(url.lastPathComponent))
                    case "item": store.post(.item(url.lastPathComponent))
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
                .environment(PlayerIdentityStore.shared)   // CRASH FIX: the Settings scene does NOT inherit the
                .environment(store)                        // WindowGroup's .environment injections — a missing
                .environment(EntitlementStore.shared)      // @Environment(PlayerIdentityStore) was a fatal crash on open.
                .tint(Tidbits.Palette.blue)                // Same rule for the Club paywall's EntitlementStore.
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)

        // The Tidbits Live projector output — its own window; drag to the
        // second display. Reads the shared host session (§A1.1/A1.2).
        //
        // `Window`, NOT `WindowGroup`. A WindowGroup permits unlimited instances,
        // so every `openWindow(id:)` opened ANOTHER projector: hosting three
        // nights left three windows, macOS restored them all on the next launch,
        // and a measured session had six stacked up behind the main window. A
        // projector is a single physical screen — the scene should be singular
        // too, and `Window` makes `openWindow` focus the existing one instead.
        //
        // Restoration is off for the same reason: a projector belongs on screen
        // only while a night is being hosted. Reopening it at launch, with no
        // session to show, is how the app came back up on the idle splash
        // ("The host will start the night shortly") with no host anywhere.
        Window("Tidbits Live", id: "tidbits-bigscreen") {
            LiveBigScreen_macOS()
                .environment(liveCoordinator)
                .tint(Tidbits.Palette.blue)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
        .windowResizability(.contentMinSize)   // projector must resize to any display
        .defaultSize(width: 1280, height: 720)
        .restorationBehavior(.disabled)
        #endif
    }

    /// Plain on-disk store with an in-memory fallback so the app ALWAYS
    /// launches. NOTE: a real Apple TV needs an App Group `ModelConfiguration`
    /// here (Application Support isn't writable on tvOS hardware — Decision
    /// 017). That path is deferred to the tvOS milestone because
    /// `groupContainer:` *traps* (not throws) when the App Group entitlement
    /// isn't present, so it can't ship before the entitlement is configured.
    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([GameRecord.self, MissedFact.self, DailyStreak.self, CalibrationTally.self, SeenStory.self,
                             MarathonRun.self, MarathonScore.self,
                             ExpeditionProgress.self, ExpeditionCertificate.self,
                             LinkWallResult.self, SavedQuizRecord.self])
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
