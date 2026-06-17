#if os(iOS)
import SwiftUI

// MARK: - Root View (iPhone + iPad)

/// iOS 26 baseline — use native APIs directly. The shape below maps to
/// Android `NavigationSuiteScaffold` (size-class-adaptive nav surface)
/// and web's nav. Same verbs, native idioms.
struct ContentView_iOS: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // For multi-tab apps, prefer TabView(.sidebarAdaptable) at
        // iOS 26+ — bottom tab bar on iPhone, sidebar on iPad, from ONE
        // hierarchy. Use Tab(role: .search) for the explore/find tab so
        // the search bar gets full-screen morph for free. Adapt to
        // regular width via @Environment(\.horizontalSizeClass), never
        // UIDevice checks.
        //
        // Navigation rules that survived four shipped apps:
        // - One NavigationPath per tab, owned by the @Observable store.
        // - ONE shared destination registry (a single ViewModifier that
        //   declares every navigationDestination), applied to every
        //   tab's NavigationStack — never per-view destinations. This is
        //   what lets any surface push any screen from any tab.
        // - Settings is a sheet behind a toolbar gear, not a tab — the
        //   tab bar is reserved for content verbs.
        @Bindable var bindableStore = store
        NavigationStack(path: $bindableStore.navigationPath) {
            DetailView()
                .navigationDestination(for: String.self) { destination in
                    // FILL IN: your navigation destinations
                    Text(destination)
                }
        }
    }
}

// MARK: - Detail View (main content area)

struct DetailView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            // FILL IN: switch on store.selectedTab to show different views
            Text("Home View")
        }
        // iOS 26 resolves .regularMaterial to Liquid Glass automatically.
        // Don't override with custom .background — let the system apply
        // navigation chrome materials (DESIGN.md "navigation chrome only").
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // iOS 26 native scroll-edge effect — use .hard for dense grids,
        // .soft for reading content.
        // .scrollEdgeEffectStyle(.hard, for: .top)
    }
}
#endif
