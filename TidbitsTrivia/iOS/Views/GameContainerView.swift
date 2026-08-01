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
    /// Expedition stage play only (docs/CLUB-FEATURES-BUILD.md "Feature 5"):
    /// the campaign + stage this round belongs to. nil for every other launch.
    var expedition: Expedition? = nil
    var expeditionStageIndex: Int? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false
    /// Weak-Spot Arena only: the round just built (questions + reasons), kept
    /// around so the empty state and the "gaps closed" result tally can read it.
    @State private var activeWeakSpotRound: WeakSpotRound?

    /// Expedition stage play only: the outcome once `finishExpeditionStage`
    /// records it (nil until then — the result view falls back to computing
    /// pass/fail straight off `game.summary` for its first render).
    @State private var expeditionStageOutcome: (passed: Bool, certificate: ExpeditionCertificate?)?
    @State private var expeditionRecorded = false
    private var expeditionStage: ExpeditionStage? {
        expedition?.stages.first { $0.index == expeditionStageIndex }
    }

    /// Marathon only (docs/CLUB-FEATURES-BUILD.md "Feature 3"): the in-progress
    /// run this session is playing into, how many questions were already
    /// answered in EARLIER sessions (so the HUD shows the true 84/200
    /// position, not this session's local index), and the finished scorecard
    /// once the run's true end is reached.
    @State private var activeMarathonRun: MarathonRun?
    @State private var marathonOffset = 0
    @State private var marathonFinishedScore: MarathonScore?

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
                GamePlayView(game: game, marathonOffset: mode == .marathon ? marathonOffset : nil, onQuit: close)
            case .finished:
                if mode == .marathon {
                    if let score = marathonFinishedScore {
                        MarathonResultsView(score: score, onPlayAgain: { replay() }, onDone: close)
                    } else {
                        // Defensive fallback — finish() runs the instant the last
                        // answer posts (before `.finished` renders), so this
                        // shouldn't be reachable in practice.
                        loadingState.onAppear(perform: close)
                    }
                } else if let expedition, let stageIndex = expeditionStageIndex, let stage = expeditionStage {
                    ExpeditionStageResultView(expedition: expedition, stage: stage, summary: game.summary,
                                              outcome: expeditionStageOutcome, onRetry: { replay() }, onDone: close)
                        .onAppear(perform: { finishExpeditionStage(expedition: expedition, stageIndex: stageIndex) })
                } else {
                    ResultsView(summary: game.summary, onPlayAgain: playAgainAction, onDone: close,
                                weakSpotGapsClosed: weakSpotGapsClosed)
                        .onAppear(perform: persistIfNeeded)
                        // A rendered marathon dismisses itself so the next game
                        // can start, but only after the results screen has been
                        // on screen long enough to photograph — the scorecard is
                        // one of the surfaces being audited, not a transition.
                        .task {
                            guard DebugHooks.marathonGames != nil else { return }
                            try? await Task.sleep(for: .seconds(max(1.0, DebugHooks.autopilotDelay * 3)))
                            close()
                        }
                }
            }
        }
        .task {
            if game.phase == .idle, mode == .mix {
                await game.startMix(modes: mixModes ?? [.classic], category: category)
            } else if game.phase == .idle, mode == .weakSpot {
                startWeakSpot()
            } else if game.phase == .idle, mode == .marathon {
                startMarathon()
            } else if game.phase == .idle, let expedition, let stageIndex = expeditionStageIndex {
                startExpeditionStage(expedition: expedition, stageIndex: stageIndex)
            } else if game.phase == .idle {
                // Weave in spaced-review questions (skip Daily — it's fair/fixed).
                // In a single-category game, only re-ask misses from THAT category —
                // otherwise a missed Film & TV question surfaces in an Arts & Lit round.
                var review = (mode.acceptsReview && GameSettings.reviewEnabled)
                    ? RecordsStore.dueReview(in: modelContext, limit: 30) : []
                if category.id != "mixed" { review = review.filter { $0.categoryID == category.id } }
                review = Array(review.prefix(2))
                // TIDBITS_QUESTION forces an exact set of corpus rows, so a
                // specific question can be looked at on screen. No-op in
                // production; the env var is never set there.
                if let ids = DebugHooks.forcedQuestionIDs {
                    let forced = CorpusDatabase.shared.questions(ids: ids)
                    if !forced.isEmpty {
                        game.startCustom(mode: mode, category: category, questions: forced)
                        return
                    }
                }
                await game.start(mode: mode, category: category, review: review, dailyDay: dailyDay)
            }
        }
        .onChange(of: game.answered.count) { _, _ in persistMarathonProgress() }
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

    // MARK: Marathon (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3")

    /// Resume the in-progress run if one exists, else start a fresh one.
    /// Loads only the REMAINING questions — the HUD adds `marathonOffset`
    /// back in so the player always sees their true position out of 200.
    private func startMarathon() {
        marathonFinishedScore = nil
        let run = Marathon.inProgress(in: modelContext) ?? Marathon.startNew(in: modelContext)
        activeMarathonRun = run
        marathonOffset = run.currentIndex
        let remaining = Marathon.resumeQuestions(run)
        guard !remaining.isEmpty else {
            // Edge case only (a run somehow already at its full length without
            // having been finished) — close it out rather than show a blank round.
            marathonFinishedScore = Marathon.finish(run: run, in: modelContext)
            activeMarathonRun = nil
            return
        }
        game.startCustom(mode: .marathon, category: .named("mixed"), questions: remaining)
    }

    /// Persist every new answer immediately (the whole point of Marathon: a
    /// crash/quit never loses progress) and, the instant the run reaches its
    /// true end, write the permanent scorecard and clear the in-progress run —
    /// computed here, ahead of the `.finished` phase render, so there's no race.
    private func persistMarathonProgress() {
        guard mode == .marathon, let run = activeMarathonRun else { return }
        let alreadyPersisted = run.currentIndex - marathonOffset
        guard alreadyPersisted < game.answered.count else { return }
        for i in alreadyPersisted..<game.answered.count {
            Marathon.record(game.answered[i], run: run, in: modelContext)
        }
        if run.currentIndex >= run.total {
            marathonFinishedScore = Marathon.finish(run: run, in: modelContext)
            activeMarathonRun = nil
        }
    }

    // MARK: Expedition (Club — docs/CLUB-FEATURES-BUILD.md "Feature 5")

    /// Route the stage's category + difficulty band into the EXISTING
    /// `.classic` launch path — an Expedition is not a new game engine.
    private func startExpeditionStage(expedition: Expedition, stageIndex: Int) {
        expeditionStageOutcome = nil
        expeditionRecorded = false
        guard let stage = expedition.stages.first(where: { $0.index == stageIndex }) else { close(); return }
        let questions = Expeditions.startStage(expedition, stageIndex: stageIndex)
        game.startCustom(mode: .classic, category: .named(stage.categoryID), questions: questions)
    }

    /// The stage is a normal round, so it records like any other (feeds
    /// Records/spaced-review/Story Archive) AND records the Expedition-specific
    /// pass/fail outcome once. TIDBITS_EXPEDITION_FORCE_PASS overrides the
    /// score for verification (autopilot always picks option 0, so it can't
    /// reliably clear a real pass bar).
    private func finishExpeditionStage(expedition: Expedition, stageIndex: Int) {
        guard !expeditionRecorded, let stage = expeditionStage else { return }
        expeditionRecorded = true
        persistIfNeeded()
        let summary = game.summary
        let correct = DebugHooks.forceExpeditionPass ? stage.questionCount : summary.correct
        expeditionStageOutcome = Expeditions.recordStageResult(
            expedition: expedition, stageIndex: stageIndex, correct: correct, total: summary.total, in: modelContext)
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
        else if mode == .marathon { startMarathon() }
        else if let expedition, let stageIndex = expeditionStageIndex { startExpeditionStage(expedition: expedition, stageIndex: stageIndex) }
        else { Task { await game.start(mode: mode, category: category) } }
    }

    private func close() {
        game.quit()
        dismiss()
    }
}
#endif
