#if os(macOS)
import SwiftUI

/// The Mac Play screen (macOS-DESIGN Part B). Reuses Core verbatim
/// (store.quickPlay / surpriseMe / GameMode / TriviaCategory). Mac idiom: the
/// window has room, so the mode + category picker lives inline on one screen
/// rather than behind a sheet — pointer + click, no tab bar.
struct HomeView_macOS: View {
    let onPlay: (LaunchRequest) -> Void
    let onNight: (NightLaunchRequest) -> Void
    let onVersus: (BotProfile) -> Void

    @Environment(AppStore.self) private var store
    @State private var mode: GameMode = .classic
    @State private var category: TriviaCategory = .named("mixed")
    @State private var showCustomize = false
    @State private var showDailyArchive = false
    @State private var showNightSetup = false
    @State private var showMultiplayer = false

    /// Single-player modes the picker offers (Daily, Trivia Night, and the
    /// Custom Mix builder are their own surfaces — parity follow-ups).
    private let modes: [GameMode] = GameMode.allCases.filter {
        $0 != .daily && $0 != .barTrivia && $0 != .mix
    }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickPlayHero
                HStack(spacing: 14) {
                    secondaryButton("Surprise me", symbol: "die.face.5.fill") { onPlay(store.surpriseMe()) }
                    secondaryButton("Customize…", symbol: "slider.horizontal.3") { showCustomize = true }
                    dailyButton
                }
                Button("Previous Tidbits…") { showDailyArchive = true }
                    .buttonStyle(.plain).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue)
                triviaNightCard
                onlineCard
                modeSection
                categorySection
                startBar
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Play")
        .sheet(isPresented: $showCustomize) {
            CustomizeSheet_macOS(initial: store.quickPlay, presets: store.presets,
                                 onStart: onPlay, onSave: { store.savePreset($0) }, onDelete: { store.deletePreset($0) })
        }
        .sheet(isPresented: $showDailyArchive) {
            DailyArchiveSheet_macOS { day in
                onPlay(LaunchRequest(mode: .daily, category: .named("mixed"), dailyDay: day))
            }
        }
        .sheet(isPresented: $showNightSetup) {
            NightSetupSheet_macOS { plan, category in
                onNight(NightLaunchRequest(plan: plan, category: category))
            }
        }
        .sheet(isPresented: $showMultiplayer) {
            MultiplayerSheet_macOS(recentAccuracy: 0.6, onPickBot: onVersus)
        }
    }

    private var onlineCard: some View {
        Button { showMultiplayer = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "globe.americas.fill").font(.system(size: 24, weight: .black))
                VStack(alignment: .leading, spacing: 3) {
                    Text("ONLINE MULTIPLAYER").font(Tidbits.TypeRamp.l2)
                    Text("Play vs CPU now — real players soon.").font(Tidbits.TypeRamp.l5).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(Tidbits.Palette.blue.legibleForeground)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.blue)
        }
        .buttonStyle(.plain)
    }

    private var triviaNightCard: some View {
        Button { showNightSetup = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "party.popper.fill").font(.system(size: 26, weight: .black))
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRIVIA NIGHT").font(Tidbits.TypeRamp.l2)
                    Text("A night of mixed rounds — every kind of question.").font(Tidbits.TypeRamp.l5).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(Tidbits.Palette.coral.legibleForeground)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.coral)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TIDBITS")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text("Trivia from the whole of Wikipedia.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private var quickPlayHero: some View {
        let req = store.quickPlay
        return Button { onPlay(req) } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "play.fill").font(.system(size: 26, weight: .black))
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUICK PLAY").font(.system(size: 28, weight: .black, design: .rounded))
                    Text("\(req.mode.title.uppercased()) · \(req.category.name.uppercased())")
                        .font(Tidbits.TypeRamp.l6).opacity(0.95)
                    Text(store.hasQuickPlayHistory ? "Click to jump straight into a round" : "Click to play — customize anytime")
                        .font(Tidbits.TypeRamp.l5).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Tidbits.Palette.coral.legibleForeground)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.coral)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)   // ⏎ starts Quick Play
    }

    private var dailyButton: some View {
        let played = DailyLog.playedToday
        return Button {
            onPlay(LaunchRequest(mode: .daily, category: .named("mixed")))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: played ? "checkmark.seal.fill" : "sun.max.fill")
                    .font(.system(size: 17, weight: .bold))
                Text(played ? "Daily done" : "Daily Tidbit").font(Tidbits.TypeRamp.l3)
            }
            .foregroundStyle(Tidbits.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.yellow))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .disabled(played)
    }

    private func secondaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
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

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a mode").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(modes) { m in
                    chip(title: m.title, symbol: m.symbol, on: mode == m, accent: m.accent) { mode = m }
                }
            }
            Text("\(mode.title): \(mode.blurb)")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a category").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(TriviaCategory.all) { c in
                    chip(title: c.name, symbol: c.symbol, on: category.id == c.id, accent: c.color) { category = c }
                }
            }
        }
    }

    private var startBar: some View {
        Button {
            onPlay(LaunchRequest(mode: mode, category: category))
        } label: {
            Label("Start \(mode.title) · \(category.name)", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
        .padding(.top, 4)
    }

    private func chip(title: String, symbol: String, on: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                Text(title).font(Tidbits.TypeRamp.l3).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? accent.legibleForeground : Tidbits.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Capsule().fill(on ? accent : Tidbits.Palette.surface))
            .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }
}
#endif
