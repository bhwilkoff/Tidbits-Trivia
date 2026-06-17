import SwiftUI
import SwiftData

@main
struct AppNameApp: App {
    init() {
        // 100 MB memory / 500 MB disk — mirrors Android's Coil 3 config
        // so image cache behavior is symmetric across platforms.
        URLCache.shared = URLCache(
            memoryCapacity: 100_000_000,
            diskCapacity: 500_000_000
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppStore())
                // .environment(AuthManager())  // FILL IN: your auth manager
                // Universal Links + custom-scheme dispatch.
                // On iOS 17+, .onOpenURL fires for BOTH Universal Links
                // AND custom schemes — do NOT use .onContinueUserActivity,
                // which silently misses Universal Links.
                //
                // Don't route directly from here. Drop the parsed request
                // into an "intent inbox" the root view consumes once
                // foregrounded — Siri intents, widget URLs, and Top Shelf
                // deep links all arrive through the same inbox, so routing
                // lives in exactly one place.
                .onOpenURL { url in
                    // FILL IN: route by url.scheme, then by path
                    // switch url.scheme {
                    // case "https": IntentInbox.shared.post(.universalLink(url))
                    // case "appname": IntentInbox.shared.post(.customScheme(url))
                    // default: break
                    // }
                }
        }
        // SwiftData: do NOT use the bare .modelContainer(for:) modifier if
        // this target includes tvOS. Its default store lives in Application
        // Support, which is NOT writable on a real Apple TV (the simulator
        // is lenient — the crash only appears on hardware; Decision 017).
        // Build the container explicitly with an App Group configuration
        // and a fallback chain so the app always launches:
        //
        // .modelContainer(Self.makeModelContainer())
        //
        // static func makeModelContainer() -> ModelContainer {
        //     let schema = Schema([/* your models */])
        //     if let groupContainer = try? ModelContainer(
        //         for: schema,
        //         configurations: ModelConfiguration(
        //             groupContainer: .identifier("group.com.example.appname"))) {
        //         return groupContainer
        //     }
        //     if let plain = try? ModelContainer(for: schema) { return plain }
        //     return try! ModelContainer(
        //         for: schema,
        //         configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        // }
    }
}

/// One entry point, two native view trees. Core/ is shared; the
/// experience is not — never port one platform's layout to the other.
struct RootView: View {
    var body: some View {
        #if os(tvOS)
        ContentView_tvOS()
        #else
        ContentView_iOS()
        #endif
    }
}
