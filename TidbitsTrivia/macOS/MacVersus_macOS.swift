#if os(macOS)
import SwiftUI

// MARK: - Online Multiplayer (Play vs CPU) — parity, Decision 038

/// Mac Online-Multiplayer sheet: v0 is Play-vs-CPU (offline, honest CPU labels);
/// Quick Match (real players over the network) is the honest v1 slot.
struct MultiplayerSheet_macOS: View {
    let recentAccuracy: Double
    let onPickBot: (BotProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Online Multiplayer").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Face an opponent on the same questions — fastest correct answers win.")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    HStack(spacing: 10) {
                        Image(systemName: "globe.americas.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quick Match").font(Tidbits.TypeRamp.l3)
                            Text("Match with real players — coming soon").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .foregroundStyle(Tidbits.Palette.border.opacity(0.5)))
                    Text("Play a CPU opponent now").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    botRow(.house(playerAccuracy: recentAccuracy), "Adapts to how you've been playing — a fair fight", Tidbits.Palette.coral)
                    botRow(.rookie, "Takes it easy. Strong on sports and film", Tidbits.Palette.mint)
                    botRow(.regular, "A solid all-rounder. Loves history", Tidbits.Palette.blue)
                    botRow(.ace, "Fast and sharp. Science is its home turf", Tidbits.Palette.grape)
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 620)
        .background(Tidbits.Palette.bg)
    }

    private func botRow(_ bot: BotProfile, _ blurb: String, _ fill: Color) -> some View {
        Button { onPickBot(bot); dismiss() } label: {
            HStack(spacing: 14) {
                Image(systemName: "cpu").font(.system(size: 22, weight: .black))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) { Text(bot.name).font(Tidbits.TypeRamp.l3); CPUTag_macOS() }
                    Text(blurb).font(Tidbits.TypeRamp.l5).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(fill.legibleForeground)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: fill)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Versus container (orchestrates the bot alongside the engine)

struct VersusContainer_macOS: View {
    let bot: BotProfile
    let onClose: () -> Void

    @Environment(AppStore.self) private var store
    @State private var match: BotMatch?

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if let match {
                switch game.phase {
                case .idle, .loading:
                    ProgressView().controlSize(.large)
                case .roundIntro, .playing, .reveal:
                    GameView_macOS(game: game, onQuit: close, versus: match)
                case .finished:
                    VersusResultsView_macOS(match: match, game: game, onRematch: rematch, onDone: close)
                }
            }
        }
        .task {
            if match == nil {
                match = BotMatch(bots: [bot])
                await game.start(mode: .classic, category: .named("mixed"))
            }
        }
        .onChange(of: game.phase) { _, phase in
            guard let match, let q = game.current else { return }
            if phase == .playing { match.beginQuestion(q, window: game.displayClockBudget) }
            if phase == .reveal { match.commit(question: q, index: game.index, budget: game.displayClockBudget) }
        }
    }

    private func rematch() {
        match = BotMatch(bots: [bot])
        Task { await game.start(mode: .classic, category: .named("mixed")) }
    }
    private func close() { game.quit(); onClose() }   // versus matches don't write records
}

struct VersusResultsView_macOS: View {
    let match: BotMatch
    let game: GameEngine
    let onRematch: () -> Void
    let onDone: () -> Void
    private var won: Bool { game.score >= (match.standings.first?.score ?? 0) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(won ? "You won! 🎉" : "\(match.standings.first?.bot.name ?? "The CPU") takes it")
                    .font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink).padding(.top, 20)
                VStack(spacing: 10) {
                    row("You", game.score, isCPU: false, highlight: won)
                    ForEach(match.standings) { seat in
                        row(seat.bot.name, seat.score, isCPU: true, highlight: !won && seat.id == match.standings.first?.id)
                    }
                }
                Text("\(game.summary.correct)/\(game.summary.total) correct · rematches sharpen recall")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                HStack(spacing: 14) {
                    Button("Rematch", action: onRematch).buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true)).keyboardShortcut(.defaultAction)
                    Button("Done", action: onDone).buttonStyle(CompactButtonStyle()).keyboardShortcut(.cancelAction)
                }
            }
            .padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
    }

    private func row(_ name: String, _ score: Int, isCPU: Bool, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name).font(Tidbits.TypeRamp.l3)
            if isCPU { CPUTag_macOS() }
            Spacer(minLength: 0)
            Text("\(score)").font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(Tidbits.Palette.ink)
        .padding(16).frame(maxWidth: .infinity)
        .chunkyCard(fill: highlight ? Tidbits.Palette.yellow : Tidbits.Palette.surface)
    }
}
#endif
