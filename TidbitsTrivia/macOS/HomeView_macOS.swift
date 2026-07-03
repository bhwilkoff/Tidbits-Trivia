#if os(macOS)
import SwiftUI

/// The Mac Play screen — parity with iOS Home (R-HOME-1): ONE primary action
/// (Quick Play), two quiet secondary buttons (Surprise + Customize) beneath it,
/// then the prominent Daily card, the Trivia Night card, and Online Multiplayer.
/// Mode/category selection lives BEHIND Customize… (a sheet), never inline —
/// the same rule as iOS. Reuses Core verbatim (quickPlay / surpriseMe / DailyLog).
struct HomeView_macOS: View {
    let onPlay: (LaunchRequest) -> Void
    let onNight: (NightLaunchRequest) -> Void
    let onVersus: (BotProfile) -> Void

    @Environment(AppStore.self) private var store
    @State private var showCustomize = false
    @State private var showDailyArchive = false
    @State private var showNightSetup = false
    @State private var showMultiplayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                quickPlayHero
                quickActionsRow
                dailyCard
                triviaNightCard
                onlineCard
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)   // centered reading column
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TIDBITS")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text("Trivia from the whole of Wikipedia.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// R-HOME-1a: the hero is ONE action (⏎ starts it).
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
        .keyboardShortcut(.defaultAction)
    }

    /// R-HOME-1a: two quiet, equal-weight secondary actions under the hero.
    private var quickActionsRow: some View {
        HStack(spacing: 14) {
            secondaryButton("Surprise me", symbol: "die.face.5.fill") { onPlay(store.surpriseMe()) }
            secondaryButton("Customize…", symbol: "slider.horizontal.3") { showCustomize = true }
        }
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

    /// The Daily card — prominent (the daily-return habit). Done → opens the
    /// Previous Tidbits archive; not done → starts today's set (R-DAILY-1).
    private var dailyCard: some View {
        let score = DailyLog.todayScore
        return Button {
            if DailyLog.playedToday { showDailyArchive = true }
            else { onPlay(LaunchRequest(mode: .daily, category: .named("mixed"))) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: score == nil ? "sun.max.fill" : "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .black)).foregroundStyle(Tidbits.Palette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY TIDBIT").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    if let score {
                        Text("Done for today — you scored \(score). New set tomorrow.")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink.opacity(0.75)).multilineTextAlignment(.leading)
                        Text("Play previous days").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink).underline()
                    } else {
                        Text("7 questions. Everyone gets the same set. Keep your streak.")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink.opacity(0.75)).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(Tidbits.Palette.ink)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.yellow)
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
                Image(systemName: "chevron.right.circle.fill").font(.system(size: 24, weight: .bold))
            }
            .foregroundStyle(Tidbits.Palette.coral.legibleForeground)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.coral)
        }
        .buttonStyle(.plain)
    }

    private var onlineCard: some View {
        Button { showMultiplayer = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "globe.americas.fill").font(.system(size: 26, weight: .black))
                VStack(alignment: .leading, spacing: 3) {
                    Text("ONLINE MULTIPLAYER").font(Tidbits.TypeRamp.l2)
                    Text("Play vs CPU now — real players soon.").font(Tidbits.TypeRamp.l5).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill").font(.system(size: 24, weight: .bold))
            }
            .foregroundStyle(Tidbits.Palette.blue.legibleForeground)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: Tidbits.Palette.blue)
        }
        .buttonStyle(.plain)
    }
}
#endif
