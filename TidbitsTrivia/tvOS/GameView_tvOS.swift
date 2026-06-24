#if os(tvOS)
import SwiftUI
import SwiftData

/// Runs one game on Apple TV, reusing the shared GameEngine. Ten-foot
/// layout, dark-first, Siri-Remote focus. Same loop as iOS — only the
/// presentation differs.
struct TVGameContainer: View {
    let mode: GameMode
    let category: TriviaCategory
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                if game.loadFailed { errorState } else { loading }
            case .playing, .reveal:
                TVGamePlayView(onQuit: close)
            case .finished:
                TVResultsView(summary: game.summary, onPlayAgain: replay, onDone: close)
                    .onAppear(perform: persist)
            }
        }
        .task {
            if game.phase == .idle {
                // Single-category game re-asks only same-category misses (no cross-category leak).
                var review = (mode.acceptsReview && GameSettings.reviewEnabled)
                    ? RecordsStore.dueReview(in: modelContext, limit: 30) : []
                if category.id != "mixed" { review = review.filter { $0.categoryID == category.id } }
                review = Array(review.prefix(2))
                await game.start(mode: mode, category: category, review: review)
            }
        }
        .onExitCommand(perform: close)   // Menu button quits the game (modal: allowed)
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
    private func replay() { recorded = false; Task { await game.start(mode: mode, category: category) } }
    private func close() { game.quit(); dismiss() }
}

// MARK: - Gameplay

private enum TVFocus: Hashable { case stake(Int), answer(Int), closestSlider, closestLock, orderRow(Int), orderSubmit, matchKey(Int), matchVal(Int), matchSubmit, typeReveal, typeKnew, typeMissed, enumReveal, enumMinus, enumPlus, enumSubmit, next }

struct TVGamePlayView: View {
    let onQuit: () -> Void
    @Environment(AppStore.self) private var store
    @FocusState private var focus: TVFocus?
    @State private var typeRevealed = false
    @State private var enumRevealed = false
    @State private var enumSelfCount = 0
    private var game: GameEngine { store.game }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
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
                if game.phase == .reveal { reveal(q) }
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
            guard DebugHooks.autopilot else { return }
            while game.phase != .finished && game.phase != .idle {
                try? await Task.sleep(for: .seconds(0.9))
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
                    game.submit(0)
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
        default: return "\(game.index + 1) / \(game.questions.count)"
        }
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
        guard game.phase == .reveal else { return .idle }
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
            Button(isLast ? "See Results" : (game.nextRoundAfterCurrent.map { "Start \($0.title)" } ?? "Next")) { game.advance() }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                .focused($focus, equals: .next)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(TVTheme.panel))
    }
    private var isLast: Bool {
        game.mode != .timeAttack && game.mode != .survival && game.index + 1 >= game.questions.count
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
    let onPlayAgain: () -> Void
    let onDone: () -> Void
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
                HStack(spacing: 60) {
                    stat("\(summary.correct)/\(summary.total)", "Correct")
                    stat("\(Int(summary.accuracy * 100))%", "Accuracy")
                    stat("\(summary.maxStreak)", "Best streak")
                }
                Text(grid).font(.system(size: 40))
                HStack(spacing: 30) {
                    Button("Play Again", action: onPlayAgain)
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                        .focused($playAgainFocused)
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
    private var headline: String {
        switch summary.accuracy {
        case 1: return "Flawless!"
        case 0.8...: return "Brilliant"
        case 0.5..<0.8: return "Nicely done"
        default: return "Good run"
        }
    }
}
#endif
