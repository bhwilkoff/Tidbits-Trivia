#if os(tvOS)
import SwiftUI
import SwiftData

/// Play vs CPU on the TV (Decision 038) — the online-multiplayer v0. Mirrors
/// the iOS VersusContainerView: a classic game with a bot resolving the same
/// questions. Bots are ALWAYS labeled CPU.
struct TVVersusContainer: View {
    let bot: BotProfile

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var match: BotMatch?

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            if let match {
                switch game.phase {
                case .idle, .loading:
                    ProgressView().controlSize(.large)
                case .playing, .reveal:
                    TVGamePlayView(onQuit: close, versus: match)
                case .finished:
                    TVVersusResults(match: match, game: game, onRematch: rematch, onDone: close)
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
        .onExitCommand(perform: close)
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

/// The honest CPU label at ten feet.
struct TVCPUTag: View {
    var body: some View {
        Text("CPU")
            .font(.system(size: 20, weight: .black, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.18)))
            .foregroundStyle(TVTheme.textSoft)
    }
}

struct TVVersusStrip: View {
    let match: BotMatch
    let game: GameEngine

    var body: some View {
        HStack(spacing: 24) {
            Text("You \(game.score)")
            Spacer()
            ForEach(match.seats) { seat in
                HStack(spacing: 10) {
                    Text("\(seat.bot.name) \(seat.score)")
                    TVCPUTag()
                }
            }
        }
        .font(.system(size: 29, weight: .bold, design: .rounded))
        .foregroundStyle(TVTheme.text)
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(TVTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct TVVersusRevealCard: View {
    let match: BotMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(match.seats) { seat in
                HStack(spacing: 12) {
                    Image(systemName: seat.lastCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(seat.lastCorrect == true ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                    Text(line(for: seat))
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .foregroundStyle(TVTheme.text)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func line(for seat: BotMatch.Seat) -> String {
        guard let answer = match.pending.first(where: { $0.botID == seat.bot.id }) else { return seat.bot.name }
        if !answer.answered { return "\(seat.bot.name) ran out of time" }
        let secs = answer.seconds.map { String(format: "%.1fs", $0) } ?? ""
        return seat.lastCorrect == true ? "\(seat.bot.name) got it in \(secs)" : "\(seat.bot.name) missed it"
    }
}

struct TVVersusResults: View {
    let match: BotMatch
    let game: GameEngine
    let onRematch: () -> Void
    let onDone: () -> Void

    private var won: Bool { game.score >= (match.standings.first?.score ?? 0) }

    var body: some View {
        VStack(spacing: 34) {
            Text(won ? "You won! 🎉" : "\(match.standings.first?.bot.name ?? "The CPU") takes it")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(TVTheme.text)
            VStack(spacing: 16) {
                row(name: "You", score: game.score, isCPU: false, highlight: won)
                ForEach(match.standings) { seat in
                    row(name: seat.bot.name, score: seat.score, isCPU: true,
                        highlight: !won && seat.id == match.standings.first?.id)
                }
            }
            .frame(maxWidth: 900)
            Text("\(game.summary.correct)/\(game.summary.total) correct")
                .font(.system(size: 27, weight: .medium, design: .rounded))
                .foregroundStyle(TVTheme.textSoft)
            HStack(spacing: 30) {
                Button("Rematch", action: onRematch)
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                Button("Done", action: onDone)
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
            }
        }
        .padding(80)
    }

    private func row(name: String, score: Int, isCPU: Bool, highlight: Bool) -> some View {
        HStack(spacing: 14) {
            Text(name).font(.system(size: 34, weight: .heavy, design: .rounded))
            if isCPU { TVCPUTag() }
            Spacer()
            Text("\(score)").font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(highlight ? .black : TVTheme.text)
        .padding(.horizontal, 34).padding(.vertical, 20)
        .background(highlight ? AnyShapeStyle(Tidbits.Palette.yellow) : AnyShapeStyle(TVTheme.panel),
                    in: RoundedRectangle(cornerRadius: 20))
    }
}
#endif
