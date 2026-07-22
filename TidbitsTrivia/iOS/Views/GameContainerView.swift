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
    /// Archive plays of a past Daily pass their day key (R-DAILY-1).
    var dailyDay: String? = nil
    /// Custom Mix: the modes behind a multi-select Customize launch.
    var mixModes: [GameMode]? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false
    /// Weak-Spot Arena only: the round just built (questions + reasons), kept
    /// around so the empty state and the "gaps closed" result tally can read it.
    @State private var activeWeakSpotRound: WeakSpotRound?

    private var game: GameEngine { store.game }

    /// The Daily is play-once (R-DAILY-1) — no replay of a locked set.
    private var playAgainAction: (() -> Void)? {
        if mode == .daily { return nil }
        return { self.replay() }
    }

    /// Count of round questions that were true misses (not domain-fill) AND
    /// answered correctly — the Weak-Spot payoff (docs/CLUB-FEATURES-BUILD.md
    /// "Feature 1"). nil outside `.weakSpot`.
    private var weakSpotGapsClosed: Int? {
        guard mode == .weakSpot, let round = activeWeakSpotRound else { return nil }
        let trueMissIDs = Set(round.reasons.filter { $0.value.hasPrefix("Missed") }.keys)
        return game.summary.answered.filter { $0.isCorrect && trueMissIDs.contains($0.question.id) }.count
    }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                // nil round = still building (loadingState); a built round under
                // the floor is the honest empty state, never the generic error.
                if mode == .weakSpot, let round = activeWeakSpotRound, round.questions.count < 2 { weakSpotEmptyState }
                else if game.loadFailed { loadError } else { loadingState }
            case .roundIntro:
                RoundIntroView(game: game, onQuit: close)
            case .playing, .reveal:
                GamePlayView(game: game, onQuit: close)
            case .finished:
                ResultsView(summary: game.summary, onPlayAgain: playAgainAction, onDone: close,
                            weakSpotGapsClosed: weakSpotGapsClosed)
                    .onAppear(perform: persistIfNeeded)
            }
        }
        .task {
            if game.phase == .idle, mode == .mix {
                await game.startMix(modes: mixModes ?? [.classic], category: category)
            } else if game.phase == .idle, mode == .weakSpot {
                startWeakSpot()
            } else if game.phase == .idle {
                // Weave in spaced-review questions (skip Daily — it's fair/fixed).
                // In a single-category game, only re-ask misses from THAT category —
                // otherwise a missed Film & TV question surfaces in an Arts & Lit round.
                var review = (mode.acceptsReview && GameSettings.reviewEnabled)
                    ? RecordsStore.dueReview(in: modelContext, limit: 30) : []
                if category.id != "mixed" { review = review.filter { $0.categoryID == category.id } }
                review = Array(review.prefix(2))
                await game.start(mode: mode, category: category, review: review, dailyDay: dailyDay)
            }
        }
    }

    private func startWeakSpot() {
        let round = WeakSpotArena.build(in: modelContext)
        activeWeakSpotRound = round
        if round.questions.count >= 2 {
            game.startCustom(mode: .weakSpot, category: .named("mixed"), questions: round.questions, reasons: round.reasons)
        } else {
            game.quit()   // drop out of `.finished` (a replay) back to `.idle` so the empty state shows
        }
    }

    private var weakSpotEmptyState: some View {
        ContentUnavailableView {
            Label("Not enough misses yet", systemImage: "scope")
        } description: {
            Text("Play a few rounds first — your misses become your arena.")
        } actions: {
            Button("Back") { close() }.tint(Tidbits.Palette.inkSoft)
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
        RecordsStore.record(game.summary, in: modelContext)   // also submits to Game Center
    }

    private func replay() {
        recorded = false
        if mode == .mix { Task { await game.startMix(modes: mixModes ?? [.classic], category: category) } }
        else if mode == .weakSpot { startWeakSpot() }
        else { Task { await game.start(mode: mode, category: category) } }
    }

    private func close() {
        game.quit()
        dismiss()
    }
}
#endif
