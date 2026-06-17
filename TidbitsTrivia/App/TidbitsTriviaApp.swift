import SwiftUI
import SwiftData

@main
struct TidbitsTriviaApp: App {
    @State private var store = AppStore()
    @State private var gameCenter = GameCenterManager.shared

    init() {
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(gameCenter)
                .tint(Tidbits.Palette.blue)
                .task { gameCenter.authenticate() }
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
        .modelContainer(Self.makeModelContainer())
    }

    /// Plain on-disk store with an in-memory fallback so the app ALWAYS
    /// launches. NOTE: a real Apple TV needs an App Group `ModelConfiguration`
    /// here (Application Support isn't writable on tvOS hardware — Decision
    /// 017). That path is deferred to the tvOS milestone because
    /// `groupContainer:` *traps* (not throws) when the App Group entitlement
    /// isn't present, so it can't ship before the entitlement is configured.
    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([GameRecord.self, MissedFact.self, DailyStreak.self])
        if let plain = try? ModelContainer(for: schema) { return plain }
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
        #else
        ContentView_iOS()
        #endif
    }
}
