import SwiftUI
import Observation

/// Drives one game from first question to summary. UI-agnostic: every
/// platform's game view observes this same engine (Core never imports
/// per-platform UI). Multiplayer modes will wrap an array of these or
/// drive a shared one over the network — the per-player loop is identical.
@Observable
@MainActor
final class GameEngine {

    enum Phase: Equatable {
        case idle
        case loading
        case playing
        case reveal          // answer shown, "learn the fact" visible
        case finished
    }

    // Configuration
    private(set) var mode: GameMode = .classic
    private(set) var category: TriviaCategory = .named("mixed")

    // Live state
    private(set) var phase: Phase = .idle
    private(set) var questions: [Question] = []
    private(set) var index: Int = 0
    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    private(set) var maxStreak: Int = 0
    private(set) var answered: [AnsweredQuestion] = []
    private(set) var lastAnswer: AnsweredQuestion?
    private(set) var chosenIndex: Int?

    // Clocks
    private(set) var remaining: Double = 0      // seconds left on the active clock
    private var clockBudget: Double = 0
    private var questionStart: Date = .now
    private var globalDeadline: Date?
    private var ticker: Task<Void, Never>?

    var current: Question? { questions.indices.contains(index) ? questions[index] : nil }
    var progress: Double {
        guard mode == .classic || mode == .daily else { return 0 }
        return questions.isEmpty ? 0 : Double(index) / Double(questions.count)
    }
    var loadFailed: Bool { phase == .idle && questions.isEmpty && triedLoad }
    private var triedLoad = false

    // MARK: Lifecycle

    func start(mode: GameMode, category: TriviaCategory) async {
        self.mode = mode
        self.category = category
        phase = .loading
        triedLoad = true
        reset()
        let qs = await QuestionProvider.shared.questions(mode: mode, category: category)
        questions = qs
        QuestionProvider.shared.markSeen(qs.map(\.id))
        guard !qs.isEmpty else { phase = .idle; return }
        if let global = mode.globalClockSeconds {
            globalDeadline = Date().addingTimeInterval(global)
        }
        beginQuestion()
    }

    /// Start a game from a pre-built question set (live "create a quiz").
    func startCustom(mode: GameMode, category: TriviaCategory, questions: [Question]) {
        self.mode = mode
        self.category = category
        phase = .loading
        triedLoad = true
        reset()
        self.questions = questions
        QuestionProvider.shared.markSeen(questions.map(\.id))
        guard !questions.isEmpty else { phase = .idle; return }
        if let global = mode.globalClockSeconds {
            globalDeadline = Date().addingTimeInterval(global)
        }
        beginQuestion()
    }

    private func reset() {
        index = 0; score = 0; streak = 0; maxStreak = 0
        answered = []; lastAnswer = nil; chosenIndex = nil; globalDeadline = nil
    }

    private func beginQuestion() {
        chosenIndex = nil
        phase = .playing
        questionStart = .now
        clockBudget = mode.perQuestionSeconds ?? (globalRemaining() ?? 30)
        remaining = activeBudget()
        startTicker()
    }

    private func activeBudget() -> Double {
        if let g = globalRemaining() { return g }
        return mode.perQuestionSeconds ?? 30
    }

    private func globalRemaining() -> Double? {
        guard let d = globalDeadline else { return nil }
        return max(0, d.timeIntervalSinceNow)
    }

    // MARK: Ticking

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard phase == .playing else { return }
        if let g = globalRemaining() {
            remaining = g
            if g <= 0 { endGame(); return }
        } else {
            let elapsed = Date().timeIntervalSince(questionStart)
            remaining = max(0, clockBudget - elapsed)
            if remaining <= 0 { submit(nil) }
        }
    }

    // MARK: Answering

    func submit(_ choice: Int?) {
        guard phase == .playing, let q = current else { return }
        ticker?.cancel()
        chosenIndex = choice
        let taken = Date().timeIntervalSince(questionStart)
        let answer = AnsweredQuestion(question: q, chosenIndex: choice, secondsTaken: taken)
        answered.append(answer)
        lastAnswer = answer

        if answer.isCorrect {
            streak += 1
            maxStreak = max(maxStreak, streak)
            score += Scoring.points(correct: true, secondsTaken: taken,
                                    budget: mode.perQuestionSeconds ?? clockBudget, streak: streak)
        } else {
            streak = 0
            if mode == .survival { phase = .reveal; return }   // reveal then end
        }
        phase = .reveal
    }

    /// Advance from the reveal screen to the next question (or finish).
    func advance() {
        // Survival ends on the first wrong answer.
        if mode == .survival, let a = lastAnswer, !a.isCorrect { endGame(); return }
        if let g = globalRemaining(), g <= 0 { endGame(); return }
        index += 1
        if index >= questions.count {
            // Time Attack / Survival keep going while the supply lasts.
            if mode == .timeAttack && (globalRemaining() ?? 0) > 0 {
                endGame(); return   // ran out of loaded questions
            }
            endGame(); return
        }
        beginQuestion()
    }

    private func endGame() {
        ticker?.cancel()
        phase = .finished
    }

    func quit() {
        ticker?.cancel()
        phase = .idle
        reset()
        questions = []
    }

    // MARK: Summary

    var summary: GameSummary {
        let correct = answered.filter(\.isCorrect).count
        return GameSummary(
            mode: mode, category: category, score: score,
            correct: correct, total: answered.count, maxStreak: maxStreak,
            answered: answered)
    }
}

/// Immutable end-of-game payload — drives the results + recap screens and
/// the record/leaderboard writes.
struct GameSummary: Sendable {
    let mode: GameMode
    let category: TriviaCategory
    let score: Int
    let correct: Int
    let total: Int
    let maxStreak: Int
    let answered: [AnsweredQuestion]

    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    var missed: [AnsweredQuestion] { answered.filter { !$0.isCorrect } }
}
