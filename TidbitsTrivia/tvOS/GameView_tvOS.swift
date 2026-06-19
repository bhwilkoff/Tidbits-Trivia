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
                var review = mode == .daily ? [] : RecordsStore.dueReview(in: modelContext, limit: 30)
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

private enum TVFocus: Hashable { case answer(Int), next }

struct TVGamePlayView: View {
    let onQuit: () -> Void
    @Environment(AppStore.self) private var store
    @FocusState private var focus: TVFocus?
    private var game: GameEngine { store.game }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            hud
            if let q = game.current {
                Text(TriviaCategory.named(q.categoryID).name.uppercased())
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(TriviaCategory.named(q.categoryID).color)
                Text(q.prompt)
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 28) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                        Button { game.submit(idx) } label: {
                            Text(opt).font(.system(size: 29, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 120)
                                .padding(.horizontal, 24)
                        }
                        .buttonStyle(TVAnswerStyle(state: state(idx, q)))
                        .focused($focus, equals: .answer(idx))
                        .disabled(game.phase == .reveal)
                    }
                }
                if game.phase == .reveal { reveal(q) }
            }
            Spacer()
        }
        .padding(90)
        .defaultFocus($focus, .answer(0))
        .onChange(of: game.index) { focus = .answer(0) }
        .onChange(of: game.phase) { _, p in
            if p == .reveal { focus = .next } else if p == .playing { focus = .answer(0) }
        }
        .task {
            guard DebugHooks.autopilot else { return }
            while game.phase != .finished && game.phase != .idle {
                try? await Task.sleep(for: .seconds(0.9))
                switch game.phase {
                case .playing: game.submit(0)
                case .reveal:  game.advance()
                default:       break
                }
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
        let budget = game.mode.perQuestionSeconds ?? game.mode.globalClockSeconds ?? 30
        return budget <= 0 ? 0 : max(0, min(1, game.remaining / budget))
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
            if !q.explanation.isEmpty {
                Text(q.explanation).font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(isLast ? "See Results" : "Next") { game.advance() }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                .focused($focus, equals: .next)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(TVTheme.panel))
    }
    private var isLast: Bool {
        (game.mode == .classic || game.mode == .daily) && game.index + 1 >= game.questions.count
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
        VStack(spacing: 30) {
            Text(headline.uppercased()).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            Text("\(summary.score)").font(.system(size: 130, weight: .black, design: .rounded)).foregroundStyle(.white)
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
            .padding(.top, 16)
        }
        .padding(90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($playAgainFocused, true)
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
