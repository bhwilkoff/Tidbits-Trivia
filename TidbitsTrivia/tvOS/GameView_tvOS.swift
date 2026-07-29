#if os(tvOS)
import SwiftUI
import SwiftData

/// Runs one game on Apple TV, reusing the shared GameEngine. Ten-foot
/// layout, dark-first, Siri-Remote focus. Same loop as iOS — only the
/// presentation differs.
struct TVGameContainer: View {
    let mode: GameMode
    let category: TriviaCategory
    /// Archive plays of a past Daily pass their day key (R-DAILY-1).
    var dailyDay: String? = nil
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
            TVTheme.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                // nil round = still building (loading); a built round under the
                // floor is the honest empty state, never the generic error.
                if mode == .weakSpot, let round = activeWeakSpotRound, round.questions.count < 2 { weakSpotEmptyState }
                else if game.loadFailed { errorState } else { loading }
            case .roundIntro:
                TVRoundIntroView(game: game)
            case .playing, .reveal:
                TVGamePlayView(onQuit: close, marathonOffset: mode == .marathon ? marathonOffset : nil)
            case .finished:
                if mode == .marathon {
                    if let score = marathonFinishedScore {
                        TVMarathonResultsView(score: score, onPlayAgain: { replay() }, onDone: close)
                    } else {
                        // Defensive fallback — finish() runs the instant the last
                        // answer posts (before `.finished` renders), so this
                        // shouldn't be reachable in practice.
                        loading.onAppear(perform: close)
                    }
                } else if let expedition, let stageIndex = expeditionStageIndex, let stage = expeditionStage {
                    TVExpeditionStageResultView(expedition: expedition, stage: stage, summary: game.summary,
                                                outcome: expeditionStageOutcome, onRetry: { replay() }, onDone: close)
                        .onAppear(perform: { finishExpeditionStage(expedition: expedition, stageIndex: stageIndex) })
                } else {
                    TVResultsView(summary: game.summary, onPlayAgain: playAgainAction, onDone: close,
                                  weakSpotGapsClosed: weakSpotGapsClosed)
                        .onAppear(perform: persist)
                }
            }
        }
        .task {
            if game.phase == .idle {
                if mode == .weakSpot {
                    startWeakSpot()
                } else if mode == .marathon {
                    startMarathon()
                } else if let expedition, let stageIndex = expeditionStageIndex {
                    startExpeditionStage(expedition: expedition, stageIndex: stageIndex)
                } else {
                    // Single-category game re-asks only same-category misses (no cross-category leak).
                    var review = (mode.acceptsReview && GameSettings.reviewEnabled)
                        ? RecordsStore.dueReview(in: modelContext, limit: 30) : []
                    if category.id != "mixed" { review = review.filter { $0.categoryID == category.id } }
                    review = Array(review.prefix(2))
                    await game.start(mode: mode, category: category, review: review, dailyDay: dailyDay)
                }
            }
        }
        .onChange(of: game.answered.count) { _, _ in persistMarathonProgress() }
        .onExitCommand(perform: close)   // Menu button quits the game (modal: allowed)
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
        VStack(spacing: 24) {
            Image(systemName: "scope").font(.system(size: 60, weight: .black)).foregroundStyle(Tidbits.Palette.grape)
            Text("Not enough misses yet").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Play a few rounds first — your misses become your arena.")
                .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                .multilineTextAlignment(.center)
            Button("Back", action: close).buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
        }
        .frame(maxWidth: 900)
    }

    private var loading: some View {
        VStack(spacing: 28) {
            ProgressView().controlSize(.extraLarge).tint(.white)
            Text("Pulling fresh tidbits…").font(.system(size: 31, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }
    private var errorState: some View {
        VStack(spacing: 24) {
            Text("No questions yet").font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("We couldn't reach Wikipedia and the corpus is empty.").font(.system(size: 29)).foregroundStyle(TVTheme.textSoft)
            Button("Back", action: close).buttonStyle(.bordered)
        }
    }

    private func persist() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }
    private func replay() {
        recorded = false
        if mode == .weakSpot { startWeakSpot() }
        else if mode == .marathon { startMarathon() }
        else if let expedition, let stageIndex = expeditionStageIndex { startExpeditionStage(expedition: expedition, stageIndex: stageIndex) }
        else { Task { await game.start(mode: mode, category: category) } }
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
        persist()
        let summary = game.summary
        let correct = DebugHooks.forceExpeditionPass ? stage.questionCount : summary.correct
        expeditionStageOutcome = Expeditions.recordStageResult(
            expedition: expedition, stageIndex: stageIndex, correct: correct, total: summary.total, in: modelContext)
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

    /// The Daily is play-once (R-DAILY-1) — no replay of a locked set.
    private var playAgainAction: (() -> Void)? {
        if mode == .daily { return nil }
        return { self.replay() }
    }
    private func close() { game.quit(); dismiss() }
}

// MARK: - Gameplay

private enum TVFocus: Hashable { case stake(Int), answer(Int), closestSlider, closestLock, orderRow(Int), orderSubmit, matchKey(Int), matchVal(Int), matchSubmit, typeReveal, typeKnew, typeMissed, enumReveal, enumMinus, enumPlus, enumSubmit, next }

struct TVGamePlayView: View {
    let onQuit: () -> Void
    /// Non-nil in a networked Trivia Night (Decision 033) — the host gets the
    /// reveal/advance controls; a joiner's reveal is held until the host reveals.
    var live: LiveNight? = nil
    /// Non-nil in a Play-vs-CPU match (Decision 038): a standings strip rides
    /// the top and each reveal shows what the bot did.
    var versus: BotMatch? = nil
    /// Marathon only: how many questions were already answered in EARLIER
    /// sessions — added to `game.index` so the HUD shows the true position
    /// out of 200, not this session's local (resumed-slice) index. nil elsewhere.
    var marathonOffset: Int? = nil
    @Environment(AppStore.self) private var store
    @FocusState private var focus: TVFocus?
    @State private var typeRevealed = false
    @State private var enumRevealed = false
    @State private var enumSelfCount = 0
    private var game: GameEngine { store.game }
    /// In a host-paced night the answer is revealed only when the host reveals.
    private var heldReveal: Bool { game.phase == .reveal && game.awaitingReveal }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            if let live { TVNightRoomStrip(live: live) }
            if let versus { TVVersusStrip(match: versus, game: game) }
            hud
            if let q = game.current {
                if game.mode == .barTrivia, let round = game.currentRound { roundBanner(round) }
                Text(TriviaCategory.named(q.categoryID).name.uppercased())
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(TriviaCategory.named(q.categoryID).color)
                if let img = q.imageURL { pictureImage(img) }
                Text(q.prompt)
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if game.mode == .weakSpot, let reason = game.weakSpotReasons[q.id] { weakSpotReasonCaption(reason) }
                if game.mode == .sweep { sweepRow }
                if game.mode == .stake && game.phase == .playing { stakeRow }
                if let spec = q.enumerate {
                    enumeratePanel(spec)
                } else if q.accepted != nil {
                    typeAnswerPanel(q)
                } else if let m = q.matching {
                    matchingPanel(m)
                } else if q.ordering != nil {
                    orderingPanel()
                } else if let spec = q.closest {
                    closestPanel(spec)
                } else {
                    HStack(spacing: 28) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                            Button { game.submit(idx) } label: {
                                Text(opt).font(.system(size: 29, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 120)
                                    .padding(.horizontal, 24)
                            }
                            .buttonStyle(TVAnswerStyle(state: state(idx, q)))
                            .focused($focus, equals: .answer(idx))
                            // Stake mode: lock the answers until a confidence chip is committed.
                            .disabled(game.phase == .reveal || (game.mode == .stake && game.currentStake == 0))
                        }
                    }
                }
                if game.phase == .reveal {
                    if heldReveal { tvLockedBeat }
                    else {
                        reveal(q)
                        if let live { TVNightStandings(live: live) }
                        if let versus { TVVersusRevealCard(match: versus) }
                    }
                }
                // Host's reveal control — reachable while answering or holding.
                if let live, live.role == .host, game.phase == .playing || heldReveal {
                    tvHostRevealBar(live)
                }
            }
            Spacer()
        }
        .padding(90)
        .onAppear { GameCenterManager.shared.setAccessPointActive(false) }
        .onDisappear { GameCenterManager.shared.setAccessPointActive(true) }
        .defaultFocus($focus, .answer(0))
        .onChange(of: game.index) { typeRevealed = false; enumRevealed = false; enumSelfCount = 0; focus = firstFocus }
        .onChange(of: game.phase) { _, p in
            if p == .reveal { focus = .next } else if p == .playing { focus = firstFocus }
        }
        // Stake: once a chip is committed, hop focus down to the answers.
        .onChange(of: game.currentStake) { _, s in
            if game.mode == .stake && s != 0 && game.phase == .playing { focus = .answer(0) }
        }
        .task {
            // Disabled in a networked night — the host paces it (autopilot would fight that).
            guard DebugHooks.autopilot, live == nil else { return }
            // A step budget parks the app on a chosen phase for a screenshot
            // (docs/STORE-SCREENSHOTS.md §2); nil runs the round to completion.
            var stepsLeft = DebugHooks.autopilotSteps
            while game.phase != .finished && game.phase != .idle {
                if let n = stepsLeft, n <= 0 { return }
                try? await Task.sleep(for: .seconds(0.9))
                if stepsLeft != nil { stepsLeft! -= 1 }
                switch game.phase {
                case .playing:
                    // Shape-driven so it also drives a Trivia Night (mixed shapes).
                    if game.current?.enumerate != nil { game.selfMarkEnum(3); break }
                    if game.current?.accepted != nil { game.markTyped(correct: true); break }
                    if game.current?.matching != nil { game.submitMatch(); break }
                    if game.current?.ordering != nil { game.submitOrder(); break }
                    if game.current?.closest != nil { game.submitGuess(); break }
                    if game.mode == .stake && game.currentStake == 0,
                       let tier = game.stakeTiers.first(where: { $0.remaining > 0 }) { game.setStake(tier.value) }
                    // Option 0 is the harness default; the store scorecard needs a real score.
                    game.submit(DebugHooks.autopilotCorrect ? (game.current?.correctIndex ?? 0) : 0)
                case .reveal:  game.advance()
                default:       break
                }
            }
        }
    }

    /// Ordering at ten feet — focusable per-row ↑/↓ + a Submit button.
    private func orderingPanel() -> some View {
        let live = game.phase == .playing
        return VStack(spacing: 16) {
            ForEach(Array(game.currentOrder.enumerated()), id: \.element) { idx, item in
                HStack(spacing: 24) {
                    Text("\(idx + 1)").font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(TVTheme.textSoft).frame(width: 44)
                    Text(item).font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if live {
                        Button { game.moveOrderItem(idx, up: true) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false)).disabled(idx == 0)
                        Button { game.moveOrderItem(idx, up: false) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false)).disabled(idx == game.currentOrder.count - 1)
                            .focused($focus, equals: .orderRow(idx))
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(TVTheme.panel))
            }
            if live {
                Button("Submit Order") { game.submitOrder() }
                    .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: false))
                    .focused($focus, equals: .orderSubmit)
            }
        }
        .frame(maxWidth: 1100)
    }

    /// Matching at ten feet — focusable key rows (select) + value chips (link) + Submit.
    private func matchingPanel(_ m: MatchSpec) -> some View {
        let live = game.phase == .playing
        return VStack(spacing: 18) {
            ForEach(Array(m.keys.enumerated()), id: \.offset) { i, key in
                HStack(spacing: 20) {
                    Button { game.selectMatchKey(i) } label: {
                        HStack {
                            Text(key).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(game.matchedValue(forKey: i) ?? "—").font(.system(size: 27, weight: .medium, design: .rounded))
                                .foregroundStyle(game.matchedValue(forKey: i) != nil ? game.mode.accent : TVTheme.textSoft)
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: game.matchSelectedKey == i))
                    .focused($focus, equals: .matchKey(i)).disabled(!live)
                }
            }
            HStack(spacing: 18) {
                ForEach(Array(game.matchValues.enumerated()), id: \.offset) { j, val in
                    let used = game.matchAssign.contains(j)
                    Button { game.assignMatchValue(j) } label: {
                        Text(val).font(.system(size: 25, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                    .focused($focus, equals: .matchVal(j)).disabled(!live || used).opacity(used ? 0.4 : 1)
                }
            }
            if live {
                Button("Submit") { game.submitMatch() }
                    .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: false))
                    .focused($focus, equals: .matchSubmit)
            }
        }
        .frame(maxWidth: 1300)
    }

    /// Type-the-answer at ten feet — text entry is a keyboard wall on tvOS, so
    /// this is active recall: think of the answer, reveal it, then self-mark
    /// honestly (the testing effect without typing).
    private func typeAnswerPanel(_ q: Question) -> some View {
        VStack(spacing: 26) {
            if !typeRevealed {
                Text("Recall the answer in your head.")
                    .font(.system(size: 31, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Button("Reveal Answer") { typeRevealed = true }
                    .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: false))
                    .focused($focus, equals: .typeReveal)
            } else {
                Text(q.correctAnswer)
                    .font(.system(size: 46, weight: .black, design: .rounded)).foregroundStyle(.white)
                HStack(spacing: 24) {
                    Button("I knew it") { typeRevealed = false; game.markTyped(correct: true) }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.mint, selected: false))
                        .focused($focus, equals: .typeKnew)
                    Button("Missed it") { typeRevealed = false; game.markTyped(correct: false) }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                        .focused($focus, equals: .typeMissed)
                }
            }
        }
        .frame(maxWidth: 1100)
        .onChange(of: typeRevealed) { _, r in if r { focus = .typeKnew } }
    }

    /// Enumeration at ten feet — typing a long list is a keyboard wall, so this
    /// is recall-then-self-mark: think of as many as you can, reveal the full
    /// set, then report how many you named (honesty-based, like flashcards).
    private func enumeratePanel(_ spec: EnumSpec) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
        return VStack(spacing: 26) {
            if !enumRevealed {
                Text("Name as many as you can in your head, then reveal the list.")
                    .font(.system(size: 31, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Button("Reveal the List") { enumRevealed = true }
                    .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: false))
                    .focused($focus, equals: .enumReveal)
            } else {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(spec.displayNames, id: \.self) { name in
                        Text(name).font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(TVTheme.panel))
                    }
                }
                .frame(maxWidth: 1500)
                HStack(spacing: 28) {
                    Button { enumSelfCount = max(0, enumSelfCount - 1) } label: { Image(systemName: "minus") }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                        .focused($focus, equals: .enumMinus)
                    Text("I named \(enumSelfCount) of \(spec.total)")
                        .font(.system(size: 33, weight: .black, design: .rounded)).foregroundStyle(.white)
                        .frame(minWidth: 360)
                    Button { enumSelfCount = min(spec.total, enumSelfCount + 1) } label: { Image(systemName: "plus") }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                        .focused($focus, equals: .enumPlus)
                }
                Button("Submit") { game.selfMarkEnum(enumSelfCount) }
                    .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: false))
                    .focused($focus, equals: .enumSubmit)
            }
        }
        .frame(maxWidth: 1500)
        .onChange(of: enumRevealed) { _, r in if r { focus = .enumPlus } }
    }

    private var firstFocus: TVFocus {
        if game.current?.enumerate != nil { return .enumReveal }
        if game.current?.accepted != nil { return .typeReveal }
        if game.current?.matching != nil { return .matchKey(0) }
        if game.current?.ordering != nil { return .orderSubmit }
        if game.current?.closest != nil { return .closestSlider }
        return game.mode == .stake && game.currentStake == 0
            ? .stake(game.stakeTiers.first?.value ?? 0)
            : .answer(0)
    }

    /// Closest Call at ten feet — tvOS has no Slider (no touch), so estimate with
    /// focusable ±coarse/±fine stepper buttons. The big number reads across the room.
    private func closestPanel(_ spec: ClosestSpec) -> some View {
        let live = game.phase == .playing
        let fine = max(spec.step, 1)
        let coarse = max(fine * 10, 10)
        return VStack(spacing: 26) {
            Text(closestFmt(game.currentGuess, spec))
                .font(.system(size: 70, weight: .black, design: .rounded)).foregroundStyle(.white)
                .contentTransition(.numericText())
            HStack(spacing: 20) {
                stepButton(-coarse, "−\(Int(coarse))", live: live).focused($focus, equals: .closestSlider)
                stepButton(-fine, "−\(Int(fine))", live: live)
                stepButton(fine, "+\(Int(fine))", live: live)
                stepButton(coarse, "+\(Int(coarse))", live: live)
            }
            if live {
                Button("Lock In") { game.submitGuess() }
                    .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: false))
                    .focused($focus, equals: .closestLock)
            }
        }
        .frame(maxWidth: 1000)
    }

    private func stepButton(_ delta: Double, _ label: String, live: Bool) -> some View {
        Button(label) { game.setGuess(game.currentGuess + delta) }
            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
            .disabled(!live)
    }

    private func closestFmt(_ v: Double, _ spec: ClosestSpec) -> String {
        let n = Int(v.rounded())
        if spec.unit.isEmpty { return String(n) }
        let s = abs(n) >= 1000 ? n.formatted(.number.grouping(.automatic)) : String(n)
        return "\(s) \(spec.unit)"
    }

    private var stakeRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(game.currentStake == 0 ? "How sure are you?" : "Staked: \(game.stakeLabel)")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(TVTheme.textSoft)
            HStack(spacing: 24) {
                ForEach(game.stakeTiers) { tier in
                    Button { game.setStake(tier.value) } label: {
                        VStack(spacing: 4) {
                            Text(tier.label).font(.system(size: 28, weight: .black, design: .rounded))
                            Text("+\(tier.value) · \(tier.remaining) left").font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        .frame(width: 200, height: 96)
                    }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.mint, selected: game.currentStake == tier.value))
                    .focused($focus, equals: .stake(tier.value))
                    .disabled(tier.remaining == 0 && game.currentStake != tier.value)
                }
            }
        }
        .focusSection()
    }

    /// Picture ID image at ten feet — large, `.fit`, async with a fallback.
    private func pictureImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
            case .failure:
                Text("Couldn't load the image").font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            default: ProgressView()
            }
        }
        .frame(maxWidth: 760, maxHeight: 320, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Sweep fill-grid at ten feet — one cell per question in the set,
    /// filled mint (hit) / coral (miss), the current cell ringed white.
    private var sweepRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<game.questions.count, id: \.self) { i in
                let answered = i < game.answered.count
                let hit = answered && game.answered[i].isCorrect
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(answered ? (hit ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                                   : Color.white.opacity(0.12))
                    .frame(width: 44, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(i == game.index ? 0.9 : 0), lineWidth: 3))
            }
        }
    }

    private var hud: some View {
        HStack(spacing: 30) {
            Text(progressLabel).font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(TVTheme.textSoft)
            ProgressView(value: clockFraction).tint(game.remaining <= 5 ? Tidbits.Palette.coral : game.mode.accent)
                .frame(maxWidth: 500)
            Spacer()
            Label("\(game.streak)", systemImage: "flame.fill").foregroundStyle(game.streak >= 2 ? Tidbits.Palette.coral : TVTheme.textSoft)
            Label("\(game.score)", systemImage: "star.fill").foregroundStyle(Tidbits.Palette.yellow)
                .font(.system(size: 31, weight: .black, design: .rounded).monospacedDigit())
        }
        .font(.system(size: 31, weight: .bold, design: .rounded))
    }

    private var progressLabel: String {
        switch game.mode {
        case .timeAttack, .survival: return "#\(game.index + 1)"
        case .marathon:
            let offset = marathonOffset ?? 0
            return "\(offset + game.index + 1) / \(offset + game.questions.count)"
        default: return "\(game.index + 1) / \(game.questions.count)"
        }
    }

    /// Weak-Spot Arena's "why you're seeing this" — transparency by
    /// construction, never an opaque model (docs/CLUB-FEATURES-BUILD.md).
    private func weakSpotReasonCaption(_ reason: String) -> some View {
        Text(reason)
            .font(.system(size: 25, weight: .semibold, design: .rounded))
            .foregroundStyle(Tidbits.Palette.grape)
    }

    private var clockFraction: Double {
        let budget = game.displayClockBudget
        return budget <= 0 ? 0 : max(0, min(1, game.remaining / budget))
    }

    /// Ten-foot Trivia Night chapter marker — "ROUND 2 / 5 · PICTURE ROUND".
    private func roundBanner(_ round: NightRound) -> some View {
        HStack(spacing: 20) {
            Image(systemName: round.symbol).font(.system(size: 30, weight: .black))
                .foregroundStyle(game.mode.accent)
            Text("ROUND \(game.currentRoundNumber) / \(game.roundCount)")
                .font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            Text(round.title.uppercased())
                .font(.system(size: 31, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<game.roundCount, id: \.self) { i in
                    Circle().fill(i == game.currentRoundNumber - 1 ? game.mode.accent : Color.white.opacity(0.18))
                        .frame(width: 16, height: 16)
                }
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 18).fill(TVTheme.panel))
    }
    private func state(_ idx: Int, _ q: Question) -> TVAnswerStyle.State {
        // Hold the reveal in a host-paced night until the host reveals.
        guard game.phase == .reveal, !game.awaitingReveal else { return .idle }
        if idx == q.correctIndex { return .correct }
        if idx == game.chosenIndex { return .wrong }
        return .dim
    }

    private func reveal(_ q: Question) -> some View {
        let correct = game.lastAnswer?.isCorrect ?? false
        return VStack(alignment: .leading, spacing: 16) {
            Text(correct ? "Nice — you knew it." : "Now you know.")
                .font(.system(size: 33, weight: .heavy, design: .rounded))
                .foregroundStyle(correct ? Tidbits.Palette.mint : Tidbits.Palette.yellow)
            if let spec = q.enumerate {
                Text("You named \(game.enumFilled.count) of \(spec.total)")
                    .font(.system(size: 31, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                let named = Set(game.enumNamed)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 10) {
                    ForEach(spec.displayNames, id: \.self) { name in
                        let got = named.contains(name)
                        Text(name).font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(got ? .white : TVTheme.textSoft)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(got ? Tidbits.Palette.mint.opacity(0.3) : TVTheme.panel))
                    }
                }
                .frame(maxWidth: 1600)
            }
            if !q.explanation.isEmpty {
                Text(q.explanation).font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if game.mode == .barTrivia, let next = game.nextRoundAfterCurrent {
                Label("Round \(game.currentRoundNumber) complete · up next: \(next.title)", systemImage: "flag.checkered")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(game.mode.accent)
            }
            // Solo advances locally; the host advances everyone; a joiner just
            // follows (the host drives the "next" beat — no button on their screen).
            if live == nil {
                Button(nextLabel) { game.advance() }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                    .focused($focus, equals: .next)
                    .padding(.top, 8)
            } else if live?.role == .host {
                Button(nextLabel) { live?.next() }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                    .focused($focus, equals: .next)
                    .padding(.top, 8)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(TVTheme.panel))
    }
    private var isLast: Bool {
        game.mode != .timeAttack && game.mode != .survival && game.index + 1 >= game.questions.count
    }
    private var nextLabel: String {
        isLast ? "See Results" : (game.nextRoundAfterCurrent.map { "Start \($0.title)" } ?? "Next")
    }

    // MARK: Networked night (held reveal + host controls)

    private var tvLockedBeat: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(game.mode.accent)
            Text("Locked in — waiting for the host to reveal…")
                .font(.system(size: 31, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
        .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(TVTheme.panel))
    }

    /// The host's pacing control at ten feet — "k of n answered" + a Reveal button
    /// (focusable; the held-reveal phase lands focus here).
    private func tvHostRevealBar(_ live: LiveNight) -> some View {
        HStack(spacing: 24) {
            Text("\(live.answeredCount) of \(live.playerCount) answered")
                .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            Spacer()
            Button("Reveal") { live.reveal() }
                .buttonStyle(TVChipStyle(accent: game.mode.accent, selected: false))
                .focused($focus, equals: .next)
        }
        .frame(maxWidth: 1300)
    }
}

// MARK: - Networked-night chrome (tvOS)

/// The room strip atop a networked night — code (host) or room name (joiner) + count.
struct TVNightRoomStrip: View {
    let live: LiveNight
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: live.role == .host ? "dot.radiowaves.left.and.right" : "iphone.radiowaves.left.and.right")
                .font(.system(size: 25, weight: .bold)).foregroundStyle(Tidbits.Palette.coral)
            if live.role == .host {
                Text("JOIN CODE \(live.roomCode)").font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(.white).kerning(2)
            } else {
                Text(live.roomName.isEmpty ? "Connected" : live.roomName)
                    .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            Spacer()
            Label("\(live.playerCount)", systemImage: "person.2.fill")
                .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }
}

/// Standings shown at each reveal — leader crowned, you highlighted.
struct TVNightStandings: View {
    let live: LiveNight
    var body: some View {
        let sorted = live.players.sorted { $0.score > $1.score }
        return VStack(alignment: .leading, spacing: 10) {
            Text("STANDINGS").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            ForEach(sorted) { p in
                HStack(spacing: 14) {
                    if live.leaderSeat == p.seat {
                        Image(systemName: "crown.fill").font(.system(size: 22)).foregroundStyle(Tidbits.Palette.yellow)
                    }
                    Text(p.name).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    if p.isHost { Text("HOST").font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(TVTheme.textSoft) }
                    Spacer()
                    Text("\(p.score)").font(.system(size: 31, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(p.seat == live.mySeat ? Tidbits.Palette.mint.opacity(0.22) : TVTheme.panel))
            }
        }
        .frame(maxWidth: 1300)
    }
}

// MARK: - Answer style

struct TVAnswerStyle: ButtonStyle {
    enum State { case idle, correct, wrong, dim }
    let state: State
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, state: state) }
    struct Inner: View {
        let configuration: Configuration; let state: State
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(state == .correct || state == .wrong ? .white : (focused ? .black : .white))
                .background(RoundedRectangle(cornerRadius: 20).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(focused ? 1 : 0), lineWidth: 5))
                .opacity(state == .dim ? 0.4 : 1)
                .scaleEffect(focused ? 1.07 : 1.0)
                .animation(.easeOut(duration: 0.16), value: focused)
                .animation(.easeOut(duration: 0.2), value: state)
        }
        private var fill: Color {
            switch state {
            case .idle, .dim: return focused ? .white : TVTheme.panel
            case .correct: return Tidbits.Palette.mint
            case .wrong: return Tidbits.Palette.coral
            }
        }
    }
}

// MARK: - Results

struct TVResultsView: View {
    let summary: GameSummary
    @Environment(PlayerIdentityStore.self) private var identity
    /// nil = replay not allowed (the Daily is play-once, R-DAILY-1).
    let onPlayAgain: (() -> Void)?
    let onDone: () -> Void
    /// Weak-Spot Arena only: how many true misses this round turned correct —
    /// the payoff headline (docs/CLUB-FEATURES-BUILD.md "Feature 1"). nil elsewhere.
    var weakSpotGapsClosed: Int? = nil
    @FocusState private var playAgainFocused: Bool

    private var grid: String {
        summary.answered.map { $0.chosenIndex == nil ? "⬛" : ($0.isCorrect ? "🟩" : "🟥") }.joined()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text(headline.uppercased()).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Text("\(summary.score)").font(.system(size: 110, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("\(summary.mode.title) · \(summary.category.name)").font(.system(size: 31, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                gapsClosedMoment
                HStack(spacing: 60) {
                    stat("\(summary.correct)/\(summary.total)", "Correct")
                    stat("\(Int(summary.accuracy * 100))%", "Accuracy")
                    stat("\(summary.maxStreak)", "Best streak")
                }
                Text(grid).font(.system(size: 40))
                if let st = identity.profile?.streak, st.current >= 1 {
                    VStack(spacing: 6) {
                        Text("🔥 \(st.current)").font(.system(size: 60, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                        Text(st.current > 1 && st.current == st.longest ? "day streak · your best ever!" : "day streak")
                            .font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        if st.freezes > 0 {
                            Text("🧊 \(st.freezes) freeze\(st.freezes == 1 ? "" : "s") banked")
                                .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        }
                    }
                }
                HStack(spacing: 30) {
                    if let onPlayAgain {
                        Button("Play Again", action: onPlayAgain)
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                            .focused($playAgainFocused)
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                }
                .padding(.top, 8)
                if !summary.missed.isEmpty { recap }
            }
            .padding(90)
            .frame(maxWidth: .infinity)
        }
        .defaultFocus($playAgainFocused, true)
        // tvOS contributes to the global Daily board (so a living-room player is ranked);
        // the board-VIEWING surface is a fast-follow (needs a TVTheme dark restyle — the
        // shared cream DailyBoardContent would clash with the ten-foot dark design).
        .task {
            if summary.mode == .daily, summary.dailyDay == nil {
                await identity.submitDailyBoard(summary: summary)
            }
        }
    }

    /// F2 — the full missed-fact recap at ten feet: every wrong answer becomes a
    /// "now you know" card (the learning-orientation mandate, not just an emoji grid).
    /// Each card is FOCUSABLE — tvOS scrolling is focus-driven, so without
    /// focusable targets below the buttons the ScrollView never reveals these
    /// cards. Making them focusable lets the viewer arrow down through every
    /// tidbit (and scrolls the page as they go).
    private var recap: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TIDBITS TO REMEMBER")
                .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            ForEach(Array(summary.missed.enumerated()), id: \.offset) { _, a in
                TVRecapCard(answer: a)
            }
        }
        .frame(maxWidth: 1500)
        .padding(.top, 20)
        .focusSection()
    }

    /// A focusable missed-fact card. `.focusable()` makes it a focus target so
    /// the results page scrolls down into the recap; the nested `Content` reads
    /// `\.isFocused` (same pattern as the button styles) to draw a focus ring.
    private struct TVRecapCard: View {
        let answer: AnsweredQuestion
        var body: some View { Content(answer: answer).focusable() }

        private struct Content: View {
            let answer: AnsweredQuestion
            @Environment(\.isFocused) private var focused
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    Text(answer.question.prompt)
                        .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(answer.question.correctAnswer)
                        .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
                    if !answer.question.explanation.isEmpty {
                        Text(answer.question.explanation)
                            .font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 18).fill(focused ? TVTheme.panel.opacity(1) : TVTheme.panel.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 4))
                .scaleEffect(focused ? 1.015 : 1.0)
                .animation(.easeOut(duration: 0.16), value: focused)
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 6) {
            Text(v).font(.system(size: 46, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text(l.uppercased()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }

    /// Weak-Spot Arena's payoff — "you didn't just play, you got better."
    @ViewBuilder private var gapsClosedMoment: some View {
        if let n = weakSpotGapsClosed {
            VStack(spacing: 6) {
                Text("You closed \(n) gap\(n == 1 ? "" : "s")")
                    .font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text(n > 0 ? "Turned a miss into a win" : "Nothing to close yet this round")
                    .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 40)
            .background(RoundedRectangle(cornerRadius: 20).fill(Tidbits.Palette.grape.opacity(0.28)))
        }
    }
    private var headline: String {
        switch summary.accuracy {
        case 1: return "Flawless!"
        case 0.8...: return "Brilliant"
        case 0.5..<0.8: return "Nicely done"
        default: return "Good run"
        }
    }
}

// MARK: - Marathon results (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3")

/// The tvOS Marathon scorecard at ten feet — mirrors the iOS reference
/// (`MarathonResultsView`) with dark-first, focus-driven chrome. Reads the
/// permanent `MarathonScore` just written (a run's true total spans however
/// many sessions it took to finish, not just this last one).
struct TVMarathonResultsView: View {
    let score: MarathonScore
    var onPlayAgain: (() -> Void)? = nil
    let onDone: () -> Void
    /// True when opened from the history list (a past run, read-only) rather
    /// than right after finishing — hides the replay + history-link actions.
    var isHistorical: Bool = false

    @Query(sort: \MarathonScore.date, order: .reverse) private var allScores: [MarathonScore]
    @State private var showHistory = false
    @FocusState private var playAgainFocused: Bool

    private var previous: MarathonScore? {
        allScores.first { $0.date < score.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text("MARATHON COMPLETE").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Text("\(score.score)").font(.system(size: 110, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("\(score.correct)/\(score.total) correct · \(Self.durationLabel(score.durationSeconds))")
                    .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                comparisonMoment
                HStack(spacing: 60) {
                    stat("\(Int(score.accuracy * 100))%", "Accuracy")
                    stat("\(score.score)", "Score")
                    stat("\(allScores.count)", "Marathons")
                }
                domainCard
                HStack(spacing: 30) {
                    if let onPlayAgain {
                        Button("Start a new Marathon", action: onPlayAgain)
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: false))
                            .focused($playAgainFocused)
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                }
                .padding(.top, 8)
                if !isHistorical {
                    Button { showHistory = true } label: {
                        Label("See Marathon history", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.teal, selected: false))
                }
            }
            .padding(90)
            .frame(maxWidth: .infinity)
        }
        .defaultFocus($playAgainFocused, true)
        .fullScreenCover(isPresented: $showHistory) { TVMarathonHistoryView() }
    }

    @ViewBuilder private var comparisonMoment: some View {
        if let previous {
            let delta = Int((score.accuracy - previous.accuracy) * 100)
            VStack(spacing: 6) {
                Text(delta == 0 ? "Same as your last run" : "\(delta > 0 ? "+" : "")\(delta)% vs your last run")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(delta >= 0 ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                Text("Last run: \(Int(previous.accuracy * 100))% · this run: \(Int(score.accuracy * 100))%")
                    .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            .padding(.vertical, 8).padding(.horizontal, 40)
            .background(RoundedRectangle(cornerRadius: 20).fill(TVTheme.panel))
        } else {
            VStack(spacing: 6) {
                Text("Your first Marathon")
                    .font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("Play another to see how you're improving")
                    .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            .padding(.vertical, 8).padding(.horizontal, 40)
            .background(RoundedRectangle(cornerRadius: 20).fill(TVTheme.panel))
        }
    }

    /// Per-domain accuracy bars — the measured-mastery map (not just a score).
    private var domainCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where you stood this run").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
            ForEach(score.domainBreakdown.filter { $0.total > 0 }) { stat in domainRow(stat) }
        }
        .frame(maxWidth: 1400)
    }

    private func domainRow(_ stat: MarathonDomainStat) -> some View {
        let cat = TriviaCategory.named(stat.categoryID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: cat.symbol).font(.system(size: 25, weight: .bold)).foregroundStyle(cat.color)
                Text(cat.name).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Text("\(stat.correct)/\(stat.total) · \(Int(stat.accuracy * 100))%")
                    .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(cat.color).frame(width: max(10, geo.size.width * stat.accuracy))
                }
            }
            .frame(height: 18)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18).fill(TVTheme.panel))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 6) {
            Text(v).font(.system(size: 46, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text(l.uppercased()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }
}

/// The between-rounds beat of a solo Trivia Night at ten feet (Decision 036
/// follow-up: rounds must be FELT). Focus lands on the single Start button.
struct TVRoundIntroView: View {
    let game: GameEngine

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            if let round = game.introRound {
                Text("ROUND \(game.currentRoundNumber) OF \(game.roundCount)")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(TVTheme.textSoft).kerning(2)
                Image(systemName: round.kind.symbol)
                    .font(.system(size: 84, weight: .black))
                    .foregroundStyle(round.kind.accent)
                Text(round.kind.nightRoundTitle)
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(TVTheme.text)
                Text("\(round.count) questions · \(round.kind.blurb)")
                    .font(.system(size: 29, weight: .medium, design: .rounded))
                    .foregroundStyle(TVTheme.textSoft)
            }
            Spacer()
            Button("Start Round \(game.currentRoundNumber)") { game.startRound() }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
            Spacer().frame(height: 60)
        }
        .padding(80)
        .frame(maxWidth: .infinity)
        .background(TVTheme.bg.ignoresSafeArea())
    }
}

// MARK: - Expedition stage result (Club — docs/CLUB-FEATURES-BUILD.md
// "Feature 5"; mirrors the iOS reference `ExpeditionStageResultView`)

/// The tvOS post-play beat for an Expedition stage, ten-foot and dark-first
/// — pass unlocks the next stage (or, on the last stage, writes a
/// certificate); fail keeps the player on the same stage, "Try Again."
struct TVExpeditionStageResultView: View {
    let expedition: Expedition
    let stage: ExpeditionStage
    let summary: GameSummary
    /// Set once `finishExpeditionStage` records the true outcome; nil for the
    /// first render (the fallback below reads straight off `summary`, which
    /// is already final by `.finished`).
    let outcome: (passed: Bool, certificate: ExpeditionCertificate?)?
    let onRetry: () -> Void
    let onDone: () -> Void
    @FocusState private var primaryFocused: Bool

    private var passed: Bool { outcome?.passed ?? (summary.correct >= stage.passBar) }
    private var certificate: ExpeditionCertificate? { outcome?.certificate }
    private var nextStageNumber: Int { min(stage.index + 2, expedition.stageCount) }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 34) {
                    Image(systemName: certificate != nil ? "rosette" : (passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill"))
                        .font(.system(size: 84, weight: .black))
                        .foregroundStyle(passed ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                    Text(certificate != nil ? "EXPEDITION COMPLETE" : (passed ? "STAGE \(stage.index + 1) PASSED" : "NOT QUITE"))
                        .font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(TVTheme.text)
                    Text(bodyLine)
                        .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 60) {
                        stat("\(summary.correct)/\(summary.total)", "Correct")
                        stat("\(stage.passBar)", "Pass bar")
                        stat("\(min(stage.index + (passed ? 2 : 1), expedition.stageCount))/\(expedition.stageCount)", "Stage")
                    }
                    if let certificate { certificateCard(certificate) }
                    HStack(spacing: 30) {
                        if passed {
                            Button(certificate != nil ? "Done" : "Continue", action: onDone)
                                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.pink, selected: false))
                                .focused($primaryFocused)
                        } else {
                            Button("Try Again", action: onRetry)
                                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                                .focused($primaryFocused)
                            Button("Back to map", action: onDone)
                                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(90)
                .frame(maxWidth: .infinity)
            }
        }
        .defaultFocus($primaryFocused, true)
    }

    private var bodyLine: String {
        if certificate != nil { return "You completed \(expedition.title) — every stage, start to finish." }
        if passed { return "\(stage.title) is done. Stage \(nextStageNumber) just unlocked." }
        return "Needed \(stage.passBar) of \(stage.questionCount) to advance — you got \(summary.correct). Give it another go."
    }

    private func certificateCard(_ cert: ExpeditionCertificate) -> some View {
        VStack(spacing: 10) {
            Text("CERTIFICATE EARNED").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.text)
            Text(cert.title).font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("\(cert.stagesCompleted) stages · \(cert.totalScore) correct total")
                .font(.system(size: 25, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28).fill(Tidbits.Palette.pink.gradient))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 6) {
            Text(v).font(.system(size: 46, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text(l.uppercased()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }
}
#endif
