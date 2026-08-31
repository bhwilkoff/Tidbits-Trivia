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
    /// TIDBITS_PAYWALL=1 — mirrors the tvOS hook. The Mac is the only surface here that
    /// can answer "does the REAL App Store return our plans": StoreKit's sandbox needs
    /// actual hardware, so a simulator can only ever exercise the local .storekit file.
    /// Launched outside Xcode, this opens the paywall on the same path App Review takes
    /// and `loadProducts()` prints what App Store Connect actually returned.
    @State private var diagPaywall = false
    @State private var path = NavigationPath()
    /// The active game. When set, the game surface REPLACES the split view as
    /// the window root (macOS-DESIGN §B2).
    @State private var launch: LaunchRequest?
    /// An Expedition stage in play (docs/CLUB-FEATURES-BUILD.md "Feature 5")
    /// — also replaces the window root, carrying the campaign context
    /// `LaunchRequest` alone can't express.
    @State private var expeditionLaunch: ExpeditionStageLaunch_macOS?
    /// A live-generated (Create) game — also replaces the window root.
    @State private var customGame: CustomLaunch?
    /// A solo Trivia Night — also replaces the window root.
    @State private var nightLaunch: NightLaunchRequest?
    /// "Join a game" — the Mac's player-side surface (MacLiveJoinView_macOS).
    @State private var joinCode: String?
    /// A Play-vs-CPU match — also replaces the window root.
    @State private var versusBot: BotProfile?
    /// Local pass-and-play (2–4 at one Mac) — also replaces the window root.
    @State private var showParty = false
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
            } else if let joinCode {
                // Root replacement, not a sheet: a player in someone's game owns the
                // window, the same rule the in-progress game follows (macOS-DESIGN).
                MacLiveJoinView_macOS(initialCode: joinCode) { self.joinCode = nil }
            } else if let nightLaunch {
                NightContainer_macOS(plan: nightLaunch.plan, category: nightLaunch.category) {
                    self.nightLaunch = nil
                }
                .transition(.opacity)
            } else if let versusBot {
                VersusContainer_macOS(bot: versusBot) { self.versusBot = nil }
                    .transition(.opacity)
            } else if showParty {
                PartyContainer_macOS { showParty = false }
                    .transition(.opacity)
            } else if let livePreview {
                LivePreviewContainer_macOS(event: livePreview) { self.livePreview = nil }
                    .transition(.opacity)
            } else if let liveHost {
                LiveHostContainer_macOS(event: liveHost) { self.liveHost = nil }
                    .transition(.opacity)
            } else if let expeditionLaunch {
                GameContainerView_macOS(request: LaunchRequest(mode: .classic, category: .named(expeditionLaunch.stage.categoryID)),
                                        onClose: { self.expeditionLaunch = nil },
                                        expedition: expeditionLaunch.expedition,
                                        expeditionStageIndex: expeditionLaunch.stageIndex)
                    .transition(.opacity)
            } else {
                shell
            }
        }
        .animation(.snappy(duration: 0.2), value: launch?.id)
        .animation(.snappy(duration: 0.2), value: customGame?.id)
        .animation(.snappy(duration: 0.2), value: nightLaunch?.id)
        .animation(.snappy(duration: 0.2), value: versusBot?.id)
        .animation(.snappy(duration: 0.2), value: showParty)
        .animation(.snappy(duration: 0.2), value: livePreview?.id)
        .animation(.snappy(duration: 0.2), value: liveHost?.id)
        .animation(.snappy(duration: 0.2), value: expeditionLaunch?.id)
        .sheet(isPresented: $diagPaywall) { ClubPaywallView_macOS() }
        .onChange(of: store.inbox) { _, _ in handleInbox() }
        .onAppear { handleInbox() }
        .task {
            DebugHooks.seedRecordsIfRequested(modelContext)
            // Screenshot/CI hook (parity with iOS/tvOS): TIDBITS_AUTOPLAY="mode:category".
            if launch == nil, let ap = DebugHooks.autoplay {
                start(LaunchRequest(mode: ap.mode, category: ap.category, mixModes: DebugHooks.mixModes))
            }
            if !showParty, DebugHooks.openParty { showParty = true }
            // TIDBITS_NIGHT_HOST=1 — host a NETWORKED night from launch.
            //
            // On the Mac that is the LIVE COCKPIT, not NightContainer. The Mac's
            // "Trivia Night" is a solo mode (`hostPaced: false`) that never opens a
            // room, so wiring this hook to it produced a Mac playing by itself while
            // a matrix run waited for a room that was never going to exist. The
            // cockpit is the Mac's networked-host idiom — it is the surface with the
            // join code, the QR, the standings and the projector.
            //
            // Trivia Night and Tidbits Live publish to the SAME live/{code} room, so a
            // joiner cannot tell which opened it. That is what makes the hook mean the
            // same thing on all six platforms: "host a night other devices can join."
            // TIDBITS_LIVE_JOIN — join a room by code. Every other platform honoured
            // this; the Mac had no join surface at all, so it was told to join in every
            // cross-platform run and landed on its Home screen.
            if joinCode == nil, let c = DebugHooks.openLiveJoin { joinCode = c }
            if liveHost == nil, DebugHooks.openNightHost {
                liveHost = await Self.quickNightEvent()
            }
            if versusBot == nil, let vb = DebugHooks.versusBot {
                versusBot = vb == "house" ? .house(playerAccuracy: 0.6) : (BotProfile.presets.first { $0.id == vb } ?? .regular)
            }
            if liveHost == nil, ProcessInfo.processInfo.environment["TIDBITS_LIVE_HOST"] == "1" {
                liveHost = await Self.quickNightEvent(name: "Friday Pub Quiz")
            }
            if ProcessInfo.processInfo.environment["TIDBITS_TAB"] == "live" {
                section = .live
            } else if let tab = DebugHooks.initialTab {
                section = SidebarSection(rawValue: tab.rawValue)
            }
            if DebugHooks.showPaywall { diagPaywall = true }
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
        .focusedSceneValue(\.joinGame, JoinGameAction { joinCode = "" })
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            OnboardingSheet_macOS { hasOnboarded = true }
        }
        // sheet(item:) not isPresented: — the id and the presentation must arrive in the
        // same state change, or a second link races the first sheet's dismissal.
        .sheet(item: Binding(get: { store.pendingItemID.map(SharedItemID_macOS.init) },
                             set: { store.pendingItemID = $0?.id })) { item in
            SharedItemView_macOS(id: item.id)
        }
    }

    @ViewBuilder private var detail: some View {
        Group {
            NavigationStack(path: $path) {
                switch section ?? .play {
                case .play:    HomeView_macOS(onPlay: start, onNight: { nightLaunch = $0 }, onVersus: { versusBot = $0 },
                                              onParty: { showParty = true },
                                              onExpedition: { expedition, stageIndex in
                                                  expeditionLaunch = ExpeditionStageLaunch_macOS(expedition: expedition, stageIndex: stageIndex)
                                              })
                case .records: RecordsView_macOS(onPlay: start)
                case .create:  CreateView_macOS { topic, qs in customGame = CustomLaunch(topic: topic, questions: qs) }
                case .live:    LiveBuilderView_macOS(onPreview: { livePreview = $0 }, onHost: { liveHost = $0 },
                                                     onJoin: { joinCode = "" })
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
            case .quiz(let id):
                store.pendingSharedQuizID = id
                section = .create
            case .item(let id):
                // A single shared question belongs to no sidebar section — it is a thing
                // someone sent you, so it opens as a sheet over wherever you were.
                store.pendingItemID = id
            case .surprise:
                section = .play
                launch = store.surpriseMe()
            }
        }
    }

    /// The two-round event both host hooks open. Shared so TIDBITS_NIGHT_HOST and
    /// TIDBITS_LIVE_HOST cannot drift into hosting different things.
    static func quickNightEvent(name: String = "Quick Night") async -> LiveEvent {
        var ev = LiveEvent(name: name)
        for (i, fmt) in [GameMode.classic, GameMode.oddOneOut].enumerated() {
            ev.rounds.append(await LiveEventStore.buildRound(
                format: fmt, category: .named(i == 0 ? "history" : "science"), count: 5))
        }
        return ev
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

/// Resolved once a member taps "Play" on an Expedition's current stage
/// (docs/CLUB-FEATURES-BUILD.md "Feature 5") — drives the window-root swap
/// into `GameContainerView_macOS`. `LaunchRequest` alone can't carry the
/// campaign context, so this is a small macOS-only wrapper (mirrors the
/// private `ExpeditionStageLaunch` on iOS).
struct ExpeditionStageLaunch_macOS: Identifiable {
    let expedition: Expedition
    let stageIndex: Int
    var id: String { "\(expedition.id)-\(stageIndex)" }
    var stage: ExpeditionStage { expedition.stages.first { $0.index == stageIndex }! }
}

// MARK: - Menu-bar commands (macOS-DESIGN §B1a: ⌘N does the app's primary create)

/// The shell publishes this so the ⌘N menu command can start a game without
/// reaching into ContentView's private @State.
struct NewGameAction { let start: () -> Void }
struct JoinGameAction { let open: () -> Void }
struct JoinGameKey: FocusedValueKey { typealias Value = JoinGameAction }

struct NewGameKey: FocusedValueKey { typealias Value = NewGameAction }
extension FocusedValues {
    var joinGame: JoinGameAction? {
        get { self[JoinGameKey.self] }
        set { self[JoinGameKey.self] = newValue }
    }
    var newGame: NewGameAction? {
        get { self[NewGameKey.self] }
        set { self[NewGameKey.self] = newValue }
    }
}

/// Menu-bar commands: ⌘N replaces File ▸ New with "New Quick Play", ⌘J joins a game.
struct TidbitsCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            NewGameMenuItem()
            JoinGameMenuItem()
        }
    }

    /// A Mac user reaches for the menu bar. The Live section carries the same door as
    /// a button, but a hosting-only Live screen is not where someone looks when a
    /// friend reads them a code over the phone.
    private struct JoinGameMenuItem: View {
        @FocusedValue(\.joinGame) private var joinGame
        var body: some View {
            Button("Join a Game…") { joinGame?.open() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(joinGame == nil)
        }
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

/// `sheet(item:)` needs an Identifiable, and a bare String isn't one.
private struct SharedItemID_macOS: Identifiable {
    let id: String
}
#endif
