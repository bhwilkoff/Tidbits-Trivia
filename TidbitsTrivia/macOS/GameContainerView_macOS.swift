#if os(macOS)
import SwiftUI
import SwiftData

/// Owns one Mac play-through: starts the engine, routes by phase, records the
/// result at the end (macOS-DESIGN Part B). This view is the WINDOW ROOT while a
/// game is live (Rule 4 / §B2) — never an overlay on the split view.
struct GameContainerView_macOS: View {
    let request: LaunchRequest
    let onClose: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false

    private var game: GameEngine { store.game }

    /// The Daily is play-once (R-DAILY-1) — no replay of a locked set.
    private var playAgainAction: (() -> Void)? {
        if request.mode == .daily { return nil }
        return { self.replay() }
    }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                if game.loadFailed { loadError } else { loadingState }
            case .roundIntro:
                // Only reachable for a Trivia Night; single-player modes never hit it.
                loadingState.task { game.startRound() }
            case .playing, .reveal:
                GameView_macOS(game: game, onQuit: close)
            case .finished:
                ResultsView_macOS(summary: game.summary,
                                  onPlayAgain: playAgainAction,
                                  onDone: close)
                    .onAppear(perform: persistIfNeeded)
            }
        }
        .task { await startIfNeeded() }
    }

    private func startIfNeeded() async {
        guard game.phase == .idle else { return }
        if request.mode == .mix {
            await game.startMix(modes: request.mixModes ?? [.classic], category: request.category)
        } else {
            var review = (request.mode.acceptsReview && GameSettings.reviewEnabled)
                ? RecordsStore.dueReview(in: modelContext, limit: 30) : []
            if request.category.id != "mixed" { review = review.filter { $0.categoryID == request.category.id } }
            review = Array(review.prefix(2))
            await game.start(mode: request.mode, category: request.category,
                             review: review, dailyDay: request.dailyDay)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Pulling fresh tidbits…")
                .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private var loadError: some View {
        ContentUnavailableView {
            Label("No questions yet", systemImage: "wifi.slash")
        } description: {
            Text("We couldn't reach Wikipedia and the corpus came up empty. Check your connection and try again.")
        } actions: {
            Button("Try Again") { Task { await game.start(mode: request.mode, category: request.category) } }
                .buttonStyle(ChunkyButtonStyle())
            Button("Back", action: close).tint(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: 420)
    }

    private func persistIfNeeded() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }

    private func replay() {
        recorded = false
        if request.mode == .mix {
            Task { await game.startMix(modes: request.mixModes ?? [.classic], category: request.category) }
        } else {
            Task { await game.start(mode: request.mode, category: request.category) }
        }
    }

    private func close() {
        game.quit()
        onClose()
    }
}

// MARK: - Custom (Create) game container

/// Runs a live-generated (Create) question set through the same Mac surface.
struct CustomGameContainer_macOS: View {
    let topic: String
    let questions: [Question]
    let onClose: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var started = false
    @State private var recorded = false

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                ProgressView().controlSize(.large)
            case .roundIntro, .playing, .reveal:
                GameView_macOS(game: game, onQuit: close)
            case .finished:
                ResultsView_macOS(summary: game.summary, onPlayAgain: replay, onDone: close)
                    .onAppear(perform: persist)
            }
        }
        .onAppear {
            if !started {
                started = true
                game.startCustom(mode: .mix, category: .named("mixed"), questions: questions)
            }
        }
    }

    private func persist() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }
    private func replay() {
        recorded = false
        game.startCustom(mode: .mix, category: .named("mixed"), questions: questions)
    }
    private func close() { game.quit(); onClose() }
}

// MARK: - Results (Mac)

struct ResultsView_macOS: View {
    let summary: GameSummary
    let onPlayAgain: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(summary.mode.title).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.inkSoft)
                Text("\(summary.score)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                HStack(spacing: 14) {
                    stat("\(summary.correct)/\(summary.total)", "Correct", Tidbits.Palette.mint)
                    stat("\(Int(summary.accuracy * 100))%", "Accuracy", Tidbits.Palette.blue)
                    stat("\(summary.maxStreak)", "Best streak", Tidbits.Palette.coral)
                }
                if !summary.missed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tidbits to remember").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                        ForEach(summary.missed) { a in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.question.prompt).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                Text("Answer: \(a.question.correctAnswer)")
                                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .chunkyCard(fill: Tidbits.Palette.surface)
                        }
                    }
                    .padding(.top, 8)
                }
                HStack(spacing: 14) {
                    if let onPlayAgain {
                        Button("Play again", action: onPlayAgain)
                            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                            .keyboardShortcut(.defaultAction)
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text(label).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .chunkyCard(fill: tint.opacity(0.18))
    }
}
#endif
