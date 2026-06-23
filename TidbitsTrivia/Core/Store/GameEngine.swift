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
    /// Trivia Night plan (bar-trivia mode only) — the rounds being played, so the
    /// UI can show round headers / end-of-round beats. nil in every other mode.
    private(set) var nightPlan: NightPlan? = nil

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

    // Stake mode: the remaining confidence-chip budget and the chip committed
    // to the current question (0 = not yet staked). Unused in other modes.
    private(set) var stakeTiers: [StakeTier] = []
    private(set) var currentStake: Int = 0
    // Stake mode: per-tier hits/total this round, for the calibration readout
    // (F1) — "did my Sure chips actually land?" Keyed by chip value.
    private(set) var stakeOutcomes: [Int: StakeOutcome] = [:]

    // Closest Call (M5): the live slider value and the points the last guess earned.
    private(set) var currentGuess: Double = 0
    private(set) var lastGuessPoints: Int = 0

    // Ordering (Q4): the player's working arrangement + points the last order earned.
    private(set) var currentOrder: [String] = []
    private(set) var lastOrderPoints: Int = 0

    // Matching (Q5): shuffled value column, per-key assignment (value index), the
    // currently-selected key (tap key then value to link), and points earned.
    private(set) var matchValues: [String] = []
    private(set) var matchAssign: [Int?] = []
    private(set) var matchSelectedKey: Int?
    private(set) var lastMatchPoints: Int = 0

    // Type-the-answer (Q6): the player's typed input (unused on tvOS, which self-marks).
    var typedText: String = ""

    // Enumeration (Q8): which answer groups have been named this puzzle, and the
    // canonical names in find-order (for the fill-grid + the recap of misses).
    private(set) var enumFilled: Set<Int> = []
    private(set) var enumNamed: [String] = []
    var enumLastHit: Bool = false   // last submit matched — drives a flash in the UI

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

    // MARK: Trivia Night helpers (bar-trivia mode)

    /// The round the current question belongs to (nil outside Trivia Night).
    var currentRound: NightRound? {
        guard let plan = nightPlan, let ri = current?.roundIndex,
              plan.rounds.indices.contains(ri) else { return nil }
        return plan.rounds[ri]
    }
    var currentRoundNumber: Int { (current?.roundIndex ?? 0) + 1 }
    var roundCount: Int { nightPlan?.rounds.count ?? 0 }

    /// If the current question is the LAST of its round, the round coming next —
    /// drives the "Round N done · up next: …" end-of-round beat. nil otherwise.
    var nextRoundAfterCurrent: NightRound? {
        guard let plan = nightPlan, let ri = current?.roundIndex else { return nil }
        let nextIdx = index + 1
        guard questions.indices.contains(nextIdx), let nextRi = questions[nextIdx].roundIndex,
              nextRi != ri, plan.rounds.indices.contains(nextRi) else { return nil }
        return plan.rounds[nextRi]
    }

    /// The clock budget to DISPLAY for the current question — shape-derived for a
    /// Trivia Night (which mixes shapes), the flat per-mode value otherwise.
    var displayClockBudget: Double {
        if mode == .barTrivia { return Self.shapeBudget(current) }
        return mode.perQuestionSeconds ?? mode.globalClockSeconds ?? 30
    }

    // MARK: Lifecycle

    func start(mode: GameMode, category: TriviaCategory, review: [Question] = []) async {
        self.mode = mode
        self.category = category
        phase = .loading
        triedLoad = true
        reset()
        var qs = await QuestionProvider.shared.questions(mode: mode, category: category)
        if !review.isEmpty { qs = Self.weave(fresh: qs, review: review) }
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

    /// Start a configurable Trivia Night ("bar trivia") from a pre-built,
    /// round-tagged mixed question list (see `QuestionProvider.nightQuestions`).
    /// Runs through the same shape-routing loop as every other mode — a night is
    /// just a question stream whose shapes change round to round.
    func startNight(plan: NightPlan, category: TriviaCategory, questions: [Question]) {
        self.mode = .barTrivia
        self.category = category
        phase = .loading
        triedLoad = true
        reset()
        self.nightPlan = plan
        self.questions = questions
        QuestionProvider.shared.markSeen(questions.map(\.id))
        guard !questions.isEmpty else { phase = .idle; return }
        beginQuestion()
    }

    private func reset() {
        nightPlan = nil
        index = 0; score = 0; streak = 0; maxStreak = 0
        answered = []; lastAnswer = nil; chosenIndex = nil; globalDeadline = nil
        stakeTiers = mode == .stake
            ? GameMode.stakeBudget.map { StakeTier(value: $0.value, label: $0.label, remaining: $0.count) }
            : []
        currentStake = 0
        stakeOutcomes = [:]
    }

    /// Interleave due review questions among fresh ones (count stays stable;
    /// interleaving is a desirable difficulty — better than blocking them).
    private static func weave(fresh: [Question], review: [Question]) -> [Question] {
        let freshIDs = Set(fresh.map(\.id))
        let inject = review.filter { !freshIDs.contains($0.id) }.prefix(max(1, fresh.count / 4))
        guard !inject.isEmpty, fresh.count > inject.count else { return fresh }
        var result = fresh
        for (i, q) in inject.enumerated() {
            let pos = min(result.count - 1, (i + 1) * result.count / (inject.count + 1))
            result[pos] = q
        }
        return result
    }

    private func beginQuestion() {
        chosenIndex = nil
        currentStake = 0
        if let spec = current?.closest { currentGuess = ((spec.min + spec.max) / 2).rounded() }
        if let order = current?.ordering { currentOrder = Self.shuffledDistinct(order) }
        if let m = current?.matching {
            matchValues = Self.shuffledDistinct(m.values)
            matchAssign = Array(repeating: nil, count: m.keys.count)
            matchSelectedKey = nil
        }
        if current?.accepted != nil { typedText = "" }
        if current?.enumerate != nil { enumFilled = []; enumNamed = []; enumLastHit = false; typedText = "" }
        phase = .playing
        questionStart = .now
        // Trivia Night mixes shapes within one run, so the clock comes from the
        // current question's SHAPE, not a single per-mode value.
        clockBudget = mode == .barTrivia
            ? Self.shapeBudget(current)
            : (mode.perQuestionSeconds ?? (globalRemaining() ?? 30))
        remaining = globalRemaining() ?? clockBudget
        startTicker()
    }

    /// Per-question time budget for a Trivia Night, by the question's shape —
    /// estimation/ordering/matching/enumeration deserve longer than a snap MCQ.
    static func shapeBudget(_ q: Question?) -> Double {
        guard let q else { return 25 }
        if q.enumerate != nil { return 60 }
        if q.matching != nil { return 40 }
        if q.ordering != nil { return 35 }
        if q.closest != nil { return 25 }
        if q.accepted != nil { return 25 }
        if q.imageURL != nil { return 22 }
        return 20
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
            if remaining <= 0 {
                // Dispatch the timeout by the question's SHAPE, not the mode, so
                // a Trivia Night (which mixes shapes) times out each question
                // correctly. Single-shape modes resolve identically.
                if current?.closest != nil { submitGuess() }
                else if current?.ordering != nil { submitOrder() }
                else if current?.matching != nil { submitMatch() }
                else if current?.accepted != nil { submitText() }
                else if current?.enumerate != nil { finishEnum() }
                else { submit(nil) }
            }
        }
    }

    // MARK: Stake

    /// Commit a confidence chip to the current question (Stake mode). Re-pickable
    /// until the answer is locked — choosing a new tier refunds the previous one.
    func setStake(_ value: Int) {
        guard mode == .stake, phase == .playing else { return }
        guard let i = stakeTiers.firstIndex(where: { $0.value == value }), stakeTiers[i].remaining > 0 else { return }
        if currentStake != 0, let p = stakeTiers.firstIndex(where: { $0.value == currentStake }) {
            stakeTiers[p].remaining += 1
        }
        stakeTiers[i].remaining -= 1
        currentStake = value
    }

    var stakeLabel: String { stakeTiers.first { $0.value == currentStake }?.label ?? "" }

    // MARK: Closest Call

    /// Move the estimate slider (Closest Call). Clamped to the question's domain.
    func setGuess(_ value: Double) {
        guard phase == .playing, let spec = current?.closest else { return }
        currentGuess = Swift.min(spec.max, Swift.max(spec.min, value))
    }

    /// Lock in the estimate — proximity scoring, adds-only (Decision 022).
    func submitGuess() {
        guard phase == .playing, let q = current, let spec = q.closest else { return }
        ticker?.cancel()
        let pts = spec.points(for: currentGuess)
        let close = spec.isClose(currentGuess)
        lastGuessPoints = pts
        let taken = Date().timeIntervalSince(questionStart)
        // chosenIndex == correctIndex (0) when close enough, so the emoji grid
        // and records read it as a hit; the score is the proximity points.
        let answer = AnsweredQuestion(question: q, chosenIndex: close ? 0 : 1, secondsTaken: taken)
        answered.append(answer)
        lastAnswer = answer
        if close {
            streak += 1; maxStreak = max(maxStreak, streak); Haptics.correct()
        } else {
            streak = 0; Haptics.wrong()
        }
        score += pts
        phase = .reveal
    }

    // MARK: Ordering

    /// Shuffle so the start order isn't already correct (a free win otherwise).
    private static func shuffledDistinct(_ order: [String]) -> [String] {
        guard order.count > 1 else { return order }
        var s = order
        for _ in 0..<6 { s.shuffle(); if s != order { break } }
        return s
    }

    /// Move an item up (toward the top) or down in the working arrangement.
    func moveOrderItem(_ index: Int, up: Bool) {
        guard phase == .playing, current?.ordering != nil, currentOrder.indices.contains(index) else { return }
        let target = up ? index - 1 : index + 1
        guard currentOrder.indices.contains(target) else { return }
        currentOrder.swapAt(index, target)
    }

    /// Lock in the arrangement — partial credit by inversion count (adds-only).
    func submitOrder() {
        guard phase == .playing, let q = current, let correct = q.ordering else { return }
        ticker?.cancel()
        let rank = Dictionary(uniqueKeysWithValues: correct.enumerated().map { ($0.element, $0.offset) })
        var inversions = 0
        for i in 0..<currentOrder.count {
            for j in (i + 1)..<currentOrder.count {
                if let a = rank[currentOrder[i]], let b = rank[currentOrder[j]], a > b { inversions += 1 }
            }
        }
        let maxInv = correct.count * (correct.count - 1) / 2
        let pts = maxInv == 0 ? 0 : Int((Double(40) * (1 - Double(inversions) / Double(maxInv))).rounded())
        lastOrderPoints = pts
        let perfect = inversions == 0
        let taken = Date().timeIntervalSince(questionStart)
        let answer = AnsweredQuestion(question: q, chosenIndex: perfect ? 0 : 1, secondsTaken: taken)
        answered.append(answer)
        lastAnswer = answer
        if perfect { streak += 1; maxStreak = max(maxStreak, streak); Haptics.correct() }
        else { streak = 0; Haptics.wrong() }
        score += pts
        phase = .reveal
    }

    // MARK: Matching

    /// Tap a key (left column) to select it; the next value tap links to it.
    func selectMatchKey(_ keyIndex: Int) {
        guard phase == .playing, current?.matching != nil else { return }
        matchSelectedKey = (matchSelectedKey == keyIndex) ? nil : keyIndex
    }

    /// Tap a value (right column) — links it to the selected key (1:1: clears the
    /// value from any other key, and the key's prior value).
    func assignMatchValue(_ valueIndex: Int) {
        guard phase == .playing, current?.matching != nil, let key = matchSelectedKey,
              matchAssign.indices.contains(key) else { return }
        for i in matchAssign.indices where matchAssign[i] == valueIndex { matchAssign[i] = nil }
        matchAssign[key] = valueIndex
        matchSelectedKey = nil
    }

    /// The value currently linked to a key, or nil.
    func matchedValue(forKey keyIndex: Int) -> String? {
        guard matchAssign.indices.contains(keyIndex), let v = matchAssign[keyIndex],
              matchValues.indices.contains(v) else { return nil }
        return matchValues[v]
    }

    /// Lock in — partial credit by correct links (adds-only).
    func submitMatch() {
        guard phase == .playing, let q = current, let m = q.matching else { return }
        ticker?.cancel()
        var correct = 0
        for (k, key) in m.keys.enumerated() where matchedValue(forKey: k) == m.values[k] { _ = key; correct += 1 }
        let pts = m.keys.isEmpty ? 0 : Int((Double(40) * Double(correct) / Double(m.keys.count)).rounded())
        lastMatchPoints = pts
        let perfect = correct == m.keys.count
        let taken = Date().timeIntervalSince(questionStart)
        let answer = AnsweredQuestion(question: q, chosenIndex: perfect ? 0 : 1, secondsTaken: taken)
        answered.append(answer)
        lastAnswer = answer
        if perfect { streak += 1; maxStreak = max(maxStreak, streak); Haptics.correct() }
        else { streak = 0; Haptics.wrong() }
        score += pts
        phase = .reveal
    }

    // MARK: Type-the-answer

    /// Submit the typed input (iOS/web/Android) — matched against the accepted set.
    func submitText() {
        guard let q = current, let acc = q.accepted else { return }
        resolveTyped(correct: Self.matchesAccepted(typedText, acc))
    }

    /// tvOS self-mark (text entry is a keyboard wall there): the player recalls,
    /// reveals, and honestly reports — active recall without typing.
    func markTyped(correct: Bool) {
        guard current?.accepted != nil else { return }
        resolveTyped(correct: correct)
    }

    private func resolveTyped(correct: Bool) {
        guard phase == .playing, let q = current else { return }
        ticker?.cancel()
        let taken = Date().timeIntervalSince(questionStart)
        let answer = AnsweredQuestion(question: q, chosenIndex: correct ? 0 : 1, secondsTaken: taken)
        answered.append(answer)
        lastAnswer = answer
        if correct {
            streak += 1; maxStreak = max(maxStreak, streak)
            score += Scoring.points(correct: true, secondsTaken: taken,
                                    budget: mode.perQuestionSeconds ?? 25, streak: streak)
            Haptics.correct()
        } else {
            streak = 0; Haptics.wrong()
        }
        phase = .reveal
    }

    // MARK: Enumeration (Q8)

    /// Submit one typed guess for the current list puzzle. Fills the first
    /// unfilled group any of whose aliases match; +1 to the score per fill
    /// (count-scored, like Sweep — the list you fill IS the score). Returns
    /// whether it matched. Already-found or wrong inputs are no-ops.
    @discardableResult
    func submitEnumGuess(_ text: String) -> Bool {
        guard phase == .playing, let spec = current?.enumerate else { return false }
        typedText = ""
        let n = Self.normalizeType(text)
        guard !n.isEmpty else { enumLastHit = false; return false }
        for (i, group) in spec.groups.enumerated() where !enumFilled.contains(i) {
            if group.contains(where: { Self.normalizeType($0) == n }) {
                enumFilled.insert(i)
                enumNamed.append(group.first ?? "")
                score += 1
                enumLastHit = true
                Haptics.correct()
                if enumFilled.count == spec.groups.count { finishEnum() }
                return true
            }
        }
        enumLastHit = false
        Haptics.wrong()
        return false
    }

    /// tvOS recall-self-mark: the player thinks of names (no keyboard at ten
    /// feet), then reports how many they could name. Mirrors the type-answer
    /// fallback — honesty-based, the way flashcards are.
    func selfMarkEnum(_ count: Int) {
        guard phase == .playing, let spec = current?.enumerate else { return }
        let c = Swift.min(Swift.max(0, count), spec.groups.count)
        enumFilled = Set(0..<c)
        enumNamed = spec.displayNames.prefix(c).map { $0 }
        score += c
        finishEnum()
    }

    /// Finalize the current puzzle (timeout, all-found, or self-mark) and reveal.
    func finishEnum() {
        guard phase == .playing, let q = current, let spec = q.enumerate else { return }
        ticker?.cancel()
        let got = enumFilled.count
        // Synthetic chosenIndex for the emoji grid / records: a "hit" if you
        // named at least half the set; the real reward is the count (already scored).
        let hit = got > 0 && got * 2 >= spec.total
        let answer = AnsweredQuestion(question: q, chosenIndex: hit ? 0 : 1, secondsTaken: clockBudget - remaining)
        answered.append(answer)
        lastAnswer = answer
        phase = .reveal
    }

    static func matchesAccepted(_ input: String, _ accepted: [String]) -> Bool {
        let n = normalizeType(input)
        guard !n.isEmpty else { return false }
        return accepted.contains { normalizeType($0) == n }
    }

    /// Normalize for free-text comparison: fold diacritics, lowercase, keep only
    /// alphanumerics + spaces, collapse runs, drop a leading "the ".
    static func normalizeType(_ s: String) -> String {
        var t = s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        t = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        if t.hasPrefix("the ") { t = String(t.dropFirst(4)) }
        return t
    }

    // MARK: Answering

    func submit(_ choice: Int?) {
        guard phase == .playing, let q = current else { return }
        // In Stake mode a chip must be committed before a manual answer counts
        // (a timeout, choice == nil, still resolves as a miss with no chip spent).
        if mode == .stake, currentStake == 0, choice != nil { return }
        ticker?.cancel()
        chosenIndex = choice
        let taken = Date().timeIntervalSince(questionStart)
        let answer = AnsweredQuestion(question: q, chosenIndex: choice, secondsTaken: taken)
        answered.append(answer)
        lastAnswer = answer

        if mode == .stake, currentStake != 0 {
            var o = stakeOutcomes[currentStake] ?? StakeOutcome(hits: 0, total: 0)
            o.total += 1
            if answer.isCorrect { o.hits += 1 }
            stakeOutcomes[currentStake] = o
        }

        if answer.isCorrect {
            streak += 1
            maxStreak = max(maxStreak, streak)
            // Stake: the reward IS the chip you bet (no speed/streak multiplier —
            // it's calibration, not a race). Sweep: +1 per correct — the score IS
            // the count of the set you filled, beat-your-own-best (no speed bonus,
            // so the grid stays an honest tally). Other modes: speed-aware scoring.
            switch mode {
            case .stake: score += currentStake
            case .sweep: score += 1
            case .ladder:
                // Climb bonus: harder rungs (F3 derived difficulty) pay more.
                let d = DifficultyOverlay.shared.difficulty(for: q)
                score += Scoring.points(correct: true, secondsTaken: taken,
                                        budget: mode.perQuestionSeconds ?? clockBudget, streak: streak) + (d - 1) * 10
            default:
                score += Scoring.points(correct: true, secondsTaken: taken,
                                        budget: mode.perQuestionSeconds ?? clockBudget, streak: streak)
            }
            Haptics.correct()
        } else {
            streak = 0
            Haptics.wrong()
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
            answered: answered, stakeOutcomes: stakeOutcomes)
    }
}

/// One confidence tier in Stake mode's budget: a point value, a friendly
/// label, and how many chips of this tier remain to spend in the round.
struct StakeTier: Identifiable, Sendable, Hashable {
    let value: Int
    let label: String
    var remaining: Int
    var id: Int { value }
}

/// One confidence tier's outcome in a Stake round (F1 calibration).
struct StakeOutcome: Sendable, Hashable, Codable {
    var hits: Int
    var total: Int
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
    var stakeOutcomes: [Int: StakeOutcome] = [:]

    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    var missed: [AnsweredQuestion] { answered.filter { !$0.isCorrect } }
}
