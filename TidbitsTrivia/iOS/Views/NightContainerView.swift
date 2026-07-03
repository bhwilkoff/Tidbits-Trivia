#if os(iOS)
import SwiftUI
import SwiftData

/// Runs one Trivia Night — builds the round-tagged mixed question list from the
/// plan, starts the engine in `.barTrivia` mode, then reuses the SAME play +
/// results views every other mode uses (the night is just a mixed question
/// stream). Solo / pass-and-play on one device, fully offline.
struct NightContainerView: View {
    let plan: NightPlan
    let category: TriviaCategory

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                if game.loadFailed { loadError } else { loadingState }
            case .roundIntro:
                RoundIntroView(game: game, onQuit: close)
            case .playing, .reveal:
                GamePlayView(game: game, onQuit: close)
            case .finished:
                ResultsView(summary: game.summary, onPlayAgain: replay, onDone: close)
                    .onAppear(perform: persistIfNeeded)
            }
        }
        .task { if game.phase == .idle { await begin() } }
    }

    private func begin() async {
        let qs = await QuestionProvider.shared.nightQuestions(plan: plan, category: category)
        game.startNight(plan: plan, category: category, questions: qs)
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            Text("Setting up your night…")
                .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private var loadError: some View {
        ContentUnavailableView {
            Label("Couldn't build the night", systemImage: "wifi.slash")
        } description: {
            Text("Some rounds need fresh data and we couldn't reach it. Check your connection and try again.")
        } actions: {
            Button("Try Again") { Task { await begin() } }
                .buttonStyle(ChunkyButtonStyle()).frame(maxWidth: 260)
            Button("Back") { close() }.tint(Tidbits.Palette.inkSoft)
        }
    }

    private func persistIfNeeded() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }

    private func replay() { recorded = false; Task { await begin() } }
    private func close() { game.quit(); dismiss() }
}

// MARK: - Round interstitial (owner: "rounds" must be FELT, not just a banner)

/// The beat between rounds of a solo/pass Trivia Night: what round is coming,
/// what kind of questions it holds, and how many — then an explicit start.
struct RoundIntroView: View {
    let game: GameEngine
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: onQuit) { Image(systemName: "xmark").font(.system(size: 16, weight: .black)) }
                    .tint(Tidbits.Palette.ink)
                Spacer()
            }
            Spacer()
            if let round = game.introRound {
                Text("ROUND \(game.currentRoundNumber) OF \(game.roundCount)")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).kerning(1.5)
                Image(systemName: round.kind.symbol)
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(round.kind.accent)
                Text(round.kind.nightRoundTitle)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                    .multilineTextAlignment(.center)
                Text("\(round.count) questions · \(round.kind.blurb)")
                    .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                withAnimation { game.startRound() }
            } label: {
                Text("Start Round \(game.currentRoundNumber)").frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: Tidbits.Palette.coral.legibleForeground))
        }
        .padding(Tidbits.Metric.pad)
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .transition(.opacity)
    }
}

#endif
