#if os(macOS)
import SwiftUI
import SwiftData

/// Owns one Mac play-through: starts the engine, routes by phase, records the
/// result at the end (macOS-DESIGN Part B). This view is the WINDOW ROOT while a
/// game is live (Rule 4 / §B2) — never an overlay on the split view.
struct GameContainerView_macOS: View {
    let request: LaunchRequest
    let onClose: () -> Void
    /// Expedition stage play only (docs/CLUB-FEATURES-BUILD.md "Feature 5"):
    /// the campaign + stage this round belongs to. nil for every other launch.
    var expedition: Expedition? = nil
    var expeditionStageIndex: Int? = nil

    @Environment(AppStore.self) private var store
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
                GameView_macOS(game: game, onQuit: close, marathonOffset: request.mode == .marathon ? marathonOffset : nil)
            case .finished:
                if request.mode == .marathon {
                    if let score = marathonFinishedScore {
                        MarathonResultsView_macOS(score: score, onPlayAgain: { replay() }, onDone: close)
                    } else {
                        // Defensive fallback — finish() runs the instant the last
                        // answer posts (before `.finished` renders), so this
                        // shouldn't be reachable in practice.
                        loadingState.onAppear(perform: close)
                    }
                } else if let expedition, let stageIndex = expeditionStageIndex, let stage = expeditionStage {
                    ExpeditionStageResultView_macOS(expedition: expedition, stage: stage, summary: game.summary,
                                                    outcome: expeditionStageOutcome, onRetry: { replay() }, onDone: close)
                        .onAppear(perform: { finishExpeditionStage(expedition: expedition, stageIndex: stageIndex) })
                } else {
                    ResultsView_macOS(summary: game.summary,
                                      onPlayAgain: playAgainAction,
                                      onDone: close,
                                      weakSpotGapsClosed: weakSpotGapsClosed)
                        .onAppear(perform: persistIfNeeded)
                }
            }
        }
        .task { await startIfNeeded() }
        .onChange(of: game.answered.count) { _, _ in persistMarathonProgress() }
    }

    private func startIfNeeded() async {
        guard game.phase == .idle else { return }
        if request.mode == .mix {
            await game.startMix(modes: request.mixModes ?? [.classic], category: request.category)
        } else if request.mode == .weakSpot {
            startWeakSpot()
        } else if request.mode == .marathon {
            startMarathon()
        } else if let expedition, let stageIndex = expeditionStageIndex {
            startExpeditionStage(expedition: expedition, stageIndex: stageIndex)
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
        guard request.mode == .marathon, let run = activeMarathonRun else { return }
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
        } else if request.mode == .marathon {
            startMarathon()
        } else if let expedition, let stageIndex = expeditionStageIndex {
            startExpeditionStage(expedition: expedition, stageIndex: stageIndex)
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

// MARK: - Marathon results (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3")

/// The Mac Marathon scorecard — mirrors the iOS reference (`MarathonResultsView`)
/// with Mac-native chrome (`CompactButtonStyle`, ⌘-friendly keyboard shortcuts).
/// Reads the permanent `MarathonScore` just written (a run's true total spans
/// however many sessions it took, not just this last one).
struct MarathonResultsView_macOS: View {
    let score: MarathonScore
    var onPlayAgain: (() -> Void)? = nil
    let onDone: () -> Void
    /// True when opened from the history list (a past run, read-only) rather
    /// than right after finishing — hides the replay + history-link actions.
    var isHistorical: Bool = false

    @Query(sort: \MarathonScore.date, order: .reverse) private var allScores: [MarathonScore]
    @State private var showHistory = false

    /// The run before this one (excludes the one just written) — "vs your
    /// last run," per the design spec's literal phrasing.
    private var previous: MarathonScore? {
        allScores.first { $0.date < score.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scoreCard
                comparisonMoment
                statsRow
                domainCard
                if !isHistorical {
                    Button { showHistory = true } label: {
                        Label("See Marathon history", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(CompactButtonStyle())
                }
                buttons
            }
            .padding(32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
        .sheet(isPresented: $showHistory) { MarathonHistoryView_macOS() }
    }

    private var scoreCard: some View {
        VStack(spacing: 8) {
            Text("MARATHON COMPLETE").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text("\(score.score)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text("\(score.correct)/\(score.total) correct · \(Self.durationLabel(score.durationSeconds))")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .chunkyCard(fill: Tidbits.Palette.teal.opacity(0.18))
    }

    /// "+6% vs your last run" — the measured-mastery payoff (the whole reason
    /// Marathon isn't just a long Classic).
    @ViewBuilder private var comparisonMoment: some View {
        if let previous {
            let delta = Int((score.accuracy - previous.accuracy) * 100)
            VStack(spacing: 4) {
                Text(delta == 0 ? "Same as your last run" : "\(delta > 0 ? "+" : "")\(delta)% vs your last run")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(delta >= 0 ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Text("Last run: \(Int(previous.accuracy * 100))% · this run: \(Int(score.accuracy * 100))%")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .chunkyCard(fill: Tidbits.Palette.surface)
        } else {
            VStack(spacing: 4) {
                Text("Your first Marathon")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                Text("Play another to see how you're improving")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .chunkyCard(fill: Tidbits.Palette.surface)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat("\(Int(score.accuracy * 100))%", "Accuracy", Tidbits.Palette.blue)
            stat("\(score.score)", "Score", Tidbits.Palette.teal)
            stat("\(allScores.count)", "Marathons", Tidbits.Palette.coral)
        }
    }

    /// Per-domain accuracy bars — the measured-mastery map (not just a score).
    private var domainCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where you stood this run").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            ForEach(score.domainBreakdown.filter { $0.total > 0 }) { stat in domainRow(stat) }
        }
        .padding(16)
        .chunkyCard()
    }

    private func domainRow(_ stat: MarathonDomainStat) -> some View {
        let cat = TriviaCategory.named(stat.categoryID)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: cat.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(cat.color.legibleAccent)
                Text(cat.name).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Text("\(stat.correct)/\(stat.total) · \(Int(stat.accuracy * 100))%")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tidbits.Palette.bgDeep)
                    Capsule().fill(cat.color).frame(width: max(6, geo.size.width * stat.accuracy))
                }
                .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2))
            }
            .frame(height: 10)
        }
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            if let onPlayAgain {
                Button("Start a new Marathon", action: onPlayAgain)
                    .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.teal, textColor: .white, prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            Button("Done", action: onDone)
                .buttonStyle(CompactButtonStyle())
                .keyboardShortcut(.cancelAction)
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

    private static func durationLabel(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }
}

// MARK: - Expedition stage result (Club — docs/CLUB-FEATURES-BUILD.md
// "Feature 5"; mirrors the iOS reference `ExpeditionStageResultView`)

/// The Mac post-play beat for an Expedition stage — pass unlocks the next
/// stage (or, on the last stage, writes a certificate); fail keeps the
/// player on the same stage, "Try Again."
struct ExpeditionStageResultView_macOS: View {
    let expedition: Expedition
    let stage: ExpeditionStage
    let summary: GameSummary
    /// Set once `finishExpeditionStage` records the true outcome; nil for the
    /// first render (the fallback below reads straight off `summary`, which
    /// is already final by `.finished`).
    let outcome: (passed: Bool, certificate: ExpeditionCertificate?)?
    let onRetry: () -> Void
    let onDone: () -> Void

    private var passed: Bool { outcome?.passed ?? (summary.correct >= stage.passBar) }
    private var certificate: ExpeditionCertificate? { outcome?.certificate }
    private var nextStageNumber: Int { min(stage.index + 2, expedition.stageCount) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headline
                statsRow
                if let certificate { certificateCard(certificate) }
                buttons
            }
            .padding(32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Image(systemName: certificate != nil ? "rosette" : (passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill"))
                .font(.system(size: 44))
                .foregroundStyle(passed ? Tidbits.Palette.mint : Tidbits.Palette.coral)
            Text(certificate != nil ? "EXPEDITION COMPLETE" : (passed ? "STAGE \(stage.index + 1) PASSED" : "NOT QUITE"))
                .font(Tidbits.TypeRamp.l1)
                .foregroundStyle(Tidbits.Palette.ink)
            Text(bodyLine)
                .font(Tidbits.TypeRamp.l4)
                .foregroundStyle(Tidbits.Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .chunkyCard(fill: (passed ? Tidbits.Palette.mint : Tidbits.Palette.coral).opacity(0.16))
    }

    private var bodyLine: String {
        if certificate != nil { return "You completed \(expedition.title) — every stage, start to finish." }
        if passed { return "\(stage.title) is done. Stage \(nextStageNumber) just unlocked." }
        return "Needed \(stage.passBar) of \(stage.questionCount) to advance — you got \(summary.correct). Give it another go."
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            stat("\(summary.correct)/\(summary.total)", "Correct", Tidbits.Palette.blue)
            stat("\(stage.passBar)", "Pass bar", Tidbits.Palette.pink)
            stat("\(min(stage.index + (passed ? 2 : 1), expedition.stageCount))/\(expedition.stageCount)", "Stage", Tidbits.Palette.ink)
        }
    }

    private func certificateCard(_ cert: ExpeditionCertificate) -> some View {
        VStack(spacing: 6) {
            Text("CERTIFICATE EARNED").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            Text(cert.title).font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("\(cert.stagesCompleted) stages · \(cert.totalScore) correct total")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .chunkyCard(fill: Tidbits.Palette.pink)
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            if passed {
                Button(certificate != nil ? "Done" : "Continue", action: onDone)
                    .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.pink, textColor: .white, prominent: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Try Again", action: onRetry)
                    .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true))
                    .keyboardShortcut(.defaultAction)
                Button("Back to map", action: onDone)
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text(label).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .chunkyCard(fill: tint.opacity(0.18))
    }
}
#endif
