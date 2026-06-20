#if os(iOS)
import SwiftUI
import SwiftData

/// Owns one play-through: kicks off the engine, then routes by phase
/// (loading → playing/reveal → finished). Handles all four content states
/// (loading / error / empty / happy) the universal-feature-states skill
/// requires.
struct GameContainerView: View {
    let mode: GameMode
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
        .task {
            if game.phase == .idle {
                // Weave in spaced-review questions (skip Daily — it's fair/fixed).
                // In a single-category game, only re-ask misses from THAT category —
                // otherwise a missed Film & TV question surfaces in an Arts & Lit round.
                var review = mode.acceptsReview ? RecordsStore.dueReview(in: modelContext, limit: 30) : []
                if category.id != "mixed" { review = review.filter { $0.categoryID == category.id } }
                review = Array(review.prefix(2))
                await game.start(mode: mode, category: category, review: review)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            Text("Pulling fresh tidbits…")
                .font(Tidbits.TypeRamp.l3)
                .foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private var loadError: some View {
        ContentUnavailableView {
            Label("No questions yet", systemImage: "wifi.slash")
        } description: {
            Text("We couldn't reach Wikipedia and the corpus came up empty. Check your connection and try again.")
        } actions: {
            Button("Try Again") { Task { await game.start(mode: mode, category: category) } }
                .buttonStyle(ChunkyButtonStyle())
                .frame(maxWidth: 260)
            Button("Back") { close() }.tint(Tidbits.Palette.inkSoft)
        }
    }

    private func persistIfNeeded() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
        if mode == .classic { GameCenterManager.shared.submit(game.summary.score, to: GameCenterManager.Leaderboard.classicHigh) }
    }

    private func replay() {
        recorded = false
        Task { await game.start(mode: mode, category: category) }
    }

    private func close() {
        game.quit()
        dismiss()
    }
}
#endif
