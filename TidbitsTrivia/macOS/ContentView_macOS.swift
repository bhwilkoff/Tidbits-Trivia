#if os(macOS)
import SwiftUI

// MARK: - Root View (macOS)
//
// The Mac shell (macOS-DESIGN Part B): a NavigationSplitView (sidebar Section
// enum → one detail column), NOT the iOS per-tab stack. A game in progress
// REPLACES the window root (Rule 4 / §B2) — never an overlay on the split view,
// whose toolbar + sidebar toggle would bleed through.

struct ContentView_macOS: View {
    @Environment(AppStore.self) private var store
    @State private var section: SidebarSection? = .play
    @State private var path = NavigationPath()
    /// The active game. When set, the game surface REPLACES the split view as
    /// the window root (macOS-DESIGN §B2).
    @State private var launch: LaunchRequest?

    var body: some View {
        Group {
            if let launch {
                GameContainerView_macOS(request: launch) { self.launch = nil }
                    .transition(.opacity)
            } else {
                shell
            }
        }
        .animation(.snappy(duration: 0.2), value: launch?.id)
        .task {
            // Screenshot/CI hook (parity with iOS/tvOS): TIDBITS_AUTOPLAY="mode:category".
            if launch == nil, let ap = DebugHooks.autoplay {
                start(LaunchRequest(mode: ap.mode, category: ap.category, mixModes: DebugHooks.mixModes))
            }
            if let tab = DebugHooks.initialTab {
                section = SidebarSection(rawValue: tab.rawValue)
            }
        }
    }

    private var shell: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack(path: $path) {
                switch section ?? .play {
                case .play:    HomeView_macOS(onPlay: start)
                case .records: RecordsPlaceholder_macOS()
                case .create:  CreatePlaceholder_macOS()
                }
            }
        }
        .tint(Tidbits.Palette.blue)
    }

    /// Launch a game and (unless it's the Daily) remember it as the Quick Play
    /// default — the same rule as the iOS Home (R-HOME-1).
    private func start(_ request: LaunchRequest) {
        if request.mode != .daily {
            store.rememberSelection(mode: request.mode, category: request.category, mixModes: request.mixModes)
        }
        launch = request
    }
}

/// Sidebar sections = the top-level verbs (the macOS analog of the iOS tab bar).
/// Settings rides the app menu (⌘,), never a sidebar row.
enum SidebarSection: String, CaseIterable, Identifiable {
    case play, records, create
    var id: String { rawValue }
    var title: String {
        switch self {
        case .play: "Play"; case .records: "Records"; case .create: "Create"
        }
    }
    var symbol: String {
        switch self {
        case .play: "play.fill"; case .records: "chart.bar.fill"; case .create: "sparkles"
        }
    }
}

// MARK: - Placeholders (next parity increments — Records + Create Mac views)

private struct RecordsPlaceholder_macOS: View {
    var body: some View {
        ContentUnavailableView("Records",
            systemImage: "chart.bar.fill",
            description: Text("Your history, streak, and drill-ins — the native Mac Records screen lands next."))
            .navigationTitle("Records")
    }
}

private struct CreatePlaceholder_macOS: View {
    var body: some View {
        ContentUnavailableView("Create",
            systemImage: "sparkles",
            description: Text("Spin a quiz on any topic — the native Mac Create screen lands next."))
            .navigationTitle("Create")
    }
}
#endif
