#if os(macOS)
import SwiftUI

// MARK: - Root View (macOS) — STARTER SCAFFOLD
//
// Read the `macos-platform-patterns` skill before building on this. macOS is a
// full-parity platform sharing the same Core/ as iOS + tvOS — the FEATURE set is
// identical (play, daily, records, create, online); the IDIOM is a pointer +
// keyboard + menu-bar + resizable multi-window Mac app, NOT the iOS app resized.
//
// This file is a STARTING POINT for the macOS scope of work. The detail columns
// are placeholders on purpose — the iOS views (ContentView_iOS, RecordsView,
// etc.) are `#if os(iOS)`-guarded, so the Mac shell gets its own views that
// reuse Core (AppStore, the game engine, RecordsStore, the corpus) verbatim.
//
// The load-bearing macOS rules (all cost real iteration to learn — see the skill):
//   1. Shell = NavigationSplitView (sidebar Section enum + ONE NavigationPath
//      feeding a single detail column) — NOT the iOS per-tab stack.
//   2. A game in progress REPLACES the split view as the window root — never an
//      .overlay/cover on the split view (its toolbar + sidebar toggle bleed
//      through). The iOS game overlay pattern maps to "swap the window root".
//   3. A resizable-window hero is full-width 16:9 aspect-FIT with NO maxHeight
//      cap; art rides .background/.overlay + .clipped() so a fill image can't
//      inflate layout (the same trap called out in CLAUDE.md for iOS).
//   4. Never bare AsyncImage for picture-round art — route through an
//      ImagePipeline (decoded NSCache + one capped URLSession); decode non-RGB
//      → sRGB once (Image(nsImage:)'s Metal path renders grayscale as a white box).
//   5. Structured concurrency (.task(id:)), never Combine Timer.publish, for the
//      question clock / hero rotation.
//   6. Menu-bar `.commands` are first-class (⌘N new game, ⌘, Settings). Settings
//      rides the app menu, never a sidebar row.

struct ContentView_macOS: View {
    @Environment(AppStore.self) private var store
    @State private var section: SidebarSection? = .play
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            // ONE NavigationPath feeds the single detail column. Every pushable
            // destination is a Hashable route resolved by a single
            // .navigationDestination — never a per-view destination (the same
            // shared-registry rule as iOS/tvOS in CLAUDE.md).
            NavigationStack(path: $path) {
                switch section ?? .play {
                case .play:    Text("Play — Quick Play, Daily, Trivia Night, Online")   // FILL IN (macOS scope)
                case .records: Text("Records — history, drill-ins, bests")              // FILL IN (macOS scope)
                case .create:  Text("Create — build a set")                             // FILL IN (macOS scope)
                }
            }
        }
        .tint(Tidbits.Palette.blue)
    }
}

/// Sidebar sections = the top-level verbs (the macOS analog of the iOS tab bar /
/// tvOS sidebar). Mirrors Tidbits' three destinations. Settings rides the app
/// menu (⌘,), never a sidebar row.
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
#endif
