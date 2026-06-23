#if os(iOS)
import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedMode: GameMode = .classic
    @State private var launch: LaunchRequest?
    @State private var showParty = false
    @State private var showSettings = false
    @State private var showNightSetup = false
    @State private var nightLaunch: NightLaunchRequest?
    @AppStorage("tidbits.hasOnboarded") private var hasOnboarded = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var showOnboarding: Binding<Bool> {
        Binding(get: { !hasOnboarded || DebugHooks.forceOnboarding },
                set: { if !$0 { hasOnboarded = true } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                DailyCard { launch = LaunchRequest(mode: .daily, category: .named("mixed")) }
                TriviaNightCard { showNightSetup = true }
                PartyCard { showParty = true }
                modePicker
                categoriesSection
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
            GameContainerView(mode: req.mode, category: req.category)
        }
        .fullScreenCover(item: $nightLaunch) { req in
            NightContainerView(plan: req.plan, category: req.category)
        }
        .fullScreenCover(isPresented: $showParty) { PartyContainerView() }
        .sheet(isPresented: $showNightSetup) {
            NightSetupView { plan, category in
                nightLaunch = NightLaunchRequest(plan: plan, category: category)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: showOnboarding) {
            OnboardingView { hasOnboarded = true }
        }
        .task {
            // Screenshot/CI hooks — no-ops unless the env vars are set.
            if launch == nil, let ap = DebugHooks.autoplay {
                launch = LaunchRequest(mode: ap.mode, category: ap.category)
            }
            if DebugHooks.openParty { showParty = true }
        }
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

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a mode")
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia }) { mode in
                        ModeChip(mode: mode, selected: selectedMode == mode) {
                            selectedMode = mode
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 8)
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a category")
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(TriviaCategory.all) { cat in
                    CategoryCard(category: cat) {
                        launch = LaunchRequest(mode: selectedMode, category: cat)
                    }
                }
            }
        }
    }
}

// MARK: - Daily card

private struct DailyCard: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Tidbits.Palette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY TIDBIT")
                        .font(Tidbits.TypeRamp.l2)
                        .foregroundStyle(Tidbits.Palette.ink)
                    Text("7 questions. Everyone gets the same set. Keep your streak.")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.ink.opacity(0.75))
                        .multilineTextAlignment(.leading)
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

// MARK: - Party card

private struct PartyCard: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PASS & PLAY")
                        .font(Tidbits.TypeRamp.l2)
                        .foregroundStyle(.white)
                    Text("2–4 players, one phone, same questions.")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(18)
            .chunkyCard(fill: Tidbits.Palette.grape)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Trivia Night card

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
                    Text("Host a night of mixed rounds — every kind of question.")
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

// MARK: - Mode chip

private struct ModeChip: View {
    let mode: GameMode
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.symbol).font(.system(size: 15, weight: .bold))
                Text(mode.title).font(Tidbits.TypeRamp.l3)
            }
            .foregroundStyle(selected ? mode.accent.legibleForeground : Tidbits.Palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(
                Capsule().fill(selected ? mode.accent : Tidbits.Palette.surface)
            )
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category card

private struct CategoryCard: View {
    let category: TriviaCategory
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(category.color.legibleForeground)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(category.color))
                    .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                Text(category.name)
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(Tidbits.Palette.ink)
                Text(category.blurb)
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(16)
            .chunkyCard()
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
        .padding(.bottom, Tidbits.Metric.shadowOffset)
    }
}
#endif
