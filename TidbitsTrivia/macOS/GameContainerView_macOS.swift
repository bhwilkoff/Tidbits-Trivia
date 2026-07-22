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
    /// Weak-Spot Arena only: the round just built (questions + reasons), kept
    /// around so the empty state and the "gaps closed" result tally can read it.
    @State private var activeWeakSpotRound: WeakSpotRound?

    private var game: GameEngine { store.game }

    /// The Daily is play-once (R-DAILY-1) — no replay of a locked set.
    private var playAgainAction: (() -> Void)? {
        if request.mode == .daily { return nil }
        return { self.replay() }
    }

    /// Count of round questions that were true misses (not domain-fill) AND
    /// answered correctly — the Weak-Spot payoff (docs/CLUB-FEATURES-BUILD.md
    /// "Feature 1"). nil outside `.weakSpot`.
    private var weakSpotGapsClosed: Int? {
        guard request.mode == .weakSpot, let round = activeWeakSpotRound else { return nil }
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
                if request.mode == .weakSpot, let round = activeWeakSpotRound, round.questions.count < 2 { weakSpotEmptyState }
                else if game.loadFailed { loadError } else { loadingState }
            case .roundIntro:
                // Only reachable for a Trivia Night; single-player modes never hit it.
                loadingState.task { game.startRound() }
            case .playing, .reveal:
                GameView_macOS(game: game, onQuit: close)
            case .finished:
                ResultsView_macOS(summary: game.summary,
                                  onPlayAgain: playAgainAction,
                                  onDone: close,
                                  weakSpotGapsClosed: weakSpotGapsClosed)
                    .onAppear(perform: persistIfNeeded)
            }
        }
        .task { await startIfNeeded() }
    }

    private func startIfNeeded() async {
        guard game.phase == .idle else { return }
        if request.mode == .mix {
            await game.startMix(modes: request.mixModes ?? [.classic], category: request.category)
        } else if request.mode == .weakSpot {
            startWeakSpot()
        } else {
            var review = (request.mode.acceptsReview && GameSettings.reviewEnabled)
                ? RecordsStore.dueReview(in: modelContext, limit: 30) : []
            if request.category.id != "mixed" { review = review.filter { $0.categoryID == request.category.id } }
            review = Array(review.prefix(2))
            await game.start(mode: request.mode, category: request.category,
                             review: review, dailyDay: request.dailyDay)
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
            Button("Back", action: close).tint(Tidbits.Palette.inkSoft)
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
        } else if request.mode == .weakSpot {
            startWeakSpot()
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
    /// Weak-Spot Arena only: how many true misses this round turned correct —
    /// the payoff headline (docs/CLUB-FEATURES-BUILD.md "Feature 1"). nil elsewhere.
    var weakSpotGapsClosed: Int? = nil
    @State private var showBoard = false

    private var isTodayDaily: Bool { summary.mode == .daily && summary.dailyDay == nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(summary.mode.title).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.inkSoft)
                Text("\(summary.score)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                gapsClosedMoment
                HStack(spacing: 14) {
                    stat("\(summary.correct)/\(summary.total)", "Correct", Tidbits.Palette.mint)
                    stat("\(Int(summary.accuracy * 100))%", "Accuracy", Tidbits.Palette.blue)
                    stat("\(summary.maxStreak)", "Best streak", Tidbits.Palette.coral)
                }
                if isTodayDaily {
                    Button { showBoard = true } label: {
                        Label("See how the world did", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.blue.opacity(0.14)))
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
                            .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true))
                            .keyboardShortcut(.defaultAction)
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(CompactButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
        .task { if isTodayDaily { await PlayerIdentityStore.shared.submitDailyBoard(summary: summary) } }
        .sheet(isPresented: $showBoard) {
            VStack(spacing: 0) {
                DailyBoardContent(day: QuestionProvider.dayKey(), myScore: summary.score, myMarks: todayMarks)
                Button("Done") { showBoard = false }
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .padding(.bottom, 16)
            }
            .frame(minWidth: 460, minHeight: 560)
        }
    }

    /// The player's 7-char hit string aligned to the shared pickDaily order.
    private var todayMarks: String {
        let ids = CorpusDatabase.shared.orderedIDs(categoryID: "mixed")
        let qids = DailyPick.pick(ids: ids, day: QuestionProvider.dayKey(), categoryID: "mixed", count: GameMode.daily.questionCount)
        return DailyBoard.marks(answered: summary.answered, qids: qids)
    }

    /// Weak-Spot Arena's payoff — "you didn't just play, you got better."
    @ViewBuilder private var gapsClosedMoment: some View {
        if let n = weakSpotGapsClosed {
            VStack(spacing: 4) {
                Text("You closed \(n) gap\(n == 1 ? "" : "s")")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                Text(n > 0 ? "Turned a miss into a win" : "Nothing to close yet this round")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .chunkyCard(fill: Tidbits.Palette.grape.opacity(0.18))
        }
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
