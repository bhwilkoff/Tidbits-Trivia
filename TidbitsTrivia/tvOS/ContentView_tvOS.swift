#if os(tvOS)
import SwiftUI
import SwiftData

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
    @Environment(PlayerIdentityStore.self) private var identity
    @Environment(EntitlementStore.self) private var entitlement
    private var dayStreak: Int { identity.profile?.streak.current ?? 0 }
    @State private var launch: LaunchRequest?
    @State private var nightLaunch: NightLaunchRequest?
    @State private var hostLaunch: NightLaunchRequest?
    @State private var showJoinNight = false
    @State private var showRecords = false
    @State private var showSettings = false
    @State private var showNightSetup = false
    @State private var showCustomize = false
    @State private var showDailyArchive = false
    @State private var showClubPaywall = false
    @State private var versusBot: BotProfile?
    @State private var showQuickMatch = false
    @Environment(\.modelContext) private var modelContext
    @FocusState private var primaryFocused: Bool
    // Marathon (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3").
    @Query private var marathonRuns: [MarathonRun]
    @Query(sort: \MarathonScore.date, order: .reverse) private var marathonHistory: [MarathonScore]
    @State private var showMarathonChoice = false
    // Expeditions (Club — docs/CLUB-FEATURES-BUILD.md "Feature 5").
    @Query private var expeditionProgress: [ExpeditionProgress]
    @State private var showExpeditions = false
    @State private var expeditionLaunch: TVExpeditionStageLaunch?
    // Link Wall (Club — docs/CLUB-FEATURES-BUILD.md "Feature 6"). Sorted desc
    // + filtered by day rather than a predicate-init'd @Query, so this view's
    // existing memberwise init stays untouched (rows accumulate, one per day).
    @Query(sort: \LinkWallResult.date, order: .reverse) private var linkWallResults: [LinkWallResult]
    @State private var showLinkWall = false

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
                    quickActionsRow
                    dailyHero
                    linkWallHero
                    nightHero
                    weakSpotHero
                    marathonHero
                    expeditionsHero
                    multiplayerPanel
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
            TVGameContainer(mode: req.mode, category: req.category, dailyDay: req.dailyDay)
        }
        .fullScreenCover(item: $versusBot) { bot in
            TVVersusContainer(bot: bot)
        }
        .fullScreenCover(isPresented: $showQuickMatch) {
            TVQuickMatchContainer()
        }
        .fullScreenCover(isPresented: $showDailyArchive) {
            TVDailyArchive { day in
                showDailyArchive = false
                launch = LaunchRequest(mode: .daily, category: .named("mixed"), dailyDay: day)
            }
        }
        .fullScreenCover(item: $nightLaunch) { req in
            TVNightContainer(plan: req.plan, category: req.category)
        }
        .fullScreenCover(item: $hostLaunch) { req in
            TVNightHostView(plan: req.plan, category: req.category)
        }
        .fullScreenCover(isPresented: $showJoinNight) {
            TVJoinGameContainer()
        }
        .fullScreenCover(isPresented: $showNightSetup) {
            NightSetupView_tvOS { plan, category, mode in
                switch mode {
                case .solo: nightLaunch = NightLaunchRequest(plan: plan, category: category)
                case .host: hostLaunch = NightLaunchRequest(plan: plan, category: category)
                }
            }
        }
        .fullScreenCover(isPresented: $showRecords) {
            RecordsView_tvOS(onPlay: { req in showRecords = false; launch = req })
        }
        .fullScreenCover(isPresented: $showSettings) { SettingsView_tvOS() }
        .fullScreenCover(isPresented: $showClubPaywall) { ClubPaywallView_tvOS() }
        .fullScreenCover(isPresented: $showMarathonChoice) {
            TVMarathonChoiceView(
                run: marathonRuns.first,
                onResume: { showMarathonChoice = false; launch = LaunchRequest(mode: .marathon, category: .named("mixed")) },
                onStartOver: {
                    Marathon.startNew(in: modelContext)
                    showMarathonChoice = false
                    launch = LaunchRequest(mode: .marathon, category: .named("mixed"))
                },
                onCancel: { showMarathonChoice = false })
        }
        .fullScreenCover(isPresented: $showExpeditions) {
            TVExpeditionsHubView(onPlayStage: { expedition, stageIndex in
                showExpeditions = false
                expeditionLaunch = TVExpeditionStageLaunch(expedition: expedition, stageIndex: stageIndex)
            })
        }
        .fullScreenCover(item: $expeditionLaunch) { launch in
            TVGameContainer(mode: .classic, category: .named(launch.stage.categoryID),
                            expedition: launch.expedition, expeditionStageIndex: launch.stageIndex)
        }
        .fullScreenCover(isPresented: $showLinkWall) {
            LinkWallView_tvOS(day: QuestionProvider.dayKey()) { showLinkWall = false }
        }
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
            if launch == nil, DebugHooks.openMarathon {
                launch = LaunchRequest(mode: .marathon, category: .named("mixed"))
            }
            if DebugHooks.openExpedition || DebugHooks.expeditionMapPreview != nil || DebugHooks.expeditionAutoplay != nil {
                showExpeditions = true
            }
            if DebugHooks.openLinkWall { openLinkWall() }
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
                    Text("Host a night, or join one with a code — including a Tidbits Live event.")
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
                    Label("Join a game", systemImage: "number").font(.system(size: 27, weight: .bold, design: .rounded))
                }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: false))
            }
            .focusSection()
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVTheme.panel, in: RoundedRectangle(cornerRadius: 28))
    }

    /// R-HOME-1a: the hero is ONE action — Surprise + Customize are a quiet
    /// chip row directly beneath it.
    private var quickActionsRow: some View {
        HStack(spacing: 24) {
            Button { let s = store.surpriseMe(); play(s.mode, s.category) } label: {
                Label("Surprise me", systemImage: "die.face.5.fill")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
            }
            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.grape, selected: false))
            Button { showCustomize = true } label: {
                Label("Customize a game", systemImage: "slider.horizontal.3")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
            }
            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
            Spacer()
        }
        .focusSection()
    }

    // MARK: - Link Wall (Club — docs/CLUB-FEATURES-BUILD.md "Feature 6")

    /// Today's Link Wall row, if any — `nil` for a not-yet-played day, present
    /// (possibly `completed`) once a guess has been submitted.
    private var linkWallToday: LinkWallResult? {
        linkWallResults.first { $0.day == QuestionProvider.dayKey() }
    }

    /// A real preview for non-members — today's easiest (yellow) group's
    /// label, straight off the actual generator (MONETIZATION §4a: "a real
    /// preview, never a nag"). Never reveals the group's members/why.
    private var linkWallPreviewLabel: String? {
        LinkWall.puzzle(for: QuestionProvider.dayKey())?.groups.first?.label
    }

    /// Club members launch (or resume) today's board directly; everyone else
    /// see the existing paywall — never a blank wall.
    private func openLinkWall() {
        if entitlement.isClub { showLinkWall = true } else { showClubPaywall = true }
    }

    private var linkWallSubtitle: String {
        if entitlement.isClub {
            if let r = linkWallToday {
                if r.completed { return r.won ? "Solved today's wall — see the recap." : "See today's groups." }
                return "In progress — press to keep going."
            }
            return "4 groups of 4. One guess at a time, 4 mistakes allowed."
        }
        if let linkWallPreviewLabel { return "Today's board includes \"\(linkWallPreviewLabel)\" — find all four groups." }
        return "A second daily: 16 facts, 4 hidden groups. Find them all."
    }

    private var linkWallHero: some View {
        Button(action: openLinkWall) {
            HStack(spacing: 28) {
                Image(systemName: "square.grid.3x3.fill").font(.system(size: 52, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("LINK WALL").font(.system(size: 40, weight: .black, design: .rounded))
                        if !entitlement.isClub {
                            Text("CLUB")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(.white.opacity(0.92)))
                                .foregroundStyle(Tidbits.Palette.mint)
                        }
                    }
                    Text(linkWallSubtitle)
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.75))
                        .lineLimit(2)
                }
                Spacer()
            }
            .foregroundStyle(.black)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVLinkWallHeroStyle())
    }

    // MARK: - Weak-Spot Arena (Club — docs/CLUB-FEATURES-BUILD.md "Feature 1")

    /// A real sample from the player's own misses, shown to non-members instead
    /// of a generic sell line (MONETIZATION §4a: "a real preview, never a nag").
    private var weakSpotPreviewLine: String? {
        entitlement.isClub ? nil : WeakSpotArena.previewLine(in: modelContext)
    }

    /// Club members launch the arena directly (never remembered as the Quick
    /// Play default — `AppStore.rememberSelection` already excludes it);
    /// everyone else sees the existing paywall (never a blank wall).
    private func openWeakSpot() {
        if entitlement.isClub { launch = LaunchRequest(mode: .weakSpot, category: .named("mixed")) }
        else { showClubPaywall = true }
    }

    private var weakSpotHero: some View {
        Button(action: openWeakSpot) {
            HStack(spacing: 28) {
                Image(systemName: "scope").font(.system(size: 52, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("WEAK-SPOT ARENA").font(.system(size: 40, weight: .black, design: .rounded))
                        if !entitlement.isClub {
                            Text("CLUB")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(.white.opacity(0.92)))
                                .foregroundStyle(Tidbits.Palette.grape)
                        }
                    }
                    Text(entitlement.isClub ? "Turn your misses into a round." : (weakSpotPreviewLine ?? "Your misses, turned into a round you can actually close."))
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVWeakSpotHeroStyle())
    }

    // MARK: - Marathon (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3")

    /// Members with a run in progress get the focusable Resume/Start Over
    /// choice (never a pointer `confirmationDialog` — ten-foot needs a
    /// focusable screen, tvos-platform-patterns); with no run, they launch
    /// straight into a fresh one. Non-members see the existing paywall.
    private func openMarathon() {
        guard entitlement.isClub else { showClubPaywall = true; return }
        if marathonRuns.first != nil {
            showMarathonChoice = true
        } else {
            launch = LaunchRequest(mode: .marathon, category: .named("mixed"))
        }
    }

    /// A real, concrete subtitle in every state — never a nag. Members see
    /// their true position or their real last-run number; non-members see a
    /// specific illustration of the domain scorecard.
    private var marathonSubtitle: String {
        if entitlement.isClub {
            if let run = marathonRuns.first { return "Question \(run.currentIndex + 1) of \(run.total) — press to resume" }
            if let last = marathonHistory.first { return "\(Int(last.accuracy * 100))% on your last run — press to start a new one" }
            return "200 questions. Play it across as many sittings as you like — we'll keep your place."
        }
        return "See exactly where you stand — e.g. Geography 91% · History 64% — across a 200-question run you can pause and resume anytime."
    }

    private var marathonHero: some View {
        Button(action: openMarathon) {
            HStack(spacing: 28) {
                Image(systemName: "flag.checkered").font(.system(size: 52, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("MARATHON").font(.system(size: 40, weight: .black, design: .rounded))
                        if !entitlement.isClub {
                            Text("CLUB")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(.white.opacity(0.92)))
                                .foregroundStyle(Tidbits.Palette.teal)
                        }
                        if marathonRuns.first != nil {
                            Text("RESUME")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(Tidbits.Palette.coral))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(marathonSubtitle)
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVMarathonHeroStyle())
    }

    // MARK: - Expeditions (Club — docs/CLUB-FEATURES-BUILD.md "Feature 5")

    /// A real preview even for non-members — the expeditions themselves are
    /// curated content, not player data, so there's nothing to hide behind a
    /// generic sell line (MONETIZATION §4a). The hero always opens the hub
    /// (never the paywall directly); only pressing Play on a stage is gated.
    private var expeditionSubtitle: String {
        if let active = expeditionProgress.first, let exp = Expedition.named(active.expeditionID) {
            return "\(exp.title): stage \(active.currentStageIndex + 1) of \(exp.stageCount) — press to continue"
        }
        return "Multi-week campaigns through a single subject — pick one, and go at your own pace."
    }

    private var expeditionsHero: some View {
        Button { showExpeditions = true } label: {
            HStack(spacing: 28) {
                Image(systemName: "figure.run").font(.system(size: 52, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("EXPEDITIONS").font(.system(size: 40, weight: .black, design: .rounded))
                        if !entitlement.isClub {
                            Text("CLUB")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(.white.opacity(0.92)))
                                .foregroundStyle(Tidbits.Palette.pink)
                        }
                    }
                    Text(expeditionSubtitle)
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVExpeditionHeroStyle())
    }

    // Online Multiplayer (Decision 038): v0 Play-vs-CPU chips; the Quick Match
    // line is the honest v1 slot. Bots are ALWAYS labeled CPU.
    private var multiplayerPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 28) {
                Image(systemName: "globe.americas.fill").font(.system(size: 52, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    Text("ONLINE MULTIPLAYER").font(.system(size: 40, weight: .black, design: .rounded))
                    Text("Match with real players over Game Center, or face a CPU opponent.")
                        .font(.system(size: 29, weight: .medium, design: .rounded))
                        .foregroundStyle(TVTheme.textSoft)
                }
                Spacer()
            }
            .foregroundStyle(TVTheme.text)
            HStack(spacing: 24) {
                Button { showQuickMatch = true } label: {
                    Label("Quick Match", systemImage: "globe.americas.fill")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                versusChip(BotProfile.house(playerAccuracy: recentAccuracy), accent: Tidbits.Palette.coral)
                versusChip(.rookie, accent: Tidbits.Palette.mint)
                versusChip(.regular, accent: Tidbits.Palette.blue)
                versusChip(.ace, accent: Tidbits.Palette.grape)
            }
            .focusSection()
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVTheme.panel, in: RoundedRectangle(cornerRadius: 28))
    }

    private func versusChip(_ bot: BotProfile, accent: Color) -> some View {
        Button { versusBot = bot } label: {
            HStack(spacing: 10) {
                Image(systemName: "cpu").font(.system(size: 24, weight: .black))
                Text(bot.name).font(.system(size: 27, weight: .bold, design: .rounded))
                TVCPUTag()
            }
        }
        .buttonStyle(TVChipStyle(accent: accent, selected: false))
    }

    /// Rolling accuracy over recent games — tunes the adaptive House bot.
    private var recentAccuracy: Double {
        var d = FetchDescriptor<GameRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 20
        let recs = (try? modelContext.fetch(d)) ?? []
        let total = recs.reduce(0) { $0 + $1.total }
        guard total > 0 else { return 0.6 }
        return Double(recs.reduce(0) { $0 + $1.correct }) / Double(total)
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
        let played = DailyLog.todayScore
        return Button {
            if played != nil { showDailyArchive = true }
            else { launch = LaunchRequest(mode: .daily, category: .named("mixed")) }
        } label: {
            HStack(spacing: 28) {
                Image(systemName: played == nil ? "sun.max.fill" : "checkmark.seal.fill")
                    .font(.system(size: 64, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    Text("DAILY TIDBIT").font(.system(size: 40, weight: .black, design: .rounded))
                    Text(played.map { "Done for today — you scored \($0)." + (dayStreak >= 2 ? " 🔥 \(dayStreak)-day streak kept alive." : "") + " Press to play previous days." }
                         ?? (dayStreak >= 2 ? "🔥 \(dayStreak)-day streak — play today's 7 to keep it going" : "7 questions. Everyone gets the same set. Start your streak."))
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
                                // .weakSpot / .marathon are Club-only and never a free Customize
                                // pick — they have their own Home entry points (docs/CLUB-FEATURES-BUILD.md).
                                ForEach(GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia && $0 != .weakSpot && $0 != .marathon }) { mode in
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

// MARK: - Previous Tidbits (the Daily archive, R-DAILY-1)

private struct TVDailyArchive: View {
    let onPlay: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    Text("Previous Tidbits")
                        .font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
                    Text("Every day has its own set of 7 — the same for everyone. Catching up doesn't change your streak.")
                        .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    VStack(spacing: 18) {
                        ForEach(DailyLog.recentDays(), id: \.day) { entry in
                            let today = QuestionProvider.dayKey()
                            Button {
                                if entry.score == nil { onPlay(entry.day) } else { dismiss() }
                            } label: {
                                HStack {
                                    Text(entry.day == today ? "Today" : entry.day)
                                        .font(.system(size: 29, weight: .bold, design: .rounded))
                                    Spacer()
                                    Text(entry.score.map { "Scored \($0)" } ?? "Play")
                                        .font(.system(size: 27, weight: .medium, design: .rounded))
                                        .foregroundStyle(entry.score == nil ? TVTheme.text : TVTheme.textSoft)
                                }
                                .padding(.horizontal, 32).padding(.vertical, 18)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TVChipStyle(accent: entry.score == nil ? Tidbits.Palette.coral : Tidbits.Palette.blue,
                                                     selected: false))
                            .disabled(entry.score != nil && entry.day != today)
                        }
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
            }
        }
    }
}

// MARK: - Expedition stage launch (Club — docs/CLUB-FEATURES-BUILD.md "Feature 5")

/// Resolved once a member presses Play on an Expedition's current stage —
/// drives `TVGameContainer` via `.fullScreenCover(item:)`. `LaunchRequest`
/// alone can't carry the campaign context (mirrors iOS's private
/// `ExpeditionStageLaunch` / macOS's `ExpeditionStageLaunch_macOS`).
struct TVExpeditionStageLaunch: Identifiable {
    let expedition: Expedition
    let stageIndex: Int
    var id: String { "\(expedition.id)-\(stageIndex)" }
    var stage: ExpeditionStage { expedition.stages.first { $0.index == stageIndex }! }
}

// MARK: - Marathon Resume / Start Over (Club — a focusable choice, never a
// pointer confirmationDialog — tvos-platform-patterns)

private struct TVMarathonChoiceView: View {
    let run: MarathonRun?
    let onResume: () -> Void
    let onStartOver: () -> Void
    let onCancel: () -> Void
    @FocusState private var focus: Choice?
    private enum Choice { case resume, startOver, cancel }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            VStack(spacing: 40) {
                Spacer()
                Image(systemName: "flag.checkered").font(.system(size: 76, weight: .black)).foregroundStyle(Tidbits.Palette.teal)
                Text("Marathon in progress").font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
                if let run {
                    Text("Question \(run.currentIndex + 1) of \(run.total) — resume where you left off, or start a fresh run.")
                        .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 28) {
                    Button("Resume", action: onResume)
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: false))
                        .focused($focus, equals: .resume)
                    Button("Start Over", action: onStartOver)
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                        .focused($focus, equals: .startOver)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                        .focused($focus, equals: .cancel)
                }
                .focusSection()
                Spacer()
            }
            .padding(90)
            .frame(maxWidth: 1400)
        }
        .defaultFocus($focus, .resume)
        .onExitCommand(perform: onCancel)
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

/// The Weak-Spot Arena hero — grape, white-on-dark, lit on focus (same shape
/// as `TVNightHeroStyle`, different accent for a distinct Club card).
struct TVWeakSpotHeroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 28).fill(Tidbits.Palette.grape.gradient))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.03 : 1.0)
                .shadow(color: Tidbits.Palette.grape.opacity(focused ? 0.6 : 0), radius: 30, y: 12)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

/// The Marathon hero — teal, white-on-dark, lit on focus (same shape as
/// `TVWeakSpotHeroStyle`, distinct accent for a distinct Club card).
struct TVMarathonHeroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 28).fill(Tidbits.Palette.teal.gradient))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.03 : 1.0)
                .shadow(color: Tidbits.Palette.teal.opacity(focused ? 0.6 : 0), radius: 30, y: 12)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

/// The Expeditions hero — pink, white-on-dark, lit on focus (same shape as
/// `TVMarathonHeroStyle`, distinct accent for a distinct Club card).
struct TVExpeditionHeroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 28).fill(Tidbits.Palette.pink.gradient))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 5))
                .scaleEffect(focused ? 1.03 : 1.0)
                .shadow(color: Tidbits.Palette.pink.opacity(focused ? 0.6 : 0), radius: 30, y: 12)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}

/// The Link Wall hero — mint, a LIGHT pop (like the Daily's yellow), so it's
/// black-on-mint rather than white-on-dark like the other Club heroes.
struct TVLinkWallHeroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 28).fill(Tidbits.Palette.mint))
                .scaleEffect(focused ? 1.04 : 1.0)
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 24, y: 10)
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
