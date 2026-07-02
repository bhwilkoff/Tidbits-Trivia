#if os(iOS)
import SwiftUI

/// Online Multiplayer — the home surface (Decision 038). v0 = Play vs CPU
/// (offline, honest CPU labels); the Quick Match row is the v1 slot and says
/// so honestly instead of pretending.
struct MultiplayerSheet: View {
    let recentAccuracy: Double
    let onPickBot: (BotProfile) -> Void
    let onQuickMatch: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Online Multiplayer")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                Text("Face an opponent on the same questions — fastest correct answers win.")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)

                // LIVE (Decision 039): Game Center matchmaking, Apple-to-Apple.
                Button(action: onQuickMatch) {
                    HStack(spacing: 14) {
                        Image(systemName: "globe.americas.fill").font(.system(size: 24, weight: .black))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quick Match").font(Tidbits.TypeRamp.l3)
                            Text("Match with real players over Game Center")
                                .font(Tidbits.TypeRamp.l5).opacity(0.9)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(Tidbits.Palette.blue.legibleForeground)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .chunkyCard(fill: Tidbits.Palette.blue)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Tidbits.Metric.shadowOffset)

                Text("Play a CPU opponent now")
                    .font(Tidbits.TypeRamp.l2)
                    .foregroundStyle(Tidbits.Palette.ink)

                botRow(BotProfile.house(playerAccuracy: recentAccuracy),
                       blurb: "Adapts to how you've been playing — a fair fight",
                       fill: Tidbits.Palette.coral)
                botRow(.rookie, blurb: "Takes it easy. Strong on sports and film", fill: Tidbits.Palette.mint)
                botRow(.regular, blurb: "A solid all-rounder. Loves history", fill: Tidbits.Palette.blue)
                botRow(.ace, blurb: "Fast and sharp. Science is its home turf", fill: Tidbits.Palette.grape)
            }
            .padding(24)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func botRow(_ bot: BotProfile, blurb: String, fill: Color) -> some View {
        Button { onPickBot(bot) } label: {
            HStack(spacing: 14) {
                Image(systemName: "cpu").font(.system(size: 24, weight: .black))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bot.name).font(Tidbits.TypeRamp.l3)
                        CPUTag()
                    }
                    Text(blurb).font(Tidbits.TypeRamp.l5).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(fill.legibleForeground)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard(fill: fill)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

/// The honest label (Decision 038): every bot is visibly CPU, everywhere.
struct CPUTag: View {
    var body: some View {
        Text("CPU")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.black.opacity(0.25)))
    }
}

/// Owns one Play-vs-CPU match: a normal classic game with a BotMatch resolving
/// the opponent on the same questions; standings live in the play view seam.
struct VersusContainerView: View {
    let bot: BotProfile

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var match: BotMatch?

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            if let match {
                switch game.phase {
                case .idle, .loading:
                    ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
                case .playing, .reveal:
                    GamePlayView(game: game, versus: match, onQuit: close)
                case .finished:
                    VersusResultsView(match: match, game: game, onRematch: rematch, onDone: close)
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

    private func close() {
        game.quit()
        dismiss()
    }
}

// MARK: - In-game strip + reveal card

/// "You 320 · Ace Botsworth CPU 410" — the running head-to-head.
struct VersusStrip: View {
    let match: BotMatch
    let game: GameEngine

    var body: some View {
        HStack(spacing: 10) {
            Text("You \(game.score)")
                .font(Tidbits.TypeRamp.l3)
                .foregroundStyle(Tidbits.Palette.ink)
            Spacer(minLength: 0)
            ForEach(match.seats) { seat in
                HStack(spacing: 5) {
                    Text("\(seat.bot.name) \(seat.score)")
                        .font(Tidbits.TypeRamp.l3)
                        .foregroundStyle(Tidbits.Palette.ink)
                    CPUTag().foregroundStyle(Tidbits.Palette.ink)
                }
            }
        }
        .padding(.horizontal, Tidbits.Metric.pad)
        .padding(.vertical, 8)
        .background(Tidbits.Palette.surface)
    }
}

/// What the opponent did on THIS question — shown inside the reveal beat.
struct VersusRevealCard: View {
    let match: BotMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(match.seats) { seat in
                HStack(spacing: 8) {
                    Image(systemName: seat.lastCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(seat.lastCorrect == true ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                    Text(line(for: seat))
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.ink)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tidbits.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
    }

    private func line(for seat: BotMatch.Seat) -> String {
        guard let answer = match.pending.first(where: { $0.botID == seat.bot.id }) else { return seat.bot.name }
        if !answer.answered { return "\(seat.bot.name) ran out of time" }
        let secs = answer.seconds.map { String(format: "%.1fs", $0) } ?? ""
        return seat.lastCorrect == true
            ? "\(seat.bot.name) got it in \(secs)"
            : "\(seat.bot.name) missed it"
    }
}

// MARK: - Final standings

struct VersusResultsView: View {
    let match: BotMatch
    let game: GameEngine
    let onRematch: () -> Void
    let onDone: () -> Void

    private var won: Bool { game.score >= (match.standings.first?.score ?? 0) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(won ? "You won! 🎉" : "\(match.standings.first?.bot.name ?? "The CPU") takes it")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                    .padding(.top, 30)
                VStack(spacing: 10) {
                    standingRow(name: "You", score: game.score, isCPU: false,
                                highlight: won)
                    ForEach(match.standings) { seat in
                        standingRow(name: seat.bot.name, score: seat.score, isCPU: true,
                                    highlight: !won && seat.id == match.standings.first?.id)
                    }
                }
                Text("\(game.summary.correct)/\(game.summary.total) correct · rematches sharpen recall")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
                Button("Rematch", action: onRematch)
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                Button("Done", action: onDone)
                    .font(Tidbits.TypeRamp.l3)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .padding(Tidbits.Metric.pad)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
    }

    private func standingRow(name: String, score: Int, isCPU: Bool, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name).font(Tidbits.TypeRamp.l3)
            if isCPU { CPUTag().foregroundStyle(Tidbits.Palette.ink) }
            Spacer(minLength: 0)
            Text("\(score)").font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(Tidbits.Palette.ink)
        .padding(16)
        .frame(maxWidth: .infinity)
        .chunkyCard(fill: highlight ? Tidbits.Palette.yellow : Tidbits.Palette.surface)
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}
#endif
