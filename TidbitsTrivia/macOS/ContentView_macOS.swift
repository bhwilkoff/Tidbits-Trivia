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
    @Environment(\.modelContext) private var modelContext
    @State private var section: SidebarSection? = .play
    @State private var path = NavigationPath()
    /// The active game. When set, the game surface REPLACES the split view as
    /// the window root (macOS-DESIGN §B2).
    @State private var launch: LaunchRequest?
    /// A live-generated (Create) game — also replaces the window root.
    @State private var customGame: CustomLaunch?
    /// A solo Trivia Night — also replaces the window root.
    @State private var nightLaunch: NightLaunchRequest?
    /// A Play-vs-CPU match — also replaces the window root.
    @State private var versusBot: BotProfile?
    /// A Tidbits Live event being previewed solo — replaces the window root.
    @State private var livePreview: LiveEvent?
    /// A Tidbits Live event being HOSTED (the emcee cockpit) — replaces the root.
    @State private var liveHost: LiveEvent?
    @AppStorage("tidbits.hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            if let launch {
                GameContainerView_macOS(request: launch) { self.launch = nil }
                    .transition(.opacity)
            } else if let customGame {
                CustomGameContainer_macOS(topic: customGame.topic, questions: customGame.questions) {
                    self.customGame = nil
                }
                .transition(.opacity)
            } else if let nightLaunch {
                NightContainer_macOS(plan: nightLaunch.plan, category: nightLaunch.category) {
                    self.nightLaunch = nil
                }
                .transition(.opacity)
            } else if let versusBot {
                VersusContainer_macOS(bot: versusBot) { self.versusBot = nil }
                    .transition(.opacity)
            } else if let livePreview {
                LivePreviewContainer_macOS(event: livePreview) { self.livePreview = nil }
                    .transition(.opacity)
            } else if let liveHost {
                LiveHostContainer_macOS(event: liveHost) { self.liveHost = nil }
                    .transition(.opacity)
            } else {
                shell
            }
        }
        .animation(.snappy(duration: 0.2), value: launch?.id)
        .animation(.snappy(duration: 0.2), value: customGame?.id)
        .animation(.snappy(duration: 0.2), value: nightLaunch?.id)
        .animation(.snappy(duration: 0.2), value: versusBot?.id)
        .animation(.snappy(duration: 0.2), value: livePreview?.id)
        .animation(.snappy(duration: 0.2), value: liveHost?.id)
        .onChange(of: store.inbox) { _, _ in handleInbox() }
        .onAppear { handleInbox() }
        .task {
            DebugHooks.seedRecordsIfRequested(modelContext)
            // Screenshot/CI hook (parity with iOS/tvOS): TIDBITS_AUTOPLAY="mode:category".
            if launch == nil, let ap = DebugHooks.autoplay {
                start(LaunchRequest(mode: ap.mode, category: ap.category, mixModes: DebugHooks.mixModes))
            }
            if versusBot == nil, let vb = DebugHooks.versusBot {
                versusBot = vb == "house" ? .house(playerAccuracy: 0.6) : (BotProfile.presets.first { $0.id == vb } ?? .regular)
            }
            if liveHost == nil, ProcessInfo.processInfo.environment["TIDBITS_LIVE_HOST"] == "1" {
                var ev = LiveEvent(name: "Friday Pub Quiz")
                for (i, fmt) in [GameMode.classic, GameMode.oddOneOut].enumerated() {
                    ev.rounds.append(await LiveEventStore.buildRound(format: fmt, category: .named(i == 0 ? "history" : "science"), count: 5))
                }
                liveHost = ev
            }
            if ProcessInfo.processInfo.environment["TIDBITS_TAB"] == "live" {
                section = .live
            } else if let tab = DebugHooks.initialTab {
                section = SidebarSection(rawValue: tab.rawValue)
            }
        }
    }

    private var shell: some View {
        NavigationSplitView {
            // Explicit .tag(item) so the row tag type matches the selection
            // binding (SidebarSection). Without it the List auto-tags rows by
            // their String id, the types mismatch, and clicks never select.
            List(selection: $section) {
                ForEach(SidebarSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            // Discoverable entry to Settings + Sign in with Apple. ⌘, still works; this is the
            // visible affordance (the app menu alone wasn't discoverable). SettingsLink opens the
            // native Settings scene.
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("Settings & Account", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail
        }
        .tint(Tidbits.Palette.blue)
        // ⌘N (menu bar) → start Quick Play. focusedSceneValue is only live while
        // the shell is on screen, so ⌘N is naturally disabled mid-game.
        .focusedSceneValue(\.newGame, NewGameAction { start(store.quickPlay) })
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            OnboardingSheet_macOS { hasOnboarded = true }
        }
    }

    @ViewBuilder private var detail: some View {
        Group {
            NavigationStack(path: $path) {
                switch section ?? .play {
                case .play:    HomeView_macOS(onPlay: start, onNight: { nightLaunch = $0 }, onVersus: { versusBot = $0 })
                case .records: RecordsView_macOS()
                case .create:  CreateView_macOS { topic, qs in customGame = CustomLaunch(topic: topic, questions: qs) }
                case .live:    LiveBuilderView_macOS(onPreview: { livePreview = $0 }, onHost: { liveHost = $0 })
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

    /// Deep links land in the store inbox (App.onOpenURL) and are consumed here
    /// once foregrounded — never mutating navigation from outside the view tree.
    private func handleInbox() {
        for link in store.drainInbox() {
            switch link {
            case .daily:
                section = .play
                launch = LaunchRequest(mode: .daily, category: .named("mixed"))
            case .topic, .category:
                section = .play
            }
        }
    }
}

/// Sidebar sections = the top-level verbs (the macOS analog of the iOS tab bar).
/// Settings rides the app menu (⌘,), never a sidebar row.
enum SidebarSection: String, CaseIterable, Identifiable {
    case play, records, create, live
    var id: String { rawValue }
    var title: String {
        switch self {
        case .play: "Play"; case .records: "Records"; case .create: "Create"; case .live: "Tidbits Live"
        }
    }
    var symbol: String {
        switch self {
        case .play: "play.fill"; case .records: "chart.bar.fill"; case .create: "sparkles"; case .live: "megaphone.fill"
        }
    }
}

/// A live-generated (Create) game launch — carries the pre-built question set.
struct CustomLaunch: Identifiable {
    let id = UUID()
    let topic: String
    let questions: [Question]
}

// MARK: - Menu-bar commands (macOS-DESIGN §B1a: ⌘N does the app's primary create)

/// The shell publishes this so the ⌘N menu command can start a game without
/// reaching into ContentView's private @State.
struct NewGameAction { let start: () -> Void }
struct NewGameKey: FocusedValueKey { typealias Value = NewGameAction }
extension FocusedValues {
    var newGame: NewGameAction? {
        get { self[NewGameKey.self] }
        set { self[NewGameKey.self] = newValue }
    }
}

/// Menu-bar commands: ⌘N replaces File ▸ New with "New Quick Play".
struct TidbitsCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) { NewGameMenuItem() }
    }
    private struct NewGameMenuItem: View {
        @FocusedValue(\.newGame) private var newGame
        var body: some View {
            Button("New Quick Play") { newGame?.start() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newGame == nil)
        }
    }
}
#endif
