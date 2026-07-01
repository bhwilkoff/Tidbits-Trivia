#if os(tvOS)
import SwiftUI

// MARK: - tvOS palette (dark-first; reserve brightness for focus)

enum TVTheme {
    static let bg = Color(hex: 0x0E0C0B)
    static let panel = Color(hex: 0x1C1916)
    static let text = Color.white
    static let textSoft = Color(hex: 0xB9AE9F)
}

// MARK: - Home (browse)

/// Apple TV home. Dark-first, 90/60 safe area, focusSection per row so
/// vertical moves jump row-to-row. Reuses the shared GameEngine — only the
/// ten-foot presentation is tvOS-specific (Core never imports UI).
struct ContentView_tvOS: View {
    @Environment(AppStore.self) private var store
    @Environment(GameCenterManager.self) private var gameCenter
    @State private var launch: LaunchRequest?
    @State private var nightLaunch: NightLaunchRequest?
    @State private var hostLaunch: NightLaunchRequest?
    @State private var showJoinNight = false
    @State private var showRecords = false
    @State private var showSettings = false
    @State private var showNightSetup = false
    @State private var showCustomize = false
    @FocusState private var primaryFocused: Bool

    /// Launch a game and (unless Daily) remember it as the Quick Play default.
    private func play(_ mode: GameMode, _ category: TriviaCategory) {
        store.rememberSelection(mode: mode, category: category)
        launch = LaunchRequest(mode: mode, category: category)
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 60) {
                    header
                    quickPlayHero
                    dailyHero
                    nightHero
                    customizeHero
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
            }
        }
        .defaultFocus($primaryFocused, true)
        .fullScreenCover(isPresented: $showCustomize) {
            TVCustomizePicker(initialMode: store.quickPlay.mode) { mode, cat in
                showCustomize = false; play(mode, cat)
            }
        }
        .fullScreenCover(item: $launch) { req in
            TVGameContainer(mode: req.mode, category: req.category)
        }
        .fullScreenCover(item: $nightLaunch) { req in
            TVNightContainer(plan: req.plan, category: req.category)
        }
        .fullScreenCover(item: $hostLaunch) { req in
            TVNightLiveContainer(hosting: req.plan, category: req.category,
                                 engine: store.game, hostName: NightClient.lastName)
        }
        .fullScreenCover(isPresented: $showJoinNight) {
            TVNightLiveContainer(joining: store.game)
        }
        .fullScreenCover(isPresented: $showNightSetup) {
            NightSetupView_tvOS { plan, category, mode in
                switch mode {
                case .solo: nightLaunch = NightLaunchRequest(plan: plan, category: category)
                case .host: hostLaunch = NightLaunchRequest(plan: plan, category: category)
                }
            }
        }
        .fullScreenCover(isPresented: $showRecords) { RecordsView_tvOS() }
        .fullScreenCover(isPresented: $showSettings) { SettingsView_tvOS() }
        .task {
            if launch == nil, nightLaunch == nil, let ap = DebugHooks.autoplay {
                // Trivia Night needs a plan, not a bare category — autoplay it with
                // a quick preset so screenshots/CI can drive the whole night.
                if ap.mode == .barTrivia {
                    nightLaunch = NightLaunchRequest(plan: .quick, category: ap.category)
                } else {
                    launch = LaunchRequest(mode: ap.mode, category: ap.category)
                }
            }
            // TIDBITS_TAB=records opens Records straight away (screenshots /
            // verification — Decision 018). tvOS has no tab bar, so the hook
            // presents the cover instead.
            if DebugHooks.initialTab == .records { showRecords = true }
            if launch == nil, let mode = gameCenter.consumePendingChallenge() {
                launch = LaunchRequest(mode: mode, category: .named("mixed"))
            }
        }
        // A friend's Game Center challenge accepted at runtime → launch the mode.
        .onChange(of: gameCenter.pendingChallengeMode) { _, m in
            if m != nil, launch == nil, let mode = gameCenter.consumePendingChallenge() {
                launch = LaunchRequest(mode: mode, category: .named("mixed"))
            }
        }
    }

    private var quickPlayHero: some View {
        Button { play(store.quickPlay.mode, store.quickPlay.category) } label: {
            HStack(spacing: 28) {
                Image(systemName: "play.fill").font(.system(size: 60, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    Text("QUICK PLAY").font(.system(size: 44, weight: .black, design: .rounded))
                    Text("\(store.quickPlay.mode.title.uppercased()) · \(store.quickPlay.category.name.uppercased())")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVNightHeroStyle())
        .focused($primaryFocused)
    }

    // One unified Trivia Night entry — both verbs live inside the card (backlog #4).
    private var nightHero: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 28) {
                Image(systemName: "party.popper.fill").font(.system(size: 52, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRIVIA NIGHT").font(.system(size: 40, weight: .black, design: .rounded))
                    Text("Host or join a night of mixed rounds.")
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .foregroundStyle(TVTheme.textSoft)
                }
                Spacer()
            }
            .foregroundStyle(TVTheme.text)
            HStack(spacing: 24) {
                Button { showNightSetup = true } label: {
                    Label("Start a night", systemImage: "play.fill").font(.system(size: 27, weight: .bold, design: .rounded))
                }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                Button { showJoinNight = true } label: {
                    Label("Join a night", systemImage: "number").font(.system(size: 27, weight: .bold, design: .rounded))
                }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: false))
            }
            .focusSection()
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVTheme.panel, in: RoundedRectangle(cornerRadius: 28))
    }

    private var customizeHero: some View {
        Button { showCustomize = true } label: {
            HStack(spacing: 24) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 40, weight: .black))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Customize a game").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("Pick a mode, a category, save a mix")
                        .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                }
                Spacer()
            }
            .foregroundStyle(TVTheme.text)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TIDBITS")
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .foregroundStyle(TVTheme.text)
                Text("Trivia from the whole of Wikipedia.")
                    .font(.system(size: 31, weight: .medium, design: .rounded))
                    .foregroundStyle(TVTheme.textSoft)
            }
            Spacer()
            HStack(spacing: 20) {
                Button { showRecords = true } label: {
                    Label("Records", systemImage: "chart.bar.fill")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.grape, selected: false))
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
            }
            .focusSection()
        }
    }

    private var dailyHero: some View {
        Button {
            launch = LaunchRequest(mode: .daily, category: .named("mixed"))
        } label: {
            HStack(spacing: 28) {
                Image(systemName: "sun.max.fill").font(.system(size: 64, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    Text("DAILY TIDBIT").font(.system(size: 40, weight: .black, design: .rounded))
                    Text("7 questions. Everyone gets the same set. Keep your streak.")
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.7))
                }
                Spacer()
            }
            .foregroundStyle(.black)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVHeroStyle())
    }
}

// MARK: - Customize picker (the mode + category shelves, on demand)

/// Full-screen focus picker opened from the Customize hero. Mode shelf drives the
/// category shelf; selecting a category starts the game. Shelves scroll
/// horizontally (14 modes × 240pt overflow 1920pt — a bare HStack would balloon
/// the whole content width and render everything oversized).
private struct TVCustomizePicker: View {
    let initialMode: GameMode
    let onPlay: (GameMode, TriviaCategory) -> Void
    @State private var selectedMode: GameMode

    init(initialMode: GameMode, onPlay: @escaping (GameMode, TriviaCategory) -> Void) {
        self.initialMode = initialMode; self.onPlay = onPlay
        _selectedMode = State(initialValue: initialMode)
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 50) {
                    Text("Customize a game")
                        .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Mode").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 30) {
                                ForEach(GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia }) { mode in
                                    Button { selectedMode = mode } label: {
                                        VStack(spacing: 10) {
                                            Image(systemName: mode.symbol).font(.system(size: 34, weight: .black))
                                            Text(mode.title).font(.system(size: 27, weight: .bold, design: .rounded))
                                        }
                                        .frame(width: 240, height: 150)
                                    }
                                    .buttonStyle(TVChipStyle(accent: mode.accent, selected: selectedMode == mode))
                                }
                            }
                            .padding(.vertical, 30)
                        }
                        .scrollClipDisabled()
                    }
                    .focusSection()
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Category · \(selectedMode.title)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 36) {
                                ForEach(TriviaCategory.all) { cat in
                                    Button { onPlay(selectedMode, cat) } label: {
                                        VStack(alignment: .leading, spacing: 16) {
                                            Image(systemName: cat.symbol).font(.system(size: 44, weight: .black)).foregroundStyle(.white)
                                            Spacer()
                                            Text(cat.name).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                                            Text(cat.blurb).font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                                                .lineLimit(2)
                                        }
                                        .padding(28)
                                        .frame(width: 320, height: 300, alignment: .leading)
                                    }
                                    .buttonStyle(TVCategoryStyle(accent: cat.color))
                                }
                            }
                            .padding(.vertical, 30)
                        }
                        .scrollClipDisabled()
                    }
                    .focusSection()
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
            }
        }
    }
}

// MARK: - tvOS button styles (custom focus treatment; never .plain)

struct TVHeroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 28).fill(Tidbits.Palette.yellow))
                .scaleEffect(focused ? 1.04 : 1.0)
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 24, y: 10)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

/// The Trivia Night hero — coral, white-on-dark, lit on focus (a darker tile so
/// the white text stays legible, unlike the bright-yellow Daily hero).
struct TVNightHeroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 28).fill(Tidbits.Palette.coral.gradient))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.03 : 1.0)
                .shadow(color: Tidbits.Palette.coral.opacity(focused ? 0.6 : 0), radius: 30, y: 12)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

struct TVChipStyle: ButtonStyle {
    let accent: Color; let selected: Bool
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, accent: accent, selected: selected) }
    struct Inner: View {
        let configuration: Configuration; let accent: Color; let selected: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(selected || focused ? .white : TVTheme.textSoft)
                // Internal padding so a plain-text label ("Play Again", "Done",
                // "Next", "Submit", "Reveal…") never touches the pill's outline.
                // Labels that carry their own .frame(…) just gain a little more
                // breathing room — harmless, and this guarantees no overlap
                // anywhere TVChipStyle is used.
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 22).fill(selected ? accent : (focused ? accent.opacity(0.85) : TVTheme.panel)))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 4))
                .scaleEffect(focused ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

struct TVCategoryStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, accent: accent) }
    struct Inner: View {
        let configuration: Configuration; let accent: Color
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 26).fill(accent.gradient))
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(focused ? 1 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.1 : 1.0)
                .shadow(color: accent.opacity(focused ? 0.6 : 0), radius: 30, y: 12)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}
#endif
