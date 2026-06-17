#if os(tvOS)
import SwiftUI

// MARK: - Root View (Apple TV)
//
// Read the `tvos-platform-patterns` skill before building on this.
// The five unbreakable rules:
//   1. Dark-first, 29pt body floor, 90/60pt safe area.
//   2. Back is sacred — never intercept outside player/modal.
//   3. Every focusable reachable from every other via arrows.
//   4. Never .buttonStyle(.plain) — it silently destroys focusability.
//   5. Preserve focus across state changes by stable ID, not index.

struct ContentView_tvOS: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // TabView(.sidebarAdaptable) is the native tvOS 18+/26 shell:
        // a sidebar that collapses to icons and auto-expands on focus
        // entry. Reserve it for content verbs; Settings is a sidebar
        // FOOTER item or a Home toolbar destination, not a peer tab.
        //
        // Navigation rules (same Core store as iOS, different shell):
        // - One NavigationStack per tab; RESET a tab's path when the
        //   user leaves it via the sidebar, or stale push-state greets
        //   the next visit.
        // - The first screen's hero claims initial focus exactly ONCE
        //   (a hasClaimedInitialFocus guard) — a bare .task re-fires
        //   when lazy views recycle and yanks focus back mid-browse.
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeView_tvOS()
                }
            }
            // FILL IN: more content-verb tabs
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    // .searchable gives the directional keyboard AND
                    // free Siri dictation — never invent a grid keyboard.
                    Text("Search")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

// MARK: - Home (starter shape)

struct HomeView_tvOS: View {
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 60) {
                // Shelf pattern: each row is its own .focusSection() so
                // vertical moves jump row-to-row regardless of horizontal
                // scroll position. Never put .focusSection() on the outer
                // ScrollView/LazyVStack — parent + child sections conflict.
                ForEach(0..<3, id: \.self) { shelf in
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Shelf \(shelf + 1)")
                            .font(.title3)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 40) {
                                ForEach(0..<8, id: \.self) { item in
                                    Button {
                                        // FILL IN: open detail
                                    } label: {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.quaternary)
                                            .frame(width: 380, height: 214)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                        }
                        // Lets the focused card's 1.08 scale bloom past
                        // the row edges instead of clipping.
                        .scrollClipDisabled()
                    }
                    .focusSection()
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
        }
    }
}
#endif
