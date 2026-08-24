#if os(tvOS)
import SwiftUI
import SwiftData

// MARK: - tvOS palette (dark-first; reserve brightness for focus)

/// A created/saved quiz on its way to the game container. Identifiable so it can
/// drive `fullScreenCover(item:)` — the questions are carried rather than re-drawn,
/// because a saved quiz must be the SAME quiz every time.
struct TVCustomLaunch: Identifiable {
    let id = UUID()
    let title: String
    let questions: [Question]
    let mode: GameMode
}

enum TVTheme {
    static let bg = Color(hex: 0x0E0C0B)
    static let panel = Color(hex: 0x1C1916)
    /// One step up from `panel` — the fill a focused row lifts to. Brightness is reserved
    /// for focus (tvOS-DESIGN), so this is the ONLY lighter surface in the palette.
    static let panelFocused = Color(hex: 0x2E2823)
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
    @State private var sharedItemID: TVSharedItemID?
    /// Same key as macOS, so a household that already saw the walkthrough on one Apple
    /// device does not get it again on another once iCloud syncs defaults.
    @AppStorage("tidbits.hasOnboarded") private var hasOnboarded = false
    @State private var showSettings = false
    @State private var showNightSetup = false
    @State private var showCustomize = false
    @State private var showDailyArchive = false
    @State private var showClubPaywall = false
    @State private var showClubHub = false
    @State private var versusBot: BotProfile?
    @State private var showQuickMatch = false
    @State private var showCreate = false
    @State private var customLaunch: TVCustomLaunch?
    @Environment(\.modelContext) private var modelContext
    @FocusState private var primaryFocused: Bool
    // Marathon (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3").
    @Query private var marathonRuns: [MarathonRun]
    @State private var showMarathonChoice = false
    // Expeditions (Club — docs/CLUB-FEATURES-BUILD.md "Feature 5"). Reached from the Club
    // hub (R-CLUB-1); ContentView still owns the stage launch.
    @State private var expeditionLaunch: TVExpeditionStageLaunch?
    // Link Wall (Club — docs/CLUB-FEATURES-BUILD.md "Feature 6"). Sorted desc
    // + filtered by day rather than a predicate-init'd @Query, so this view's
    // existing memberwise init stays untouched (rows accumulate, one per day).
    @State private var showLinkWall = false

    /// Launch a game and (unless Daily) remember it as the Quick Play default.
    /// Consume the deep-link inbox. The TV has no tab bar and no navigation stack, so a
    /// link resolves to "present the right cover", which is what every other tvOS entry
    /// point does too.
    private func handleInbox() {
        for link in store.drainInbox() {
            switch link {
            case .daily:
                launch = LaunchRequest(mode: .daily, category: .named("mixed"))
            case .topic, .category:
                break   // the Play screen IS the home surface here; nothing to navigate to
            case .quiz(let id):
                store.pendingSharedQuizID = id
                showCreate = true          // Create owns saved quizzes on tvOS too
            case .item(let id):
                sharedItemID = TVSharedItemID(id: id)
            case .surprise:
                launch = store.surpriseMe()
            }
        }
    }

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
                    nightHero
                    multiplayerPanel
                    createPanel
                    // R-CLUB-1: ONE Club door for the whole app.
                    clubHero
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
            }
        }
        .defaultFocus($primaryFocused, true)
        .task { if DebugHooks.openCreate { showCreate = true } }
        // Deep links land in the store inbox (App.onOpenURL) and are consumed HERE.
        // tvOS registered `tidbits://` from day one (one Info.plist serves the whole
        // universal target) and posted every link into the inbox — but nothing ever
        // drained it, so a Top Shelf / Siri / QR link launched the app and then did
        // nothing at all. iOS and macOS have always had this; the TV never did.
        .onChange(of: store.inbox) { _, _ in handleInbox() }
        .onAppear {
            if let id = DebugHooks.openItemID { store.post(.item(id)) }
            // An App Intent runs before the scene exists on a cold launch (see IntentInbox).
            if let fromIntent = IntentInbox.take() { store.post(fromIntent) }
            handleInbox()
        }
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
        .fullScreenCover(isPresented: $showCreate) {
            CreateView_tvOS { title, questions, mode in
                showCreate = false
                customLaunch = TVCustomLaunch(title: title, questions: questions, mode: mode)
            }
        }
        .fullScreenCover(item: $customLaunch) { req in
            TVGameContainer(mode: req.mode, category: .named("mixed"), customQuestions: req.questions)
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
        .fullScreenCover(item: $sharedItemID) { SharedItemView_tvOS(id: $0.id) }
        // First run. A cover rather than a sheet: tvOS has no partial presentation, and
        // the walkthrough should own the screen once and never again.
        .fullScreenCover(isPresented: Binding(get: { (!hasOnboarded || DebugHooks.forceOnboarding) && !DebugHooks.skipOnboarding },
                                              set: { if !$0 { hasOnboarded = true } })) {
            OnboardingView_tvOS { hasOnboarded = true }
        }
        .fullScreenCover(isPresented: $showClubPaywall) { ClubPaywallView_tvOS() }
        .fullScreenCover(isPresented: $showClubHub) {
            ClubHubView_tvOS(onStartWeakSpot: { showClubHub = false; launch = LaunchRequest(mode: .weakSpot, category: .named("mixed")) },
                             onStartMarathon: { showClubHub = false; openMarathon() },
                             onOpenLinkWall: { showClubHub = false; openLinkWall() },
                             onPlayExpeditionStage: { expedition, stageIndex in
                                 showClubHub = false
                                 expeditionLaunch = TVExpeditionStageLaunch(expedition: expedition, stageIndex: stageIndex)
                             },
                             onPlay: { req in showClubHub = false; launch = req },
                             onClose: { showClubHub = false })
        }
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
        .fullScreenCover(item: $expeditionLaunch) { launch in
            TVGameContainer(mode: .classic, category: .named(launch.stage.categoryID),
                            expedition: launch.expedition, expeditionStageIndex: launch.stageIndex)
        }
        .fullScreenCover(isPresented: $showLinkWall) {
            LinkWallView_tvOS(day: QuestionProvider.dayKey()) { showLinkWall = false }
        }
        .task {
            DebugHooks.seedRecordsIfRequested(modelContext)
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
            // R-CLUB-1: the per-feature hooks open the hub, which routes from there.
            if DebugHooks.openExpedition || DebugHooks.expeditionMapPreview != nil
                || DebugHooks.expeditionAutoplay != nil
                || DebugHooks.openStoryArchive || DebugHooks.openAtlas || DebugHooks.openClubHub {
                openClub()
            }
            if DebugHooks.openLinkWall { openLinkWall() }
            if DebugHooks.openNightSetup { showNightSetup = true }
            // TIDBITS_NIGHT_HOST=1 hosts a networked night directly (the QA
            // harness's cross-platform join test pins TIDBITS_LIVE_CODE and a
            // scripted RTDB player joins) — found unwired on tvOS, same class
            // as the TIDBITS_VERSUS gap.
            if hostLaunch == nil, DebugHooks.openNightHost {
                hostLaunch = NightLaunchRequest(plan: .quick, category: .named("mixed"))
            }
            if DebugHooks.openCustomize { showCustomize = true }
            if DebugHooks.openDailyArchive { showDailyArchive = true }
            if let q = DebugHooks.sharedQuizID { store.post(.quiz(q)) }
            // TIDBITS_PAYWALL=1 opens the paywall on the real path App Review takes
            // (Home → Tidbits Club), one cover deep — never stacked under Settings.
            if DebugHooks.showPaywall { showClubPaywall = true }
            if DebugHooks.openSettings { showSettings = true }
            // TIDBITS_VERSUS / TIDBITS_MULTIPLAYER were iOS-only until the device
            // QA harness found the tvOS scenarios silently exercising the HOME
            // screen — the hooks parsed fine and set nothing here.
            if launch == nil, let bot = DebugHooks.versusBot {
                switch bot {
                case "rookie":  versusBot = .rookie
                case "regular": versusBot = .regular
                case "ace":     versusBot = .ace
                default:        versusBot = BotProfile.house(playerAccuracy: recentAccuracy)
                }
            }
            if DebugHooks.openMultiplayer { showQuickMatch = true }
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

    // MARK: - Tidbits Club (rule R-CLUB-1) — the app's ONE Club entry point

    /// Was four locked heroes here plus three "see all" rows in Records. One quiet door,
    /// below the free surfaces: members go to `ClubHubView_tvOS`, everyone else to the
    /// paywall. Nothing else in the app may offer Club.
    private var clubHero: some View {
        Button { openClub() } label: {
            HStack(spacing: 28) {
                Image(systemName: entitlement.isClub ? "star.circle.fill" : "star.circle")
                    .font(.system(size: 44, weight: .black)).foregroundStyle(Tidbits.Palette.blue).frame(width: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tidbits Club").font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                    Text(entitlement.isClub ? "Your six Club features, all in one place."
                                            : "Six optional extras for getting better. Everything else in Tidbits is free.")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(TVTheme.textSoft).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 26, weight: .bold))
                    .foregroundStyle(TVTheme.textSoft)
            }
            .padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TVAtlasCardStyle())
    }

    private func openClub() {
        if entitlement.isClub { showClubHub = true } else { showClubPaywall = true }
    }

    private func openLinkWall() { showLinkWall = true }

    /// Members with a run in progress get the Resume / Start Over choice; with no run they
    /// go straight into a fresh one. Driven from the hub, but ContentView owns the launch.
    private func openMarathon() {
        if marathonRuns.first != nil {
            showMarathonChoice = true
        } else {
            launch = LaunchRequest(mode: .marathon, category: .named("mixed"))
        }
    }


    /// Create earns a home-screen panel rather than a tab, because tvOS has no tab
    /// bar here — the home IS the map. Copy leads with the shelf, since on a TV most
    /// quizzes arrive from a phone rather than being typed in the room.
    private var createPanel: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 28) {
                Image(systemName: "sparkles").font(.system(size: 52, weight: .black))
                VStack(alignment: .leading, spacing: 8) {
                    Text("CREATE").font(.system(size: 40, weight: .black, design: .rounded))
                    Text("Build a quiz on any subject — and play the ones you made on your phone.")
                        .font(.body).foregroundStyle(TVTheme.textSoft)
                        .frame(maxWidth: 900, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(34)
        }
        .buttonStyle(.card)
        .focusSection()
    }

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
                                    // Coverage disclosure (the rule iOS + web already carry):
                                    // a mode x category the bundle cannot fill still PLAYS —
                                    // assembled from other categories — and saying nothing
                                    // reads as a lie. The card says what you'll actually get.
                                    let thin = !QuestionProvider.canFill(mode: selectedMode, categoryID: cat.id)
                                    Button { onPlay(selectedMode, cat) } label: {
                                        VStack(alignment: .leading, spacing: 16) {
                                            Image(systemName: cat.symbol).font(.system(size: 44, weight: .black)).foregroundStyle(.white)
                                            Spacer()
                                            Text(cat.name).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                                            Text(thin ? "No \(selectedMode.title) questions yet — you'll get a mixed round." : cat.blurb)
                                                .font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                                                .lineLimit(2)
                                        }
                                        .padding(28)
                                        .frame(width: 320, height: 300, alignment: .leading)
                                    }
                                    // Dimmed, never disabled — on a TV a disabled card is a
                                    // focus dead end, which is worse than an honest one.
                                    .buttonStyle(TVCategoryStyle(accent: thin ? cat.color.opacity(0.45) : cat.color))
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

/// `fullScreenCover(item:)` needs an Identifiable, and a bare String isn't one.
struct TVSharedItemID: Identifiable {
    let id: String
}
#endif
