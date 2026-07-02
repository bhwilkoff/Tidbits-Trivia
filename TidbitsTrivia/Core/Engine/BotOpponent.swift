import Foundation
import Observation

/// Play vs CPU — the online-multiplayer v0 (Decision 038,
/// docs/ONLINE-MULTIPLAYER-PLAYBOOK.md §5). A bot is a small parameterized
/// model resolved locally against the same question the player sees; later
/// (v1) the identical resolution runs inside the server room actor as the
/// timeout-fill / dropout brain.
///
/// HONESTY RULE (learning-orientation, non-negotiable): a bot is always
/// visibly labeled CPU. Never present a bot as a human.
///
/// Believability levers (the playbook's spec): non-extreme, category-varying
/// correct-rates (visible strengths/weaknesses) + jittered right-skewed
/// timing with an occasional freeze — a bot that answers in exactly 3.0s
/// every time is the tell. Mirrors: `Bots.kt` (Android) and `js/bots.js`
/// (web); keep the three in lockstep.
nonisolated struct BotProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Global correct-rate at medium difficulty (0…1, never extreme).
    let baseSkill: Double
    /// Per-category offset — strengths/weaknesses (e.g. Sports +0.15).
    let categorySkill: [String: Double]
    /// Answer-time model: log-normal around `speedMean` seconds.
    let speedMean: Double
    let speedSigma: Double

    static let rookie = BotProfile(
        id: "rookie", name: "Rookie Rae", baseSkill: 0.55,
        categorySkill: ["sports": 0.15, "film": 0.10, "science": -0.12],
        speedMean: 6.5, speedSigma: 0.45)
    static let regular = BotProfile(
        id: "regular", name: "Trivia Tina", baseSkill: 0.70,
        categorySkill: ["history": 0.10, "arts": 0.08, "sports": -0.10],
        speedMean: 5.5, speedSigma: 0.40)
    static let ace = BotProfile(
        id: "ace", name: "Ace Botsworth", baseSkill: 0.85,
        categorySkill: ["science": 0.10, "geography": 0.08, "music": -0.08],
        speedMean: 4.0, speedSigma: 0.35)

    /// The adaptive sparring partner: tracks the player's recent accuracy so
    /// solo-vs-CPU stays a fair fight ("meet the learner where they are").
    static func house(playerAccuracy: Double) -> BotProfile {
        BotProfile(
            id: "house", name: "The House", baseSkill: min(0.90, max(0.35, playerAccuracy)),
            categorySkill: [:], speedMean: 5.0, speedSigma: 0.40)
    }

    static let presets: [BotProfile] = [.rookie, .regular, .ace]
}

/// One bot's resolution for one question. `seconds == nil` = froze / ran out
/// of clock (humans do too — that variance is the believability payload).
nonisolated struct BotAnswer: Sendable {
    let botID: String
    let choiceIndex: Int?
    let seconds: Double?
    var answered: Bool { choiceIndex != nil }
}

nonisolated enum BotBrain {
    static func difficultyAdj(_ difficulty: Int) -> Double {
        if difficulty <= 2 { return 0.15 }
        if difficulty >= 4 { return -0.20 }
        return 0
    }

    /// Resolve what this bot does with this question, inside `window` seconds.
    static func resolve(_ bot: BotProfile, categoryID: String, difficulty: Int,
                        correctIndex: Int, optionCount: Int, window: Double) -> BotAnswer {
        let p = min(0.98, max(0.02,
            bot.baseSkill + (bot.categorySkill[categoryID] ?? 0) + difficultyAdj(difficulty)))
        // ~5% freeze: no answer at all.
        if Double.random(in: 0..<1) < 0.05 {
            return BotAnswer(botID: bot.id, choiceIndex: nil, seconds: nil)
        }
        let correct = Double.random(in: 0..<1) < p
        // Log-normal, right-skewed; knowing feels fast, so correct trims ~15%.
        let gauss = Self.gaussian()
        var t = exp(log(bot.speedMean) + gauss * bot.speedSigma)
        if correct { t *= 0.85 }
        t = min(max(t, 0.8), max(1.0, window - 0.5))
        let choice: Int
        if correct {
            choice = correctIndex
        } else {
            var wrong = Array(0..<max(optionCount, 2))
            wrong.removeAll { $0 == correctIndex }
            choice = wrong.randomElement() ?? 0
        }
        return BotAnswer(botID: bot.id, choiceIndex: choice, seconds: t)
    }

    private static func gaussian() -> Double {
        // Box–Muller.
        let u1 = Double.random(in: Double.ulpOfOne..<1)
        let u2 = Double.random(in: 0..<1)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// The running vs-CPU match: per-bot scores/streaks beside the player's own
/// engine-scored game. Resolve at question start, commit at reveal — so the
/// reveal can show what each opponent did on the SAME question.
@Observable
@MainActor
final class BotMatch {
    struct Seat: Identifiable {
        let bot: BotProfile
        var score = 0
        var streak = 0
        var lastCorrect: Bool?
        var id: String { bot.id }
    }

    private(set) var seats: [Seat]
    private(set) var pending: [BotAnswer] = []
    private var committedIndex = -1

    init(bots: [BotProfile]) {
        seats = bots.map { Seat(bot: $0) }
    }

    func beginQuestion(_ q: Question, window: Double) {
        pending = seats.map {
            BotBrain.resolve($0.bot, categoryID: q.categoryID, difficulty: q.difficulty,
                             correctIndex: q.correctIndex, optionCount: q.options.count, window: window)
        }
    }

    /// Apply the pending answers with the SAME Scoring rules the player gets.
    func commit(question q: Question, index: Int, budget: Double) {
        guard index != committedIndex else { return }   // reveal fires once
        committedIndex = index
        for answer in pending {
            guard let i = seats.firstIndex(where: { $0.bot.id == answer.botID }) else { continue }
            let correct = answer.choiceIndex == q.correctIndex
            seats[i].lastCorrect = answer.answered ? correct : false
            if correct {
                seats[i].streak += 1
                seats[i].score += Scoring.points(correct: true, secondsTaken: answer.seconds ?? budget,
                                                 budget: budget, streak: seats[i].streak)
            } else {
                seats[i].streak = 0
            }
        }
    }

    /// Standings rows (bot side only — the caller weaves in the human player).
    var standings: [Seat] { seats.sorted { $0.score > $1.score } }
}
