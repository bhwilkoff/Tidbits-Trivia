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
#endif
