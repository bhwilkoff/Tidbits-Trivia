#if os(iOS)
import SwiftUI

/// Home (rule R-HOME-1): ONE primary action — Quick Play — with everything else
/// visually secondary and the mode/category pickers behind a Customize sheet.
/// See docs/HOME-REDESIGN-PROPOSAL.md.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(GameCenterManager.self) private var gameCenter
    @State private var launch: LaunchRequest?
    @State private var showCustomize = false
    @State private var showNightSheet = false
    @State private var showNightSetup = false
    @State private var showJoinNight = false
    @State private var showParty = false
    @State private var showSettings = false
    @State private var showDailyArchive = false
    @State private var nightLaunch: NightLaunchRequest?
    @State private var hostLaunch: NightLaunchRequest?
    @AppStorage("tidbits.hasOnboarded") private var hasOnboarded = false

    private var showOnboarding: Binding<Bool> {
        Binding(get: { !hasOnboarded || DebugHooks.forceOnboarding },
                set: { if !$0 { hasOnboarded = true } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                QuickPlayHero(request: store.quickPlay,
                              isFirstRun: !store.hasQuickPlayHistory,
                              onPlay: { start(store.quickPlay) })
                quickActionsRow
                DailyCard(playedScore: DailyLog.todayScore) {
                    if DailyLog.playedToday { showDailyArchive = true }
                    else { start(LaunchRequest(mode: .daily, category: .named("mixed")), remember: false) }
                }
                TriviaNightCard { showNightSheet = true }
                moreWaysSection
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .padding(.bottom, 32)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                    .tint(Tidbits.Palette.ink)
            }
        }
        .fullScreenCover(item: $launch) { req in
            GameContainerView(mode: req.mode, category: req.category, dailyDay: req.dailyDay)
        }
        .sheet(isPresented: $showDailyArchive) {
            DailyArchiveSheet { day in
                showDailyArchive = false
                start(LaunchRequest(mode: .daily, category: .named("mixed"), dailyDay: day), remember: false)
            }
        }
        .fullScreenCover(item: $nightLaunch) { req in
            NightContainerView(plan: req.plan, category: req.category)
        }
        .fullScreenCover(item: $hostLaunch) { req in
            NightLiveContainer(hosting: req.plan, category: req.category,
                               engine: store.game, hostName: NightClient.lastName)
        }
        .fullScreenCover(isPresented: $showJoinNight) {
            NightLiveContainer(joining: store.game)
        }
        .fullScreenCover(isPresented: $showParty) { PartyContainerView() }
        .sheet(isPresented: $showCustomize) {
            CustomizeSheet(initial: store.quickPlay,
                           presets: store.presets,
                           onStart: { req in showCustomize = false; start(req) },
                           onSave: { store.savePreset($0) },
                           onDelete: { store.deletePreset($0) })
        }
        .sheet(isPresented: $showNightSheet) {
            NightEntrySheet(onStart: { showNightSheet = false; showNightSetup = true },
                            onJoin: { showNightSheet = false; showJoinNight = true })
        }
        .sheet(isPresented: $showNightSetup) {
            NightSetupView { plan, category, mode in
                switch mode {
                case .solo: nightLaunch = NightLaunchRequest(plan: plan, category: category)
                case .host: hostLaunch = NightLaunchRequest(plan: plan, category: category)
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: showOnboarding) {
            OnboardingView { hasOnboarded = true }
        }
        .task {
            if launch == nil, let ap = DebugHooks.autoplay {
                start(LaunchRequest(mode: ap.mode, category: ap.category))
            }
            if DebugHooks.openParty { showParty = true }
            if DebugHooks.openCustomize { showCustomize = true }
            if DebugHooks.openDailyArchive { showDailyArchive = true }
        }
        .onChange(of: gameCenter.pendingChallengeMode) { _, m in
            if m != nil, let mode = gameCenter.consumePendingChallenge() {
                start(LaunchRequest(mode: mode, category: .named("mixed")))
            }
        }
    }

    /// Launch a game and (unless it's the Daily) remember it as the Quick Play default.
    private func start(_ req: LaunchRequest, remember: Bool = true) {
        if remember { store.rememberSelection(mode: req.mode, category: req.category) }
        launch = req
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TIDBITS")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
                .kerning(1)
            Text("Trivia from the whole of Wikipedia.")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    /// R-HOME-1a: the hero is ONE action — Surprise + Customize live here,
    /// two quiet equal-weight secondary buttons directly beneath it.
    private var quickActionsRow: some View {
        HStack(spacing: 14) {
            QuickActionButton(symbol: "die.face.5.fill", title: "Surprise me") { start(store.surpriseMe()) }
            QuickActionButton(symbol: "slider.horizontal.3", title: "Customize") { showCustomize = true }
        }
    }

    private var moreWaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More ways to play")
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            HStack(spacing: 14) {
                SmallTile(symbol: "person.2.fill", title: "Pass & Play", fill: Tidbits.Palette.grape) { showParty = true }
                // Placeholder for the next marquee feature (Decision 036) —
                // Create still lives one tap away in its own tab.
                ComingSoonTile(symbol: "globe.americas.fill", title: "Online Multiplayer")
            }
        }
    }
}

// MARK: - Quick Play hero (the ONE primary action)

private struct QuickPlayHero: View {
    let request: LaunchRequest
    let isFirstRun: Bool
    let onPlay: () -> Void

    private var fg: Color { Tidbits.Palette.coral.legibleForeground }

    // ONE action, one real Button (R-HOME-1a) — no embedded second target.
    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 28, weight: .black))
                    Text("QUICK PLAY")
                        .font(.system(size: 30, weight: .black, design: .rounded)).kerning(0.5)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(fg)
                Text("\(request.mode.title.uppercased()) · \(request.category.name.uppercased())")
                    .font(Tidbits.TypeRamp.l6)
                    .foregroundStyle(fg.opacity(0.95))
                Text(isFirstRun ? "Tap to play — customize anytime" : "Jump straight into a round")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(fg.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .chunkyCard(fill: Tidbits.Palette.coral)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

/// One of the two quiet secondary actions under the hero (R-HOME-1a).
private struct QuickActionButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                Text(title).font(Tidbits.TypeRamp.l3)
            }
            .foregroundStyle(Tidbits.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small tile (More ways to play)

private struct SmallTile: View {
    let symbol: String
    let title: String
    let fill: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 24, weight: .black))
                Text(title).font(Tidbits.TypeRamp.l3)
            }
            .foregroundStyle(fill.legibleForeground)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .padding(14)
            .chunkyCard(fill: fill)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .padding(.bottom, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Coming-soon tile (the Online Multiplayer placeholder, Decision 036)

private struct ComingSoonTile: View {
    let symbol: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24, weight: .black))
            Text(title).font(Tidbits.TypeRamp.l3)
            Text("Coming soon").font(Tidbits.TypeRamp.l5).opacity(0.7)
        }
        .foregroundStyle(Tidbits.Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5])))
        .opacity(0.75)
        .accessibilityLabel("\(title), coming soon")
    }
}

// MARK: - Unified Trivia Night sheet (host OR join — backlog #4)

private struct NightEntrySheet: View {
    let onStart: () -> Void
    let onJoin: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trivia Night")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text("A night of mixed rounds — every kind of question. Host for the room, or join someone's code. Apple or Android, same code.")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            Button(action: onStart) {
                nightRow(symbol: "play.fill", title: "Start a night", sub: "Host for others, or play solo")
                    .chunkyCard(fill: Tidbits.Palette.coral)
            }
            .buttonStyle(.plain)
            Button(action: onJoin) {
                nightRow(symbol: "number", title: "Join a night", sub: "Enter a host's 4-letter code")
                    .chunkyCard(fill: Tidbits.Palette.teal)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func nightRow(symbol: String, title: String, sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .black))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Tidbits.TypeRamp.l3)
                Text(sub).font(Tidbits.TypeRamp.l5).opacity(0.9)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
        }
        .foregroundStyle(Color.white)
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Customize sheet (mode + category + presets, one Start)

private struct CustomizeSheet: View {
    let initial: LaunchRequest
    let presets: [GamePreset]
    let onStart: (LaunchRequest) -> Void
    let onSave: (GamePreset) -> Void
    let onDelete: (GamePreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: GameMode
    @State private var category: TriviaCategory
    @State private var showAllModes: Bool
    @State private var saving = false
    @State private var presetName = ""

    private let coreModes: [GameMode] = [.classic, .timeAttack, .survival, .stake]
    private var playableModes: [GameMode] {
        GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia }
    }
    // 150pt floor: every mode/category name fits ONE line — narrower cells
    // mid-word-wrapped "Survival"/"Geography" (the owner's "text is bad" bug).
    private let grid = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    init(initial: LaunchRequest, presets: [GamePreset],
         onStart: @escaping (LaunchRequest) -> Void,
         onSave: @escaping (GamePreset) -> Void,
         onDelete: @escaping (GamePreset) -> Void) {
        self.initial = initial; self.presets = presets
        self.onStart = onStart; self.onSave = onSave; self.onDelete = onDelete
        _mode = State(initialValue: initial.mode)
        _category = State(initialValue: initial.category)
        _showAllModes = State(initialValue: ![GameMode.classic, .timeAttack, .survival, .stake].contains(initial.mode))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    modeSection
                    categorySection
                    if !presets.isEmpty { presetsSection }
                }
                .padding(20)
            }
            .background(Tidbits.Palette.bg.ignoresSafeArea())
            .navigationTitle("Customize a game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save preset") { presetName = suggestedName; saving = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { onStart(LaunchRequest(mode: mode, category: category)) } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .alert("Save this combination", isPresented: $saving) {
                TextField("Name", text: $presetName)
                Button("Save") {
                    let name = presetName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { onSave(GamePreset(name: name, mode: mode, categoryIDs: [category.id])) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    private var suggestedName: String { "\(category.name) \(mode.title)" }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
                ForEach(showAllModes ? playableModes : coreModes) { m in
                    ModeChip(mode: m, selected: mode == m) { mode = m }
                }
            }
            // Bare mode names ("Stake", "Which First?") don't explain
            // themselves — the selected mode always shows its one-liner.
            Text("\(mode.title): \(mode.blurb)")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            Button { withAnimation { showAllModes.toggle() } } label: {
                Text(showAllModes ? "Show fewer modes" : "Show all modes")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
                ForEach(TriviaCategory.all) { c in
                    let on = category.id == c.id
                    Button { category = c } label: {
                        Text(c.name)
                            .font(Tidbits.TypeRamp.l3)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(on ? c.color.legibleForeground : Tidbits.Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .background(Capsule().fill(on ? c.color : Tidbits.Palette.surface))
                            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My presets").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
                ForEach(presets) { p in
                    Button { mode = p.mode; category = .named(p.primaryCategoryID) } label: {
                        Text(p.name)
                            .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .background(Capsule().fill(Tidbits.Palette.surface))
                            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { onDelete(p) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
    }
}

// MARK: - Daily card (kept prominent — the daily-return habit)

private struct DailyCard: View {
    /// Non-nil once today's Daily is done — the card flips to its locked
    /// state and the tap opens the Previous Tidbits archive (R-DAILY-1).
    let playedScore: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: playedScore == nil ? "sun.max.fill" : "checkmark.seal.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Tidbits.Palette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY TIDBIT")
                        .font(Tidbits.TypeRamp.l2)
                        .foregroundStyle(Tidbits.Palette.ink)
                    if let playedScore {
                        Text("Done for today — you scored \(playedScore). New set tomorrow.")
                            .font(Tidbits.TypeRamp.l5)
                            .foregroundStyle(Tidbits.Palette.ink.opacity(0.75))
                            .multilineTextAlignment(.leading)
                        Text("Play previous days")
                            .font(Tidbits.TypeRamp.l5)
                            .foregroundStyle(Tidbits.Palette.ink)
                            .underline()
                    } else {
                        Text("7 questions. Everyone gets the same set. Keep your streak.")
                            .font(Tidbits.TypeRamp.l5)
                            .foregroundStyle(Tidbits.Palette.ink.opacity(0.75))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Tidbits.Palette.ink)
            }
            .padding(18)
            .chunkyCard(fill: Tidbits.Palette.yellow)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Previous Tidbits (the Daily archive, R-DAILY-1)

private struct DailyArchiveSheet: View {
    let onPlay: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DailyLog.recentDays(), id: \.day) { entry in
                        row(for: entry)
                    }
                } footer: {
                    Text("Every day has its own set of 7 — the same for everyone. Catching up on a missed day doesn't change your streak.")
                }
            }
            .navigationTitle("Previous Tidbits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func row(for entry: (day: String, score: Int?)) -> some View {
        let today = QuestionProvider.dayKey()
        HStack {
            Text(Self.label(for: entry.day, today: today))
            Spacer()
            if let score = entry.score {
                Text("Scored \(score)")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            } else if entry.day == today {
                Button("Play") { onPlay(entry.day) }.buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
            } else {
                Button("Play") { onPlay(entry.day) }.buttonStyle(.bordered)
            }
        }
    }

    static func label(for day: String, today: String) -> String {
        if day == today { return "Today" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day) else { return day }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

// MARK: - Trivia Night card (one unified entry → the host/join sheet)

private struct TriviaNightCard: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Tidbits.Palette.coral.legibleForeground)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRIVIA NIGHT")
                        .font(Tidbits.TypeRamp.l2)
                        .foregroundStyle(Tidbits.Palette.coral.legibleForeground)
                    Text("Host or join a night of mixed rounds.")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.coral.legibleForeground.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Tidbits.Palette.coral.legibleForeground)
            }
            .padding(18)
            .chunkyCard(fill: Tidbits.Palette.coral)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Mode chip (used in the Customize sheet)

private struct ModeChip: View {
    let mode: GameMode
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.symbol).font(.system(size: 15, weight: .bold))
                Text(mode.title).font(Tidbits.TypeRamp.l3)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? mode.accent.legibleForeground : Tidbits.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Capsule().fill(selected ? mode.accent : Tidbits.Palette.surface))
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }
}
#endif
